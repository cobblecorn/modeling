--[[
	Ranger's Longbow + arrows + quiver.

	Rig (all Motor6Ds, so every piece can be keyframed in the Animation Editor):
	  BodyAttach (riser)
	  ├─ UpperLimb   flexes back as the bow is drawn
	  ├─ LowerLimb
	  └─ Nock        slides back along +Z to draw the string
	      └─ Arrow   (welded) the nocked arrow; cloned as the projectile

	The string is two Beams (StringTop -> StringNock -> StringBottom) so it
	follows the limbs and nock automatically.
]]
local roblox = require("@lune/roblox")
local ToolKit = require("../builder/ToolKit")
local Parts = require("../builder/Parts")
local C = require("./Palette")

local CFrame, Vector3, Instance, Color3 = roblox.CFrame, roblox.Vector3, roblox.Instance, roblox.Color3
local V = Vector3.new

local ARROW_Y = 0.39
local BRACE_Z = 0.46
local ARROW_LEN = 2.5
local DRAW = 1.7

-- limb centreline as {y, z}; mirrored for the lower limb
local LIMB = { { 0.9, 0 }, { 1.25, 0.03 }, { 1.6, 0.1 }, { 1.95, 0.22 }, { 2.25, 0.37 }, { 2.5, 0.52 }, { 2.68, 0.46 } }

local function arrow(b, nockPos, fletch1, fletch2)
	-- nockPos: where the nock sits; arrow points toward -Z
	local x, y, z = nockPos.X, nockPos.Y, nockPos.Z
	local tipZ = z - ARROW_LEN
	b:cylBetween("Shaft", V(x, y, z - 0.02), V(x, y, tipZ + 0.3), 0.07, C.WoodLight)
	b:cylBetween("Ferrule", V(x, y, tipZ + 0.33), V(x, y, tipZ + 0.24), 0.09, C.Iron)
	local tip = V(x, y, tipZ)
	local back = V(x, y, tipZ + 0.36)
	for _, dir in { V(0, 1, 0), V(0, -1, 0), V(1, 0, 0), V(-1, 0, 0) } do
		b:triangle("Head", tip, V(x, y, tipZ + 0.3) + dir * 0.11, back, C.SteelBright, 0.025)
	end
	b:cylBetween("Nock", V(x, y, z + 0.06), V(x, y, z - 0.04), 0.085, fletch1)
	for i, ang in { 90, 210, 330 } do
		local r = math.rad(ang)
		local out = V(math.cos(r), math.sin(r), 0)
		local style = if i == 1 then fletch1 else fletch2
		b:triangle(
			"Fletching",
			V(x, y, z - 0.08) + out * 0.03,
			V(x, y, z - 0.62) + out * 0.03,
			V(x, y, z - 0.16) + out * 0.15,
			style,
			0.015
		)
	end
end

return function()
	local tool, model, root, b = ToolKit.newTool({
		name = "Longbow",
		toolTip = "Hold click: draw (longer = faster, harder)  |  Release: loose arrow  |  Q / Right-click: zoom",
		script = "Longbow",
		handleSize = V(0.4, 1.2, 0.4),
		attributes = {
			MinDamage = 16,
			MaxDamage = 55,
			DrawTime = 0.9,
			MinSpeed = 90,
			MaxSpeed = 260,
			Cooldown = 0.35,
			ArrowLifetime = 12,
			ZoomFOV = 40,
			DrawWalkSpeed = 10,
			ScriptedDraw = true,
			FriendlyFire = false,
			ShowHolstered = true,
			AnimIdle = "",
			AnimDraw = "",
			AnimRelease = "",
		},
	})

	-- Riser -------------------------------------------------------------------
	b:block("Riser", V(0.2, 1.2, 0.28), CFrame.new(0, -0.3, -0.05), C.WoodDark)
	b:block("RiserWindow", V(0.1, 0.46, 0.28), CFrame.new(0.1, 0.53, -0.05), C.WoodDark)
	b:block("RiserTop", V(0.2, 0.16, 0.28), CFrame.new(0, 0.83, -0.05), C.WoodDark)
	b:block("ArrowShelf", V(0.14, 0.05, 0.22), CFrame.new(-0.02, 0.33, -0.05), C.Leather)
	b:ring("Grip", -0.08, 0.62, 0.3, C.Leather, V(0, 0, -0.05))
	for _, y in { -0.33, -0.08, 0.17 } do
		b:ring("GripLace", y, 0.05, 0.32, C.LeatherDark, V(0, 0, -0.05))
	end
	for _, s in { 1, -1 } do
		b:ring("LimbSocket", s * 0.9, 0.12, 0.32, C.Bronze, V(0, 0, -0.03))
	end
	b:ball("RiserGem", 0.12, V(0.11, -0.62, -0.05), C.GemCyan)
	b:ball("RiserGem", 0.12, V(-0.11, -0.62, -0.05), C.GemCyan)

	-- Limbs (each its own rig root) -------------------------------------------
	local limbRoots = {}
	for _, s in { 1, -1 } do
		local name = if s == 1 then "UpperLimb" else "LowerLimb"
		local limbRoot = b:sub(model, false):rootPart(name, CFrame.new(0, s * 0.9, 0))
		local lb = b:sub(model, limbRoot)
		for i = 1, #LIMB - 1 do
			local p, q = LIMB[i], LIMB[i + 1]
			local a, c = V(0, s * p[1], p[2]), V(0, s * q[1], q[2])
			local dir = (c - a).Unit
			local t = (i - 1) / (#LIMB - 2)
			local width = 0.2 - 0.09 * t
			local depth = 0.14 - 0.06 * t
			lb:strut(name .. "Segment", a - dir * 0.03, c + dir * 0.03, width, depth, C.WoodLight, V(0, 0, 1))
			-- sinew backing on the back (-Z) face
			local normal = dir:Cross(V(1, 0, 0)).Unit * s
			if normal.Z > 0 then
				normal = -normal
			end
			lb:strut(
				name .. "Backing",
				a + normal * (depth / 2),
				c + normal * (depth / 2),
				width * 0.7,
				0.03,
				C.LeatherRed,
				V(0, 0, 1)
			)
		end
		local tipPt = V(0, s * LIMB[#LIMB][1], LIMB[#LIMB][2])
		lb:ball(name .. "Tip", 0.13, tipPt, C.Gold)
		b:attachment(if s == 1 then "StringTop" else "StringBottom", limbRoot, CFrame.new(tipPt))
		local motor = Parts.motor(name, root, limbRoot)
		-- flex applied at full draw (read by the Longbow script)
		motor:SetAttribute("PoseDrawn", CFrame.Angles(s * 0.17, 0, 0))
		limbRoots[s] = limbRoot
	end

	-- Nock + string -------------------------------------------------------------
	local nock = b:sub(model, false):rootPart("Nock", CFrame.new(0, ARROW_Y, BRACE_Z), V(0.1, 0.1, 0.1))
	local nockMotor = Parts.motor("Nock", root, nock)
	nockMotor:SetAttribute("PoseDrawn", CFrame.new(0, 0, DRAW))
	local nockAtt = Instance.new("Attachment")
	nockAtt.Name = "StringNock"
	nockAtt.Parent = nock

	local stringColor = roblox.ColorSequence.new(Color3.fromRGB(236, 228, 206))
	for _, pair in { { "StringUpper", limbRoots[1]:FindFirstChild("StringTop") }, { "StringLower", limbRoots[-1]:FindFirstChild("StringBottom") } } do
		local beam = Instance.new("Beam")
		beam.Name = pair[1]
		beam.Attachment0 = pair[2]
		beam.Attachment1 = nockAtt
		beam.Width0 = 0.045
		beam.Width1 = 0.045
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Color = stringColor
		beam.Transparency = roblox.NumberSequence.new(0)
		beam.LightInfluence = 1
		beam.Parent = root
	end

	-- Nocked arrow (hidden until drawn; cloned when fired) ------------------------
	local arrowModel = Instance.new("Model")
	arrowModel.Name = "Arrow"
	arrowModel.Parent = model
	local tipCf = CFrame.new(0, ARROW_Y, BRACE_Z - ARROW_LEN)
	local arrowRoot = b:sub(arrowModel, false):rootPart("ArrowRoot", tipCf, V(0.12, 0.12, 0.12))
	arrowModel.PrimaryPart = arrowRoot
	local ab = b:sub(arrowModel, arrowRoot)
	arrow(ab, V(0, ARROW_Y, BRACE_Z), C.Feather, C.FeatherWhite)
	ToolKit.trail(arrowRoot, "FlightTrail", V(0, 0.06, 0.9), V(0, -0.06, 0.9), Color3.fromRGB(255, 255, 255))
	Parts.weldConstraint("ArrowWeld", nock, arrowRoot, nock)

	ToolKit.setRig(root, "RightHand", "RightGripAttachment", CFrame.new())
	ToolKit.setHolster(root, "UpperTorso", "BodyBackAttachment", CFrame.new(0.05, 0.1, 0.62) * Parts.basis(V(0, 0, 1), V(-0.35, 0.94, 0)))

	-- Quiver: worn on the right hip whether or not the bow is equipped ----------
	local quiver = Instance.new("Model")
	quiver.Name = "Quiver"
	quiver.Parent = tool
	local qFrame = CFrame.new(0, 0, 3)
	local qb = b:sub(quiver, false)
	local qRoot = qb:rootPart("QuiverAttach", qFrame)
	quiver.PrimaryPart = qRoot
	qb.root = qRoot
	local function qring(name, y, len, dia, style)
		qb:cylinder(name, len, dia, qFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), style)
	end
	qring("Tube", 0, 2.1, 0.55, C.Leather)
	qring("Rim", 1.02, 0.12, 0.62, C.LeatherDark)
	qring("Cap", -1.04, 0.1, 0.6, C.Bronze)
	qring("Band", 0.45, 0.08, 0.58, C.LeatherRed)
	qring("Band", -0.5, 0.08, 0.58, C.LeatherRed)
	qb:block("Strap", V(0.12, 1.5, 0.08), qFrame * CFrame.new(0, 0.1, 0.3), C.LeatherDark)
	for i = 1, 6 do
		local ang = math.rad(i * 60 + 15)
		local r = if i % 2 == 0 then 0.14 else 0.08
		local base = qFrame * V(math.cos(ang) * r, 0.5, math.sin(ang) * r)
		local top = base + V(0, 1.2 + (i % 3) * 0.06, 0)
		qb:cylBetween("QuiverArrow", base, top, 0.06, C.WoodLight)
		local style = if i % 3 == 0 then C.Feather else C.FeatherWhite
		for _, side in { V(1, 0, 0), V(0, 0, 1) } do
			qb:triangle("QuiverFletch", top - V(0, 0.05, 0), top - V(0, 0.45, 0), top - V(0, 0.12, 0) + side * 0.11, style, 0.015)
		end
	end
	local qOffset = CFrame.new(1.12, -0.35, 0.8) * Parts.basis(V(1, 0, 0), V(0, 0.94, 0.34))
	ToolKit.setRig(qRoot, "LowerTorso", "WaistCenterAttachment", qOffset)
	ToolKit.setHolster(qRoot, "LowerTorso", "WaistCenterAttachment", qOffset)
	Parts.weldConstraint("StowWeld", tool:FindFirstChild("Handle"), qRoot, qRoot)

	local handle = tool:FindFirstChild("Handle")
	ToolKit.sound(handle, "Draw", "rbxasset://sounds/unsheath.wav", { volume = 0.5, speed = 0.55 })
	ToolKit.sound(handle, "Release", "rbxasset://sounds/swordlunge.wav", { volume = 0.7, speed = 1.7 })
	ToolKit.sound(handle, "Equip", "rbxasset://sounds/unsheath.wav", { volume = 0.4, speed = 0.8 })

	b:weld()
	ToolKit.addScripts(tool, "Longbow")
	return tool
end
