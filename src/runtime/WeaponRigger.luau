--[[
	WeaponRigger: attaches a weapon to a character rig in Studio so you can
	animate it with the Animation Editor. It creates exactly the same Motor6D
	joints the weapons use in game, so your keyframes line up.

	1. Insert a rig: Avatar tab > Rig Builder (R15 or R6), it appears as workspace.Rig
	2. Put this module in ServerStorage and run in the Command Bar (adjust the
	   paths to where you put things):

	     local R = require(game.ServerStorage.WeaponRigger)
	     R.rig(workspace.Rig, game.StarterPack.Longsword)

	3. Open the Animation Editor on the rig. The weapon joints appear in the
	   track list and can be keyframed:
	     BodyAttach                 the weapon in the right hand (all hand-held weapons)
	     OffhandAttach              the left-hand dagger
	     Nock, UpperLimb, LowerLimb bow string and limbs
	     QuiverAttach               the quiver
	     YawBase, Cannon, Barrel    shoulder blaster turret, tilt and recoil
	4. Publish the animation and paste its ID into the Tool's matching
	   Anim<Name> attribute (e.g. AnimSlash1 = "rbxassetid://1234567890").

	R.unrig(workspace.Rig) removes rigged weapons again.
]]

local WeaponRigger = {}

function WeaponRigger.unrig(rig: Model)
	for _, child in rig:GetChildren() do
		if child:GetAttribute("RiggedWeapon") then
			child:Destroy()
		end
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") and string.sub(d.Name, 1, 12) == "WeaponJoint_" then
			d:Destroy()
		end
	end
end

function WeaponRigger.rig(rig: Model, tool: Tool): { Model }
	assert(typeof(rig) == "Instance" and rig:FindFirstChildOfClass("Humanoid"), "rig(rig, tool): rig must be a Model with a Humanoid")
	assert(typeof(tool) == "Instance" and tool:IsA("Tool"), "rig(rig, tool): tool must be one of the weapon Tools")
	local core = tool:FindFirstChild("WeaponCore")
	assert(core and core:FindFirstChild("Rig"), "rig(rig, tool): that Tool has no WeaponCore")
	local Rig = require(core:FindFirstChild("Rig") :: ModuleScript)

	WeaponRigger.unrig(rig)
	local added = {}
	for _, model in tool:GetChildren() do
		if model:IsA("Model") and model.PrimaryPart and model.PrimaryPart:GetAttribute("RigLimb") then
			local copy = model:Clone()
			copy.Name = "Rigged_" .. model.Name
			copy:SetAttribute("RiggedWeapon", tool.Name)
			for _, d in copy:GetDescendants() do
				if d:IsA("WeldConstraint") and d.Name == "StowWeld" then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Anchored = false
				end
			end
			copy.Parent = rig
			local joint = Rig.join(rig, copy.PrimaryPart :: BasePart, "Rig", "WeaponJoint_" .. model.Name)
			if joint then
				local j = joint :: Motor6D
				copy:PivotTo((j.Part0 :: BasePart).CFrame * j.C0 * j.C1:Inverse())
				table.insert(added, copy)
			else
				warn(`WeaponRigger: {rig.Name} has no limb "{copy.PrimaryPart:GetAttribute("RigLimb")}" for {model.Name}`)
				copy:Destroy()
			end
		end
	end
	print(`WeaponRigger: rigged {#added} model(s) from {tool.Name} onto {rig.Name}`)
	return added
end

return WeaponRigger
