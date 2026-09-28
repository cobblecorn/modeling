--[[
	Projectile: server-simulated physics projectiles.

	A copy of a template (Model or BasePart) is launched with real physics and
	owned by the server, so every player sees it move smoothly. Each frame the
	server raycasts along the path it actually travelled, so fast projectiles
	never tunnel through targets.

	The template's forward direction must be -Z of its root part, or pass
	`orient` to rotate it (e.g. a dagger whose blade points along +Y).
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Projectile = {}

local function folder(): Folder
	local f = workspace:FindFirstChild("WeaponProjectiles")
	if not f then
		f = Instance.new("Folder")
		f.Name = "WeaponProjectiles"
		f.Parent = workspace
	end
	return f :: Folder
end
Projectile.folder = folder

local function isInside(inst: Instance?, container: Instance): boolean
	return inst ~= nil and (inst == container or inst:IsDescendantOf(container))
end

--[[
	opts = {
	  template: Model | BasePart,  -- copied, never modified
	  origin: Vector3, direction: Vector3, speed: number,
	  gravity: boolean?,           -- false = flies straight (energy bolts)
	  orient: CFrame?,             -- extra rotation applied after facing `direction`
	  tipOffset: number?,          -- studs from the root to the impact point
	  maxDistance: number?, lifetime: number?,
	  ignore: { Instance }?,       -- the shooter's character, etc.
	  stick: number?,              -- seconds to stay embedded; nil = vanish on impact
	  stickDepth: number?,
	  onHit: (result: RaycastResult, projectile: Instance, direction: Vector3) -> ()?,
	  onExpire: (position: Vector3) -> ()?,
	}
]]
function Projectile.fire(opts)
	local projectile = opts.template:Clone()
	local root: BasePart = if projectile:IsA("Model") then projectile.PrimaryPart else projectile
	assert(root, "Projectile template needs a PrimaryPart")

	local orient = opts.orient or CFrame.identity
	local direction = opts.direction.Unit
	local start = CFrame.lookAt(opts.origin, opts.origin + direction) * orient

	-- detach from anything outside the copy (stow welds etc.) and make it inert
	local all = projectile:GetDescendants()
	table.insert(all, projectile)
	for _, d in all do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			local j = d :: any
			if not isInside(j.Part0, projectile) or not isInside(j.Part1, projectile) then
				d:Destroy()
			end
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = d ~= root
			local base = d:GetAttribute("BaseTransparency")
			if type(base) == "number" then
				d.Transparency = base
			end
		elseif d:IsA("Trail") then
			d.Enabled = true
		end
	end
	if projectile:IsA("Model") then
		projectile:PivotTo(start)
	else
		root.CFrame = start
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "ProjectileAttachment"
	attachment.Parent = root

	projectile.Parent = folder()
	pcall(root.SetNetworkOwner, root, nil)

	local antiGravity: VectorForce?
	local align: AlignOrientation?
	if opts.gravity then
		-- keep the nose pointed along the arc
		local a = Instance.new("AlignOrientation")
		a.Mode = Enum.OrientationAlignmentMode.OneAttachment
		a.Attachment0 = attachment
		a.RigidityEnabled = true
		a.CFrame = start.Rotation
		a.Parent = root
		align = a
	else
		-- cancel gravity so energy bolts fly dead straight
		local f = Instance.new("VectorForce")
		f.Attachment0 = attachment
		f.RelativeTo = Enum.ActuatorRelativeTo.World
		f.ApplyAtCenterOfMass = true
		f.Force = Vector3.new(0, workspace.Gravity * root.AssemblyMass, 0)
		f.Parent = root
		antiGravity = f
		root.AssemblyAngularVelocity = Vector3.zero
	end
	root.AssemblyLinearVelocity = direction * opts.speed

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder() }
	for _, inst in opts.ignore or {} do
		table.insert(ignore, inst)
	end
	params.FilterDescendantsInstances = ignore

	local tip = opts.tipOffset or 0
	local maxDistance = opts.maxDistance or 1000
	local lifetime = opts.lifetime or 10
	local started = os.clock()
	local travelled = 0
	local last = root.Position
	local connection: RBXScriptConnection

	local function stopFlight()
		connection:Disconnect()
		if antiGravity then
			antiGravity:Destroy()
		end
		if align then
			align:Destroy()
		end
		for _, d in projectile:GetDescendants() do
			if d:IsA("Trail") then
				d.Enabled = false
			end
		end
	end

	local function impact(result: RaycastResult, dir: Vector3)
		stopFlight()
		if opts.stick then
			local depth = opts.stickDepth or 0.3
			local tipAt = result.Position + dir * depth
			local rootAt = tipAt - dir * tip
			local pose = CFrame.lookAt(rootAt, rootAt + dir) * orient
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			local hitPart = result.Instance
			if hitPart:IsA("Terrain") or hitPart.Anchored then
				root.Anchored = true
				if projectile:IsA("Model") then
					projectile:PivotTo(pose)
				else
					root.CFrame = pose
				end
			else
				if projectile:IsA("Model") then
					projectile:PivotTo(pose)
				else
					root.CFrame = pose
				end
				root.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hitPart
				weld.Part1 = root
				weld.Parent = root
			end
			Debris:AddItem(projectile, opts.stick)
		else
			projectile:Destroy()
		end
		if opts.onHit then
			task.spawn(opts.onHit, result, projectile, dir)
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		if not root.Parent then
			connection:Disconnect()
			return
		end
		local position = root.Position
		local velocity = root.AssemblyLinearVelocity
		local dir = if velocity.Magnitude > 0.5 then velocity.Unit else direction
		local from = last + dir * tip
		local delta = position + dir * tip - from
		if delta.Magnitude > 1e-3 then
			local result = workspace:Raycast(from, delta, params)
			if result then
				impact(result, dir)
				return
			end
		end
		travelled += (position - last).Magnitude
		last = position
		if align then
			align.CFrame = CFrame.lookAt(Vector3.zero, dir) * orient.Rotation
		end
		if travelled > maxDistance or os.clock() - started > lifetime then
			stopFlight()
			if opts.onExpire then
				task.spawn(opts.onExpire, position)
			end
			projectile:Destroy()
		end
	end)

	return projectile
end

return Projectile
