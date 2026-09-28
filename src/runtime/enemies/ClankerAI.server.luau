--[[
	ClankerAI: slow, tanky zombie robot. Put this Script (with its EnemyKit
	module) inside the imported zombie_clanker model.

	Shambles around its spawn point; when it notices a player it staggers
	after them, with the occasional lurching burst of speed, and clubs them
	when in reach. Getting hit makes it reel for a moment.

	Animations (publish the model's clips, paste IDs into the attributes):
	  AnimWalk = zombie_stagger, AnimAttack = attack_swing
]]

local model = script.Parent :: Model
local Kit = require(script:WaitForChild("EnemyKit"))

local enemy = Kit.new(model, {
	MaxHealth = 140,
	WalkSpeed = 8,
	AggroRange = 70,
	LoseRange = 110,
	Damage = 20,
	AttackCooldown = 1.8,
	AttackWindup = 0.55, -- seconds from swing start to impact
	LurchChance = 0.04, -- per think tick
	AnimAttack = "",
})

local nextAttack = 0
local busyUntil = 0
local lurchUntil = 0

local function attack()
	local targetRoot = enemy:targetRoot()
	if not targetRoot then
		return
	end
	busyUntil = os.clock() + enemy:cfg("AttackWindup") + 0.6
	nextAttack = os.clock() + enemy:cfg("AttackCooldown")
	enemy:stopMoving()
	enemy:face(targetRoot.Position)
	enemy:play("Attack")
	task.delay(enemy:cfg("AttackWindup"), function()
		if not enemy.dead then
			enemy:hitArea({ damage = enemy:cfg("Damage"), range = enemy.reach + 1 })
		end
	end)
end

-- reel when shot
local lastHealth = enemy.humanoid.Health
enemy.humanoid.HealthChanged:Connect(function(health)
	if health < lastHealth and health > 0 then
		busyUntil = math.max(busyUntil, os.clock() + 0.3)
		enemy:stopMoving()
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
		enemy.humanoid.WalkSpeed = enemy:cfg("WalkSpeed") * 0.6
		enemy:wander()
		return
	end
	if enemy:distanceTo(targetRoot.Position) <= enemy.reach and now >= nextAttack then
		attack()
		return
	end
	if now > lurchUntil + 2 and math.random() < enemy:cfg("LurchChance") then
		lurchUntil = now + 1.2
	end
	enemy.humanoid.WalkSpeed = enemy:cfg("WalkSpeed") * (if now < lurchUntil then 1.9 else 1)
	enemy:moveTo(targetRoot.Position)
end)
