--[[
	Builds every weapon and writes Roblox model files to dist/.

	    lune run src/build.luau              -- build dist/*.rbxm
	    lune run src/build.luau --preview    -- also dump preview geometry (JSON)

	Run from the repository root.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local ToolKit = require("./builder/ToolKit")

local Instance = roblox.Instance

local WEAPONS = {
	{ file = "Longsword", module = "./models/Sword" },
	{ file = "BattleAxe", module = "./models/BattleAxe" },
	{ file = "TwinDaggers", module = "./models/TwinDaggers" },
	{ file = "Longbow", module = "./models/Longbow" },
	{ file = "ShoulderBlaster", module = "./models/ShoulderBlaster" },
}

local wantPreview = table.find(process.args, "--preview") ~= nil
local wantSourcemap = table.find(process.args, "--sourcemap") ~= nil
-- geometry-only builds skip embedding scripts (used while iterating on models)
ToolKit.skipScripts = table.find(process.args, "--no-scripts") ~= nil
local only = nil
for _, a in process.args do
	if string.sub(a, 1, 7) == "--only=" then
		only = string.sub(a, 8)
	end
end

--------------------------------------------------------------------------------
-- Preview export (consumed by tools/preview)
--------------------------------------------------------------------------------

local function comps(cf)
	return { cf:GetComponents() }
end

local function partInfo(p)
	local shape = if p:IsA("WedgePart") then "Wedge" else p.Shape.Name
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	return {
		hidden = p.Transparency >= 1,
		name = p.Name,
		shape = shape,
		mesh = if mesh then mesh.MeshType.Name else nil,
		size = { p.Size.X, p.Size.Y, p.Size.Z },
		cf = comps(p.CFrame),
		color = { p.Color.R, p.Color.G, p.Color.B },
		material = p.Material.Name,
		transparency = p.Transparency,
	}
end

local function indexOf(list, inst)
	for i, v in list do
		if v == inst then
			return i
		end
	end
	return nil
end

-- Exports every part of each rigged model with its parent joint, so the viewer
-- can re-pose Motor6D rigs (e.g. the drawn bow) exactly like Roblox would.
local function previewOf(tool)
	local out = { name = tool.Name, models = {} }
	local joints = {}
	for _, d in tool:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("WeldConstraint") then
			table.insert(joints, d)
		end
	end
	for _, m in tool:GetDescendants() do
		if m:IsA("Model") and m.PrimaryPart and m.PrimaryPart:GetAttribute("RigLimb") then
			local root = m.PrimaryPart
			local list = {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
			local entry = {
				name = m.Name,
				root = comps(root.CFrame),
				rig = {
					limb = root:GetAttribute("RigLimb"),
					attachment = root:GetAttribute("RigAttachment"),
					offset = comps(root:GetAttribute("RigOffset")),
				},
				parts = {},
				beams = {},
			}
			if root:GetAttribute("HolsterLimb") then
				entry.holster = {
					limb = root:GetAttribute("HolsterLimb"),
					attachment = root:GetAttribute("HolsterAttachment"),
					offset = comps(root:GetAttribute("HolsterOffset")),
				}
			end
			for i, p in list do
				local info = partInfo(p)
				info.id = i
				for _, j in joints do
					if j.Part1 == p then
						local parent = indexOf(list, j.Part0)
						if parent then
							info.parent = parent
							if j:IsA("Motor6D") then
								local poses = {}
								for key, value in j:GetAttributes() do
									if string.sub(key, 1, 4) == "Pose" then
										poses[string.sub(key, 5)] = comps(value)
									end
								end
								info.joint = { name = j.Name, c0 = comps(j.C0), c1 = comps(j.C1), poses = poses }
							end
						end
						break
					end
				end
				table.insert(entry.parts, info)
			end
			for _, d in m:GetDescendants() do
				if d:IsA("Beam") and d.Attachment0 and d.Attachment1 then
					table.insert(entry.beams, {
						a = { part = indexOf(list, d.Attachment0.Parent), cf = comps(d.Attachment0.CFrame) },
						b = { part = indexOf(list, d.Attachment1.Parent), cf = comps(d.Attachment1.CFrame) },
						width = d.Width0,
						color = { d.Color.Keypoints[1].Value.R, d.Color.Keypoints[1].Value.G, d.Color.Keypoints[1].Value.B },
					})
				end
			end
			table.insert(out.models, entry)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Sourcemap (Rojo format) so luau-lsp can type-check the runtime scripts
--------------------------------------------------------------------------------

local function sourcemapNode(inst)
	local node = { name = inst.Name, className = inst.ClassName }
	for _, entry in ToolKit.sources do
		if entry.inst == inst then
			node.filePaths = { entry.path }
		end
	end
	local children = {}
	for _, child in inst:GetChildren() do
		table.insert(children, sourcemapNode(child))
	end
	if #children > 0 then
		node.children = children
	end
	return node
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

fs.writeDir("dist")
local pack = Instance.new("Folder")
pack.Name = "WeaponsPack"

local previews = {}
local sourcemapPack = Instance.new("StarterPack")
for _, w in WEAPONS do
	if only and only ~= w.file then
		continue
	end
	local tool = (require :: any)(w.module)()
	ToolKit.validate(tool)
	local partCount = 0
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	print(string.format("%-16s %4d parts", tool.Name, partCount))

	fs.writeFile("dist/" .. w.file .. ".rbxm", roblox.serializeModel({ tool }))
	tool:Clone().Parent = pack
	if wantSourcemap then
		tool.Parent = sourcemapPack
	end
	if wantPreview then
		table.insert(previews, previewOf(tool))
	end
end

if not only and not ToolKit.skipScripts then
	local rigger = Instance.new("ModuleScript")
	rigger.Name = "WeaponRigger"
	rigger.Source = fs.readFile("src/runtime/WeaponRigger.luau")
	rigger.Parent = pack
	fs.writeFile("dist/WeaponRigger.rbxm", roblox.serializeModel({ rigger:Clone() }))
	fs.writeFile("dist/WeaponsPack.rbxm", roblox.serializeModel({ pack }))
	print("wrote dist/WeaponsPack.rbxm")
end

if wantSourcemap then
	local rigger = Instance.new("ModuleScript")
	rigger.Name = "WeaponRigger"
	rigger.Parent = sourcemapPack
	table.insert(ToolKit.sources, { inst = rigger, path = "src/runtime/WeaponRigger.luau" })
	local map = { name = "Game", className = "DataModel", children = { sourcemapNode(sourcemapPack) } }
	fs.writeFile("sourcemap.json", serde.encode("json", map, true))
	print("wrote sourcemap.json")
end

if wantPreview then
	fs.writeDir("tools/preview/out")
	fs.writeFile("tools/preview/out/weapons.json", serde.encode("json", previews))
	print("wrote tools/preview/out/weapons.json")
end
