--[[
	Loads the built .rbxm files back and checks they contain what the runtime
	expects. Run after building:  lune run tools/verify.luau
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local failures = 0
local function check(ok, message)
	if not ok then
		failures += 1
		print("  FAIL: " .. message)
	end
end

local EXPECT = {
	Longsword = { models = { "Longsword" }, sounds = { "Slash", "Lunge", "Equip", "Block" } },
	BattleAxe = { models = { "BattleAxe" }, sounds = { "Chop", "Whirlwind", "Equip" } },
	TwinDaggers = { models = { "MainDagger", "OffhandDagger" }, sounds = { "Stab", "Throw", "Equip" } },
	Longbow = { models = { "Longbow", "Quiver" }, sounds = { "Draw", "Release", "Equip" }, joints = { "Nock", "UpperLimb", "LowerLimb" } },
	HealingStaff = { models = { "HealingStaff" }, sounds = { "Cast", "Pulse", "Equip" }, joints = { "Crystal" } },
	ShoulderBlaster = { models = { "ShoulderBlaster" }, sounds = { "Fire", "ChargedFire", "Charging", "Impact" }, joints = { "Yaw", "Pitch", "Recoil" }, noHandle = true },
}

local function verifyTool(tool)
	local spec = EXPECT[tool.Name]
	print(tool.Name)
	check(spec ~= nil, "unexpected tool")
	if not spec then
		return
	end
	check(tool:IsA("Tool"), "not a Tool")
	check(tool.CanBeDropped == false, "CanBeDropped should be false")
	local handle = tool:FindFirstChild("Handle")
	if spec.noHandle then
		check(handle == nil and tool.RequiresHandle == false, "should have no Handle")
	else
		check(handle ~= nil and handle:IsA("BasePart"), "missing Handle")
	end
	for _, name in { "WeaponCore", "Server", "Client", "Remote" } do
		check(tool:FindFirstChild(name) ~= nil, "missing " .. name)
	end
	local core = tool:FindFirstChild("WeaponCore")
	for _, name in { "Util", "Rig", "Combat", "Projectile", "Effects", "Server", "Client" } do
		local m = core and core:FindFirstChild(name)
		check(m ~= nil and m:IsA("ModuleScript") and #m.Source > 100, "WeaponCore." .. name .. " missing or empty")
	end
	check(tool.Server:IsA("Script") and #tool.Server.Source > 100, "Server script empty")
	check(tool.Client:IsA("LocalScript") and #tool.Client.Source > 100, "Client script empty")
	for _, name in spec.models do
		local model = tool:FindFirstChild(name)
		check(model ~= nil and model:IsA("Model"), "missing model " .. name)
		if model then
			local root = model.PrimaryPart
			check(root ~= nil, name .. " has no PrimaryPart")
			if root then
				check(type(root:GetAttribute("RigLimb")) == "string", name .. " missing RigLimb")
				check(typeof(root:GetAttribute("RigOffset")) == "CFrame", name .. " missing RigOffset")
				check(type(root:GetAttribute("HolsterLimb")) == "string", name .. " missing HolsterLimb")
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					check(not d.Anchored, d:GetFullName() .. " is anchored")
					check(not d.CanCollide, d:GetFullName() .. " collides")
				end
			end
		end
	end
	for _, name in spec.sounds do
		local found = false
		for _, d in tool:GetDescendants() do
			if d:IsA("Sound") and d.Name == name then
				-- SoundId is stored as the newer AudioContent property; Lune only reads it back under that name
				local ok, content = pcall(function()
					return d.AudioContent
				end)
				found = ok and string.find(tostring(content), "rbxasset://", 1, true) ~= nil
			end
		end
		check(found, "missing sound " .. name)
	end
	for _, name in spec.joints or {} do
		local found = nil
		for _, d in tool:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == name then
				found = d
			end
		end
		check(found ~= nil and found.Part0 ~= nil and found.Part1 ~= nil, "missing joint " .. name)
		check(found ~= nil and typeof(found:GetAttribute("RestC0")) == "CFrame", "joint " .. name .. " missing RestC0")
	end
end

for name in EXPECT do
	local path = "dist/" .. name .. ".rbxm"
	local instances = roblox.deserializeModel(fs.readFile(path))
	check(#instances == 1, path .. " should contain exactly one Tool")
	verifyTool(instances[1])
end

local pack = roblox.deserializeModel(fs.readFile("dist/WeaponsPack.rbxm"))[1]
print("WeaponsPack")
check(pack:IsA("Folder"), "pack should be a Folder")
local tools = 0
for _, child in pack:GetChildren() do
	if child:IsA("Tool") then
		tools += 1
	end
end
check(tools == 6, "pack should contain 6 tools, found " .. tools)
check(pack:FindFirstChild("WeaponRigger") ~= nil, "pack missing WeaponRigger")

if failures > 0 then
	print(failures .. " problem(s)")
	error("verification failed")
end
print("all checks passed")
