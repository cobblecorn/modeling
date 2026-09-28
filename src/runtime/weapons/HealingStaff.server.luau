--[[
	Healing Staff (server)
	  Mend(target)  a beam from the crystal to whoever you aim at: heals allies,
	                stings enemies. A generous aim sphere (AimAssist) makes
	                moving teammates easy to hit.
	  Pulse         Renewal: heals every ally around you, yourself included.
	Allies are you and players on your team; with no teams, all players are
	allies and NPC Humanoids are enemies (see Combat.isAlly).
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Combat, Effects, Rig, Util = Core.Combat, Core.Effects, Core.Rig, Core.Util
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local weapon = Core.Server.new(tool)

local MODEL = "HealingStaff"
local staff = tool:WaitForChild(MODEL) :: Model
local crystal = staff:WaitForChild("Crystal") :: BasePart
local crystalJoint = crystal:WaitForChild("Crystal") :: Motor6D
local focus = crystal:WaitForChild("Focus") :: Attachment
local glow = focus:WaitForChild("Glow") :: PointLight

local HEAL_COLOR = Color3.fromRGB(110, 235, 190)
local HURT_COLOR = Color3.fromRGB(235, 200, 110)
local CAST_POSE = CFrame.Angles(math.rad(-70), 0, 0) -- crystal tipped toward the target

local bob: Tween? = nil

-- gentle float while held (skipped if you animate the crystal yourself)
local function startBob()
	if bob then
		bob:Cancel()
		bob = nil
	end
	if weapon:hasAnim("Idle") or not weapon.character then
		return
	end
	local rest = crystalJoint:GetAttribute("RestC0") :: CFrame
	bob = TweenService:Create(
		crystalJoint,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ C0 = rest * CFrame.new(0, 0.08, 0) }
	)
	;(bob :: Tween):Play()
end

-- moves the crystal to a pose and back, then resumes floating
local function crystalMove(pose: CFrame?, out: number, hold: number, back: number)
	if bob then
		bob:Cancel()
		bob = nil
	end
	Effects.pose(crystalJoint, pose, out)
	task.delay(hold, function()
		Effects.pose(crystalJoint, nil, back)
		task.delay(back, function()
			if not bob then
				startBob()
			end
		end)
	end)
end

-- A short-lived glowing beam from the crystal to a point.
local function beam(to: Vector3, color: Color3)
	local target = Instance.new("Attachment")
	target.WorldPosition = to
	target.Parent = workspace.Terrain
	local b = Instance.new("Beam")
	b.Attachment0 = focus
	b.Attachment1 = target
	b.Color = ColorSequence.new(color)
	b.LightEmission = 1
	b.FaceCamera = true
	b.Width0 = 0.35
	b.Width1 = 0.2
	b.Segments = 12
	b.CurveSize0 = 1.5
	b.CurveSize1 = -1
	b.TextureSpeed = 2
	b.Transparency = NumberSequence.new(0.1)
	b.Parent = target
	TweenService:Create(b, TweenInfo.new(0.35), { Width0 = 0, Width1 = 0 }):Play()
	Debris:AddItem(target, 0.4)
end

-- Floating "+12" over whoever was healed.
local function popup(model: Model, text: string, color: Color3)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(80, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(math.random() - 0.5, 2, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head :: BasePart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	gui.Parent = head
	TweenService:Create(gui, TweenInfo.new(0.9), { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 1.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(gui, 1)
end

local function flare()
	glow.Brightness = 4
	TweenService:Create(glow, TweenInfo.new(0.4), { Brightness = 1.2 }):Play()
end

local function castPose()
	if weapon:hasAnim("Cast") then
		return
	end
	weapon:pose(MODEL, CAST_POSE, 0.08)
	task.delay(0.25, function()
		weapon:pose(MODEL, nil, 0.2)
	end)
end

weapon:on("Mend", function(_player, target)
	if not Util.isVector3(target) or not weapon:ready("Mend", weapon:attr("Cooldown", 0.5)) then
		return
	end
	local character = weapon.character
	if not character then
		return
	end
	local origin = focus.WorldPosition
	local offset = target - origin
	if offset.Magnitude < 0.5 then
		return
	end
	local range = weapon:attr("Range", 90)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { character }
	local projectiles = workspace:FindFirstChild("WeaponProjectiles")
	if projectiles then
		table.insert(ignore, projectiles)
	end
	params.FilterDescendantsInstances = ignore
	local direction = offset.Unit * math.min(range, offset.Magnitude + 3)
	local hit = workspace:Spherecast(origin, weapon:attr("AimAssist", 1.5), direction, params)

	weapon:sound("Cast")
	flare()
	castPose()
	crystalMove(crystalJoint:GetAttribute("PoseCast") :: CFrame?, 0.1, 0.2, 0.3)

	local humanoid, model
	if hit then
		humanoid, model = Combat.findHumanoid(hit.Instance)
	end
	if humanoid and model and humanoid.Health > 0 then
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local at = if root then root.Position else hit.Position
		if Combat.isAlly(weapon, humanoid) then
			local healed = Combat.heal(humanoid, weapon:attr("HealAmount", 12))
			beam(at, HEAL_COLOR)
			Effects.burst(at, HEAL_COLOR, 10, 6)
			if healed > 0 then
				popup(model, "+" .. math.floor(healed + 0.5), HEAL_COLOR)
			end
		elseif Combat.canDamage(weapon, humanoid) then
			Combat.damage(weapon, humanoid, weapon:attr("EnemyDamage", 8), origin)
			beam(at, HURT_COLOR)
			Effects.burst(hit.Position, HURT_COLOR, 10, 12)
		end
	else
		-- missed: the spell fizzles where it lands
		local landed = if hit then hit.Position else origin + direction
		beam(landed, HEAL_COLOR)
		Effects.burst(landed, HEAL_COLOR, 5, 4)
	end
end)

weapon:on("Pulse", function()
	if not weapon:ready("Pulse", weapon:attr("PulseCooldown", 10)) then
		return
	end
	local root, character = weapon.root, weapon.character
	if not root or not character then
		return
	end
	local radius = weapon:attr("PulseRadius", 18)
	local amount = weapon:attr("PulseHeal", 30)
	weapon:sound("Pulse")
	flare()

	-- expanding ring on the ground + a soft flash
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = HEAL_COLOR
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.15, 2, 2)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.65)
	Effects.flash(focus.WorldPosition, HEAL_COLOR, 5, 0.4)
	if not weapon:hasAnim("Pulse") then
		crystalMove(CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.pi, 0), 0.25, 0.35, 0.4)
	end

	local healed: { [Humanoid]: boolean } = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	for _, part in workspace:GetPartBoundsInRadius(root.Position, radius, params) do
		local humanoid, model = Combat.findHumanoid(part)
		if humanoid and model and not healed[humanoid] and Combat.isAlly(weapon, humanoid) then
			healed[humanoid] = true
			local amountHealed = Combat.heal(humanoid, amount)
			if amountHealed > 0 then
				popup(model, "+" .. math.floor(amountHealed + 0.5), HEAL_COLOR)
				local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if r then
					Effects.burst(r.Position, HEAL_COLOR, 12, 5)
				end
			end
		end
	end
end)

weapon:onEquip(startBob)

weapon:onUnequip(function()
	if bob then
		bob:Cancel()
		bob = nil
	end
	Rig.setPose(crystalJoint, nil)
end)
