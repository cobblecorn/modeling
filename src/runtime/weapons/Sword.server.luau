--[[
	Longsword (server)
	  Attack(combo)  1-2 = slash, 3 = lunge
	  Block(on)      raise the blade; frontal hits deal (1 - BlockReduction) damage
	Tune the numbers with the Tool's attributes in Studio.
]]

local tool = script.Parent
local Core = require(tool:WaitForChild("WeaponCore"))
local Combat, Effects = Core.Combat, Core.Effects

local weapon = Core.Server.new(tool)

local MODEL = "Longsword"
-- fallback poses, used only while no custom animation is set
local LUNGE_POSE = CFrame.Angles(math.rad(-90), 0, 0) -- blade points forward
local BLOCK_POSE = CFrame.Angles(0, 0, math.rad(80)) * CFrame.Angles(math.rad(-15), 0, 0) -- blade across the body

local blocking = false
local savedWalkSpeed: number? = nil
local blockedConnection: RBXScriptConnection? = nil

local function setBlocking(on: boolean)
	if on == blocking then
		return
	end
	blocking = on
	local character, humanoid = weapon.character, weapon.humanoid
	if character then
		character:SetAttribute("Blocking", if on then true else nil)
		character:SetAttribute("BlockReduction", if on then weapon:attr("BlockReduction", 0.7) else nil)
	end
	if humanoid then
		if on then
			savedWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, weapon:attr("BlockWalkSpeed", 8))
		elseif savedWalkSpeed then
			humanoid.WalkSpeed = savedWalkSpeed
			savedWalkSpeed = nil
		end
	end
	if not weapon:hasAnim("Block") then
		weapon:pose(MODEL, if on then BLOCK_POSE else nil, 0.12)
	end
end

weapon:on("Attack", function(_player, combo)
	if blocking then
		return
	end
	combo = if combo == 2 or combo == 3 then combo else 1
	local lunge = combo == 3
	if not weapon:ready("Attack", weapon:attr("Cooldown", 0.45)) then
		return
	end

	weapon:sound(if lunge then "Lunge" else "Slash")
	weapon:trailFor(if lunge then 0.45 else 0.3)
	if lunge and not weapon:hasAnim("Lunge") then
		weapon:pose(MODEL, LUNGE_POSE, 0.08)
		task.delay(0.45, function()
			if not blocking then
				weapon:pose(MODEL, nil, 0.15)
			end
		end)
	end

	local damage = if lunge then weapon:attr("LungeDamage", 34) else weapon:attr("Damage", 22)
	Combat.swing(weapon, {
		range = weapon:attr("Range", 6.5) + (if lunge then 2 else 0),
		width = if lunge then 4 else 6,
		height = 6,
		delay = 0.05,
		duration = if lunge then 0.35 else 0.22,
		onHit = function(humanoid, part)
			local root = weapon.root
			local _, blocked = Combat.damage(weapon, humanoid, damage, root and root.Position)
			Effects.burst(part.Position, if blocked then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(255, 255, 255), 8)
		end,
	})
end)

weapon:on("Block", function(_player, on)
	setBlocking(on == true)
end)

weapon:onEquip(function()
	local character = weapon.character
	if character then
		-- a hit we blocked: clang!
		blockedConnection = character:GetAttributeChangedSignal("BlockedHit"):Connect(function()
			if blocking then
				weapon:sound("Block")
				local root = weapon.root
				if root then
					Effects.burst(root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1, 0), Color3.fromRGB(255, 220, 120), 14, 20)
				end
			end
		end)
	end
end)

weapon:onUnequip(function()
	setBlocking(false)
	if blockedConnection then
		blockedConnection:Disconnect()
		blockedConnection = nil
	end
end)
