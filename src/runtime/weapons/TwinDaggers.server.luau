--[[
	Twin Daggers (server)
	  Stab(hand)      quick stab with the "Right" or "Left" dagger; x BackstabMultiplier from behind
	  Throw(target)   hurl the off-hand dagger; it reappears after ThrowCooldown
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Combat, Effects, Projectile, Util = Core.Combat, Core.Effects, Core.Projectile, Core.Util

local weapon = Core.Server.new(tool)

local MAIN, OFFHAND = "MainDagger", "OffhandDagger"
local offhand = tool:WaitForChild(OFFHAND) :: Model
local VIOLET = Color3.fromRGB(190, 120, 255)

-- fallback poses
local RIGHT_STAB = CFrame.Angles(math.rad(-90), 0, 0) -- point forward (arm lunges via the default animation)
local LEFT_STAB = CFrame.new(0, 1.1, 0) -- thrust the off-hand dagger forward along its blade

local offhandAway = false

weapon:on("Stab", function(_player, hand)
	if hand ~= "Left" and hand ~= "Right" then
		return
	end
	if hand == "Left" and offhandAway then
		hand = "Right"
	end
	if not weapon:ready("Stab", weapon:attr("Cooldown", 0.28)) then
		return
	end
	local model = if hand == "Right" then MAIN else OFFHAND
	weapon:sound("Stab")
	weapon:trailFor(0.18, model)
	if not weapon:hasAnim("Stab" .. hand) then
		weapon:pose(model, if hand == "Right" then RIGHT_STAB else LEFT_STAB, 0.06)
		task.delay(0.16, function()
			weapon:pose(model, nil, 0.12)
		end)
	end

	local damage = weapon:attr("Damage", 12)
	local multiplier = weapon:attr("BackstabMultiplier", 2)
	Combat.swing(weapon, {
		range = weapon:attr("Range", 5.5),
		width = 4,
		height = 5,
		delay = 0.04,
		duration = 0.14,
		onHit = function(humanoid, part, target)
			local root = weapon.root
			local backstab = root ~= nil and Combat.isBehind(target, root.Position)
			Combat.damage(weapon, humanoid, damage * (if backstab then multiplier else 1), root and root.Position)
			Effects.burst(part.Position, VIOLET, if backstab then 22 else 7, if backstab then 22 else 12)
		end,
	})
end)

weapon:on("Throw", function(_player, target)
	if offhandAway or not Util.isVector3(target) then
		return
	end
	local cooldown = weapon:attr("ThrowCooldown", 3)
	if not weapon:ready("Throw", cooldown) then
		return
	end
	local root = weapon.root
	local character = weapon.character
	if not root or not character then
		return
	end

	-- throw from just in front of the chest toward the aim point
	local origin = root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1.2, 0)
	local direction = target - origin
	if direction.Magnitude < 1 or direction.Unit:Dot(root.CFrame.LookVector) < -0.2 then
		direction = root.CFrame.LookVector
	end

	weapon:sound("Throw")
	Projectile.fire({
		template = offhand,
		origin = origin,
		direction = direction.Unit,
		speed = weapon:attr("ThrowSpeed", 150),
		gravity = true,
		orient = CFrame.Angles(-math.pi / 2, 0, 0), -- blade (+Y) leads
		tipOffset = 2.2,
		maxDistance = 300,
		lifetime = 4,
		stick = 5,
		ignore = { character },
		onHit = function(result)
			local humanoid = Combat.findHumanoid(result.Instance)
			if humanoid and Combat.canDamage(weapon, humanoid) then
				Combat.damage(weapon, humanoid, weapon:attr("ThrowDamage", 22), origin)
				Effects.burst(result.Position, VIOLET, 14, 16)
			else
				Effects.burst(result.Position, Color3.fromRGB(230, 230, 230), 6, 8)
			end
		end,
	})

	-- the off-hand is empty until the dagger "returns"
	offhandAway = true
	Effects.setVisible(offhand, false)
	task.delay(cooldown, function()
		offhandAway = false
		Effects.setVisible(offhand, true)
		if tool.Parent and tool.Parent:IsA("Backpack") then
			weapon:_refreshHolster() -- holstered copy was made while the dagger was away
		end
	end)
end)

weapon:onUnequip(function()
	weapon:trail(false)
end)
