--[[
	SpeederAI: fast hit-and-run skirmisher. Put this Script (with its
	EnemyKit module) inside the imported speeder model.

	Sprints in, circling a little so it is hard to line up, dashes through
	its target with a blade slash, then darts away before coming back for
	another pass. Sometimes sidesteps when shot.

	Animations: AnimWalk = run, AnimSlash = slash
]]

local model = script.Parent :: Model
local Kit = require(script:WaitForChild("EnemyKit"))

local enemy = Kit.new(model, {
	MaxHealth = 60,
	WalkSpeed = 24,
	AggroRange = 110,
	LoseRange = 160,
	Damage = 14,
	DashRange = 18, -- starts a dash inside this distance
	DashSpeed = 75,
	DashCooldown = 2.2,
	RetreatTime = 1.1,
	DodgeChance = 0.35,
	SlashHitTime = 0.12, -- seconds into the dash when the blade connects
	AnimSlash = "",
})

local busyUntil = 0
local nextDash = 0
local retreatUntil = 0
local retreatGoal: Vector3? = nil
local strafeSide = if math.random() < 0.5 then 1 else -1

-- short burst of velocity (the root is server-owned, so this is authoritative)
local function burst(direction: Vector3, speed: number, duration: number)
	local root = enemy.root
	local attachment = root:FindFirstChild("RootAttachment") or Instance.new("Attachment", root)
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment :: Attachment
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	push.LineDirection = direction.Unit
	push.LineVelocity = speed
	push.MaxForce = root.AssemblyMass * 4000
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.Parent = root
	task.delay(duration, function()
		push:Destroy()
	end)
end

local function dash(targetRoot: BasePart)
	local now = os.clock()
	local offset = (targetRoot.Position - enemy.root.Position) * Vector3.new(1, 0, 1)
	if offset.Magnitude < 0.5 then
		return
	end
	nextDash = now + enemy:cfg("DashCooldown")
	local duration = math.clamp((offset.Magnitude + 6) / enemy:cfg("DashSpeed"), 0.15, 0.45)
	busyUntil = now + duration + 0.15
	enemy:stopMoving()
	enemy:face(targetRoot.Position)
	enemy:play("Slash")
	burst(offset, enemy:cfg("DashSpeed"), duration)
	task.delay(math.min(enemy:cfg("SlashHitTime"), duration), function()
		-- sweep the blade along the dash path
		local hit = false
		local finish = os.clock() + duration
		while os.clock() < finish and not enemy.dead and not hit do
			hit = enemy:hitArea({ damage = enemy:cfg("Damage"), range = enemy.reach, width = enemy.size.X + 3 }) > 0
			task.wait(0.05)
		end
	end)
	-- then peel away
	task.delay(duration + 0.1, function()
		if enemy.dead then
			return
		end
		local away = -offset.Unit
		local side = Vector3.new(-away.Z, 0, away.X) * strafeSide
		retreatGoal = enemy.root.Position + (away + side * 0.7).Unit * 22
		retreatUntil = os.clock() + enemy:cfg("RetreatTime")
		strafeSide = -strafeSide
	end)
end

local lastHealth = enemy.humanoid.Health
enemy.humanoid.HealthChanged:Connect(function(health)
	if health < lastHealth and health > 0 and os.clock() > busyUntil and math.random() < enemy:cfg("DodgeChance") then
		local look = enemy.root.CFrame.LookVector
		local side = Vector3.new(-look.Z, 0, look.X) * (if math.random() < 0.5 then 1 else -1)
		busyUntil = os.clock() + 0.25
		burst(side, enemy:cfg("DashSpeed") * 0.6, 0.2)
	end
	lastHealth = health
end)

enemy:run(function()
	local now = os.clock()
	if now < busyUntil then
		return
	end
	local target = enemy:findTarget()
	local targetRoot = enemy:targetRoot()
	if not target or not targetRoot then
		enemy.humanoid.WalkSpeed = enemy:cfg("WalkSpeed") * 0.4
		enemy:wander()
		return
	end
	enemy.humanoid.WalkSpeed = enemy:cfg("WalkSpeed")
	if now < retreatUntil and retreatGoal then
		enemy:moveTo(retreatGoal)
		return
	end
	local distance = enemy:distanceTo(targetRoot.Position)
	if distance <= enemy:cfg("DashRange") and now >= nextDash and enemy:canSee(target) then
		dash(targetRoot)
		return
	end
	-- approach on a slight curve instead of a straight line
	local toTarget = (targetRoot.Position - enemy.root.Position) * Vector3.new(1, 0, 1)
	local goal = targetRoot.Position
	if distance > 8 and toTarget.Magnitude > 0 then
		local side = Vector3.new(-toTarget.Unit.Z, 0, toTarget.Unit.X) * strafeSide
		goal += side * math.min(distance * 0.35, 10)
	end
	enemy:moveTo(goal)
end)
