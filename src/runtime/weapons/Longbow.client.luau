--[[
	Longbow (client)
	  Hold click       draw (you turn to face your aim while drawing)
	  Release          loose the arrow
	  Q / Right-click  hold to zoom
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local TweenService = game:GetService("TweenService")

local weapon = Core.Client.new(tool)

local drawing = false
local drawStart = 0
local nextShot = 0
local savedFov: number? = nil

local function setZoom(on: boolean)
	local camera = workspace.CurrentCamera
	if on and not savedFov then
		savedFov = camera.FieldOfView
		TweenService:Create(camera, TweenInfo.new(0.2), { FieldOfView = weapon:attr("ZoomFOV", 40) }):Play()
	elseif not on and savedFov then
		TweenService:Create(camera, TweenInfo.new(0.2), { FieldOfView = savedFov }):Play()
		savedFov = nil
	end
end

local function stopDrawing()
	drawing = false
	weapon:stopAnim("Draw")
	if weapon.humanoid then
		weapon.humanoid.AutoRotate = true
	end
end

tool.Activated:Connect(function()
	if not weapon.equipped or drawing then
		return
	end
	local now = os.clock()
	if now < nextShot then
		return
	end
	drawing = true
	drawStart = now
	if weapon.humanoid then
		weapon.humanoid.AutoRotate = false
	end
	weapon:play("Draw")
	weapon:fire("Draw")
end)

tool.Deactivated:Connect(function()
	if not drawing then
		return
	end
	stopDrawing()
	local target = weapon:aimPoint(1500)
	weapon:face(target)
	weapon:play("Release")
	weapon:fire("Release", target)
	nextShot = os.clock() + weapon:attr("Cooldown", 0.35)
end)

weapon:onEquip(function()
	local hud = weapon:makeHud({ crosshair = true })
	weapon:everyFrame(function()
		if drawing then
			local charge = math.clamp((os.clock() - drawStart) / weapon:attr("DrawTime", 0.9), 0, 1)
			hud:setCharge(charge, charge >= 1)
			weapon:face(weapon:aimPoint(1500))
		else
			hud:setCharge(nil)
		end
	end)
	weapon:bindSecondary("Zoom", setZoom)
end)

weapon:onUnequip(function()
	if drawing then
		stopDrawing()
	end
	setZoom(false)
end)
