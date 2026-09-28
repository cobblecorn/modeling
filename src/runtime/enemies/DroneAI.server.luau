--[[
	DroneAI: flying enemy brain. Put this Script inside the drone Model
	(e.g. the imported SentryDrone.glb) and place the model in Workspace.

	It hovers around where you placed it, hunts the nearest player it can see,
	strafes around them at range and fires bolts from the muzzle bones. Players
	hit it with any weapon that damages Humanoids (the weapons pack included).

	Nothing about the model has to be set up by hand:
	  * the largest part becomes the physics root; other parts are welded to it
	  * a Humanoid is added for health, plus a small health bar
	  * "muzzle" bones/attachments are used as gun barrels, "head"/"eye" as the eye
	  * the model's front is worked out from where the eye sits

	Tuning: attributes on the Model (defaults are created on first run).
	Animations: after importing, publish the drone's clips and paste their IDs
	into AnimIdle / AnimFly / AnimAttack / AnimHit / AnimDeath. Without them the
	drone still bobs and banks procedurally.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local model = script.Parent :: Model
local template = model:Clone() -- pristine copy for respawning (includes this script)
local homeCFrame = model:GetPivot()

local DEFAULTS = {
	MaxHealth = 60,
	Speed = 24,
	HoverHeight = 8, -- studs above its target (or the ground while patrolling)
	PatrolRadius = 30,
	AggroRange = 110,
	AttackRange = 70,
	PreferredRange = 32,
	FireRate = 0.45,
	Burst = 3, -- shots per volley
	BurstCooldown = 1.6,
	Damage = 7,
	BoltSpeed = 110,
	Spread = 1.5, -- degrees
	LeadTargets = true,
	Respawn = true,
	RespawnTime = 12,
	ShowHealthBar = true,
	AnimIdle = "",
	AnimFly = "",
	AnimAttack = "",
	AnimHit = "",
	AnimDeath = "",
}
for key, value in DEFAULTS do
	if model:GetAttribute(key) == nil then
		model:SetAttribute(key, value)
	end
end
local function cfg(key: string): any
	local value = model:GetAttribute(key)
	if value == nil or typeof(value) ~= typeof(DEFAULTS[key]) then
		return DEFAULTS[key]
	end
	return value
end

local BOLT_COLOR = Color3.fromRGB(255, 90, 30)

--------------------------------------------------------------------------------
-- Assembly
--------------------------------------------------------------------------------

local parts: { BasePart } = {}
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(parts, d)
	end
end
assert(#parts > 0, "DroneAI: the model has no parts")

local root = model.PrimaryPart
if not root then
	for _, p in parts do
		if not root or p.Size.Magnitude > root.Size.Magnitude then
			root = p
		end
	end
	model.PrimaryPart = root
end
local rootPart = root :: BasePart

local function isJoined(part: BasePart): boolean
	for _, j in part:GetJoints() do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			return true
		end
	end
	return false
end

for _, p in parts do
	p.Anchored = false
	p.CanCollide = p == rootPart
	p.Massless = p ~= rootPart
	if p ~= rootPart and not isJoined(p) then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = p
		weld.Parent = p
	end
end

-- marker lookup: bones, attachments or parts whose name contains `word`
local function findMarkers(word: string): { Instance }
	local found = {}
	for _, d in model:GetDescendants() do
		if (d:IsA("Attachment") or d:IsA("BasePart")) and string.find(string.lower(d.Name), word, 1, true) then
			table.insert(found, d)
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

local function worldCFrame(marker: Instance): CFrame
	if marker:IsA("Bone") then
		return marker.TransformedWorldCFrame -- includes the playing animation
	elseif marker:IsA("Attachment") then
		return marker.WorldCFrame
	end
	return (marker :: BasePart).CFrame
end

local muzzles = findMarkers("muzzle")
local eye = findMarkers("head")[1] or findMarkers("eye")[1]

-- which way the model faces, in root space (glTF models usually face +Z)
local frontLocal = Vector3.new(0, 0, -1)
do
	local probe = eye or muzzles[1]
	if probe then
		local offset = rootPart.CFrame:VectorToObjectSpace(worldCFrame(probe).Position - rootPart.Position)
		offset = Vector3.new(offset.X, 0, offset.Z)
		if offset.Magnitude > 0.05 then
			frontLocal = offset.Unit
		end
	end
end
-- rotation that turns the model's front onto -Z, so CFrame.lookAt aims its eye
local faceCorrection = CFrame.fromRotationBetweenVectors(frontLocal, Vector3.new(0, 0, -1))

-- health
local humanoid = model:FindFirstChildOfClass("Humanoid")
if not humanoid then
	humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
end
local hum = humanoid :: Humanoid
hum.EvaluateStateMachine = false -- we fly it ourselves
hum.RequiresNeck = false
hum.BreakJointsOnDeath = false
hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
hum.MaxHealth = cfg("MaxHealth")
hum.Health = hum.MaxHealth

-- movers
local attachment = Instance.new("Attachment")
attachment.Name = "DroneMover"
attachment.Parent = rootPart
local align = Instance.new("AlignPosition")
align.Mode = Enum.PositionAlignmentMode.OneAttachment
align.Attachment0 = attachment
align.MaxForce = 1e6
align.MaxVelocity = cfg("Speed")
align.Responsiveness = 12
align.Position = rootPart.Position
align.Parent = rootPart
local turn = Instance.new("AlignOrientation")
turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
turn.Attachment0 = attachment
turn.MaxTorque = 1e6
turn.Responsiveness = 10
turn.CFrame = rootPart.CFrame.Rotation
turn.Parent = rootPart
pcall(rootPart.SetNetworkOwner, rootPart, nil)

-- eye glow (brightens before each volley)
local eyeLight = Instance.new("PointLight")
eyeLight.Color = BOLT_COLOR
eyeLight.Range = 8
eyeLight.Brightness = 1
eyeLight.Parent = if eye and (eye:IsA("Attachment") or eye:IsA("BasePart")) then eye else rootPart

-- health bar
local bar: Frame? = nil
if cfg("ShowHealthBar") then
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromScale(3, 0.3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, rootPart.Size.Y / 2 + 1.2, 0)
	gui.MaxDistance = 120
	gui.AlwaysOnTop = true
	gui.Adornee = rootPart
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 110, 40)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = rootPart
	bar = fill
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

local animator: Animator? = nil
do
	local controller = model:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = model
	end
	animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
end
local tracks: { [string]: AnimationTrack } = {}
local function track(key: string): AnimationTrack?
	local id = cfg("Anim" .. key)
	if id == "" or not animator then
		return nil
	end
	if not tracks[key] then
		local animation = Instance.new("Animation")
		animation.AnimationId = if string.match(id, "^%d+$") then "rbxassetid://" .. id else id
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if not ok then
			warn("DroneAI: could not load Anim" .. key, result)
			return nil
		end
		tracks[key] = result
	end
	return tracks[key]
end
local function play(key: string, looped: boolean?)
	local t = track(key)
	if t and not t.IsPlaying then
		t.Looped = looped == true
		t:Play(0.2)
	end
end
local function stop(key: string)
	local t = tracks[key]
	if t and t.IsPlaying then
		t:Stop(0.25)
	end
end

--------------------------------------------------------------------------------
-- Targeting
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function projectileFolder(): Folder
	local f = workspace:FindFirstChild("EnemyProjectiles")
	if not f then
		f = Instance.new("Folder")
		f.Name = "EnemyProjectiles"
		f.Parent = workspace
	end
	return f :: Folder
end

local function canSee(from: Vector3, character: Model): boolean
	local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return false
	end
	rayParams.FilterDescendantsInstances = { model, character, projectileFolder() }
	return workspace:Raycast(from, targetRoot.Position - from, rayParams) == nil
end

local function findTarget(current: Model?): Model?
	local position = rootPart.Position
	local best, bestDistance = nil, cfg("AggroRange")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local h = character and character:FindFirstChildOfClass("Humanoid")
		local r = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and h and r and h.Health > 0 then
			local distance = (r.Position - position).Magnitude
			-- stick with the current target a bit longer before giving up on it
			local limit = if character == current then bestDistance * 1.5 else bestDistance
			if distance < limit and canSee(position, character) then
				best, bestDistance = character, distance
			end
		end
	end
	return best
end

local function groundBelow(position: Vector3): number?
	rayParams.FilterDescendantsInstances = { model, projectileFolder() }
	local hit = workspace:Raycast(position, Vector3.new(0, -200, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

--------------------------------------------------------------------------------
-- Shooting
--------------------------------------------------------------------------------

local muzzleIndex = 0

local function fireBolt(targetRoot: BasePart)
	muzzleIndex = muzzleIndex % math.max(1, #muzzles) + 1
	local origin = if #muzzles > 0 then worldCFrame(muzzles[muzzleIndex]).Position else rootPart.Position
	local speed = cfg("BoltSpeed")
	local aimAt = targetRoot.Position
	if cfg("LeadTargets") then
		local travel = (aimAt - origin).Magnitude / speed
		aimAt += targetRoot.AssemblyLinearVelocity * Vector3.new(1, 0.3, 1) * travel
	end
	local spread = math.rad(cfg("Spread"))
	local direction = (CFrame.lookAt(origin, aimAt) * CFrame.Angles((math.random() - 0.5) * spread * 2, (math.random() - 0.5) * spread * 2, 0)).LookVector

	local bolt = Instance.new("Part")
	bolt.Name = "DroneBolt"
	bolt.Size = Vector3.new(0.18, 0.18, 1.1)
	bolt.Material = Enum.Material.Neon
	bolt.Color = BOLT_COLOR
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.CastShadow = false
	bolt.CFrame = CFrame.lookAt(origin, origin + direction)
	local light = Instance.new("PointLight")
	light.Color = BOLT_COLOR
	light.Range = 6
	light.Brightness = 2
	light.Parent = bolt
	local a = Instance.new("Attachment")
	a.Parent = bolt
	local float = Instance.new("VectorForce")
	float.Attachment0 = a
	float.RelativeTo = Enum.ActuatorRelativeTo.World
	float.Parent = bolt
	bolt.Parent = projectileFolder()
	float.Force = Vector3.new(0, workspace.Gravity * bolt.AssemblyMass, 0)
	pcall(bolt.SetNetworkOwner, bolt, nil)
	bolt.AssemblyLinearVelocity = direction * speed
	Debris:AddItem(bolt, 4)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, projectileFolder() }
	local last = origin
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not bolt.Parent then
			connection:Disconnect()
			return
		end
		local position = bolt.Position + direction * 0.55
		local hit = workspace:Raycast(last, position - last, params)
		last = position
		if hit then
			connection:Disconnect()
			bolt:Destroy()
			local character = hit.Instance:FindFirstAncestorOfClass("Model")
			local victim = character and character:FindFirstChildOfClass("Humanoid")
			if victim and Players:GetPlayerFromCharacter(character) then
				victim:TakeDamage(cfg("Damage"))
			end
			local spark = Instance.new("Attachment")
			spark.WorldPosition = hit.Position
			spark.Parent = workspace.Terrain
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(BOLT_COLOR)
			emitter.LightEmission = 1
			emitter.Speed = NumberRange.new(6, 12)
			emitter.Lifetime = NumberRange.new(0.1, 0.25)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new(0.3, 0)
			emitter.Enabled = false
			emitter.Parent = spark
			emitter:Emit(8)
			Debris:AddItem(spark, 1)
		end
	end)
end

--------------------------------------------------------------------------------
-- Brain
--------------------------------------------------------------------------------

local target: Model? = nil
local dead = false
local orbitAngle = math.random() * math.pi * 2
local orbitDirection = if math.random() < 0.5 then 1 else -1
local patrolPoint = homeCFrame.Position
local nextThink = 0
local nextVolley = 0
local firing = false
local started = os.clock()

local function volley()
	firing = true
	play("Attack")
	TweenService:Create(eyeLight, TweenInfo.new(0.25), { Brightness = 6, Range = 12 }):Play()
	task.wait(0.3)
	for _ = 1, cfg("Burst") do
		if dead or not target then
			break
		end
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			fireBolt(targetRoot)
		end
		task.wait(cfg("FireRate"))
	end
	TweenService:Create(eyeLight, TweenInfo.new(0.4), { Brightness = 1, Range = 8 }):Play()
	nextVolley = os.clock() + cfg("BurstCooldown")
	firing = false
end

local function think()
	target = findTarget(target)
	local position = rootPart.Position
	local desired: Vector3
	local lookAt: Vector3
	if target then
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart
		-- circle the target at the preferred range, flipping direction now and then
		if math.random() < 0.04 then
			orbitDirection = -orbitDirection
		end
		orbitAngle += orbitDirection * 0.12
		local range = cfg("PreferredRange")
		desired = targetRoot.Position + Vector3.new(math.cos(orbitAngle) * range, cfg("HoverHeight"), math.sin(orbitAngle) * range)
		lookAt = targetRoot.Position
		local distance = (targetRoot.Position - position).Magnitude
		if not firing and os.clock() >= nextVolley and distance <= cfg("AttackRange") then
			task.spawn(volley)
		end
	else
		-- patrol: drift between random points around home
		if (patrolPoint - position).Magnitude < 4 or math.random() < 0.01 then
			local radius = cfg("PatrolRadius")
			local angle = math.random() * math.pi * 2
			local ground = groundBelow(homeCFrame.Position + Vector3.new(0, 5, 0)) or homeCFrame.Position.Y - cfg("HoverHeight")
			patrolPoint = Vector3.new(
				homeCFrame.Position.X + math.cos(angle) * radius * math.random(),
				ground + cfg("HoverHeight"),
				homeCFrame.Position.Z + math.sin(angle) * radius * math.random()
			)
		end
		desired = patrolPoint
		lookAt = if (patrolPoint - position).Magnitude > 1 then patrolPoint else position + rootPart.CFrame:VectorToWorldSpace(frontLocal)
	end
	-- never scrape the floor
	local ground = groundBelow(desired + Vector3.new(0, 3, 0))
	if ground then
		desired = Vector3.new(desired.X, math.max(desired.Y, ground + 4), desired.Z)
	end
	return desired, lookAt
end

local desiredPosition, lookTarget = rootPart.Position, rootPart.Position + rootPart.CFrame:VectorToWorldSpace(frontLocal)

local heartbeat
heartbeat = RunService.Heartbeat:Connect(function()
	if dead then
		return
	end
	local now = os.clock()
	if now >= nextThink then
		nextThink = now + 0.15
		desiredPosition, lookTarget = think()
	end
	align.MaxVelocity = cfg("Speed")
	-- hover bob
	local bob = Vector3.new(0, math.sin((now - started) * 2.2) * 0.35, 0)
	align.Position = desiredPosition + bob

	-- face the look target, banking into the direction of travel
	local position = rootPart.Position
	local flatLook = Vector3.new(lookTarget.X, position.Y, lookTarget.Z)
	local facing = if (flatLook - position).Magnitude > 0.1 then CFrame.lookAt(position, flatLook) else CFrame.new(position) * rootPart.CFrame.Rotation
	local velocity = facing:VectorToObjectSpace(rootPart.AssemblyLinearVelocity)
	local speed = cfg("Speed")
	local pitch = math.clamp(-velocity.Z / speed, -1, 1) * math.rad(-14)
	local roll = math.clamp(velocity.X / speed, -1, 1) * math.rad(-18)
	turn.CFrame = (facing * CFrame.Angles(pitch, 0, roll) * faceCorrection).Rotation

	if rootPart.AssemblyLinearVelocity.Magnitude > speed * 0.4 then
		stop("Idle")
		play("Fly", true)
	else
		stop("Fly")
		play("Idle", true)
	end
end)

--------------------------------------------------------------------------------
-- Damage / death / respawn
--------------------------------------------------------------------------------

local die: () -> ()

local lastHealth = hum.Health
hum.HealthChanged:Connect(function(health)
	if health <= 0 then
		die() -- with the state machine off, Died is not guaranteed to fire
		return
	end
	if bar then
		bar.Size = UDim2.fromScale(math.clamp(health / hum.MaxHealth, 0, 1), 1)
	end
	if health < lastHealth then
		play("Hit")
		-- knocked off course a little
		rootPart:ApplyImpulse(Vector3.new(math.random() - 0.5, 0.3, math.random() - 0.5) * rootPart.AssemblyMass * 25)
		-- whoever shot us becomes the target if they're in range
		local creator = hum:FindFirstChild("creator") :: ObjectValue?
		local attacker = creator and creator.Value
		if attacker and attacker:IsA("Player") and attacker.Character then
			target = attacker.Character
		end
	end
	lastHealth = health
end)

function die()
	if dead then
		return
	end
	dead = true
	heartbeat:Disconnect()
	stop("Idle")
	stop("Fly")
	play("Death")
	align.Enabled = false
	turn.Enabled = false
	eyeLight.Enabled = false
	local healthBar = rootPart:FindFirstChild("HealthBar")
	if healthBar then
		healthBar:Destroy()
	end
	-- sparks, a pop, then it tumbles out of the sky
	local explosion = Instance.new("Explosion")
	explosion.Position = rootPart.Position
	explosion.BlastRadius = 4
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
	rootPart.CanCollide = true
	rootPart:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * rootPart.AssemblyMass * 20)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(40, 40, 40)
	smoke.Size = 2
	smoke.RiseVelocity = 3
	smoke.Parent = rootPart

	if cfg("Respawn") then
		local parent = model.Parent
		task.delay(cfg("RespawnTime"), function()
			local fresh = template:Clone()
			fresh:PivotTo(homeCFrame)
			fresh.Parent = parent
		end)
	end
	Debris:AddItem(model, 5)
end

hum.Died:Connect(die)
