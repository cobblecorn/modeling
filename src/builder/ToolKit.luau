--[[
	ToolKit: assembles a Roblox Tool around a part-built weapon model and embeds
	the runtime scripts from src/runtime.

	Resulting hierarchy (hand-held weapon):

	Tool
	├─ Handle          invisible grip anchor the engine welds to the hand
	├─ <Model>         the visible weapon (PrimaryPart = BodyAttach)
	│   ├─ BodyAttach  rig root; the runtime joins it to the hand with a Motor6D
	│   └─ ...parts    welded to BodyAttach (or to sub-roots for moving parts)
	├─ WeaponCore      shared ModuleScript (rigging, combat, projectiles, fx)
	├─ Server          Script
	├─ Client          LocalScript
	└─ Remote          RemoteEvent
]]

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local Parts = require("./Parts")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

local ToolKit = {}

-- script instance -> source file, used to emit a sourcemap for type checking
ToolKit.sources = {}

local RUNTIME = "src/runtime"

local function readSource(path)
	return fs.readFile(path)
end

local function moduleFromDir(name, dir)
	local module = Instance.new("ModuleScript")
	module.Name = name
	module.Source = readSource(dir .. "/init.luau")
	table.insert(ToolKit.sources, { inst = module, path = dir .. "/init.luau" })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		if entry ~= "init.luau" and string.sub(entry, -5) == ".luau" then
			local child = Instance.new("ModuleScript")
			child.Name = string.sub(entry, 1, -6)
			child.Source = readSource(dir .. "/" .. entry)
			child.Parent = module
			table.insert(ToolKit.sources, { inst = child, path = dir .. "/" .. entry })
		end
	end
	return module
end

--[[
	spec = {
	  name, toolTip, textureId?,
	  handle = true | false,           -- false for tools that are not held (shoulder blaster)
	  handleSize = Vector3?,
	  attributes = { [string]: any },   -- gameplay tuning, shown in Studio's Properties
	  script = "Sword",                -- src/runtime/weapons/<script>.server/.client.luau
	}
	returns tool, model, bodyAttach, builder
]]
function ToolKit.newTool(spec)
	local tool = Instance.new("Tool")
	tool.Name = spec.name
	tool.ToolTip = spec.toolTip or spec.name
	tool.CanBeDropped = false
	tool.RequiresHandle = spec.handle ~= false
	tool.Grip = CFrame.new()
	if spec.textureId then
		tool.TextureId = spec.textureId
	end

	local model = Instance.new("Model")
	model.Name = spec.modelName or spec.name
	model.Parent = tool

	local builder = Parts.new(model, nil)
	local bodyAttach = builder:rootPart("BodyAttach", CFrame.new(), Vector3.new(0.2, 0.2, 0.2))
	model.PrimaryPart = bodyAttach
	builder.root = bodyAttach

	local handle
	if spec.handle ~= false then
		local hb = Parts.new(tool, nil)
		handle = hb:rootPart("Handle", CFrame.new(), spec.handleSize or Vector3.new(0.4, 1.2, 0.4))
		-- Handle is the engine's grip anchor and the pickup trigger
		handle.CanTouch = true
		Parts.weldConstraint("StowWeld", handle, bodyAttach, handle)
	end

	for key, value in spec.attributes or {} do
		tool:SetAttribute(key, value)
	end

	return tool, model, bodyAttach, builder, handle
end

-- Describe how a model is rigged onto a character (read by WeaponCore.Rig).
-- offset: the model's pose relative to the character attachment
function ToolKit.setRig(root, limb, attachment, offset)
	root:SetAttribute("RigLimb", limb)
	root:SetAttribute("RigAttachment", attachment)
	root:SetAttribute("RigOffset", offset or CFrame.new())
end

-- Where the model is worn while the tool sits in the backpack.
function ToolKit.setHolster(root, limb, attachment, offset)
	root:SetAttribute("HolsterLimb", limb)
	root:SetAttribute("HolsterAttachment", attachment)
	root:SetAttribute("HolsterOffset", offset or CFrame.new())
end

function ToolKit.sound(parent, name, soundId, props)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = soundId
	s.Volume = props and props.volume or 0.6
	s.PlaybackSpeed = props and props.speed or 1
	s.RollOffMaxDistance = props and props.maxDistance or 120
	if props and props.looped then
		s.Looped = true
	end
	s.Parent = parent
	return s
end

function ToolKit.trail(root, name, base, tip, color0, color1)
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "Base"
	a0.Position = base
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "Tip"
	a1.Position = tip
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.LightEmission = 0.6
	trail.FaceCamera = false
	trail.Color = roblox.ColorSequence.new(color0, color1 or color0)
	trail.Transparency = roblox.NumberSequence.new({
		roblox.NumberSequenceKeypoint.new(0, 0.35),
		roblox.NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = root
	return trail
end

function ToolKit.light(parent, name, color, brightness, range)
	local l = Instance.new("PointLight")
	l.Name = name
	l.Color = color
	l.Brightness = brightness or 1
	l.Range = range or 6
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Embed WeaponCore + the weapon's Server/Client scripts + Remote.
function ToolKit.addScripts(tool, scriptName)
	if ToolKit.skipScripts then
		return
	end
	local core = moduleFromDir("WeaponCore", RUNTIME .. "/WeaponCore")
	core.Parent = tool

	local server = Instance.new("Script")
	server.Name = "Server"
	server.Source = readSource(RUNTIME .. "/weapons/" .. scriptName .. ".server.luau")
	server.Parent = tool
	table.insert(ToolKit.sources, { inst = server, path = RUNTIME .. "/weapons/" .. scriptName .. ".server.luau" })

	local client = Instance.new("LocalScript")
	client.Name = "Client"
	client.Source = readSource(RUNTIME .. "/weapons/" .. scriptName .. ".client.luau")
	client.Parent = tool
	table.insert(ToolKit.sources, { inst = client, path = RUNTIME .. "/weapons/" .. scriptName .. ".client.luau" })

	local remote = Instance.new("RemoteEvent")
	remote.Name = "Remote"
	remote.Parent = tool
end

-- Sanity checks run on every built tool.
function ToolKit.validate(tool)
	local problems = {}
	-- Lune hands out fresh userdata per property read, so compare with == rather
	-- than using instances as table keys.
	local joints = {}
	for _, d in tool:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Weld") then
			if d.Part0 == nil or d.Part1 == nil then
				table.insert(problems, "joint without parts: " .. d:GetFullName())
			else
				table.insert(joints, d)
			end
		end
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Anchored then
				table.insert(problems, "anchored part: " .. d:GetFullName())
			end
			local joined = false
			for _, j in joints do
				if j.Part0 == d or j.Part1 == d then
					joined = true
					break
				end
			end
			if not joined and d:FindFirstAncestor("ProjectileTemplates") == nil then
				table.insert(problems, "unjoined part: " .. d:GetFullName())
			end
		end
	end
	-- a Motor6D-driven part must not also be welded to something (it would fight the motor)
	for _, j in joints do
		if j:IsA("Motor6D") then
			for _, w in joints do
				if w:IsA("WeldConstraint") and w.Part1 == j.Part1 and w.Name ~= "StowWeld" then
					table.insert(problems, "motor part is also welded: " .. j.Part1:GetFullName())
				end
			end
		end
	end
	-- rig roots may only be stow-welded (to the Handle)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RigLimb") then
			for _, w in joints do
				if w:IsA("WeldConstraint") and w.Part1 == d and w.Name ~= "StowWeld" then
					table.insert(problems, "rig root is welded: " .. d:GetFullName())
				end
			end
		end
	end
	if #problems > 0 then
		error(tool.Name .. " failed validation:\n  " .. table.concat(problems, "\n  "))
	end
end

return ToolKit
