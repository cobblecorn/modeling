local Util = {}

-- Reads a Tool attribute, falling back to `default` when unset or the wrong type.
function Util.attr(instance: Instance, name: string, default: any): any
	local value = instance:GetAttribute(name)
	if value == nil or (default ~= nil and typeof(value) ~= typeof(default)) then
		return default
	end
	return value
end

function Util.isAlive(character: Model?): boolean
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function Util.isVector3(value: any): boolean
	return typeof(value) == "Vector3" and value == value -- NaN check
end

function Util.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Finds the rigged models (Models whose PrimaryPart carries rig attributes) of a tool.
function Util.riggedModels(tool: Tool): { Model }
	local list = {}
	for _, child in tool:GetChildren() do
		if child:IsA("Model") and child.PrimaryPart and child.PrimaryPart:GetAttribute("RigLimb") then
			table.insert(list, child)
		end
	end
	return list
end

function Util.findSound(tool: Tool, name: string): Sound?
	for _, d in tool:GetDescendants() do
		if d:IsA("Sound") and d.Name == name then
			return d
		end
	end
	return nil
end

return Util
