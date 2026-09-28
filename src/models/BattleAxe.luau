-- Warlord's Battle Axe: bearded crescent blade, back spike, iron-banded haft.
local roblox = require("@lune/roblox")
local ToolKit = require("../builder/ToolKit")
local Parts = require("../builder/Parts")
local C = require("./Palette")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local V = Vector3.new

-- four-sided spike from a rectangular base to an apex
local function spike(b, name, apex, baseCenter, halfA, halfB, style)
	local axis = (apex - baseCenter).Unit
	local frame = Parts.upAlong(baseCenter, axis)
	local ra, rb = frame.RightVector * halfA, frame.LookVector * -halfB
	local corners = {
		baseCenter + ra + rb,
		baseCenter - ra + rb,
		baseCenter - ra - rb,
		baseCenter + ra - rb,
	}
	local inside = (apex + baseCenter) / 2
	for i = 1, 4 do
		b:triangle(name, corners[i], corners[i % 4 + 1], apex, style, 0.03, inside)
	end
end

return function()
	local tool, model, root, b = ToolKit.newTool({
		name = "BattleAxe",
		toolTip = "Click: heavy chop  |  Q / Right-click: whirlwind spin",
		script = "BattleAxe",
		handleSize = V(0.4, 1.4, 0.4),
		attributes = {
			Damage = 38,
			Cooldown = 1.1,
			Range = 7.5,
			WhirlwindDamage = 24,
			WhirlwindRadius = 9,
			WhirlwindCooldown = 7,
			FriendlyFire = false,
			ShowHolstered = true,
			AnimIdle = "",
			AnimChop = "",
			AnimWhirlwind = "",
		},
	})

	-- Haft -------------------------------------------------------------------
	b:ring("Haft", 0.95, 4.7, 0.27, C.Wood)
	b:ring("GripWrap", 0, 1.3, 0.32, C.LeatherDark)
	for i, y in { -0.5, -0.25, 0, 0.25, 0.5 } do
		b:cylinder("GripLace", 0.06, 0.345, CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(i * 30), math.rad(90 - 14)), C.Leather)
	end
	for _, y in { -0.72, 0.72, 1.55, 2.05 } do
		b:ring("Band", y, 0.1, 0.33, C.Iron)
	end
	b:ring("ButtCap", -1.45, 0.14, 0.36, C.Iron)
	spike(b, "ButtSpike", V(0, -1.85, 0), V(0, -1.52, 0), 0.13, 0.13, C.SteelDark)

	-- Head -------------------------------------------------------------------
	b:block("Socket", V(0.44, 1.0, 0.52), CFrame.new(0, 2.8, 0), C.Blackened)
	b:block("SocketBand", V(0.5, 0.12, 0.58), CFrame.new(0, 3.24, 0), C.Iron)
	b:block("SocketBand", V(0.5, 0.12, 0.58), CFrame.new(0, 2.36, 0), C.Iron)
	for _, x in { 0.23, -0.23 } do
		for _, y in { 2.62, 2.98 } do
			b:ball("Rivet", 0.1, V(x, y, 0), C.Bronze)
		end
	end
	spike(b, "TopSpike", V(0, 3.95, 0), V(0, 3.3, 0), 0.15, 0.17, C.Steel)

	-- the blade faces forward (-Z); per-vertex thickness gives it a bevel
	b:taperedPlate("Blade", {
		{ 3.15, -0.25, 0.3 },
		{ 3.05, -0.55, 0.22 },
		{ 3.3, -0.95, 0.12 },
		{ 3.9, -1.35, 0.04 },
		{ 3.62, -1.62, 0.03 },
		{ 3.05, -1.8, 0.03 },
		{ 2.45, -1.8, 0.03 },
		{ 1.9, -1.64, 0.03 },
		{ 1.45, -1.32, 0.04 },
		{ 1.95, -0.95, 0.12 },
		{ 2.35, -0.55, 0.22 },
		{ 2.45, -0.25, 0.3 },
	}, C.Steel, { wallStyle = C.SteelDark })
	-- honed edge highlight
	for _, seg in { { V(0, 3.62, -1.62), V(0, 3.05, -1.8) }, { V(0, 3.05, -1.8), V(0, 2.45, -1.8) }, { V(0, 2.45, -1.8), V(0, 1.9, -1.64) } } do
		b:strut("Edge", seg[1], seg[2], 0.035, 0.06, C.SteelBright, V(0, 0, -1))
	end

	-- back spike (+Z)
	spike(b, "BackSpike", V(0, 2.62, 1.05), V(0, 2.8, 0.26), 0.14, 0.24, C.SteelDark)

	-- Effects / rig ----------------------------------------------------------
	ToolKit.trail(root, "SwingTrail", V(0, 1.7, -1.6), V(0, 3.7, -1.6), roblox.Color3.fromRGB(255, 214, 170))

	ToolKit.setRig(root, "RightHand", "RightGripAttachment", CFrame.new())
	-- worn on the back, head over the left shoulder, blade facing out
	local rot = Parts.basis(V(0, 0, -1), V(-0.45, 0.89, 0))
	ToolKit.setHolster(root, "UpperTorso", "BodyBackAttachment", CFrame.new(0.42, -0.95, 0.42) * rot)

	local handle = tool:FindFirstChild("Handle")
	ToolKit.sound(handle, "Chop", "rbxasset://sounds/swordslash.wav", { volume = 0.8, speed = 0.7 })
	ToolKit.sound(handle, "Whirlwind", "rbxasset://sounds/swordlunge.wav", { volume = 0.8, speed = 0.75 })
	ToolKit.sound(handle, "Equip", "rbxasset://sounds/unsheath.wav", { volume = 0.6, speed = 0.8 })

	b:weld()
	ToolKit.addScripts(tool, "BattleAxe")
	return tool
end
