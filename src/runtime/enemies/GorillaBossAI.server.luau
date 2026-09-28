--[[
	GorillaBossAI: the Silverback boss. Put this Script (with its EnemyKit
	module) inside the imported boss_gorilla model.

	  Slam      close range: pounds the ground, shockwave damages everyone nearby
	  Leap      far away: jumps at its target and lands with a bigger shockwave
	  Summon    at 70% and 35% health it opens its back bay and launches
	            Sentry Drones (needs a drone model named MinionName in
	            ServerStorage, e.g. the imported SentryDrone with DroneAI)
	  Enrage    below EnrageAt health it moves and attacks faster
	Players near the fight get a boss health bar at the top of the screen.

	Animations: AnimWalk = knuckle_walk, AnimSlam = slam, AnimSummon = spawn
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local model = script.Parent :: Model
local Kit = require(script:WaitForChild("EnemyKit"))

local enemy = Kit.new(model, {
	BossName = "Iron Silverback",
	MaxHealth = 900,
	WalkSpeed = 13,
	AggroRange = 120,
	LoseRange = 200,
	WanderRadius = 12,
	SlamDamage = 28,
	SlamRadius = 14,
	SlamCooldown = 3,
	SlamWindup = 0.7, -- seconds from wind-up to impact
	LeapDamage = 38,
	LeapRadius = 18,
	LeapCooldown = 9,
	LeapMinRange = 28,
	LeapTime = 1.1,
	MinionName = "SentryDrone",
	MinionCount = 2,
	SummonAt = "0.7,0.35", -- health fractions that trigger a summon
	EnrageAt = 0.35,
	BossBarRange = 160,
	ShowHealthBar = false, -- uses the screen boss bar instead
	AnimSlam = "",
	AnimSummon = "",
	AnimLeap = "",
})

local SHOCK_COLOR = Color3.fromRGB(255, 140, 50)
local busyUntil = 0
local nextSlam = 0
local nextLeap = os.clock() + 4
local enraged = false
local summonsDone: { [number]: boolean } = {}
local minions: { Model } = {}

local function scale(): number
	return if enraged then 0.65 else 1
end

local function groundBelowRoot(): Vector3
	return enemy:groundAt(enemy.root.Position) or (enemy.root.Position - Vector3.new(0, enemy.size.Y / 2, 0))
end

--------------------------------------------------------------------------------
-- Attacks
--------------------------------------------------------------------------------

local function slam(targetRoot: BasePart)
	local windup = enemy:cfg("SlamWindup") * scale()
	busyUntil = os.clock() + windup + 0.7
	nextSlam = os.clock() + enemy:cfg("SlamCooldown") * scale()
	enemy:stopMoving()
	enemy:face(targetRoot.Position)
	enemy:play("Slam", false, 1 / scale())
	task.delay(windup, function()
		if enemy.dead then
			return
		end
		local impact = enemy.root.Position + enemy.root.CFrame.LookVector * enemy.reach * 0.6
		local ground = enemy:groundAt(impact) or impact
		Kit.shockwave(ground + Vector3.new(0, 0.2, 0), enemy:cfg("SlamRadius"), SHOCK_COLOR)
		enemy:hitArea({ damage = enemy:cfg("SlamDamage"), radius = enemy:cfg("SlamRadius"), center = ground, falloff = true })
	end)
end

local function leap(targetRoot: BasePart)
	local root = enemy.root
	local flight = enemy:cfg("LeapTime")
	-- aim a little ahead of a moving target
	local landing = targetRoot.Position + targetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * flight * 0.5
	local ground = enemy:groundAt(landing)
	if not ground then
		return
	end
	landing = ground + Vector3.new(0, root.Position.Y - groundBelowRoot().Y, 0)
	nextLeap = os.clock() + enemy:cfg("LeapCooldown") * scale()
	busyUntil = os.clock() + flight + 1
	enemy:stopMoving()
	enemy:face(landing)
	enemy:play("Leap")
	-- ballistic launch that lands on `landing` after `flight` seconds
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	local velocity = (landing - root.Position - 0.5 * gravity * flight * flight) / flight
	enemy.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	task.wait(0.05)
	root.AssemblyLinearVelocity = velocity
	local started = os.clock()
	task.wait(0.3)
	repeat
		task.wait(0.05)
	until enemy.dead or enemy.humanoid.FloorMaterial ~= Enum.Material.Air or os.clock() - started > flight + 0.8
	if enemy.dead then
		return
	end
	local impact = groundBelowRoot()
	Kit.shockwave(impact + Vector3.new(0, 0.2, 0), enemy:cfg("LeapRadius"), SHOCK_COLOR)
	enemy:hitArea({ damage = enemy:cfg("LeapDamage"), radius = enemy:cfg("LeapRadius"), center = impact, falloff = true })
end

local function minionTemplate(): Model?
	local name = enemy:cfg("MinionName")
	local found = ServerStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name)
	return if found and found:IsA("Model") then found else nil
end

local warnedMinion = false
local function summon()
	busyUntil = os.clock() + 1.6
	enemy:stopMoving()
	enemy:play("Summon")
	local template = minionTemplate()
	if not template then
		if not warnedMinion then
			warnedMinion = true
			warn(`{model.Name}: put a model named "{enemy:cfg("MinionName")}" in ServerStorage to let the boss summon it`)
		end
		return
	end
	-- launch points: the bay bones if the rig has them, else above the back
	local spots: { Vector3 } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") and string.find(string.lower(d.Name), "drone", 1, true) then
			table.insert(spots, d.TransformedWorldCFrame.Position)
		end
	end
	task.wait(0.6)
	for i = 1, enemy:cfg("MinionCount") do
		if enemy.dead then
			return
		end
		local from = spots[(i - 1) % math.max(1, #spots) + 1]
			or (enemy.root.Position + Vector3.new(0, enemy.size.Y * 0.6, 0) + enemy.root.CFrame.RightVector * (i - 1.5) * 3)
		local minion = template:Clone()
		minion:SetAttribute("Respawn", false)
		minion:PivotTo(CFrame.new(from + Vector3.new(0, 2, 0)))
		minion.Parent = model.Parent
		table.insert(minions, minion)
		task.wait(0.25)
	end
end

local function setEnraged()
	if enraged then
		return
	end
	enraged = true
	enemy.humanoid.WalkSpeed = enemy:cfg("WalkSpeed") * 1.35
	local glow = Instance.new("PointLight")
	glow.Name = "EnrageGlow"
	glow.Color = Color3.fromRGB(255, 60, 30)
	glow.Range = enemy.size.Y * 2
	glow.Brightness = 0
	glow.Parent = enemy.root
	TweenService:Create(glow, TweenInfo.new(0.6), { Brightness = 3 }):Play()
end

--------------------------------------------------------------------------------
-- Boss bar (a ScreenGui per nearby player, driven from the server)
--------------------------------------------------------------------------------

local barName = "BossBar_" .. model.Name
local function makeBar(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = barName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 56)
	frame.Size = UDim2.new(0.42, 0, 0, 16)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(214, 62, 40)
	fill.BorderSizePixel = 0
	fill.Parent = frame
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -2)
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 235, 220)
	label.TextStrokeTransparency = 0.4
	label.Text = string.upper(enemy:cfg("BossName"))
	label.Parent = frame
	return gui
end

local function updateBars()
	local fraction = math.clamp(enemy.humanoid.Health / enemy.humanoid.MaxHealth, 0, 1)
	for _, player in Players:GetPlayers() do
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui then
			local character = player.Character
			local r = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local near = not enemy.dead and r ~= nil and (r.Position - enemy.root.Position).Magnitude < enemy:cfg("BossBarRange")
			local bar = gui:FindFirstChild(barName)
			if near and not bar then
				bar = makeBar()
				bar.Parent = gui
			elseif not near and bar then
				bar:Destroy()
				bar = nil
			end
			if bar then
				local fill = bar:FindFirstChild("Fill", true) :: Frame?
				if fill then
					fill.Size = UDim2.fromScale(fraction, 1)
					fill.BackgroundColor3 = if enraged then Color3.fromRGB(255, 90, 20) else Color3.fromRGB(214, 62, 40)
				end
			end
		end
	end
end

task.spawn(function()
	while model.Parent and not enemy.dead do
		updateBars()
		task.wait(0.25)
	end
	updateBars() -- removes the bars
end)

enemy:onDeath(function()
	updateBars()
	for _, minion in minions do
		local h = minion.Parent and minion:FindFirstChildOfClass("Humanoid")
		if h then
			h.Health = 0 -- the drones drop with their master
		end
	end
end)

--------------------------------------------------------------------------------
-- Brain
--------------------------------------------------------------------------------

local thresholds: { number } = {}
for piece in string.gmatch(enemy:cfg("SummonAt"), "[%d%.]+") do
	local value = tonumber(piece)
	if value then
		table.insert(thresholds, value)
	end
end

enemy:run(function()
	local now = os.clock()
	if now < busyUntil then
		return
	end
	local fraction = enemy.humanoid.Health / enemy.humanoid.MaxHealth
	if fraction <= enemy:cfg("EnrageAt") then
		setEnraged()
	end
	for i, at in thresholds do
		if fraction <= at and not summonsDone[i] then
			summonsDone[i] = true
			task.spawn(summon)
			return
		end
	end

	local target = enemy:findTarget()
	local targetRoot = enemy:targetRoot()
	if not target or not targetRoot then
		enemy:wander()
		return
	end
	local distance = enemy:distanceTo(targetRoot.Position)
	if distance <= enemy.reach + 2 and now >= nextSlam then
		slam(targetRoot)
	elseif distance >= enemy:cfg("LeapMinRange") and now >= nextLeap and enemy:canSee(target) then
		task.spawn(leap, targetRoot) -- sets busyUntil for the whole jump
	else
		enemy:moveTo(targetRoot.Position)
	end
end)
