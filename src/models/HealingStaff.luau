--[[
	Wayfarer's Staff: a support staff. Weathered wood, bronze fittings and a
	jade crystal floating in a bronze claw: arcane and natural rather than holy
	or sinister.

	Rig: BodyAttach (the staff, in the right hand)
	     └─ Crystal   Motor6D; the crystal bobs and flares when casting
	The "Focus" attachment in the crystal is where heal beams start.
]]
local roblox = require("@lune/roblox")
local ToolKit = require("../builder/ToolKit")
local Parts = require("../builder/Parts")
local C = require("./Palette")

local CFrame, Vector3, Instance, Color3 = roblox.CFrame, roblox.Vector3, roblox.Instance, roblox.Color3
local V = Vector3.new

local JADE = Parts.style(96, 226, 184, "Neon")
local JADE_DEEP = Parts.style(40, 150, 120, "Glass", { transparency = 0.15 })
local WOOD = Parts.style(112, 84, 58, "Wood")
local BRONZE = C.Bronze
local BRONZE_DARK = Parts.style(118, 78, 46, "Metal")
local CORD = Parts.style(150, 120, 86, "Fabric")

local HEAD_Y = 3.0 -- top of the shaft
local CRYSTAL_Y = 3.62

return function()
	local tool, model, root, b = ToolKit.newTool({
		name = "HealingStaff",
		toolTip = "Click / hold: Mend (heal an ally you aim at, stings enemies)  |  Q / Right-click: Renewal pulse (heals everyone around you)",
		script = "HealingStaff",
		handleSize = V(0.35, 1.2, 0.35),
		attributes = {
			HealAmount = 12,
			Cooldown = 0.5,
			Range = 90,
			AimAssist = 1.5, -- radius of the aim sphere, so moving allies are easy to hit
			EnemyDamage = 8,
			PulseHeal = 30,
			PulseRadius = 18,
			PulseCooldown = 10,
			FriendlyFire = false,
			ShowHolstered = true,
			AnimIdle = "",
			AnimCast = "",
			AnimPulse = "",
		},
	})

	-- Shaft ------------------------------------------------------------------
	b:ring("Shaft", 0.65, 4.7, 0.2, WOOD)
	-- a knot and a slight gnarl so it reads as a branch, not a pole
	b:ellipsoid("Knot", V(0.26, 0.34, 0.24), CFrame.new(0.03, 1.55, 0.02), WOOD)
	b:ellipsoid("Knot", V(0.24, 0.3, 0.26), CFrame.new(-0.03, -1.05, -0.02), WOOD)
	b:ring("Grip", 0, 1.1, 0.25, C.Leather)
	for i, y in { -0.42, -0.22, -0.02, 0.18, 0.38 } do
		b:cylinder("GripWrap", 0.05, 0.27, CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(i * 35), math.rad(90 - 14)), C.LeatherDark)
	end
	for _, y in { -0.6, 0.6, 2.2 } do
		b:ring("Band", y, 0.08, 0.26, BRONZE)
	end
	-- butt: bronze cap and a rounded foot
	b:ring("ButtCap", -1.62, 0.16, 0.25, BRONZE_DARK)
	b:ball("ButtFoot", 0.24, V(0, -1.72, 0), BRONZE)

	-- Head: collar + four curling prongs --------------------------------------
	b:ring("Collar", HEAD_Y - 0.05, 0.2, 0.3, BRONZE)
	b:ring("CollarLip", HEAD_Y + 0.07, 0.06, 0.36, BRONZE_DARK)
	local PRONG = { { 0.1, 0.1 }, { 0.33, 0.38 }, { 0.41, 0.66 }, { 0.34, 0.94 }, { 0.16, 1.12 } } -- {radius, height above HEAD_Y}
	for k = 0, 3 do
		local ang = math.rad(45 + k * 90)
		local dir = V(math.cos(ang), 0, math.sin(ang))
		for i = 1, #PRONG - 1 do
			local p, q = PRONG[i], PRONG[i + 1]
			local a = dir * p[1] + V(0, HEAD_Y + p[2], 0)
			local c = dir * q[1] + V(0, HEAD_Y + q[2], 0)
			b:strut("Prong", a - (c - a).Unit * 0.02, c + (c - a).Unit * 0.02, 0.085, 0.07, BRONZE, dir)
		end
		local tip = PRONG[#PRONG]
		b:ball("ProngTip", 0.09, dir * tip[1] + V(0, HEAD_Y + tip[2], 0), BRONZE_DARK)
	end
	-- a cord with two beads hanging from the collar
	b:cylBetween("Cord", V(0.15, HEAD_Y - 0.05, 0.05), V(0.2, HEAD_Y - 0.55, 0.08), 0.03, CORD)
	b:ball("Bead", 0.09, V(0.2, HEAD_Y - 0.58, 0.08), JADE_DEEP)
	b:cylBetween("Cord", V(0.2, HEAD_Y - 0.62, 0.08), V(0.22, HEAD_Y - 0.8, 0.09), 0.03, CORD)
	b:ball("Bead", 0.12, V(0.22, HEAD_Y - 0.86, 0.09), BRONZE)

	-- Crystal (its own rig root so it can float and spin) ------------------------
	local crystal = b:sub(model, false):rootPart("Crystal", CFrame.new(0, CRYSTAL_Y, 0))
	local cb = b:sub(model, crystal)
	local top, bottom = V(0, CRYSTAL_Y + 0.46, 0), V(0, CRYSTAL_Y - 0.4, 0)
	local ring = {}
	for i = 0, 5 do
		local ang = math.rad(i * 60)
		ring[i + 1] = V(math.cos(ang) * 0.21, CRYSTAL_Y + 0.04, math.sin(ang) * 0.21)
	end
	local inside = V(0, CRYSTAL_Y, 0)
	for i = 1, 6 do
		local a, c = ring[i], ring[i % 6 + 1]
		cb:triangle("Crystal", a, c, top, if i % 2 == 0 then JADE else JADE_DEEP, 0.02, inside)
		cb:triangle("Crystal", c, a, bottom, if i % 2 == 1 then JADE else JADE_DEEP, 0.02, inside)
	end
	cb:ball("CrystalCore", 0.26, V(0, CRYSTAL_Y + 0.02, 0), JADE)
	local focus = Instance.new("Attachment")
	focus.Name = "Focus"
	focus.Parent = crystal
	local light = ToolKit.light(crystal, "Glow", Color3.fromRGB(110, 235, 190), 1.2, 8)
	light.Parent = focus
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = roblox.ColorSequence.new(Color3.fromRGB(150, 255, 210))
	motes.LightEmission = 1
	motes.Rate = 6
	motes.Lifetime = roblox.NumberRange.new(0.8, 1.4)
	motes.Speed = roblox.NumberRange.new(0.3, 0.8)
	motes.SpreadAngle = roblox.Vector2.new(180, 180)
	motes.Size = roblox.NumberSequence.new(0.12, 0)
	motes.Parent = focus
	local crystalJoint = Parts.motor("Crystal", root, crystal)
	crystalJoint:SetAttribute("PoseCast", CFrame.new(0, 0.12, 0) * CFrame.Angles(0, math.rad(60), 0))

	-- Rig: right hand; worn diagonally across the back, crystal over the left shoulder
	ToolKit.setRig(root, "RightHand", "RightGripAttachment", CFrame.new())
	ToolKit.setHolster(root, "UpperTorso", "BodyBackAttachment", CFrame.new(0.5, -1.35, 0.5) * Parts.basis(V(0, 0, 1), V(-0.3, 0.954, 0)))

	local handle = tool:FindFirstChild("Handle")
	ToolKit.sound(handle, "Cast", "rbxasset://sounds/electronicpingshort.wav", { volume = 0.45, speed = 1.6 })
	ToolKit.sound(handle, "Pulse", "rbxasset://sounds/electronicpingshort.wav", { volume = 0.7, speed = 0.6 })
	ToolKit.sound(handle, "Equip", "rbxasset://sounds/unsheath.wav", { volume = 0.4, speed = 0.7 })

	b:weld()
	ToolKit.addScripts(tool, "HealingStaff")
	return tool
end
