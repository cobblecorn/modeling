-- Twin Shadow Daggers: a matched pair, one per hand, blackened hilts with void gems.
local roblox = require("@lune/roblox")
local ToolKit = require("../builder/ToolKit")
local Parts = require("../builder/Parts")
local C = require("./Palette")

local CFrame, Vector3, Instance = roblox.CFrame, roblox.Vector3, roblox.Instance
local V = Vector3.new

-- Builds one dagger around `frame` (the grip point) with builder `b`.
local function dagger(b, frame)
	local function at(x, y, z)
		return frame * V(x, y, z)
	end
	local function cf(x, y, z)
		return frame * CFrame.new(x, y, z)
	end
	local function ringAt(name, y, len, dia, style)
		b:cylinder(name, len, dia, cf(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), style)
	end

	-- grip
	ringAt("Grip", 0, 1.0, 0.2, C.LeatherDark)
	for i, y in { -0.33, -0.12, 0.09, 0.3 } do
		b:cylinder("GripWrap", 0.06, 0.225, cf(0, y, 0) * CFrame.Angles(0, math.rad(i * 40), math.rad(90 - 15)), C.LeatherRed)
	end
	ringAt("Ferrule", -0.47, 0.08, 0.24, C.Blackened)
	-- pommel
	b:ellipsoid("Pommel", V(0.2, 0.24, 0.26), cf(0, -0.6, 0), C.Blackened)
	b:ball("PommelGem", 0.1, at(0, -0.74, 0), C.GemViolet)
	-- guard: a swept bar with points curling toward the blade
	b:block("Guard", V(0.24, 0.12, 0.62), cf(0, 0.56, 0), C.Blackened)
	for _, s in { 1, -1 } do
		b:strut("GuardHook", at(0, 0.56, s * 0.28), at(0, 0.8, s * 0.42), 0.14, 0.1, C.Blackened, frame.RightVector)
		b:ball("GuardTip", 0.1, at(0, 0.82, s * 0.43), C.Blackened)
	end
	b:ball("GuardGem", 0.14, at(0.09, 0.56, 0), C.GemViolet)
	b:ball("GuardGem", 0.14, at(-0.09, 0.56, 0), C.GemViolet)
	-- blade
	b:blade("Blade", {
		base = 0.62,
		length = 1.2,
		tip = 0.5,
		width0 = 0.16,
		width1 = 0.12,
		ridge = 0.09,
		edge = 0.02,
		frame = frame,
	}, C.Steel, C.SteelBright)
	b:block("Fuller", V(0.095, 0.95, 0.035), cf(0, 1.2, 0), C.GemViolet)
end

return function()
	local tool, model, root, b = ToolKit.newTool({
		name = "TwinDaggers",
		toolTip = "Click: rapid alternating stabs (x2 from behind)  |  Q / Right-click: throw a dagger",
		script = "TwinDaggers",
		handleSize = V(0.35, 1.0, 0.35),
		modelName = "MainDagger",
		attributes = {
			Damage = 12,
			Cooldown = 0.28,
			Range = 5.5,
			BackstabMultiplier = 2,
			ThrowDamage = 22,
			ThrowSpeed = 150,
			ThrowCooldown = 3,
			FriendlyFire = false,
			ShowHolstered = true,
			AnimIdle = "",
			AnimStabRight = "",
			AnimStabLeft = "",
			AnimThrow = "",
		},
	})

	dagger(b, CFrame.new())
	ToolKit.trail(root, "SwingTrail", V(0, 0.8, 0), V(0, 2.2, 0), roblox.Color3.fromRGB(190, 140, 255))
	ToolKit.setRig(root, "RightHand", "RightGripAttachment", CFrame.new())
	-- worn horizontally across the small of the back
	ToolKit.setHolster(
		root,
		"LowerTorso",
		"WaistBackAttachment",
		CFrame.new(0.55, 0.12, 0.2) * Parts.basis(V(0, 0, 1), V(-1, 0.18, 0))
	)

	-- Off-hand dagger: its own model + rig root so it can live in the left hand.
	local offModel = Instance.new("Model")
	offModel.Name = "OffhandDagger"
	offModel.Parent = tool
	local stowFrame = CFrame.new(0.5, 0, 0)
	local ob = b:sub(offModel, false)
	local offRoot = ob:rootPart("OffhandAttach", stowFrame)
	offModel.PrimaryPart = offRoot
	ob.root = offRoot
	dagger(ob, stowFrame)
	ToolKit.trail(offRoot, "SwingTrail", V(0, 0.8, 0), V(0, 2.2, 0), roblox.Color3.fromRGB(190, 140, 255))
	ToolKit.setRig(offRoot, "LeftHand", "LeftGripAttachment", CFrame.new())
	ToolKit.setHolster(
		offRoot,
		"LowerTorso",
		"WaistBackAttachment",
		CFrame.new(-0.55, -0.1, 0.32) * Parts.basis(V(0, 0, 1), V(1, 0.18, 0))
	)
	-- keeps the pair together while the tool is not equipped
	Parts.weldConstraint("StowWeld", tool:FindFirstChild("Handle"), offRoot, offRoot)

	local handle = tool:FindFirstChild("Handle")
	ToolKit.sound(handle, "Stab", "rbxasset://sounds/swordslash.wav", { volume = 0.55, speed = 1.35 })
	ToolKit.sound(handle, "Throw", "rbxasset://sounds/swordlunge.wav", { volume = 0.6, speed = 1.4 })
	ToolKit.sound(handle, "Equip", "rbxasset://sounds/unsheath.wav", { volume = 0.5, speed = 1.3 })

	b:weld()
	ToolKit.addScripts(tool, "TwinDaggers")
	return tool
end
