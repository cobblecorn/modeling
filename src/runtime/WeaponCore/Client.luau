--[[
	Client weapon base (used by each weapon's LocalScript).

	  * predicts the rig locally so the weapon is in hand instantly
	  * plays your custom animations (Anim<Key> attributes on the Tool) and falls
	    back to Roblox's built-in tool animations ("Slash" / "Lunge") when unset
	  * secondary action on Q / right mouse / gamepad L2, with an on-screen
	    button on touch devices
	  * aim point under the mouse, touch or crosshair
	  * a small HUD: charge bar + ability cooldown
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Util = require(script.Parent.Util)
local Rig = require(script.Parent.Rig)

local Client = {}
Client.__index = Client

local lastTouch: Vector2? = nil
local touchHooked = false

local function hookTouch()
	if touchHooked then
		return
	end
	touchHooked = true
	local function track(input: InputObject, processed: boolean)
		if not processed then
			lastTouch = Vector2.new(input.Position.X, input.Position.Y)
		end
	end
	UserInputService.TouchStarted:Connect(track)
	UserInputService.TouchMoved:Connect(track)
end

function Client.new(tool: Tool)
	local self = setmetatable({}, Client)
	self.tool = tool
	self.remote = tool:WaitForChild("Remote") :: RemoteEvent
	self.player = Players.LocalPlayer
	self.equipped = false
	self.tracks = {} :: { [string]: AnimationTrack }
	self.localJoints = {} :: { [string]: Motor6D }
	self.cleanup = {} :: { () -> () }
	self.equipCallbacks = {}
	self.unequipCallbacks = {}
	self.character = nil :: Model?
	self.humanoid = nil :: Humanoid?
	self.root = nil :: BasePart?
	self.animator = nil :: Animator?
	self.hud = nil
	hookTouch()
	tool.Equipped:Connect(function()
		self:_equipped()
	end)
	tool.Unequipped:Connect(function()
		self:_unequipped()
	end)
	return self
end

function Client:attr(name: string, default: any): any
	return Util.attr(self.tool, name, default)
end

function Client:fire(action: string, ...)
	self.remote:FireServer(action, ...)
end

function Client:onEquip(callback: () -> ())
	table.insert(self.equipCallbacks, callback)
end

function Client:onUnequip(callback: () -> ())
	table.insert(self.unequipCallbacks, callback)
end

-- Runs `fn(dt)` every frame while equipped.
function Client:everyFrame(fn: (number) -> ())
	local connection = RunService.RenderStepped:Connect(fn)
	table.insert(self.cleanup, function()
		connection:Disconnect()
	end)
end

--------------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------------

function Client:hasAnim(key: string): boolean
	local id = self.tool:GetAttribute("Anim" .. key)
	return type(id) == "string" and id ~= ""
end

--[[
	Plays the animation in the Tool's Anim<key> attribute (an asset id such as
	"rbxassetid://123" or just "123"). If none is set and `fallback` is given,
	asks the default Animate script for its built-in tool animation instead.
]]
function Client:play(key: string, fallback: string?, speed: number?): AnimationTrack?
	if self:hasAnim(key) and self.animator then
		local track = self.tracks[key]
		if not track then
			local id = self.tool:GetAttribute("Anim" .. key) :: string
			local animation = Instance.new("Animation")
			animation.AnimationId = if string.match(id, "^%d+$") then "rbxassetid://" .. id else id
			local ok, result = pcall(function()
				return (self.animator :: Animator):LoadAnimation(animation)
			end)
			if ok then
				track = result
				self.tracks[key] = track
			else
				warn(`[{self.tool.Name}] could not load Anim{key}: {result}`)
			end
		end
		if track then
			track:Play(0.1, 1, speed or 1)
			return track
		end
	end
	if fallback then
		local value = Instance.new("StringValue")
		value.Name = "toolanim"
		value.Value = fallback
		value.Parent = self.tool
		Debris:AddItem(value, 0.5)
	end
	return nil
end

function Client:stopAnim(key: string, fade: number?)
	local track = self.tracks[key]
	if track then
		track:Stop(fade or 0.15)
	end
end

--------------------------------------------------------------------------------
-- Input / aiming
--------------------------------------------------------------------------------

--[[
	Binds the weapon's secondary action (call from onEquip). `callback(true)`
	on press, `callback(false)` on release. Right mouse is passed through so
	camera dragging keeps working.
]]
function Client:bindSecondary(title: string, callback: (boolean) -> ())
	local name = "WeaponSecondary_" .. self.tool.Name
	ContextActionService:BindAction(name, function(_, state, input)
		if state == Enum.UserInputState.Begin then
			callback(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			callback(false)
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL2, Enum.UserInputType.MouseButton2)
	ContextActionService:SetTitle(name, title)
	table.insert(self.cleanup, function()
		ContextActionService:UnbindAction(name)
	end)
end

-- World position the player is aiming at.
function Client:aimPoint(maxDistance: number?): Vector3
	local distance = maxDistance or 1000
	local camera = workspace.CurrentCamera
	local lastType = UserInputService:GetLastInputType()
	local ray: Ray
	if lastType == Enum.UserInputType.Touch and lastTouch then
		ray = camera:ScreenPointToRay(lastTouch.X, lastTouch.Y)
	elseif string.find(lastType.Name, "Gamepad") then
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	else
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { self.character :: Instance }
	local projectiles = workspace:FindFirstChild("WeaponProjectiles")
	if projectiles then
		table.insert(ignore, projectiles)
	end
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(ray.Origin, ray.Direction * distance, params)
	return if result then result.Position else ray.Origin + ray.Direction * distance
end

-- Turns the character to face a point (yaw only).
function Client:face(point: Vector3)
	local root = self.root
	if not root then
		return
	end
	local flat = Vector3.new(point.X, root.Position.Y, point.Z)
	if (flat - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

local Hud = {}
Hud.__index = Hud

function Client:makeHud(opts: { crosshair: boolean? }?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeaponHud_" .. self.tool.Name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -116)
	holder.Size = UDim2.fromOffset(220, 40)
	holder.BackgroundTransparency = 1
	holder.Parent = gui

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	bar.BackgroundTransparency = 0.35
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = holder
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 214, 120)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, 12)
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = holder

	gui.Parent = self.player:WaitForChild("PlayerGui")

	local previousIcon = UserInputService.MouseIcon
	if opts and opts.crosshair then
		UserInputService.MouseIcon = "rbxasset://textures/GunCursor.png"
	end

	local hud = setmetatable({ gui = gui, bar = bar, fill = fill, label = label }, Hud)
	table.insert(self.cleanup, function()
		if opts and opts.crosshair then
			UserInputService.MouseIcon = previousIcon
		end
		gui:Destroy()
	end)
	self.hud = hud
	return hud
end

-- 0..1 shows the bar, nil hides it.
function Hud:setCharge(fraction: number?, full: boolean?)
	self.bar.Visible = fraction ~= nil
	if fraction then
		self.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		self.fill.BackgroundColor3 = if full then Color3.fromRGB(120, 255, 170) else Color3.fromRGB(255, 214, 120)
	end
end

function Hud:setText(text: string)
	self.label.Text = text
end

-- Shows "<name>: ready" or "<name>: 2.4s" for an ability.
function Hud:setAbility(name: string, readyAt: number)
	local remaining = readyAt - os.clock()
	if remaining > 0 then
		self.label.Text = string.format("%s  %.1fs", name, remaining)
		self.label.TextColor3 = Color3.fromRGB(190, 190, 200)
	else
		self.label.Text = name .. "  ready"
		self.label.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

--------------------------------------------------------------------------------
-- Equip lifecycle
--------------------------------------------------------------------------------

function Client:_equipped()
	local character = self.tool.Parent :: Model
	self.character = character
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.animator = if self.humanoid then self.humanoid:FindFirstChildOfClass("Animator") else nil
	self.equipped = true
	self.localJoints = Rig.predict(self.tool, character)
	self:play("Equip")
	self:play("Idle")
	for _, callback in self.equipCallbacks do
		task.spawn(callback)
	end
end

function Client:_unequipped()
	self.equipped = false
	for _, callback in self.unequipCallbacks do
		task.spawn(callback)
	end
	for _, fn in self.cleanup do
		fn()
	end
	table.clear(self.cleanup)
	self.hud = nil
	for _, track in self.tracks do
		track:Stop(0.15)
	end
	Rig.detachAll(self.tool, self.localJoints)
end

return Client
