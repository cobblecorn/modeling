--[[
	Effects: short-lived visual/audio feedback. Everything is created on the
	server so all players see it.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Rig = require(script.Parent.Rig)

local Effects = {}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function anchorAt(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	Debris:AddItem(attachment, lifetime)
	return attachment
end

-- Burst of sparks at a point.
function Effects.burst(position: Vector3, color: Color3, count: number?, speed: number?)
	local attachment = anchorAt(position, 1.5)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new((speed or 14) * 0.5, speed or 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	emitter.Drag = 6
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(count or 8)
end

-- Expanding, fading neon sphere.
function Effects.flash(position: Vector3, color: Color3, size: number, duration: number?)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Size = Vector3.one * (size * 0.3)
	ball.CFrame = CFrame.new(position)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Transparency = 0.2
	ball.Parent = workspace
	local time = duration or 0.3
	TweenService:Create(ball, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, time + 0.05)
end

-- Visual-only explosion (damage is handled by Combat.explode).
function Effects.explosion(position: Vector3, radius: number, color: Color3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
	Effects.flash(position, color, radius * 1.2, 0.45)
	Effects.burst(position, color, 30, 40)
end

-- Plays a copy of `sound` at a world position (so it outlives its source).
function Effects.soundAt(sound: Sound?, position: Vector3)
	if not sound then
		return
	end
	local attachment = anchorAt(position, 4)
	local copy = sound:Clone()
	copy.Looped = false
	copy.Parent = attachment
	copy:Play()
end

-- Shows/hides every part of a model, remembering authored transparency.
function Effects.setVisible(model: Instance, visible: boolean)
	local parts = model:GetDescendants()
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, d in parts do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("BaseTransparency")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseTransparency", base)
			end
			d.Transparency = if visible then base else 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = if visible then 0 else 1
		end
	end
end

--[[
	Tweens a Motor6D to RestC0 * offset (nil offset = back to rest). Joints
	driven this way replicate to every player, so these act as built-in
	animations until you publish your own.
]]
function Effects.pose(joint: Motor6D?, offset: CFrame?, duration: number?, style: Enum.EasingStyle?): Tween?
	if not joint or not joint.Parent then
		return nil
	end
	local rest = joint:GetAttribute("RestC0")
	if typeof(rest) ~= "CFrame" then
		Rig.setPose(joint, nil)
		rest = joint.C0
	end
	local goal = rest * (offset or CFrame.identity)
	if not duration or duration <= 0 then
		joint.C0 = goal
		return nil
	end
	local tween = TweenService:Create(
		joint,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = goal }
	)
	tween:Play()
	return tween
end

return Effects
