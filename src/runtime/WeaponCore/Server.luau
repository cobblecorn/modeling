--[[
	Server weapon base. Handles the parts every weapon needs:
	  * rigging the models onto the character on equip / removing on unequip
	  * holstered copies while the tool is in the backpack
	  * validated RemoteEvent dispatch (only the holder, only while alive)
	  * per-action cooldowns, sounds, trails and joint poses

	local weapon = Server.new(tool)
	weapon:on("Attack", function(player, ...) end)
]]

local Players = game:GetService("Players")

local Util = require(script.Parent.Util)
local Rig = require(script.Parent.Rig)
local Effects = require(script.Parent.Effects)

local Server = {}
Server.__index = Server

function Server.new(tool: Tool)
	local self = setmetatable({}, Server)
	self.tool = tool
	self.remote = tool:WaitForChild("Remote") :: RemoteEvent
	self.handlers = {}
	self.equipCallbacks = {}
	self.unequipCallbacks = {}
	self.cooldowns = {}
	self.joints = {} :: { [string]: Motor6D }
	self.holstered = {} :: { Model }
	self.character = nil :: Model?
	self.player = nil :: Player?
	self.humanoid = nil :: Humanoid?
	self.root = nil :: BasePart?

	Rig.syncGrip(tool)
	Rig.setStowed(tool, true)

	tool.Equipped:Connect(function()
		self:_equipped()
	end)
	tool.Unequipped:Connect(function()
		self:_unequipped()
	end)
	self.remote.OnServerEvent:Connect(function(player, action, ...)
		self:_dispatch(player, action, ...)
	end)
	tool.AncestryChanged:Connect(function()
		self:_refreshHolster()
	end)
	task.defer(function()
		self:_refreshHolster()
	end)
	return self
end

function Server:attr(name: string, default: any): any
	return Util.attr(self.tool, name, default)
end

-- True when the player supplied a custom animation for `key` (Anim<key> attribute).
function Server:hasAnim(key: string): boolean
	local id = self.tool:GetAttribute("Anim" .. key)
	return type(id) == "string" and id ~= ""
end

function Server:on(action: string, handler: (Player, ...any) -> ())
	self.handlers[action] = handler
end

function Server:onEquip(callback: () -> ())
	table.insert(self.equipCallbacks, callback)
end

function Server:onUnequip(callback: () -> ())
	table.insert(self.unequipCallbacks, callback)
end

--[[
	Cooldown gate. The server accepts actions slightly early (85%) so honest
	players with jittery connections are not rejected.
]]
function Server:ready(key: string, duration: number): boolean
	local now = os.clock()
	local nextAllowed = self.cooldowns[key]
	if nextAllowed and now < nextAllowed then
		return false
	end
	self.cooldowns[key] = now + duration * 0.85
	return true
end

function Server:sound(name: string, position: Vector3?)
	local sound = Util.findSound(self.tool, name)
	if not sound then
		return
	end
	if position then
		Effects.soundAt(sound, position)
	else
		sound:Play()
	end
end

-- Enables/disables every Trail called `name` in the tool (default "SwingTrail").
function Server:trail(on: boolean, modelName: string?, name: string?)
	local scope: Instance = self.tool
	if modelName then
		scope = self.tool:FindFirstChild(modelName) or self.tool
	end
	for _, d in scope:GetDescendants() do
		if d:IsA("Trail") and d.Name == (name or "SwingTrail") then
			d.Enabled = on
		end
	end
end

function Server:trailFor(seconds: number, modelName: string?)
	self:trail(true, modelName)
	task.delay(seconds, function()
		self:trail(false, modelName)
	end)
end

-- The Motor6D holding model `modelName` (e.g. "Longsword", "OffhandDagger").
function Server:joint(modelName: string): Motor6D?
	return self.joints[modelName]
end

-- Tweens the weapon's grip joint to RestC0 * offset (nil = rest).
function Server:pose(modelName: string, offset: CFrame?, duration: number?, style: Enum.EasingStyle?)
	return Effects.pose(self.joints[modelName], offset, duration, style)
end

function Server:model(name: string): Model?
	local m = self.tool:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

function Server:_dispatch(player: Player, action: any, ...)
	if type(action) ~= "string" then
		return
	end
	local character = self.tool.Parent
	if not character or character ~= player.Character or character ~= self.character then
		return
	end
	if not self.humanoid or self.humanoid.Health <= 0 then
		return
	end
	local handler = self.handlers[action]
	if handler then
		handler(player, ...)
	end
end

function Server:_equipped()
	local character = self.tool.Parent :: Model
	self.character = character
	self.player = Players:GetPlayerFromCharacter(character)
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	self:_clearHolster()
	self.joints = Rig.attachAll(self.tool, character)
	self:sound("Equip")
	for _, callback in self.equipCallbacks do
		task.spawn(callback)
	end
end

function Server:_unequipped()
	for _, callback in self.unequipCallbacks do
		task.spawn(callback)
	end
	self:trail(false)
	Rig.detachAll(self.tool, self.joints)
	self.character = nil
	self.player = nil
	self.humanoid = nil
	self.root = nil
end

function Server:_clearHolster()
	for _, copy in self.holstered do
		copy:Destroy()
	end
	table.clear(self.holstered)
	if self.holsterWatch then
		self.holsterWatch:Disconnect()
		self.holsterWatch = nil
	end
end

function Server:_refreshHolster()
	self:_clearHolster()
	local backpack = self.tool.Parent
	if not backpack or not backpack:IsA("Backpack") then
		return
	end
	local player = backpack.Parent
	if not player or not player:IsA("Player") then
		return
	end
	local character = player.Character
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		-- backpack filled before the character finished spawning; try again then
		self.holsterWatch = player.CharacterAdded:Connect(function()
			task.delay(0.5, function()
				if self.tool.Parent == backpack then
					self:_refreshHolster()
				end
			end)
		end)
		return
	end
	self.holstered = Rig.holster(self.tool, character)
	-- avatars can swap body parts while loading; re-mount when that happens
	local pending = false
	self.holsterWatch = character.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") and not pending then
			pending = true
			task.delay(0.2, function()
				pending = false
				if self.tool.Parent == backpack and player.Character == character then
					self:_refreshHolster()
				end
			end)
		end
	end)
end

return Server
