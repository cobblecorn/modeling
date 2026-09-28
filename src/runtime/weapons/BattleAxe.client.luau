--[[
	Battle Axe (client)
	  Click            heavy chop
	  Q / Right-click  whirlwind spin
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))

local weapon = Core.Client.new(tool)

local nextChop = 0
local whirlwindReadyAt = 0
local spinning = false

local function spin(duration: number)
	local root, humanoid = weapon.root, weapon.humanoid
	if not root or not humanoid then
		return
	end
	spinning = true
	humanoid.AutoRotate = false
	local _, startYaw, _ = root.CFrame:ToOrientation()
	local started = os.clock()
	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 or not weapon.equipped or not root.Parent then
			connection:Disconnect()
			humanoid.AutoRotate = true
			spinning = false
			return
		end
		-- two full turns, easing out
		local eased = 1 - (1 - t) ^ 2
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, startYaw - eased * math.pi * 4, 0)
	end)
end

tool.Activated:Connect(function()
	if not weapon.equipped or spinning then
		return
	end
	local now = os.clock()
	if now < nextChop then
		return
	end
	nextChop = now + weapon:attr("Cooldown", 1.1)
	if not weapon:play("Chop") then
		-- built-in slash, timed to land with the chop
		task.delay(0.2, function()
			if weapon.equipped then
				weapon:play("Chop", "Slash")
			end
		end)
	end
	weapon:fire("Chop")
end)

weapon:onEquip(function()
	local hud = weapon:makeHud()
	weapon:everyFrame(function()
		hud:setAbility("Whirlwind", whirlwindReadyAt)
	end)
	weapon:bindSecondary("Spin", function(down)
		if not down or spinning then
			return
		end
		local now = os.clock()
		if now < whirlwindReadyAt then
			return
		end
		whirlwindReadyAt = now + weapon:attr("WhirlwindCooldown", 7)
		weapon:play("Whirlwind")
		weapon:fire("Whirlwind")
		spin(0.75)
	end)
end)
