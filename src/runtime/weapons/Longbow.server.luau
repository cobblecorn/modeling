--[[
	Longbow (server)
	  Draw            nock an arrow and pull the string (the bow rig bends as you draw)
	  Release(target) loose the arrow; speed and damage scale with draw time
	Arrows are physics projectiles that arc, stick in whatever they hit and
	deal x1.5 damage on headshots.

	The string/limb motion is driven by script. If you keyframe Nock / UpperLimb /
	LowerLimb in your own draw animation, set the ScriptedDraw attribute to false.
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Combat, Effects, Projectile, Util = Core.Combat, Core.Effects, Core.Projectile, Core.Util

local weapon = Core.Server.new(tool)

local bow = tool:WaitForChild("Longbow") :: Model
local arrow = bow:WaitForChild("Arrow") :: Model
local bowJoints: { Motor6D } = {}
for _, name in { "Nock", "UpperLimb", "LowerLimb" } do
	local part = bow:WaitForChild(name)
	table.insert(bowJoints, part:WaitForChild(name) :: Motor6D)
end

Effects.setVisible(arrow, false)

local drawing = false
local drawStart = 0
local savedWalkSpeed: number? = nil

local function poseBow(drawn: boolean, duration: number)
	if tool:GetAttribute("ScriptedDraw") == false then
		return
	end
	for _, joint in bowJoints do
		local pose = joint:GetAttribute("PoseDrawn")
		Effects.pose(joint, if drawn and typeof(pose) == "CFrame" then pose else nil, duration, if drawn then Enum.EasingStyle.Sine else Enum.EasingStyle.Quad)
	end
end

local function setSlowed(on: boolean)
	local humanoid = weapon.humanoid
	if on and humanoid then
		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, weapon:attr("DrawWalkSpeed", 10))
	elseif not on then
		if humanoid and savedWalkSpeed then
			humanoid.WalkSpeed = savedWalkSpeed
		end
		savedWalkSpeed = nil
	end
end

local function reset(duration: number)
	drawing = false
	setSlowed(false)
	poseBow(false, duration)
	Effects.setVisible(arrow, false)
end

weapon:on("Draw", function()
	if drawing or not weapon:ready("Shot", weapon:attr("Cooldown", 0.35)) then
		return
	end
	drawing = true
	drawStart = os.clock()
	Effects.setVisible(arrow, true)
	weapon:sound("Draw")
	setSlowed(true)
	poseBow(true, weapon:attr("DrawTime", 0.9))
end)

weapon:on("Release", function(_player, target)
	if not drawing then
		return
	end
	local charge = math.clamp((os.clock() - drawStart) / weapon:attr("DrawTime", 0.9), 0, 1)
	local root, character = weapon.root, weapon.character
	if charge < 0.2 or not Util.isVector3(target) or not root or not character then
		reset(0.2)
		return
	end

	local origin = (arrow.PrimaryPart :: BasePart).Position
	local direction = target - origin
	if direction.Magnitude < 1 or direction.Unit:Dot(root.CFrame.LookVector) < 0 then
		direction = root.CFrame.LookVector
	end
	local speed = Util.lerp(weapon:attr("MinSpeed", 90), weapon:attr("MaxSpeed", 260), charge)
	local damage = Util.lerp(weapon:attr("MinDamage", 16), weapon:attr("MaxDamage", 55), charge)

	Projectile.fire({
		template = arrow,
		origin = origin,
		direction = direction.Unit,
		speed = speed,
		gravity = true,
		tipOffset = 0.1,
		maxDistance = 1500,
		lifetime = 8,
		stick = weapon:attr("ArrowLifetime", 12),
		ignore = { character },
		onHit = function(result)
			local humanoid = Combat.findHumanoid(result.Instance)
			if humanoid and Combat.canDamage(weapon, humanoid) then
				local headshot = result.Instance.Name == "Head"
				Combat.damage(weapon, humanoid, damage * (if headshot then 1.5 else 1), origin)
				Effects.burst(result.Position, Color3.fromRGB(255, 90, 80), if headshot then 20 else 10, 14)
			else
				Effects.burst(result.Position, Color3.fromRGB(210, 190, 160), 5, 6)
			end
		end,
	})
	weapon:sound("Release")
	reset(0.08)
end)

weapon:onUnequip(function()
	if drawing then
		reset(0)
	end
end)
