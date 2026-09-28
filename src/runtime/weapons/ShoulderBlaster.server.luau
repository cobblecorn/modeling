--[[
	Shoulder Blaster (server)
	  Aim(yaw, pitch)        turret angles from the owner (replicated to everyone)
	  Fire(target)           energy bolt toward the target
	  Charge(on)             start charging a heavy shot
	  ChargeRelease(target)  release; fires an explosive orb if fully charged
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Combat, Effects, Projectile, Rig, Util = Core.Combat, Core.Effects, Core.Projectile, Core.Rig, Core.Util

local weapon = Core.Server.new(tool)

local blaster = tool:WaitForChild("ShoulderBlaster") :: Model
local yawJoint = blaster:WaitForChild("YawBase"):WaitForChild("Yaw") :: Motor6D
local pitchJoint = blaster:WaitForChild("Cannon"):WaitForChild("Pitch") :: Motor6D
local barrel = blaster:WaitForChild("Barrel")
local recoilJoint = barrel:WaitForChild("Recoil") :: Motor6D
local muzzle = barrel:WaitForChild("Muzzle") :: Attachment

-- keep projectile templates out of the world
local templates = tool:WaitForChild("ProjectileTemplates")
local BOLT = templates:WaitForChild("Bolt")
local CHARGED = templates:WaitForChild("ChargedBolt")
templates.Parent = nil

local CYAN = Color3.fromRGB(80, 220, 255)

local charging = false
local chargeStart = 0
local chargedReadyAt = 0
local lastAim = 0

local function clampAim(yaw: number, pitch: number): (number, number)
	return math.clamp(yaw, -math.rad(weapon:attr("YawRight", 100)), math.rad(weapon:attr("YawLeft", 25))),
		math.clamp(pitch, -math.rad(weapon:attr("PitchDown", 35)), math.rad(weapon:attr("PitchUp", 70)))
end

local function resetAim()
	Rig.setPose(yawJoint, nil)
	Rig.setPose(pitchJoint, nil)
end

local function kick(distance: number)
	local flash = muzzle:FindFirstChild("Flash") :: PointLight?
	local sparks = muzzle:FindFirstChild("MuzzleSparks") :: ParticleEmitter?
	if flash then
		flash.Enabled = true
		task.delay(0.06, function()
			flash.Enabled = false
		end)
	end
	if sparks then
		sparks:Emit(10)
	end
	Effects.pose(recoilJoint, CFrame.new(0, 0, distance), 0.03)
	task.delay(0.05, function()
		Effects.pose(recoilJoint, nil, 0.15)
	end)
end

-- direction from the muzzle to `target`, limited to where the barrel points
local function aim(target: Vector3): (Vector3, Vector3)
	local origin = muzzle.WorldPosition
	local forward = muzzle.WorldCFrame.LookVector
	local offset = target - origin
	if offset.Magnitude < 1 then
		return origin, forward
	end
	local direction = offset.Unit
	if direction:Dot(forward) < math.cos(math.rad(40)) then
		direction = forward
	end
	return origin, direction
end

local function setCharging(on: boolean)
	charging = on
	local particles = muzzle:FindFirstChild("ChargeParticles") :: ParticleEmitter?
	if particles then
		particles.Enabled = on
	end
	local sound = Util.findSound(tool, "Charging")
	if sound then
		if on then
			sound:Play()
		else
			sound:Stop()
		end
	end
end

weapon:on("Aim", function(_player, yaw, pitch)
	if not Util.isFiniteNumber(yaw) or not Util.isFiniteNumber(pitch) then
		return
	end
	local now = os.clock()
	if now - lastAim < 1 / 30 then
		return
	end
	lastAim = now
	yaw, pitch = clampAim(yaw, pitch)
	Rig.setPose(yawJoint, CFrame.Angles(0, yaw, 0))
	Rig.setPose(pitchJoint, CFrame.Angles(pitch, 0, 0))
end)

weapon:on("Fire", function(_player, target)
	if charging or not Util.isVector3(target) then
		return
	end
	if not weapon:ready("Fire", weapon:attr("FireRate", 0.2)) then
		return
	end
	local origin, direction = aim(target)
	local speed = weapon:attr("BoltSpeed", 240)
	local range = weapon:attr("Range", 600)
	local damage = weapon:attr("Damage", 12)
	Projectile.fire({
		template = BOLT,
		origin = origin,
		direction = direction,
		speed = speed,
		gravity = false,
		tipOffset = 0.55,
		maxDistance = range,
		lifetime = range / speed + 0.5,
		ignore = { weapon.character },
		onHit = function(result)
			local humanoid = Combat.findHumanoid(result.Instance)
			if humanoid and Combat.canDamage(weapon, humanoid) then
				Combat.damage(weapon, humanoid, damage, origin)
			end
			Effects.burst(result.Position, CYAN, 10, 16)
			Effects.flash(result.Position, CYAN, 1.8, 0.15)
			weapon:sound("Impact", result.Position)
		end,
	})
	weapon:sound("Fire")
	kick(0.3)
end)

weapon:on("Charge", function(_player, on)
	if on == true and not charging and os.clock() >= chargedReadyAt then
		chargeStart = os.clock()
		setCharging(true)
	end
end)

weapon:on("ChargeRelease", function(_player, target)
	if not charging then
		return
	end
	setCharging(false)
	local held = os.clock() - chargeStart
	if held < weapon:attr("ChargeTime", 1.2) * 0.85 or not Util.isVector3(target) then
		return
	end
	chargedReadyAt = os.clock() + weapon:attr("ChargedCooldown", 5) * 0.85

	local radius = weapon:attr("ChargedRadius", 10)
	local damage = weapon:attr("ChargedDamage", 55)
	local function explode(position: Vector3)
		Effects.explosion(position, radius, CYAN)
		Combat.explode(weapon, position, radius, damage, 0.4)
	end
	local origin, direction = aim(target)
	local speed = weapon:attr("BoltSpeed", 240) * 0.6
	local range = weapon:attr("Range", 600)
	Projectile.fire({
		template = CHARGED,
		origin = origin,
		direction = direction,
		speed = speed,
		gravity = false,
		tipOffset = 0.5,
		maxDistance = range,
		lifetime = range / speed + 0.5,
		ignore = { weapon.character },
		onHit = function(result)
			local humanoid = Combat.findHumanoid(result.Instance)
			if humanoid and Combat.canDamage(weapon, humanoid) then
				Combat.damage(weapon, humanoid, damage * 0.5, origin) -- direct hit bonus
			end
			explode(result.Position + result.Normal * 0.5)
		end,
		onExpire = explode,
	})
	weapon:sound("ChargedFire")
	kick(0.5)
end)

weapon:onUnequip(function()
	setCharging(false)
	resetAim()
end)
