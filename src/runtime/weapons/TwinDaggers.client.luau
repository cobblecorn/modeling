--[[
	Twin Daggers (client)
	  Click            alternate right / left stabs
	  Q / Right-click  throw the off-hand dagger at your aim point
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))

local weapon = Core.Client.new(tool)

local nextStab = 0
local nextHand = "Right"
local throwReadyAt = 0

tool.Activated:Connect(function()
	if not weapon.equipped then
		return
	end
	local now = os.clock()
	if now < nextStab then
		return
	end
	nextStab = now + weapon:attr("Cooldown", 0.28)
	local hand = nextHand
	if hand == "Left" and now < throwReadyAt then
		hand = "Right" -- off-hand dagger is still "in the air"
	end
	nextHand = if hand == "Right" then "Left" else "Right"
	if hand == "Right" then
		weapon:play("StabRight", "Lunge")
	else
		weapon:play("StabLeft")
	end
	weapon:fire("Stab", hand)
end)

weapon:onEquip(function()
	local hud = weapon:makeHud()
	weapon:everyFrame(function()
		hud:setAbility("Throw", throwReadyAt)
	end)
	weapon:bindSecondary("Throw", function(down)
		if not down then
			return
		end
		local now = os.clock()
		if now < throwReadyAt then
			return
		end
		throwReadyAt = now + weapon:attr("ThrowCooldown", 3)
		local target = weapon:aimPoint(300)
		weapon:face(target)
		weapon:play("Throw", "Slash")
		weapon:fire("Throw", target)
	end)
end)
