--[[
	EnemyKit: shared plumbing for ground enemies (ModuleScript, sits inside
	each enemy's AI Script).

	Turns an imported model (e.g. a rigged .glb: a skinned MeshPart + Bones)
	into a Humanoid NPC without any manual setup:
	  * builds an invisible HumanoidRootPart sized to the model and welds the
	    mesh to it, so the Humanoid can walk, path-find and be hit by weapons
	  * works out which way the model faces (override with FacingOffset)
	  * health bar, animations from Anim<Name> attributes, death + respawn
	  * target selection, path-finding movement, melee / area hits on players
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Kit = {}
Kit.__index = Kit

export type Enemy = typeof(setmetatable({} :: {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	animator: Animator,
	size: Vector3,
	reach: number,
	target: Model?,
	dead: boolean,
}, Kit))

local SHARED_DEFAULTS = {
	MaxHealth = 100,
	WalkSpeed = 12,
	AggroRange = 90,
	LoseRange = 140,
	WanderRadius = 25,
	FacingOffset = 0, -- degrees; set 180 if it walks backwards, 90 / -90 if sideways
	Respawn = true,
	RespawnTime = 15,
	ShowHealthBar = true,
	AnimIdle = "",
	AnimWalk = "",
	AnimDeath = "",
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Kit.new(model: Model, defaults: { [string]: any }): Enemy
	local self = setmetatable({}, Kit) :: any
	self.model = model
	self.template = model:Clone() -- pristine copy (includes the AI script) for respawning
	self.home = model:GetPivot()
	self.defaults = table.clone(SHARED_DEFAULTS)
	for key, value in defaults do
		self.defaults[key] = value
	end
	for key, value in self.defaults do
		if model:GetAttribute(key) == nil then
			model:SetAttribute(key, value)
		end
	end
	self.tracks = {}
	self.deathCallbacks = {}
	self.dead = false
	self.target = nil
	self.nextPath = 0
	self.path = nil
	self.waypoint = 0
	self.lastProgress = { at = os.clock(), distance = math.huge }
	self:_build()
	return self
end

function Kit:cfg(key: string): any
	local value = self.model:GetAttribute(key)
	local default = self.defaults[key]
	if value == nil or (default ~= nil and typeof(value) ~= typeof(default)) then
		return default
	end
	return value
end

-- which horizontal direction the model faces, in world space
function Kit:_detectFront(box: CFrame, size: Vector3): Vector3
	local base = box.LookVector
	-- a head bone well ahead of the body's centre gives the facing away
	-- (hunched models: gorillas, runners); snapped to the model's box axes
	for _, d in self.model:GetDescendants() do
		if d:IsA("Bone") and string.lower(d.Name) == "head" then
			local offset = box:VectorToObjectSpace(d.WorldPosition - box.Position)
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local footprint = math.max(size.X, size.Z)
			if flat.Magnitude > footprint * 0.12 then
				if math.abs(flat.X) > math.abs(flat.Z) then
					base = box.RightVector * math.sign(flat.X)
				else
					base = -box.LookVector * math.sign(flat.Z)
				end
			end
			break
		end
	end
	local turn = math.rad(self:cfg("FacingOffset"))
	return (CFrame.Angles(0, turn, 0) * Vector3.new(base.X, 0, base.Z)).Unit
end

function Kit:_build()
	local model = self.model
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	assert(#parts > 0, model.Name .. ": enemy model has no parts")
	for _, d in model:GetDescendants() do
		-- a Humanoid's Animator drives the bones; drop the importer's controller
		if d:IsA("AnimationController") then
			d:Destroy()
		end
	end

	local box, size = model:GetBoundingBox()
	self.size = size
	local front = self:_detectFront(box, size)
	local footprint = math.max(size.X, size.Z)
	local bottom = box.Position - box.UpVector * size.Y / 2
	local hip = size.Y * 0.25
	local rootSize = Vector3.new(math.max(size.X * 0.55, 1), math.max(size.Y * 0.45, 1), math.max(size.Z * 0.55, 1))
	local rootCenter = bottom + Vector3.new(0, hip + rootSize.Y / 2, 0)

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		local r = Instance.new("Part")
		r.Name = "HumanoidRootPart"
		r.Size = rootSize
		r.CFrame = CFrame.lookAt(rootCenter, rootCenter + front)
		r.Transparency = 1
		r.CanCollide = true
		r.CanQuery = false -- let weapons hit the visible mesh instead
		r.CanTouch = false
		r.Parent = model
		root = r
	end
	local rootPart = root :: BasePart
	rootPart.Anchored = false
	for _, p in parts do
		if p ~= rootPart then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			local joined = false
			for _, j in p:GetJoints() do
				if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
					joined = true
				end
			end
			if not joined then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model.PrimaryPart = rootPart
	self.root = rootPart
	self.reach = footprint * 0.5 + 3

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 uses HipHeight directly
		humanoid.HipHeight = hip
		humanoid.Parent = model
	end
	local h = humanoid :: Humanoid
	h.RequiresNeck = false
	h.BreakJointsOnDeath = false
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.MaxHealth = self:cfg("MaxHealth")
	h.Health = h.MaxHealth
	h.WalkSpeed = self:cfg("WalkSpeed")
	self.humanoid = h
	self.animator = h:FindFirstChildOfClass("Animator") or Instance.new("Animator", h)
	pcall(rootPart.SetNetworkOwner, rootPart, nil)

	if self:cfg("ShowHealthBar") then
		self:_healthBar()
	end
	h.HealthChanged:Connect(function(health)
		if health <= 0 then
			self:_die()
		end
	end)
	h.Died:Connect(function()
		self:_die()
	end)
end

function Kit:_healthBar()
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromScale(math.clamp(self.size.X, 3, 6), 0.35)
	gui.StudsOffsetWorldSpace = Vector3.new(0, self.size.Y * 0.55 + 0.8, 0)
	gui.MaxDistance = 120
	gui.AlwaysOnTop = true
	gui.Adornee = self.root
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 70, 50)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = self.root
	self.humanoid.HealthChanged:Connect(function(health)
		fill.Size = UDim2.fromScale(math.clamp(health / self.humanoid.MaxHealth, 0, 1), 1)
	end)
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

-- Loads Anim<key>; returns nil when no animation is set.
function Kit:track(key: string): AnimationTrack?
	local id = self:cfg("Anim" .. key)
	if type(id) ~= "string" or id == "" then
		return nil
	end
	if not self.tracks[key] then
		local animation = Instance.new("Animation")
		animation.AnimationId = if string.match(id, "^%d+$") then "rbxassetid://" .. id else id
		local ok, result = pcall(function()
			return self.animator:LoadAnimation(animation)
		end)
		if not ok then
			warn(self.model.Name .. ": could not load Anim" .. key, result)
			return nil
		end
		self.tracks[key] = result
	end
	return self.tracks[key]
end

function Kit:play(key: string, looped: boolean?, speed: number?): AnimationTrack?
	local t = self:track(key)
	if t then
		t.Looped = looped == true
		if not t.IsPlaying then
			t:Play(0.2)
		end
		t:AdjustSpeed(speed or 1)
	end
	return t
end

function Kit:stop(key: string)
	local t = self.tracks[key]
	if t and t.IsPlaying then
		t:Stop(0.2)
	end
end

-- keeps the walk / idle loop in sync with movement
function Kit:updateLocomotion()
	local moving = self.root.AssemblyLinearVelocity.Magnitude > 1.5
	if moving then
		self:stop("Idle")
		self:play("Walk", true, math.clamp(self.humanoid.WalkSpeed / self:cfg("WalkSpeed"), 0.5, 2))
	else
		self:stop("Walk")
		self:play("Idle", true)
	end
end

--------------------------------------------------------------------------------
-- Senses
--------------------------------------------------------------------------------

function Kit:eyePosition(): Vector3
	return self.root.Position + Vector3.new(0, self.size.Y * 0.3, 0)
end

function Kit:canSee(character: Model): boolean
	local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { self.model, character }
	for _, name in { "WeaponProjectiles", "EnemyProjectiles" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	local from = self:eyePosition()
	return workspace:Raycast(from, targetRoot.Position - from, params) == nil
end

-- Nearest living player it can see (or hear, when very close).
function Kit:findTarget(): Model?
	local best, bestDistance = nil, math.huge
	local position = self.root.Position
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local h = character and character:FindFirstChildOfClass("Humanoid")
		local r = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and h and r and h.Health > 0 then
			local distance = (r.Position - position).Magnitude
			local limit = if character == self.target then self:cfg("LoseRange") else self:cfg("AggroRange")
			if distance < limit and distance < bestDistance and (distance < 12 or self:canSee(character)) then
				best, bestDistance = character, distance
			end
		end
	end
	self.target = best
	return best
end

function Kit:targetRoot(): BasePart?
	local t = self.target
	return if t then t:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

function Kit:distanceTo(position: Vector3): number
	return ((position - self.root.Position) * Vector3.new(1, 0, 1)).Magnitude
end

--------------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------------

function Kit:face(position: Vector3)
	local p = self.root.Position
	local flat = Vector3.new(position.X, p.Y, position.Z)
	if (flat - p).Magnitude > 0.2 then
		self.root.CFrame = CFrame.lookAt(p, flat)
	end
end

function Kit:stopMoving()
	self.path = nil
	self.humanoid:Move(Vector3.zero)
	self.humanoid:MoveTo(self.root.Position)
end

--[[
	Walks toward `goal`: straight at it when the way is clear, otherwise along
	a computed path. Call every think tick.
]]
function Kit:moveTo(goal: Vector3)
	local now = os.clock()
	local position = self.root.Position
	local distance = (goal - position).Magnitude

	-- stuck detection: no progress for a while -> jump, then path-find
	if distance < self.lastProgress.distance - 1 then
		self.lastProgress = { at = now, distance = distance }
	elseif now - self.lastProgress.at > 1.2 then
		self.humanoid.Jump = true
		self.nextPath = 0
		self.lastProgress = { at = now, distance = distance }
	end

	local clear = distance < 6
	if not clear then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { self.model }
		if self.target then
			table.insert(ignore, self.target)
		end
		params.FilterDescendantsInstances = ignore
		clear = workspace:Spherecast(position, math.min(self.size.X, self.size.Z) * 0.3, goal - position, params) == nil
	end

	if clear then
		self.path = nil
		self.humanoid:MoveTo(goal)
		return
	end
	if not self.path or now >= self.nextPath then
		self.nextPath = now + 1
		local path = PathfindingService:CreatePath({
			AgentRadius = math.max(self.size.X, self.size.Z) * 0.45,
			AgentHeight = self.size.Y,
			AgentCanJump = true,
		})
		local ok = pcall(function()
			path:ComputeAsync(position, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			self.path = path:GetWaypoints()
			self.waypoint = 2
		else
			self.path = nil
			self.humanoid:MoveTo(goal)
			return
		end
	end
	local waypoints = self.path
	if waypoints then
		local wp = waypoints[math.min(self.waypoint, #waypoints)]
		if wp then
			if self:distanceTo(wp.Position) < 2.5 then
				self.waypoint += 1
				wp = waypoints[math.min(self.waypoint, #waypoints)]
			end
			if wp.Action == Enum.PathWaypointAction.Jump then
				self.humanoid.Jump = true
			end
			self.humanoid:MoveTo(wp.Position)
		end
	end
end

-- Random stroll around the spawn point while there is no target.
function Kit:wander()
	local now = os.clock()
	if not self.wanderGoal or now > (self.wanderUntil or 0) or self:distanceTo(self.wanderGoal) < 3 then
		local angle = math.random() * math.pi * 2
		local radius = self:cfg("WanderRadius") * math.random()
		self.wanderGoal = self.home.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		self.wanderUntil = now + 4 + math.random() * 4
		self.wanderRest = now + math.random() * 2.5
	end
	if now < (self.wanderRest or 0) then
		self:stopMoving()
	else
		self:moveTo(self.wanderGoal)
	end
end

--------------------------------------------------------------------------------
-- Hurting players
--------------------------------------------------------------------------------

local function playerHumanoid(part: Instance): (Humanoid?, Model?)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then
			if Players:GetPlayerFromCharacter(model) then
				return h, model
			end
			return nil, nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

--[[
	Damages players in a box in front of the enemy (radius = nil) or a sphere
	around `center`. Returns how many were hit. Blocking (Longsword) is honoured.
]]
function Kit:hitArea(opts: { damage: number, range: number?, width: number?, radius: number?, center: Vector3?, falloff: boolean? }): number
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model }
	local parts
	local center = opts.center or self.root.Position
	if opts.radius then
		parts = workspace:GetPartBoundsInRadius(center, opts.radius, params)
	else
		local range = opts.range or self.reach
		local cf = self.root.CFrame * CFrame.new(0, 0, -range / 2)
		parts = workspace:GetPartBoundsInBox(cf, Vector3.new(opts.width or self.size.X + 2, self.size.Y + 2, range), params)
	end
	local hit: { [Humanoid]: boolean } = {}
	local count = 0
	for _, part in parts do
		local h, character = playerHumanoid(part)
		if h and character and not hit[h] and h.Health > 0 then
			hit[h] = true
			count += 1
			local amount = opts.damage
			local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if opts.falloff and opts.radius and targetRoot then
				local t = math.clamp((targetRoot.Position - center).Magnitude / opts.radius, 0, 1)
				amount *= 1 - 0.5 * t
			end
			-- respect the Longsword block (attribute set on the blocking character)
			if character:GetAttribute("Blocking") and targetRoot then
				local toUs = (self.root.Position - targetRoot.Position) * Vector3.new(1, 0, 1)
				if toUs.Magnitude > 0.01 and targetRoot.CFrame.LookVector:Dot(toUs.Unit) > 0.2 then
					local reduction = character:GetAttribute("BlockReduction")
					amount *= 1 - (if type(reduction) == "number" then reduction else 0.7)
					character:SetAttribute("BlockedHit", os.clock())
				end
			end
			h:TakeDamage(amount)
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

function Kit.shockwave(position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)
	local dust = Instance.new("Attachment")
	dust.WorldPosition = position
	dust.Parent = workspace.Terrain
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 110, 100))
	smoke.Size = NumberSequence.new(2, 5)
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Lifetime = NumberRange.new(0.6, 1)
	smoke.Speed = NumberRange.new(10, 18)
	smoke.SpreadAngle = Vector2.new(90, 10)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Enabled = false
	smoke.Parent = dust
	smoke:Emit(30)
	Debris:AddItem(dust, 1.5)
end

-- Where the ground is under a point (or nil over the void).
function Kit:groundAt(position: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model }
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else nil
end

--------------------------------------------------------------------------------
-- Life cycle
--------------------------------------------------------------------------------

function Kit:onDeath(callback: () -> ())
	table.insert(self.deathCallbacks, callback)
end

-- Runs `think(dt)` about 10 times a second until the enemy dies.
function Kit:run(think: (number) -> ())
	local last = os.clock()
	task.spawn(function()
		local warned = false
		while not self.dead and self.model.Parent do
			local now = os.clock()
			-- one bad tick must not freeze the enemy for good
			local ok, err = pcall(think, now - last)
			if not ok and not warned then
				warned = true
				warn(self.model.Name .. " AI error: " .. tostring(err))
			end
			last = now
			pcall(self.updateLocomotion, self)
			task.wait(0.1)
		end
	end)
end

function Kit:_die()
	if self.dead then
		return
	end
	self.dead = true
	for _, callback in self.deathCallbacks do
		task.spawn(callback)
	end
	for key, t in self.tracks do
		if key ~= "Death" then
			t:Stop(0.1)
		end
	end
	self.humanoid:MoveTo(self.root.Position)
	local bar = self.root:FindFirstChild("HealthBar")
	if bar then
		bar:Destroy()
	end
	local deathTrack = self:play("Death")
	if not deathTrack then
		-- no death animation: keel over
		self.humanoid.PlatformStand = true
		self.root:ApplyAngularImpulse(self.root.CFrame.RightVector * self.root.AssemblyMass * self.size.Y * 6)
	end
	-- fade out, then respawn a fresh copy at the spawn point
	task.delay(3, function()
		for _, d in self.model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				TweenService:Create(d, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			end
		end
	end)
	if self:cfg("Respawn") then
		local parent = self.model.Parent
		local template, home = self.template, self.home
		task.delay(self:cfg("RespawnTime"), function()
			local fresh = template:Clone()
			fresh:PivotTo(home)
			fresh.Parent = parent
		end)
	end
	Debris:AddItem(self.model, 5)
end

return Kit
