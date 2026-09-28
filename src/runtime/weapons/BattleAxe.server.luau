--[[
	Battle Axe (server)
	  Chop        slow, heavy overhead blow
	  Whirlwind   spin that hits everything around you
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Combat, Effects = Core.Combat, Core.Effects

local weapon = Core.Server.new(tool)

local MODEL = "BattleAxe"
local WINDUP_POSE = CFrame.Angles(math.rad(55), 0, 0) -- head tipped back over the shoulder
local CHOP_POSE = CFrame.Angles(math.rad(-80), 0, 0) -- head driven forward and down
local SPIN_POSE = CFrame.Angles(0, 0, math.rad(-90)) -- axe held straight out to the side

local WINDUP = 0.28

weapon:on("Chop", function()
	if not weapon:ready("Chop", weapon:attr("Cooldown", 1.1)) then
		return
	end
	local custom = weapon:hasAnim("Chop")
	if not custom then
		weapon:pose(MODEL, WINDUP_POSE, WINDUP, Enum.EasingStyle.Sine)
	end
	task.delay(WINDUP, function()
		if not weapon.character then
			return
		end
		weapon:sound("Chop")
		weapon:trailFor(0.3)
		if not custom then
			weapon:pose(MODEL, CHOP_POSE, 0.1, Enum.EasingStyle.Quad)
			task.delay(0.35, function()
				weapon:pose(MODEL, nil, 0.3, Enum.EasingStyle.Sine)
			end)
		end
	end)

	local damage = weapon:attr("Damage", 38)
	Combat.swing(weapon, {
		range = weapon:attr("Range", 7.5),
		width = 6,
		height = 7,
		delay = WINDUP,
		duration = 0.2,
		onHit = function(humanoid, part)
			local root = weapon.root
			local _, blocked = Combat.damage(weapon, humanoid, damage, root and root.Position)
			Effects.burst(part.Position, if blocked then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(255, 190, 150), 14, 18)
		end,
	})
end)

weapon:on("Whirlwind", function()
	if not weapon:ready("Whirlwind", weapon:attr("WhirlwindCooldown", 7)) then
		return
	end
	local duration = 0.75
	weapon:sound("Whirlwind")
	weapon:trailFor(duration)
	if not weapon:hasAnim("Whirlwind") then
		weapon:pose(MODEL, SPIN_POSE, 0.1)
		task.delay(duration, function()
			weapon:pose(MODEL, nil, 0.25)
		end)
	end
	local damage = weapon:attr("WhirlwindDamage", 24)
	Combat.swing(weapon, {
		radius = weapon:attr("WhirlwindRadius", 9),
		delay = 0.05,
		duration = duration,
		onHit = function(humanoid, part)
			local root = weapon.root
			Combat.damage(weapon, humanoid, damage, root and root.Position)
			Effects.burst(part.Position, Color3.fromRGB(255, 190, 150), 12, 18)
		end,
	})
end)

weapon:onUnequip(function()
	weapon:trail(false)
end)
