-- Knight's Longsword: gilded cross-guard, leather grip, ridged steel blade.
local roblox = require("@lune/roblox")
local ToolKit = require("../builder/ToolKit")
local Parts = require("../builder/Parts")
local C = require("./Palette")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local V = Vector3.new

return function()
	local tool, model, root, b = ToolKit.newTool({
		name = "Longsword",
		toolTip = "Click: slash combo (3rd hit lunges)  |  Q / Right-click: block",
		script = "Sword",
		handleSize = V(0.4, 1.4, 0.4),
		attributes = {
			Damage = 22,
			LungeDamage = 34,
			Cooldown = 0.45,
			ComboWindow = 0.7,
			Range = 6.5,
			BlockReduction = 0.7,
			BlockWalkSpeed = 8,
			FriendlyFire = false,
			ShowHolstered = true,
			AnimIdle = "",
			AnimSlash1 = "",
			AnimSlash2 = "",
			AnimLunge = "",
			AnimBlock = "",
		},
	})

	-- Grip -------------------------------------------------------------------
	b:ring("Grip", 0, 1.4, 0.26, C.Leather)
	for i, y in { -0.52, -0.3, -0.08, 0.14, 0.36 } do
		b:cylinder(
			"GripWrap",
			0.07,
			0.29,
			CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(i * 25), math.rad(90 - 12)),
			C.Wrap
		)
	end
	b:ring("FerruleTop", 0.66, 0.1, 0.32, C.GoldDark)
	b:ring("FerruleBottom", -0.66, 0.1, 0.32, C.GoldDark)

	-- Pommel -----------------------------------------------------------------
	b:ring("PommelNeck", -0.76, 0.12, 0.2, C.Gold)
	b:ellipsoid("Pommel", V(0.3, 0.36, 0.42), CFrame.new(0, -0.95, 0), C.Gold)
	b:ring("PommelCap", -1.14, 0.08, 0.16, C.GoldDark)
	b:ball("PommelGem", 0.13, V(0.14, -0.95, 0), C.GemRed)
	b:ball("PommelGem", 0.13, V(-0.14, -0.95, 0), C.GemRed)

	-- Cross-guard ------------------------------------------------------------
	b:block("GuardCenter", V(0.34, 0.3, 0.46), CFrame.new(0, 0.84, 0), C.Gold)
	b:wedge("GuardLanget", V(0.3, 0.22, 0.2), CFrame.new(0, 1.1, 0.1), C.Gold)
	b:wedge("GuardLanget", V(0.3, 0.22, 0.2), CFrame.new(0, 1.1, -0.1) * CFrame.Angles(0, math.pi, 0), C.Gold)
	for _, s in { 1, -1 } do
		b:strut("GuardArm", V(0, 0.8, s * 0.2), V(0, 0.9, s * 0.78), 0.2, 0.17, C.Gold, V(0, 1, 0))
		b:strut("GuardTip", V(0, 0.9, s * 0.76), V(0, 1.06, s * 0.92), 0.17, 0.14, C.GoldDark, V(0, 1, 0))
		b:ball("GuardFinial", 0.2, V(0, 1.08, s * 0.94), C.Gold)
	end
	b:ball("GuardGem", 0.17, V(0.15, 0.84, 0), C.GemRed)
	b:ball("GuardGem", 0.17, V(-0.15, 0.84, 0), C.GemRed)

	-- Blade ------------------------------------------------------------------
	b:blade("Blade", {
		base = 0.98,
		length = 2.55,
		tip = 0.55,
		width0 = 0.22,
		width1 = 0.17,
		ridge = 0.13,
		edge = 0.025,
	}, C.Steel, C.SteelBright)
	b:block("Ricasso", V(0.15, 0.22, 0.34), CFrame.new(0, 1.07, 0), C.Steel)
	b:block("Fuller", V(0.135, 1.7, 0.06), CFrame.new(0, 2.1, 0), C.SteelDark)

	-- Effects ----------------------------------------------------------------
	ToolKit.trail(root, "SwingTrail", V(0, 1.3, 0), V(0, 3.9, 0), roblox.Color3.fromRGB(235, 240, 255))

	-- Rig: held in the right hand, worn across the back ------------------------
	ToolKit.setRig(root, "RightHand", "RightGripAttachment", CFrame.new())
	local backRot = Parts.basis(V(0, 0, 1), V(-0.45, -0.89, 0))
	ToolKit.setHolster(root, "UpperTorso", "BodyBackAttachment", CFrame.new(0.55, 1.05, 0.28) * backRot)

	local handle = tool:FindFirstChild("Handle")
	ToolKit.sound(handle, "Slash", "rbxasset://sounds/swordslash.wav", { volume = 0.7 })
	ToolKit.sound(handle, "Lunge", "rbxasset://sounds/swordlunge.wav", { volume = 0.7 })
	ToolKit.sound(handle, "Equip", "rbxasset://sounds/unsheath.wav", { volume = 0.6 })
	ToolKit.sound(handle, "Block", "rbxasset://sounds/unsheath.wav", { volume = 0.7, speed = 1.6 })

	b:weld()
	ToolKit.addScripts(tool, "Sword")
	return tool
end
