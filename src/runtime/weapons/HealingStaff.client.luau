--[[
	Healing Staff (client)
	  Click / hold      Mend whoever is under your aim (allies heal, enemies sting)
	  Q / Right-click   Renewal pulse around you
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))

local weapon = Core.Client.new(tool)

local holding = false
local nextCast = 0
local pulseReadyAt = 0

local function cast()
	local now = os.clock()
	if now < nextCast then
		return
	end
	nextCast = now + weapon:attr("Cooldown", 0.5)
	local target = weapon:aimPoint(weapon:attr("Range", 90) + 20)
	weapon:face(target)
	weapon:play("Cast", "Lunge")
	weapon:fire("Mend", target)
end

tool.Activated:Connect(function()
	holding = true
	if weapon.equipped then
		cast()
	end
end)

tool.Deactivated:Connect(function()
	holding = false
end)

weapon:onEquip(function()
	local hud = weapon:makeHud({ crosshair = true })
	weapon:everyFrame(function()
		if holding then
			cast()
		end
		hud:setAbility("Renewal", pulseReadyAt)
	end)
	weapon:bindSecondary("Renew", function(down)
		if not down then
			return
		end
		local now = os.clock()
		if now < pulseReadyAt then
			return
		end
		pulseReadyAt = now + weapon:attr("PulseCooldown", 10)
		weapon:play("Pulse", "Slash")
		weapon:fire("Pulse")
	end)
end)

weapon:onUnequip(function()
	holding = false
end)
