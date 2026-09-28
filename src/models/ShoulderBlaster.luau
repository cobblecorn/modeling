--[[
	Shoulder Blaster: a pauldron-mounted energy cannon that tracks your aim.

	Rig (Motor6Ds):
	  BodyAttach (pauldron, joined to UpperTorso at RightCollarAttachment)
	  └─ YawBase      turns left/right   (Motor6D "Yaw")
	      └─ Cannon   tilts up/down      (Motor6D "Pitch")
	          └─ Barrel  kicks back on fire (Motor6D "Recoil")
	Muzzle attachment sits on the Barrel tip.
]]
local roblox = require("@lune/roblox")
local ToolKit = require("../builder/ToolKit")
local Parts = require("../builder/Parts")
local C = require("./Palette")

local CFrame, Vector3, Instance, Color3 = roblox.CFrame, roblox.Vector3, roblox.Instance, roblox.Color3
local V = Vector3.new

local TX, TZ = 0.1, 0.2 -- turret position on the pauldron
local PIVOT_Y = 0.84

local function zcyl(b, name, x, y, z0, z1, dia, style)
	return b:cylBetween(name, V(x, y, z0), V(x, y, z1), dia, style)
end

local function projectileTemplates(tool)
	local folder = Instance.new("Folder")
	folder.Name = "ProjectileTemplates"
	folder.Parent = tool

	local energy = Color3.fromRGB(64, 210, 255)

	local bolt = Instance.new("Model")
	bolt.Name = "Bolt"
	bolt.Parent = folder
	local base = CFrame.new(0, 0, 6)
	local bb = Parts.new(bolt, nil)
	local core = bb:ellipsoid("BoltCore", V(0.22, 0.22, 1.1), base, Parts.style(170, 240, 255, "Neon"))
	core.CastShadow = false
	bolt.PrimaryPart = core
	bb.root = core
	local glow = bb:ellipsoid("Glow", V(0.5, 0.5, 1.6), base, C.Energy)
	glow.Transparency = 0.6
	glow.CastShadow = false
	ToolKit.light(core, "Light", energy, 2, 8)
	ToolKit.trail(core, "FlightTrail", V(0, 0.09, 0.4), V(0, -0.09, 0.4), energy)
	bb:weld()

	local charged = Instance.new("Model")
	charged.Name = "ChargedBolt"
	charged.Parent = folder
	local cbase = CFrame.new(0, 0, 9)
	local cb = Parts.new(charged, nil)
	local ccore = cb:ball("Core", 0.9, cbase.Position, Parts.style(210, 250, 255, "Neon"))
	ccore.CastShadow = false
	charged.PrimaryPart = ccore
	cb.root = ccore
	local cglow = cb:ball("Glow", 1.6, cbase.Position, C.Energy)
	cglow.Transparency = 0.55
	cglow.CastShadow = false
	ToolKit.light(ccore, "Light", energy, 4, 16)
	local trail = ToolKit.trail(ccore, "FlightTrail", V(0, 0.4, 0), V(0, -0.4, 0), energy)
	trail.Lifetime = 0.3
	cb:weld()
end

return function()
	local tool, model, root, b = ToolKit.newTool({
		name = "ShoulderBlaster",
		toolTip = "Hold click: rapid fire  |  Hold Q / Right-click: charge a blast, release to fire",
		script = "ShoulderBlaster",
		handle = false,
		attributes = {
			Damage = 12,
			FireRate = 0.2,
			BoltSpeed = 240,
			Range = 600,
			ChargeTime = 1.2,
			ChargedDamage = 55,
			ChargedRadius = 10,
			ChargedCooldown = 5,
			TurnSpeed = 540,
			YawLeft = 25,
			YawRight = 100,
			PitchUp = 70,
			PitchDown = 35,
			FriendlyFire = false,
			ShowHolstered = true,
			AnimEquip = "",
		},
	})

	-- Pauldron + harness (BodyAttach) ------------------------------------------
	b:block("Pauldron", V(1.25, 0.2, 1.2), CFrame.new(0.35, 0.12, 0) * CFrame.Angles(0, 0, math.rad(-12)), C.Armor)
	for _, z in { 0.6, -0.6 } do
		b:block("PauldronTrim", V(1.25, 0.12, 0.07), CFrame.new(0.35, 0.12, z) * CFrame.Angles(0, 0, math.rad(-12)), C.Paint)
	end
	b:block("Lame", V(0.7, 0.14, 1.12), CFrame.new(0.98, -0.16, 0) * CFrame.Angles(0, 0, math.rad(-38)), C.Armor)
	b:block("Lame", V(0.5, 0.12, 1.02), CFrame.new(1.16, -0.46, 0) * CFrame.Angles(0, 0, math.rad(-62)), C.ArmorLight)
	for _, z in { 0.53, -0.53 } do
		b:block("Strap", V(0.26, 1.0, 0.05), CFrame.new(-0.05, -0.42, z) * CFrame.Angles(0, 0, math.rad(8)), C.LeatherDark)
		b:block("Buckle", V(0.3, 0.16, 0.06), CFrame.new(-0.02, -0.62, z * 1.02), C.Gold)
	end
	for _, x in { -0.1, 0.55, 0.85 } do
		for _, z in { 0.42, -0.42 } do
			b:ball("Rivet", 0.09, V(x, 0.24 - (x - 0.1) * 0.21, z), C.SteelBright)
		end
	end
	b:cylinder("TurretMount", 0.16, 0.62, CFrame.new(TX, 0.32, TZ) * CFrame.Angles(0, 0, math.pi / 2), C.Iron)

	-- Yaw ---------------------------------------------------------------------
	local yaw = b:sub(model, false):rootPart("YawBase", CFrame.new(TX, 0.42, TZ))
	local yb = b:sub(model, yaw)
	yb:cylinder("Turntable", 0.1, 0.56, CFrame.new(TX, 0.43, TZ) * CFrame.Angles(0, 0, math.pi / 2), C.Blackened)
	for _, s in { 1, -1 } do
		yb:block("Cheek", V(0.08, 0.52, 0.5), CFrame.new(TX + s * 0.26, 0.68, TZ), C.Armor)
		yb:block("CheekStripe", V(0.085, 0.08, 0.5), CFrame.new(TX + s * 0.26, 0.56, TZ), C.Paint)
	end
	yb:strut("Piston", V(TX + 0.3, 0.48, TZ + 0.2), V(TX + 0.3, 0.8, TZ - 0.12), 0.06, 0.06, C.SteelBright, V(1, 0, 0))
	Parts.motor("Yaw", root, yaw)

	-- Pitch (cannon body) -----------------------------------------------------------
	local cannon = b:sub(model, false):rootPart("Cannon", CFrame.new(TX, PIVOT_Y, TZ))
	local cbd = b:sub(model, cannon)
	cbd:cylinder("Axle", 0.66, 0.16, CFrame.new(TX, PIVOT_Y, TZ), C.SteelDark)
	cbd:block("Housing", V(0.4, 0.42, 1.0), CFrame.new(TX, PIVOT_Y + 0.02, TZ - 0.15), C.Armor)
	cbd:wedge("HousingNose", V(0.4, 0.14, 0.22), CFrame.new(TX, PIVOT_Y + 0.3, TZ - 0.54) * CFrame.Angles(0, math.pi, 0), C.Armor)
	cbd:block("HousingTop", V(0.4, 0.14, 0.78), CFrame.new(TX, PIVOT_Y + 0.3, TZ - 0.04), C.Armor)
	for i = 0, 2 do
		cbd:block("Fin", V(0.46, 0.05, 0.08), CFrame.new(TX, PIVOT_Y + 0.4, TZ + 0.2 - i * 0.2), C.SteelDark)
	end
	cbd:block("Stripe", V(0.41, 0.06, 0.9), CFrame.new(TX, PIVOT_Y - 0.08, TZ - 0.15), C.Paint)
	cbd:block("RearVent", V(0.32, 0.3, 0.08), CFrame.new(TX, PIVOT_Y + 0.04, TZ + 0.38), C.Blackened)
	for _, y in { -0.06, 0.04, 0.14 } do
		cbd:block("VentGlow", V(0.26, 0.03, 0.02), CFrame.new(TX, PIVOT_Y + y, TZ + 0.425), C.Energy)
	end
	local cell = zcyl(cbd, "EnergyCell", TX + 0.28, PIVOT_Y + 0.02, TZ + 0.2, TZ - 0.45, 0.2, C.Energy)
	zcyl(cbd, "CellCap", TX + 0.28, PIVOT_Y + 0.02, TZ + 0.26, TZ + 0.16, 0.24, C.Iron)
	zcyl(cbd, "CellCap", TX + 0.28, PIVOT_Y + 0.02, TZ - 0.41, TZ - 0.51, 0.24, C.Iron)
	ToolKit.light(cell, "CellLight", Color3.fromRGB(64, 210, 255), 0.8, 5)
	cbd:block("Sight", V(0.06, 0.14, 0.3), CFrame.new(TX - 0.14, PIVOT_Y + 0.43, TZ - 0.3), C.Blackened)
	cbd:block("SightLens", V(0.07, 0.06, 0.02), CFrame.new(TX - 0.14, PIVOT_Y + 0.45, TZ - 0.46), C.GemRed)
	Parts.motor("Pitch", yaw, cannon)

	-- Barrel (recoils) ------------------------------------------------------------
	local barrelZ = TZ - 0.65
	local barrel = b:sub(model, false):rootPart("Barrel", CFrame.new(TX, PIVOT_Y, barrelZ))
	local bb = b:sub(model, barrel)
	cbd:block("Shroud", V(0.32, 0.32, 0.4), CFrame.new(TX, PIVOT_Y, barrelZ - 0.15), C.SteelDark)
	zcyl(bb, "BarrelTube", TX, PIVOT_Y, barrelZ + 0.1, barrelZ - 1.1, 0.2, C.SteelDark)
	for i = 0, 2 do
		local z = barrelZ - 0.5 - i * 0.16
		zcyl(bb, "Coil", TX, PIVOT_Y, z + 0.03, z - 0.03, 0.3, C.Energy)
	end
	zcyl(bb, "Muzzle", TX, PIVOT_Y, barrelZ - 1.05, barrelZ - 1.27, 0.32, C.Blackened)
	zcyl(bb, "MuzzleGlow", TX, PIVOT_Y, barrelZ - 1.27, barrelZ - 1.285, 0.17, C.Energy)
	local muzzleCf = CFrame.new(TX, PIVOT_Y, barrelZ - 1.32)
	local muzzle = b:attachment("Muzzle", barrel, muzzleCf)
	local flash = ToolKit.light(muzzle, "Flash", Color3.fromRGB(120, 230, 255), 5, 12)
	flash.Enabled = false
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "MuzzleSparks"
	sparks.Enabled = false
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = roblox.ColorSequence.new(Color3.fromRGB(130, 230, 255))
	sparks.LightEmission = 1
	sparks.Lifetime = roblox.NumberRange.new(0.08, 0.18)
	sparks.Speed = roblox.NumberRange.new(8, 16)
	sparks.SpreadAngle = roblox.Vector2.new(25, 25)
	sparks.Size = roblox.NumberSequence.new(0.35, 0)
	sparks.EmissionDirection = roblox.Enum.NormalId.Front
	sparks.Parent = muzzle
	local charge = sparks:Clone()
	charge.Name = "ChargeParticles"
	charge.Speed = roblox.NumberRange.new(-4, -2)
	charge.Lifetime = roblox.NumberRange.new(0.2, 0.35)
	charge.Rate = 40
	charge.SpreadAngle = roblox.Vector2.new(180, 180)
	charge.Parent = muzzle
	local recoil = Parts.motor("Recoil", cannon, barrel)
	recoil:SetAttribute("PoseRecoil", CFrame.new(0, 0, 0.3))

	-- Rig: always mounted on the right shoulder -------------------------------------
	ToolKit.setRig(root, "UpperTorso", "RightCollarAttachment", CFrame.new())
	ToolKit.setHolster(root, "UpperTorso", "RightCollarAttachment", CFrame.new())

	ToolKit.sound(root, "Fire", "rbxasset://sounds/electronicpingshort.wav", { volume = 0.5, speed = 1.2 })
	ToolKit.sound(root, "ChargedFire", "rbxasset://sounds/Rocket shot.wav", { volume = 0.8 })
	ToolKit.sound(root, "Charging", "rbxasset://sounds/electronicpingshort.wav", { volume = 0.3, speed = 0.5, looped = true })
	ToolKit.sound(root, "Impact", "rbxasset://sounds/paintball.wav", { volume = 0.6 })

	projectileTemplates(tool)

	b:weld()
	ToolKit.addScripts(tool, "ShoulderBlaster")
	return tool
end
