--[[
	Longsword (client)
	  Click           slash, slash, lunge (click within ComboWindow to chain)
	  Q / Right-click hold to block
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))

local weapon = Core.Client.new(tool)

local combo = 0
local lastAttack = 0
local nextAttack = 0
local blocking = false

local function lungeForward()
	local root = weapon.root
	if not root then
		return
	end
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then
		return
	end
	local attachment = root:FindFirstChild("RootAttachment") or Instance.new("Attachment", root)
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment :: Attachment
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	push.LineDirection = flat.Unit
	push.LineVelocity = 38
	push.MaxForce = 60000
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.Parent = root
	task.delay(0.16, function()
		push:Destroy()
	end)
end

tool.Activated:Connect(function()
	if not weapon.equipped or blocking then
		return
	end
	local now = os.clock()
	if now < nextAttack then
		return
	end
	combo = if now - lastAttack <= weapon:attr("ComboWindow", 0.7) then combo % 3 + 1 else 1
	lastAttack = now
	local lunge = combo == 3
	nextAttack = now + weapon:attr("Cooldown", 0.45) * (if lunge then 1.6 else 1)

	if lunge then
		weapon:play("Lunge", "Lunge")
		lungeForward()
	else
		weapon:play("Slash" .. combo, "Slash")
	end
	weapon:fire("Attack", combo)
end)

weapon:onEquip(function()
	weapon:bindSecondary("Block", function(down)
		if down == blocking then
			return
		end
		blocking = down
		if down then
			weapon:play("Block")
		else
			weapon:stopAnim("Block")
		end
		weapon:fire("Block", down)
	end)
end)

weapon:onUnequip(function()
	blocking = false
	combo = 0
end)
