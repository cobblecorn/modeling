"""
De-box rigged GLB models without touching their rigs.

    python src/meshes/refine_models.py                    # every file in src/meshes/source/
    python src/meshes/refine_models.py in.glb -o out.glb  # a single model
    python src/meshes/refine_models.py --budget 15000     # triangle cap (Roblox allows ~20k per mesh)

The models are built from primitives (boxes, spheres, cylinders), one rigid
piece per bone. This script splits each mesh into those pieces and rebuilds
them nicer:

  * chunky boxes (limbs, torsos, heads, feet) -> superellipsoid "pillows"
                 that keep each piece's size and placement but lose the block outline
  * thin boxes (armour plates, trims) -> crisp boxes with rounded edges
                 (the triangle budget decides how smooth each piece gets)
  * cylinders -> 16-sided cylinders / cones with crisp caps
  * spheres   -> exact sphere normals (smooth without extra triangles);
                 tiny rivets drop to fewer triangles when the budget is tight
  * the rest  -> auto-smoothed normals (hard edges above 40 degrees)

Every new vertex copies the bone binding of the piece it replaces, and the
skeleton, skin and animations are copied through unchanged, so everything
still animates exactly as before.
"""

import argparse
import glob
import math
import os

import numpy as np
import pygltflib
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(HERE, "source")
OUT_DIR = os.path.join(HERE, "..", "..", "dist", "enemies")

COMPONENT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8, 5122: np.int16, 5120: np.int8}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_accessor(gltf, blob, index):
    a = gltf.accessors[index]
    view = gltf.bufferViews[a.bufferView]
    dtype = COMPONENT[a.componentType]
    width = WIDTH[a.type]
    stride = view.byteStride or 0
    offset = (view.byteOffset or 0) + (a.byteOffset or 0)
    if stride and stride != np.dtype(dtype).itemsize * width:
        raw = np.frombuffer(blob, dtype=np.uint8, count=stride * a.count, offset=offset).reshape(a.count, stride)
        return raw[:, : np.dtype(dtype).itemsize * width].copy().view(dtype).reshape(a.count, width)
    return np.frombuffer(blob, dtype=dtype, count=a.count * width, offset=offset).reshape(a.count, width).copy()


# ---------------------------------------------------------------------------
# Shape builders (all return positions, normals, triangle indices)
# ---------------------------------------------------------------------------


def rounded_box(half, radius, arcs):
    """Box with half-extents `half` whose edges are rounded with `radius`,
    using `arcs` segments per rounded edge (0 = sharp box)."""
    hx, hy, hz = half
    inner = np.maximum(np.array(half) - radius, 0)

    def axis_coords(h, i):
        if arcs == 0 or radius <= 0:
            return np.array([-h, h])
        angles = np.linspace(0, math.pi / 2, arcs + 1)
        side = i + radius * np.sin(angles)
        return np.unique(np.concatenate([-side, side]))

    coords = [axis_coords(h, i) for h, i in zip(half, inner)]
    positions, normals, tris = [], [], []
    for axis in range(3):
        for sign in (-1, 1):
            u_axis, v_axis = [a for a in range(3) if a != axis]
            us, vs = coords[u_axis], coords[v_axis]
            base = len(positions)
            for u in us:
                for v in vs:
                    p = np.zeros(3)
                    p[axis] = sign * half[axis]
                    p[u_axis], p[v_axis] = u, v
                    core = np.clip(p, -inner, inner)
                    d = p - core
                    length = np.linalg.norm(d)
                    if arcs and radius > 0 and length > 1e-9:
                        n = d / length
                        p = core + n * radius
                    else:
                        n = np.zeros(3)
                        n[axis] = sign
                    positions.append(p)
                    normals.append(n)
            nv = len(vs)
            for i in range(len(us) - 1):
                for j in range(nv - 1):
                    a, b, c, d = base + i * nv + j, base + (i + 1) * nv + j, base + (i + 1) * nv + j + 1, base + i * nv + j + 1
                    tris += [[a, b, c], [a, c, d]]
    return orient(np.array(positions), np.array(normals), np.array(tris))


def superellipsoid(half, exponent, segments):
    """Rounded 'pillow' solid filling a box: |x/a|^n + |y/b|^n + |z/c|^n = 1.
    Built from a cube grid projected in the box's own proportions, so long
    boxes keep an even triangle spread."""
    a = np.array(half, float)
    grid = np.tan(np.linspace(-1, 1, segments + 1) * math.pi / 4)  # even angular spacing
    positions, normals, tris = [], [], []
    for axis in range(3):
        for sign in (-1, 1):
            u_axis, v_axis = [k for k in range(3) if k != axis]
            base = len(positions)
            for u in grid:
                for v in grid:
                    q = np.zeros(3)
                    q[axis], q[u_axis], q[v_axis] = sign, u, v
                    w = q / (np.abs(q) ** exponent).sum() ** (1 / exponent)
                    positions.append(w * a)
                    n = np.sign(w) * np.abs(w) ** (exponent - 1) / a
                    normals.append(n / np.linalg.norm(n))
            m = segments + 1
            for i in range(segments):
                for j in range(segments):
                    p0, p1, p2, p3 = base + i * m + j, base + (i + 1) * m + j, base + (i + 1) * m + j + 1, base + i * m + j + 1
                    tris += [[p0, p1, p2], [p0, p2, p3]]
    return orient(np.array(positions), np.array(normals), np.array(tris))


def frustum(p0, p1, r0, r1, sides=16):
    """Capped cylinder / cone from p0 (radius r0) to p1 (radius r1)."""
    axis = p1 - p0
    length = np.linalg.norm(axis)
    w = axis / length
    helper = np.array([1.0, 0, 0]) if abs(w[0]) < 0.9 else np.array([0, 1.0, 0])
    u = np.cross(w, helper)
    u /= np.linalg.norm(u)
    v = np.cross(w, u)
    angles = np.linspace(0, 2 * math.pi, sides, endpoint=False)
    ring = np.outer(np.cos(angles), u) + np.outer(np.sin(angles), v)
    slope = (r0 - r1) / length
    side_normal = ring + slope * w
    side_normal /= np.linalg.norm(side_normal, axis=1, keepdims=True)
    positions, normals, tris = [], [], []
    # side wall
    positions += list(p0 + ring * r0) + list(p1 + ring * r1)
    normals += list(side_normal) + list(side_normal)
    for i in range(sides):
        j = (i + 1) % sides
        tris += [[i, j, sides + j], [i, sides + j, sides + i]]
    # caps (skipped for a pointed end)
    for center, r, n in ((p0, r0, -w), (p1, r1, w)):
        if r < 1e-5:
            continue
        base = len(positions)
        positions.append(center)
        normals.append(n)
        positions += list(center + ring * r)
        normals += [n] * sides
        for i in range(sides):
            tris.append([base, base + 1 + i, base + 1 + (i + 1) % sides])
    return orient(np.array(positions), np.array(normals), np.array(tris))


def orient(positions, normals, tris):
    """Flip triangles so their winding agrees with the vertex normals."""
    a, b, c = positions[tris[:, 0]], positions[tris[:, 1]], positions[tris[:, 2]]
    face = np.cross(b - a, c - a)
    avg = normals[tris].sum(axis=1)
    flip = (face * avg).sum(axis=1) < 0
    tris = tris.copy()
    tris[flip] = tris[flip][:, [0, 2, 1]]
    keep = np.linalg.norm(face, axis=1) > 1e-12
    return positions, normals, tris[keep]


def icosphere(subdivisions):
    t = (1 + 5**0.5) / 2
    verts = [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]
    faces = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
    verts = [np.array(v, float) / np.linalg.norm(v) for v in verts]
    for _ in range(subdivisions):
        cache, new_faces = {}, []

        def mid(i, j):
            key = (min(i, j), max(i, j))
            if key not in cache:
                m = verts[i] + verts[j]
                verts.append(m / np.linalg.norm(m))
                cache[key] = len(verts) - 1
            return cache[key]

        for a, b, c in faces:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            new_faces += [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]
        faces = new_faces
    return np.array(verts), np.array(faces)


def autosmooth(positions, tris, angle=40):
    """Per-corner normals that stay sharp across edges steeper than `angle`."""
    a, b, c = positions[tris[:, 0]], positions[tris[:, 1]], positions[tris[:, 2]]
    face = np.cross(b - a, c - a)
    area_n = face.copy()
    unit = face / np.maximum(np.linalg.norm(face, axis=1, keepdims=True), 1e-12)
    limit = math.cos(math.radians(angle))
    by_vertex = {}
    for t, tri in enumerate(tris):
        for v in tri:
            by_vertex.setdefault(int(v), []).append(t)
    out_pos, out_nrm, out_tri, lookup = [], [], [], {}
    for t, tri in enumerate(tris):
        corner = []
        for v in tri:
            n = np.zeros(3)
            for other in by_vertex[int(v)]:
                if unit[other] @ unit[t] >= limit:
                    n += area_n[other]
            n = n / max(np.linalg.norm(n), 1e-12)
            key = (int(v), tuple(np.round(n, 3)))
            if key not in lookup:
                lookup[key] = len(out_pos)
                out_pos.append(positions[v])
                out_nrm.append(n)
            corner.append(lookup[key])
        out_tri.append(corner)
    return np.array(out_pos), np.array(out_nrm), np.array(out_tri)


# ---------------------------------------------------------------------------
# Piece analysis
# ---------------------------------------------------------------------------


def box_frame(P, tris):
    """Centre, half-extents and axes of an 8-vertex box."""
    edges = []
    for tri in tris:
        pts = P[tri]
        sides = [(np.linalg.norm(pts[i] - pts[(i + 1) % 3]), i) for i in range(3)]
        longest = max(sides)[1]
        for length, i in sides:
            if i != longest:
                edges.append(pts[(i + 1) % 3] - pts[i])
    axes, lengths = [], []
    for e in edges:
        length = np.linalg.norm(e)
        if length < 1e-9:
            continue
        d = e / length
        if all(abs(d @ a) < 0.99 for a in axes):
            axes.append(d)
            lengths.append(length)
        if len(axes) == 3:
            break
    if len(axes) < 3:
        return None
    R = np.array(axes).T
    if np.linalg.det(R) < 0:
        R[:, 2] *= -1
    center = P.mean(axis=0)
    local = (P - center) @ R
    half = np.abs(local).max(axis=0)
    return center, half, R


def cylinder_info(P, tris):
    """Axis end points and radii of a centre-fan capped cylinder/cone."""
    n = len(P)
    sides = (n - 2) // 2
    if n != 2 * sides + 2 or len(tris) != 4 * sides or sides < 5:
        return None
    degree = np.zeros(n, int)
    for tri in tris:
        for v in tri:
            degree[v] += 1
    centers = np.argsort(degree)[-2:]
    if degree[centers].min() < sides:
        return None
    c0, c1 = P[centers[0]], P[centers[1]]
    axis = c1 - c0
    if np.linalg.norm(axis) < 1e-6:
        return None
    w = axis / np.linalg.norm(axis)
    rest = np.delete(P, centers, axis=0)
    t = (rest - c0) @ w
    radial = np.linalg.norm((rest - c0) - np.outer(t, w), axis=1)
    near = t < np.linalg.norm(axis) / 2
    if near.sum() == 0 or (~near).sum() == 0:
        return None
    return c0, c1, radial[near].mean(), radial[~near].mean(), sides


def sphere_info(P):
    center = P.mean(axis=0)
    d = np.linalg.norm(P - center, axis=1)
    if len(P) >= 12 and d.std() / max(d.mean(), 1e-9) < 0.03:
        return center, d.mean()
    return None


# ---------------------------------------------------------------------------
# Model processing
# ---------------------------------------------------------------------------


def split_pieces(pos, tris):
    n = len(pos)
    e = np.vstack([tris[:, [0, 1]], tris[:, [1, 2]]])
    graph = coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n))
    count, labels = connected_components(graph, directed=False)
    tri_label = labels[tris[:, 0]]
    pieces = []
    for c in range(count):
        verts = np.where(labels == c)[0]
        remap = -np.ones(n, int)
        remap[verts] = np.arange(len(verts))
        pieces.append((verts, remap[tris[tri_label == c]]))
    return pieces


def refine(path, out, budget):
    gltf = pygltflib.GLTF2().load(path)
    blob = gltf.binary_blob()

    # gather every piece of every primitive
    work = []
    for mi, mesh in enumerate(gltf.meshes):
        for pi, prim in enumerate(mesh.primitives):
            pos = read_accessor(gltf, blob, prim.attributes.POSITION).astype(float)
            joints = read_accessor(gltf, blob, prim.attributes.JOINTS_0) if prim.attributes.JOINTS_0 is not None else None
            weights = read_accessor(gltf, blob, prim.attributes.WEIGHTS_0) if prim.attributes.WEIGHTS_0 is not None else None
            tris = read_accessor(gltf, blob, prim.indices).reshape(-1, 3).astype(int)
            for verts, local_tris in split_pieces(pos, tris):
                P = pos[verts]
                piece = {"mesh": mi, "prim": pi, "P": P, "tris": local_tris,
                         "joints": joints[verts] if joints is not None else None,
                         "weights": weights[verts] if weights is not None else None}
                if len(P) == 8 and len(local_tris) == 12 and (frame := box_frame(P, local_tris)):
                    piece["kind"], piece["box"] = "box", frame
                elif (cyl := cylinder_info(P, local_tris)):
                    piece["kind"], piece["cyl"] = "cylinder", cyl
                elif (sph := sphere_info(P)):
                    piece["kind"], piece["sphere"] = "sphere", sph
                else:
                    piece["kind"] = "other"
                work.append(piece)

    def box_cost(arcs):
        n = 2 if arcs == 0 else 2 * (arcs + 1)
        return 12 * (n - 1) ** 2

    def cost(p):
        return 12 * p["segments"] ** 2 if p["shape"] == "pillow" else box_cost(p["arcs"])

    # chunky blocks (limbs, torsos, heads, feet) become pillows; thin plates stay
    # crisp rounded boxes so armour still reads as armour
    boxes = [p for p in work if p["kind"] == "box"]
    for p in boxes:
        dims = np.sort(p["box"][1] * 2)
        bulk = dims[0] / dims[2]
        p["size"] = float(np.prod(dims) ** (1 / 3))
        if bulk >= 0.18 and dims[0] >= 0.08:
            p["shape"], p["segments"] = "pillow", 4
            p["exponent"] = 3.0 if bulk >= 0.5 else (3.6 if bulk >= 0.3 else 4.5)
        else:
            p["shape"], p["arcs"] = "plate", (0 if dims[0] < 0.024 else 1)
    boxes.sort(key=lambda p: -p["size"])

    fixed = 0
    for p in work:
        if p["kind"] == "cylinder":
            fixed += 16 * 4
        elif p["kind"] in ("sphere", "other"):
            fixed += len(p["tris"])
    spheres = sorted([p for p in work if p["kind"] == "sphere"], key=lambda p: p["sphere"][1])
    minimum = sum(cost(p) for p in boxes)
    # if the minimum doesn't fit, spend fewer triangles on the smallest spheres (rivets)
    for target, lod in ((80, 1), (20, 0)):
        for p in spheres:
            if fixed + minimum <= budget:
                break
            if len(p["tris"]) > target and p["sphere"][1] < 0.08 and p.get("tris_est", 1e9) > target:
                fixed -= p.get("tris_est", len(p["tris"])) - target
                p["lod"], p["tris_est"] = lod, target
    # still too many: coarser pillows, then sharp tiny plates, smallest first
    for p in reversed(boxes):
        if fixed + minimum <= budget:
            break
        if p["shape"] == "pillow" and p["segments"] > 3:
            minimum -= 12 * (16 - 9)
            p["segments"] = 3
    for p in reversed(boxes):
        if fixed + minimum <= budget:
            break
        if p["shape"] == "plate" and p["arcs"] > 0:
            minimum -= box_cost(p["arcs"]) - box_cost(0)
            p["arcs"] = 0
    remaining = budget - fixed - minimum
    # then make the biggest pieces smoother while the budget lasts
    for step in range(3):
        for p in boxes:
            if p["shape"] == "pillow" and p["segments"] == 4 + step and p["size"] > 0.15 + 0.1 * step:
                extra = 12 * ((p["segments"] + 1) ** 2 - p["segments"] ** 2)
                if extra <= remaining:
                    remaining -= extra
                    p["segments"] += 1
            elif p["shape"] == "plate" and p["arcs"] == 1 + step and step < 2 and p["box"][1].min() > 0.03:
                extra = box_cost(p["arcs"] + 1) - box_cost(p["arcs"])
                if extra <= remaining:
                    remaining -= extra
                    p["arcs"] += 1

    # rebuild geometry per primitive
    rebuilt = {}
    counts = {"box": 0, "cylinder": 0, "sphere": 0, "other": 0}
    for p in work:
        kind = p["kind"]
        counts[kind] += 1
        if kind == "box":
            center, half, R = p["box"]
            if p["shape"] == "pillow":
                lp, ln, lt = superellipsoid(half, p["exponent"], p["segments"])
            else:
                radius = 0.45 * half.min() if p["arcs"] else 0
                lp, ln, lt = rounded_box(half, radius, p["arcs"])
            P, N, T = lp @ R.T + center, ln @ R.T, lt
        elif kind == "cylinder":
            c0, c1, r0, r1, _ = p["cyl"]
            P, N, T = frustum(c0, c1, r0, r1, 16)
        elif kind == "sphere":
            center, radius = p["sphere"]
            if "lod" in p:
                unit, T = icosphere(p["lod"])
                P = center + unit * radius
            else:
                P, T = p["P"], p["tris"]
            N = P - center
            N = N / np.linalg.norm(N, axis=1, keepdims=True)
            P, N, T = orient(P, N, T)
        else:
            P, N, T = autosmooth(p["P"], p["tris"])
        count = len(P)
        joints = np.repeat(p["joints"][:1], count, axis=0) if p["joints"] is not None else None
        weights = np.repeat(p["weights"][:1], count, axis=0) if p["weights"] is not None else None
        if p["joints"] is not None and len(np.unique(p["joints"][:, 0])) > 1:
            # not a rigid piece: take each new vertex's binding from the nearest old vertex
            nearest = np.argmin(((P[:, None, :] - p["P"][None, :, :]) ** 2).sum(-1), axis=1)
            joints, weights = p["joints"][nearest], p["weights"][nearest]
        key = (p["mesh"], p["prim"])
        slot = rebuilt.setdefault(key, {"P": [], "N": [], "T": [], "J": [], "W": [], "offset": 0})
        slot["P"].append(P)
        slot["N"].append(N)
        slot["T"].append(T + slot["offset"])
        if joints is not None:
            slot["J"].append(joints)
            slot["W"].append(weights)
        slot["offset"] += count

    write(gltf, blob, rebuilt, out)
    total = sum(sum(len(t) for t in s["T"]) for s in rebuilt.values())
    before = sum(len(p["tris"]) for p in work)
    print(f"{os.path.basename(out)}: {before} -> {total} tris  (boxes {counts['box']}, cylinders {counts['cylinder']}, spheres {counts['sphere']}, other {counts['other']})")
    return total


def write(gltf, blob, rebuilt, out):
    """Re-pack the file: new mesh data, everything else copied verbatim."""
    data = bytearray()
    views, accessors = [], []

    def add(array, component, kind, target=None, minmax=False):
        array = np.ascontiguousarray(array)
        while len(data) % 4:
            data.append(0)
        views.append(pygltflib.BufferView(buffer=0, byteOffset=len(data), byteLength=array.nbytes, target=target))
        data.extend(array.tobytes())
        acc = pygltflib.Accessor(bufferView=len(views) - 1, componentType=component, count=array.shape[0], type=kind)
        if minmax:
            flat = array.reshape(array.shape[0], -1)
            acc.min, acc.max = flat.min(axis=0).tolist(), flat.max(axis=0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    def copy(index):
        a = gltf.accessors[index]
        values = read_accessor(gltf, blob, index)
        return add(values, a.componentType, a.type, minmax=a.min is not None)

    for mi, mesh in enumerate(gltf.meshes):
        for pi, prim in enumerate(mesh.primitives):
            s = rebuilt[(mi, pi)]
            P = np.vstack(s["P"]).astype(np.float32)
            N = np.vstack(s["N"]).astype(np.float32)
            T = np.vstack(s["T"]).astype(np.uint32).reshape(-1)
            attrs = pygltflib.Attributes(
                POSITION=add(P, pygltflib.FLOAT, pygltflib.VEC3, pygltflib.ARRAY_BUFFER, minmax=True),
                NORMAL=add(N, pygltflib.FLOAT, pygltflib.VEC3, pygltflib.ARRAY_BUFFER),
            )
            if s["J"]:
                attrs.JOINTS_0 = add(np.vstack(s["J"]).astype(np.uint16), pygltflib.UNSIGNED_SHORT, pygltflib.VEC4, pygltflib.ARRAY_BUFFER)
                attrs.WEIGHTS_0 = add(np.vstack(s["W"]).astype(np.float32), pygltflib.FLOAT, pygltflib.VEC4, pygltflib.ARRAY_BUFFER)
            prim.attributes = attrs
            prim.indices = add(T, pygltflib.UNSIGNED_INT, pygltflib.SCALAR, pygltflib.ELEMENT_ARRAY_BUFFER)
    for skin in gltf.skins or []:
        if skin.inverseBindMatrices is not None:
            skin.inverseBindMatrices = copy(skin.inverseBindMatrices)
    for anim in gltf.animations or []:
        for sampler in anim.samplers:
            sampler.input = copy(sampler.input)
            sampler.output = copy(sampler.output)

    gltf.accessors, gltf.bufferViews = accessors, views
    gltf.buffers = [pygltflib.Buffer(byteLength=len(data))]
    gltf.asset.generator = (gltf.asset.generator or "") + " + refine_models.py"
    gltf.set_binary_blob(bytes(data))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    gltf.save_binary(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("inputs", nargs="*", help="GLB files (default: src/meshes/source/*.glb)")
    parser.add_argument("-o", "--out", help="output file (single input) or folder")
    parser.add_argument("--budget", type=int, default=19000, help="max triangles per model (default 19000)")
    args = parser.parse_args()
    inputs = args.inputs or sorted(glob.glob(os.path.join(SOURCE_DIR, "*.glb")))
    for path in inputs:
        if args.out and len(inputs) == 1 and args.out.endswith(".glb"):
            out = args.out
        else:
            out = os.path.join(args.out or OUT_DIR, os.path.basename(path))
        refine(path, out, args.budget)
