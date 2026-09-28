--[[
	Shoulder Blaster (client)
	  The turret follows your aim (mouse / touch / crosshair).
	  Hold click         rapid fire
	  Hold Q / R-click   charge; release when the bar is full for an explosive shot
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Rig = Core.Rig

local weapon = Core.Client.new(tool)

local blaster = tool:WaitForChild("ShoulderBlaster") :: Model
local body = blaster:WaitForChild("BodyAttach") :: BasePart
local yawJoint = blaster:WaitForChild("YawBase"):WaitForChild("Yaw") :: Motor6D
local pitchJoint = blaster:WaitForChild("Cannon"):WaitForChild("Pitch") :: Motor6D

local yaw, pitch = 0, 0
local sentYaw, sentPitch, lastSent = math.huge, math.huge, 0
local firing = false
local nextFire = 0
local charging = false
local chargeStart = 0
local chargedReadyAt = 0

local function restOf(joint: Motor6D): CFrame
	local rest = joint:GetAttribute("RestC0")
	return if typeof(rest) == "CFrame" then rest else joint.C0
end

-- yaw/pitch that point the barrel at `target`, within the Tool's limits
local function solveAim(target: Vector3): (number, number)
	local yawFrame = body.CFrame * restOf(yawJoint)
	local localTarget = yawFrame:PointToObjectSpace(target)
	local wantYaw = math.atan2(-localTarget.X, -localTarget.Z)
	local pitchFrame = yawFrame * CFrame.Angles(0, wantYaw, 0) * restOf(pitchJoint)
	local p = pitchFrame:PointToObjectSpace(target)
	local wantPitch = math.atan2(p.Y, -p.Z)
	return math.clamp(wantYaw, -math.rad(weapon:attr("YawRight", 100)), math.rad(weapon:attr("YawLeft", 25))),
		math.clamp(wantPitch, -math.rad(weapon:attr("PitchDown", 35)), math.rad(weapon:attr("PitchUp", 70)))
end

tool.Activated:Connect(function()
	firing = true
end)

tool.Deactivated:Connect(function()
	firing = false
end)

weapon:onEquip(function()
	yaw, pitch = 0, 0
	local hud = weapon:makeHud({ crosshair = true })

	weapon:everyFrame(function(dt)
		local now = os.clock()
		local range = weapon:attr("Range", 600)
		local target = weapon:aimPoint(range)

		-- swing the turret toward the target at TurnSpeed deg/s
		local wantYaw, wantPitch = solveAim(target)
		local step = math.rad(weapon:attr("TurnSpeed", 540)) * dt
		yaw += math.clamp(wantYaw - yaw, -step, step)
		pitch += math.clamp(wantPitch - pitch, -step, step)
		Rig.setPose(yawJoint, CFrame.Angles(0, yaw, 0))
		Rig.setPose(pitchJoint, CFrame.Angles(pitch, 0, 0))
		if now - lastSent > 1 / 15 and (math.abs(yaw - sentYaw) > 0.01 or math.abs(pitch - sentPitch) > 0.01) then
			lastSent, sentYaw, sentPitch = now, yaw, pitch
			weapon:fire("Aim", yaw, pitch)
		end

		if firing and not charging and now >= nextFire then
			nextFire = now + weapon:attr("FireRate", 0.2)
			weapon:fire("Fire", target)
		end

		if charging then
			local charge = math.clamp((now - chargeStart) / weapon:attr("ChargeTime", 1.2), 0, 1)
			hud:setCharge(charge, charge >= 1)
		else
			hud:setCharge(nil)
		end
		hud:setAbility("Charged shot", chargedReadyAt)
	end)

	weapon:bindSecondary("Charge", function(down)
		local now = os.clock()
		if down then
			if not charging and now >= chargedReadyAt then
				charging = true
				chargeStart = now
				weapon:fire("Charge", true)
			end
		elseif charging then
			charging = false
			if now - chargeStart >= weapon:attr("ChargeTime", 1.2) then
				chargedReadyAt = now + weapon:attr("ChargedCooldown", 5)
			end
			weapon:fire("ChargeRelease", weapon:aimPoint(weapon:attr("Range", 600)))
		end
	end)
end)

weapon:onUnequip(function()
	firing = false
	charging = false
end)
