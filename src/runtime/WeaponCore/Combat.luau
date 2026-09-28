--[[
	Combat: server-side hit detection and damage.

	Damage goes through Humanoid:TakeDamage (respects ForceFields) and leaves a
	classic "creator" ObjectValue on the victim's Humanoid, so standard
	leaderboard / kill-feed scripts credit the attacker.

	Blocking: a character with the attribute Blocking = true takes
	(1 - BlockReduction) damage from attacks that come from in front of it. Any
	of your own abilities can use this too.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Combat = {}

-- Humanoid + character model that own `part`, if any.
function Combat.findHumanoid(part: Instance): (Humanoid?, Model?)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

function Combat.canDamage(weapon, humanoid: Humanoid): boolean
	if humanoid.Health <= 0 then
		return false
	end
	local target = humanoid.Parent
	if target == weapon.character then
		return false
	end
	if weapon.tool:GetAttribute("FriendlyFire") ~= true and weapon.player then
		local other = Players:GetPlayerFromCharacter(target)
		if other and not weapon.player.Neutral and not other.Neutral and weapon.player.Team == other.Team then
			return false
		end
	end
	return true
end

function Combat.hasLineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	local projectiles = workspace:FindFirstChild("WeaponProjectiles")
	if projectiles then
		table.insert(list, projectiles)
	end
	params.FilterDescendantsInstances = list
	return workspace:Raycast(from, to - from, params) == nil
end

--[[
	Allies for support abilities: yourself, and other players on your team.
	Without teams (players Neutral), every player counts as an ally and
	non-player Humanoids (NPC enemies) do not.
]]
function Combat.isAlly(weapon, humanoid: Humanoid): boolean
	local target = humanoid.Parent
	if target == weapon.character then
		return true
	end
	local other = Players:GetPlayerFromCharacter(target)
	if not other or not weapon.player then
		return false
	end
	if weapon.player.Neutral or other.Neutral then
		return true
	end
	return weapon.player.Team == other.Team
end

-- Heals up to MaxHealth; returns the amount actually restored.
function Combat.heal(humanoid: Humanoid, amount: number): number
	if humanoid.Health <= 0 then
		return 0
	end
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, before + amount)
	return humanoid.Health - before
end

-- True when `attackerPosition` is behind the target (for backstabs).
function Combat.isBehind(target: Model, attackerPosition: Vector3): boolean
	local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local offset = (attackerPosition - root.Position) * Vector3.new(1, 0, 1)
	if offset.Magnitude < 0.01 then
		return false
	end
	return root.CFrame.LookVector:Dot(offset.Unit) < -0.3
end

local function tag(humanoid: Humanoid, attacker: Player?)
	local old = humanoid:FindFirstChild("creator")
	if old then
		old:Destroy()
	end
	if attacker then
		local creator = Instance.new("ObjectValue")
		creator.Name = "creator"
		creator.Value = attacker
		creator.Parent = humanoid
		Debris:AddItem(creator, 3)
	end
end

--[[
	Combat.damage(weapon, humanoid, amount, fromPosition?) -> (dealt, blocked)
	`weapon` is the Server weapon object (see Server.luau).
]]
function Combat.damage(weapon, humanoid: Humanoid, amount: number, fromPosition: Vector3?): (number, boolean)
	local target = humanoid.Parent :: Model
	local blocked = false
	if target:GetAttribute("Blocking") and fromPosition then
		local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local toAttacker = (fromPosition - root.Position) * Vector3.new(1, 0, 1)
			if toAttacker.Magnitude > 0.01 and root.CFrame.LookVector:Dot(toAttacker.Unit) > 0.2 then
				local reduction = target:GetAttribute("BlockReduction")
				amount *= 1 - (if type(reduction) == "number" then reduction else 0.7)
				blocked = true
				-- lets the blocker's weapon react (sound, sparks)
				target:SetAttribute("BlockedHit", os.clock())
			end
		end
	end
	tag(humanoid, weapon.player)
	humanoid:TakeDamage(amount)
	return amount, blocked
end

--[[
	Opens a melee hit window. Each humanoid is hit at most once per call.
	opts = {
	  range, width?, height?      -- box in front of the attacker's HumanoidRootPart
	  radius?                     -- or: sphere around it (spin attacks)
	  delay?, duration?           -- seconds
	  onHit(humanoid, part, model)
	}
]]
function Combat.swing(weapon, opts)
	local character = weapon.character
	local root = weapon.root
	if not character or not root then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit: { [Humanoid]: boolean } = {}

	task.delay(opts.delay or 0, function()
		local started = os.clock()
		repeat
			if not root.Parent or weapon.character ~= character then
				return
			end
			local parts
			if opts.radius then
				parts = workspace:GetPartBoundsInRadius(root.Position, opts.radius, params)
			else
				local range = opts.range or 6
				local cf = root.CFrame * CFrame.new(0, 0, -range / 2)
				parts = workspace:GetPartBoundsInBox(cf, Vector3.new(opts.width or 5, opts.height or 6, range), params)
			end
			for _, part in parts do
				local humanoid, model = Combat.findHumanoid(part)
				if humanoid and model and not hit[humanoid] and Combat.canDamage(weapon, humanoid) then
					local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
					local aimAt = if targetRoot then targetRoot.Position else part.Position
					if Combat.hasLineOfSight(root.Position, aimAt, { character, model }) then
						hit[humanoid] = true
						opts.onHit(humanoid, part, model)
					end
				end
			end
			RunService.Heartbeat:Wait()
		until os.clock() - started >= (opts.duration or 0.2)
	end)
end

-- Radial damage with linear falloff down to `minScale` at the edge.
function Combat.explode(weapon, position: Vector3, radius: number, damage: number, minScale: number?)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { weapon.character }
	local done: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius, params) do
		local humanoid, model = Combat.findHumanoid(part)
		if humanoid and model and not done[humanoid] and Combat.canDamage(weapon, humanoid) then
			done[humanoid] = true
			local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local at = if targetRoot then targetRoot.Position else part.Position
			if Combat.hasLineOfSight(position, at, { model }) then
				local t = math.clamp((at - position).Magnitude / radius, 0, 1)
				local scale = 1 - t * (1 - (minScale or 0.4))
				Combat.damage(weapon, humanoid, damage * scale, position)
			end
		end
	end
end

return Combat
