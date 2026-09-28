--[[
	Parts: geometry helpers for building part-based Roblox models from Lune.

	Every weapon is authored in its own "model space":
	  * origin  = the point the hand (or mount) holds
	  * +Y      = along the handle toward the business end (blade / head / limbs)
	  * -Z      = "forward" (the direction the edge / muzzle faces when held)
	  * X       = the flat of the blade (thin axis)

	A Builder creates parts under a parent and remembers which rig root each part
	should be welded to. Call `builder:weld()` once at the end to create the
	WeldConstraints.
]]

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Enum = roblox.Enum

local Parts = {}

--------------------------------------------------------------------------------
-- Math helpers (Lune's CFrame.lookAt misbehaves for some directions, so we
-- build our own from fromMatrix)
--------------------------------------------------------------------------------

local function orthoUp(dir, upHint)
	local up = upHint or Vector3.new(0, 1, 0)
	if math.abs(dir.Unit:Dot(up.Unit)) > 0.999 then
		up = if math.abs(dir.Unit:Dot(Vector3.new(1, 0, 0))) < 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	end
	return up
end

-- CFrame at `pos` whose LookVector (-Z) points along `dir`.
function Parts.lookAlong(pos, dir, upHint)
	local look = dir.Unit
	local right = look:Cross(orthoUp(look, upHint)).Unit
	local up = right:Cross(look).Unit
	return CFrame.fromMatrix(pos, right, up, -look)
end

-- CFrame at `pos` whose UpVector (+Y) points along `dir`; `backHint` picks +Z.
function Parts.upAlong(pos, dir, backHint)
	local up = dir.Unit
	local back = backHint or Vector3.new(0, 0, 1)
	if math.abs(up:Dot(back.Unit)) > 0.999 then
		back = Vector3.new(1, 0, 0)
	end
	local right = up:Cross(back).Unit
	back = right:Cross(up).Unit
	return CFrame.fromMatrix(pos, right, up, back)
end

-- CFrame at `pos` whose RightVector (+X) points along `dir`. Handy for
-- Cylinder parts, whose axis is their X axis.
function Parts.xAlong(pos, dir, upHint)
	local x = dir.Unit
	local up = orthoUp(x, upHint)
	local z = x:Cross(up).Unit
	up = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, up, z)
end

-- Right-handed rotation from the images of the X and Y axes (Z = X cross Y).
function Parts.basis(x, y, pos)
	x, y = x.Unit, y.Unit
	return CFrame.fromMatrix(pos or Vector3.zero, x, y, x:Cross(y).Unit)
end

function Parts.rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- style(r, g, b, "Metal", { transparency = 0.2, reflectance = 0.1 })
function Parts.style(r, g, b, material, extra)
	return {
		color = Color3.fromRGB(r, g, b),
		material = Enum.Material[material],
		transparency = extra and extra.transparency or nil,
		reflectance = extra and extra.reflectance or nil,
	}
end

--------------------------------------------------------------------------------
-- 2D triangulation (ear clipping) for concave outlines
--------------------------------------------------------------------------------

local function cross2(ax, ay, bx, by, cx, cy)
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

local function pointInTri(px, py, a, b, c)
	local d1 = cross2(a[1], a[2], b[1], b[2], px, py)
	local d2 = cross2(b[1], b[2], c[1], c[2], px, py)
	local d3 = cross2(c[1], c[2], a[1], a[2], px, py)
	local hasNeg = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
	local hasPos = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
	return not (hasNeg and hasPos)
end

-- poly: array of {u, v, ...}; returns array of {i, j, k} (1-based indices)
function Parts.triangulate(poly)
	local n = #poly
	local area = 0
	for i = 1, n do
		local p, q = poly[i], poly[i % n + 1]
		area += p[1] * q[2] - q[1] * p[2]
	end
	local idx = {}
	for i = 1, n do
		idx[i] = if area > 0 then i else n - i + 1
	end
	local tris = {}
	local guard = 0
	while #idx > 3 and guard < 5000 do
		guard += 1
		local clipped = false
		local m = #idx
		for i = 1, m do
			local i0, i1, i2 = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
			local a, b, c = poly[i0], poly[i1], poly[i2]
			if cross2(a[1], a[2], b[1], b[2], c[1], c[2]) > 1e-9 then
				local ear = true
				for _, j in idx do
					if j ~= i0 and j ~= i1 and j ~= i2 and pointInTri(poly[j][1], poly[j][2], a, b, c) then
						ear = false
						break
					end
				end
				if ear then
					table.insert(tris, { i0, i1, i2 })
					table.remove(idx, i)
					clipped = true
					break
				end
			end
		end
		if not clipped then
			error("triangulate: polygon is self-intersecting or degenerate")
		end
	end
	if #idx == 3 then
		table.insert(tris, { idx[1], idx[2], idx[3] })
	end
	return tris
end

--------------------------------------------------------------------------------
-- Builder
--------------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

--[[
	Parts.new(parent, root)
	  parent: Instance new parts are parented to
	  root:   BasePart new parts get welded to (nil = don't weld)
]]
function Parts.new(parent, root)
	local self = setmetatable({}, Builder)
	self.parent = parent
	self.root = root
	self.shared = { welds = {}, count = 0 }
	return self
end

-- A builder that shares bookkeeping but targets a different parent/root.
-- Pass root = false for parts that must not be welded (e.g. a new rig root).
function Builder:sub(parent, root)
	local child = setmetatable({}, Builder)
	child.parent = parent or self.parent
	if root == false then
		child.root = nil
	else
		child.root = root or self.root
	end
	child.shared = self.shared
	return child
end

function Builder:_finish(part, name, style)
	part.Name = name
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = style.color
	part.Material = style.material
	if style.transparency then
		part.Transparency = style.transparency
	end
	if style.reflectance then
		part.Reflectance = style.reflectance
	end
	part.Parent = self.parent
	if self.root and part ~= self.root then
		table.insert(self.shared.welds, { part = part, root = self.root })
	end
	self.shared.count += 1
	return part
end

local MIN = 0.001

local function clampSize(size)
	return Vector3.new(math.max(size.X, MIN), math.max(size.Y, MIN), math.max(size.Z, MIN))
end

function Builder:block(name, size, cf, style)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Size = clampSize(size)
	p.CFrame = cf
	return self:_finish(p, name, style)
end

-- Roblox wedge: full bottom (-Y) and back (+Z) faces, slope from top-back to bottom-front.
function Builder:wedge(name, size, cf, style)
	local p = Instance.new("WedgePart")
	p.Size = clampSize(size)
	p.CFrame = cf
	return self:_finish(p, name, style)
end

-- Cylinder whose axis is the X axis of `cf`.
function Builder:cylinder(name, length, diameter, cf, style)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = clampSize(Vector3.new(length, diameter, diameter))
	p.CFrame = cf
	return self:_finish(p, name, style)
end

-- Cylinder spanning from a to b.
function Builder:cylBetween(name, a, b, diameter, style)
	local d = b - a
	return self:cylinder(name, d.Magnitude, diameter, Parts.xAlong((a + b) / 2, d), style)
end

-- Vertical (model +Y) cylinder centred at y on the handle axis.
function Builder:ring(name, y, length, diameter, style, offset)
	local c = Vector3.new(0, y, 0) + (offset or Vector3.zero)
	return self:cylinder(name, length, diameter, CFrame.new(c) * CFrame.Angles(0, 0, math.pi / 2), style)
end

function Builder:ball(name, diameter, pos, style)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = clampSize(Vector3.new(diameter, diameter, diameter))
	p.CFrame = CFrame.new(pos)
	return self:_finish(p, name, style)
end

-- Ellipsoid via SpecialMesh sphere fitted to the part's box.
function Builder:ellipsoid(name, size, cf, style)
	local p = self:block(name, size, cf, style)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Box running from a to b. `width` is along the box X, `depth` along Z;
-- `backHint` orients the Z axis.
function Builder:strut(name, a, b, width, depth, style, backHint)
	local d = b - a
	local cf = Parts.upAlong((a + b) / 2, d, backHint)
	return self:block(name, Vector3.new(width, d.Magnitude, depth), cf, style)
end

--[[
	Triangle from two wedges (the classic Roblox "3D triangle" trick).
	thickness: slab thickness along the triangle normal
	inside:    optional point; when given, the slab is pushed inward so its
	           outer face lies exactly on the triangle (for closed surfaces)
]]
function Builder:triangle(name, a, b, c, style, thickness, inside)
	thickness = thickness or 0.05
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-7 then
		return nil
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local offset = Vector3.zero
	if inside then
		local n = right
		if (inside - (a + b + c) / 3):Dot(n) < 0 then
			n = -n
		end
		offset = n * (thickness / 2)
	end

	local made = {}
	local len1 = math.abs(ab:Dot(back))
	if len1 > 1e-4 and height > 1e-4 then
		table.insert(
			made,
			self:wedge(
				name,
				Vector3.new(thickness, height, len1),
				CFrame.fromMatrix((a + b) / 2 + offset, right, up, back),
				style
			)
		)
	end
	local len2 = math.abs(ac:Dot(back))
	if len2 > 1e-4 and height > 1e-4 then
		table.insert(
			made,
			self:wedge(
				name,
				Vector3.new(thickness, height, len2),
				CFrame.fromMatrix((a + c) / 2 + offset, -right, up, -back),
				style
			)
		)
	end
	return made
end

function Builder:quad(name, a, b, c, d, style, thickness, inside)
	self:triangle(name, a, b, c, style, thickness, inside)
	self:triangle(name, a, c, d, style, thickness, inside)
end

--[[
	Flat polygon plate in the model YZ plane (blade plane), extruded along X.
	outline: array of {y, z}; thickness: total X thickness; x: centre X.
	frame:   optional CFrame applied to the whole plate.
]]
function Builder:plate(name, outline, thickness, style, x, frame)
	x = x or 0
	frame = frame or CFrame.new()
	for _, t in Parts.triangulate(outline) do
		local p1, p2, p3 = outline[t[1]], outline[t[2]], outline[t[3]]
		self:triangle(
			name,
			frame * Vector3.new(x, p1[1], p1[2]),
			frame * Vector3.new(x, p2[1], p2[2]),
			frame * Vector3.new(x, p3[1], p3[2]),
			style,
			thickness
		)
	end
end

--[[
	Solid plate whose thickness varies per vertex, so edges can taper to a
	sharp bevel. outline: array of {y, z, thickness}. Walls are generated
	for outline edges thicker than `wallMin`.
]]
function Builder:taperedPlate(name, outline, style, opts)
	opts = opts or {}
	local frame = opts.frame or CFrame.new()
	local skin = opts.skin or 0.03
	local wallMin = opts.wallMin or 0.06
	local wallStyle = opts.wallStyle or style
	local inside = frame * Vector3.new(0, 0, 0)
	-- use the outline centroid as the interior reference
	local cy, cz = 0, 0
	for _, p in outline do
		cy += p[1]
		cz += p[2]
	end
	inside = frame * Vector3.new(0, cy / #outline, cz / #outline)

	local function v(p, side)
		return frame * Vector3.new(side * p[3] / 2, p[1], p[2])
	end

	for _, t in Parts.triangulate(outline) do
		local p1, p2, p3 = outline[t[1]], outline[t[2]], outline[t[3]]
		for _, side in { 1, -1 } do
			self:triangle(name, v(p1, side), v(p2, side), v(p3, side), style, skin, inside)
		end
	end
	local n = #outline
	for i = 1, n do
		local p, q = outline[i], outline[i % n + 1]
		if p[3] > wallMin or q[3] > wallMin then
			self:quad(name .. "Wall", v(p, 1), v(q, 1), v(q, -1), v(p, -1), wallStyle, skin, inside)
		end
	end
end

--[[
	Double-edged blade with a centre ridge, pointing along +Y.
	spec = {
	  base = y where the blade starts, length = y distance to where the tip starts,
	  tip = tip length, width0 = half-width at base, width1 = half-width at tip start,
	  ridge = thickness at the ridge, edge = thickness at the edges,
	  ridgeWidth = optional half-width of a flat central ridge band,
	}
]]
function Builder:blade(name, spec, style, edgeStyle)
	edgeStyle = edgeStyle or style
	local y0, y1 = spec.base, spec.base + spec.length
	local y2 = y1 + spec.tip
	local w0, w1 = spec.width0, spec.width1
	local r, e = spec.ridge / 2, spec.edge / 2
	local skin = spec.skin or 0.02
	local inside = Vector3.new(0, (y0 + y1) / 2, 0)
	local frame = spec.frame or CFrame.new()

	local function P(x, y, z)
		return frame * Vector3.new(x, y, z)
	end
	inside = frame * inside

	for _, s in { 1, -1 } do -- front / back face
		for _, side in { 1, -1 } do -- right / left edge
			local ridge0, ridge1 = P(s * r, y0, 0), P(s * r * 0.8, y1, 0)
			local edge0, edge1 = P(s * e, y0, side * w0), P(s * e, y1, side * w1)
			local tipPt = P(0, y2, 0)
			self:quad(name, ridge0, edge0, edge1, ridge1, edgeStyle, skin, inside)
			self:triangle(name, ridge1, edge1, tipPt, edgeStyle, skin, inside)
		end
	end
	-- a flat cap at the base so the blade reads as solid when seen from below
	self:block(name .. "Base", Vector3.new(spec.ridge, 0.04, w0 * 2), frame * CFrame.new(0, y0 + 0.02, 0), style)
end

--------------------------------------------------------------------------------
-- Rig helpers
--------------------------------------------------------------------------------

-- Invisible root part used as a weld / animation root.
function Builder:rootPart(name, cf, size)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf
	p.Transparency = 1
	p.Name = name
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = self.parent
	if self.root and p ~= self.root then
		table.insert(self.shared.welds, { part = p, root = self.root })
	end
	return p
end

function Builder:attachment(name, parentPart, worldCf)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = parentPart.CFrame:ToObjectSpace(worldCf)
	a.Parent = parentPart
	return a
end

-- Motor6D from part0 to part1 whose joint sits at part1's current CFrame.
function Parts.motor(name, part0, part1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	m.C1 = CFrame.new()
	m.Parent = part1
	-- remember the rest pose so scripts can layer poses on top of it
	m:SetAttribute("RestC0", m.C0)
	return m
end

function Parts.weldConstraint(name, part0, part1, parent)
	local w = Instance.new("WeldConstraint")
	w.Name = name
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = parent or part1
	return w
end

-- Create all pending WeldConstraints.
function Builder:weld()
	for _, w in self.shared.welds do
		Parts.weldConstraint("Weld", w.root, w.part, w.part)
	end
	table.clear(self.shared.welds)
end

function Builder:count()
	return self.shared.count
end

return Parts
