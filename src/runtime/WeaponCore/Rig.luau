--[[
	Rig: joins weapon models to characters with Motor6Ds.

	Each rigged model's PrimaryPart (BodyAttach, OffhandAttach, QuiverAttach...)
	carries attributes describing where it goes:

	  RigLimb / RigAttachment / RigOffset             while the tool is equipped
	  HolsterLimb / HolsterAttachment / HolsterOffset while it sits in the backpack

	Limb names are R15; R6 equivalents are used automatically. The offset is the
	model's pose relative to the character attachment, so the joint is
	  C0 = attachment.CFrame, C1 = offset:Inverse()

	Joints are named "WeaponJoint_<ModelName>". Because they are Motor6Ds whose
	Part1 is the model root, animations can keyframe the weapon itself.
]]

local Util = require(script.Parent.Util)

local Rig = {}

local R6_LIMBS = {
	RightHand = "Right Arm",
	RightLowerArm = "Right Arm",
	RightUpperArm = "Right Arm",
	LeftHand = "Left Arm",
	LeftLowerArm = "Left Arm",
	LeftUpperArm = "Left Arm",
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	RightUpperLeg = "Right Leg",
	RightLowerLeg = "Right Leg",
	LeftUpperLeg = "Left Leg",
	LeftLowerLeg = "Left Leg",
}

function Rig.findLimb(character: Model, limbName: string): BasePart?
	local limb = character:FindFirstChild(limbName)
	if not limb and R6_LIMBS[limbName] then
		limb = character:FindFirstChild(R6_LIMBS[limbName])
	end
	if limb and limb:IsA("BasePart") then
		return limb
	end
	return nil
end

-- Used when a rig lacks the named attachment (custom or very old characters).
local function fallbackFrame(limb: BasePart, attachmentName: string): CFrame
	local half = limb.Size / 2
	local isR6Torso = limb.Name == "Torso"
	if attachmentName == "RightGripAttachment" or attachmentName == "LeftGripAttachment" then
		return CFrame.new(0, -half.Y, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	elseif attachmentName == "RightCollarAttachment" then
		return CFrame.new(half.X, half.Y, 0)
	elseif attachmentName == "LeftCollarAttachment" then
		return CFrame.new(-half.X, half.Y, 0)
	elseif attachmentName == "BodyBackAttachment" then
		return CFrame.new(0, 0, half.Z)
	elseif attachmentName == "BodyFrontAttachment" then
		return CFrame.new(0, 0, -half.Z)
	elseif attachmentName == "WaistCenterAttachment" then
		return CFrame.new(0, if isR6Torso then -half.Y else 0, 0)
	elseif attachmentName == "WaistBackAttachment" then
		return CFrame.new(0, if isR6Torso then -half.Y else 0, half.Z)
	elseif attachmentName == "WaistFrontAttachment" then
		return CFrame.new(0, if isR6Torso then -half.Y else 0, -half.Z)
	end
	return CFrame.identity
end

function Rig.mountFrame(limb: BasePart, attachmentName: string?): CFrame
	if not attachmentName then
		return CFrame.identity
	end
	local attachment = limb:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return attachment.CFrame
	end
	return fallbackFrame(limb, attachmentName)
end

--[[
	Creates a joint from the character to `root` using the root's
	<mode>Limb / <mode>Attachment / <mode>Offset attributes (mode = "Rig" | "Holster").
	The joint is parented to the limb (like the character's own Motor6Ds).
]]
function Rig.join(character: Model, root: BasePart, mode: string, jointName: string, className: string?): JointInstance?
	local limbName = root:GetAttribute(mode .. "Limb")
	if type(limbName) ~= "string" then
		return nil
	end
	local limb = Rig.findLimb(character, limbName)
	if not limb then
		return nil
	end
	local offset = root:GetAttribute(mode .. "Offset")
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.identity
	end
	local attachmentName = root:GetAttribute(mode .. "Attachment")
	local joint = Instance.new(className or "Motor6D") :: any
	joint.Name = jointName
	joint.C0 = Rig.mountFrame(limb, if type(attachmentName) == "string" then attachmentName else nil)
	joint.C1 = offset:Inverse()
	joint:SetAttribute("RestC0", joint.C0)
	joint.Part0 = limb
	joint.Part1 = root
	joint.Parent = limb
	return joint
end

function Rig.setStowed(tool: Tool, stowed: boolean)
	for _, d in tool:GetDescendants() do
		if d:IsA("WeldConstraint") and d.Name == "StowWeld" then
			d.Enabled = stowed
		end
	end
end

-- Keeps the engine's Handle grip in sync with the main model's rig offset.
function Rig.syncGrip(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	for _, model in Util.riggedModels(tool) do
		local root = model.PrimaryPart :: BasePart
		if root.Name == "BodyAttach" then
			local offset = root:GetAttribute("RigOffset")
			if typeof(offset) == "CFrame" then
				tool.Grip = offset:Inverse()
			end
		end
	end
end

--[[
	Attaches every rigged model of an equipped tool. Returns { [modelName]: Motor6D }.
	`suffix` lets the client create short-lived local copies ("Local") that
	hide network latency until the server's joints replicate.
]]
function Rig.attachAll(tool: Tool, character: Model, suffix: string?): { [string]: Motor6D }
	local joints = {}
	for _, model in Util.riggedModels(tool) do
		local joint = Rig.join(character, model.PrimaryPart :: BasePart, "Rig", "WeaponJoint_" .. model.Name .. (suffix or ""))
		if joint then
			joints[model.Name] = joint :: Motor6D
		end
	end
	Rig.setStowed(tool, false)
	return joints
end

function Rig.detachAll(tool: Tool, joints: { [string]: Motor6D })
	for _, joint in joints do
		joint:Destroy()
	end
	table.clear(joints)
	if tool.Parent then
		Rig.setStowed(tool, true)
	end
end

--[[
	Client-side prediction: attach locally right away, then drop each local joint
	once the server's joint for the same model shows up.
]]
function Rig.predict(tool: Tool, character: Model): { [string]: Motor6D }
	local joints = Rig.attachAll(tool, character, "Local")
	for modelName, joint in joints do
		local limb = joint.Part0
		task.spawn(function()
			local serverJoint = limb and limb:WaitForChild("WeaponJoint_" .. modelName, 5)
			if serverJoint and joint.Parent then
				joint:Destroy()
			end
		end)
	end
	return joints
end

--[[
	Creates visual copies of a tool's models on the character's body (sword on
	the back, daggers at the belt...). Returns the copies so they can be removed.
]]
function Rig.holster(tool: Tool, character: Model): { Model }
	local copies = {}
	if tool:GetAttribute("ShowHolstered") == false then
		return copies
	end
	for _, model in Util.riggedModels(tool) do
		local root = model.PrimaryPart :: BasePart
		local limbName = root:GetAttribute("HolsterLimb")
		if type(limbName) == "string" then
			local limb = Rig.findLimb(character, limbName)
			if limb then
				local copy = model:Clone()
				copy.Name = tool.Name .. "_" .. model.Name .. "_Holstered"
				for _, d in copy:GetDescendants() do
					if d:IsA("Trail") or d:IsA("ParticleEmitter") then
						d.Enabled = false
					elseif d:IsA("Sound") or d:IsA("BaseScript") then
						d:Destroy()
					elseif d:IsA("WeldConstraint") and d.Name == "StowWeld" then
						d:Destroy()
					elseif d:IsA("Motor6D") then
						-- holstered copies sit at their rest pose (no aim, no drawn string)
						local rest = d:GetAttribute("RestC0")
						if typeof(rest) == "CFrame" then
							d.C0 = rest
						end
					elseif d:IsA("BasePart") then
						d.CanQuery = false
						d.CanTouch = false
						d.CanCollide = false
						d.Massless = true
					end
				end
				copy.Parent = character
				if Rig.join(character, copy.PrimaryPart :: BasePart, "Holster", "HolsterJoint", "Weld") then
					table.insert(copies, copy)
				else
					copy:Destroy()
				end
			end
		end
	end
	return copies
end

-- Tween-free pose helper: sets joint.C0 = RestC0 * offset.
function Rig.setPose(joint: Motor6D, offset: CFrame?)
	local rest = joint:GetAttribute("RestC0")
	if typeof(rest) ~= "CFrame" then
		rest = joint.C0
		joint:SetAttribute("RestC0", rest)
	end
	joint.C0 = rest * (offset or CFrame.identity)
end

return Rig
