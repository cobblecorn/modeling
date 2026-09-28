"""
Sentry Drone: a small flying robot enemy, exported as a rigged + animated GLB.

    pip install numpy trimesh pygltflib
    python src/meshes/sentry_drone.py              -> dist/SentryDrone.glb
    python src/meshes/sentry_drone.py --scale 0.8  -> smaller (or bigger) drone

Same conventions as the rest of the enemy set (gunmetal / steel / hazard / rust
palette, hot orange-red eye, faces +Z, ~2.2 units across). One skinned mesh,
every vertex bound 100% to one bone, so it imports as a rigid-part robot.

Skeleton
  root                      whole drone (hover bob, death fall)
  └ body                    hull (tilt, jolts)
     ├ head                 eye turret (looks around)
     ├ antenna              wobbles
     ├ rotor_FL/FR/BL/BR    ducted fans (spin on Y)
     ├ gun_L / gun_R        under-slung blasters (recoil on Z)
     │  └ muzzle_L/_R       projectile spawn points (no geometry)
     └ thruster             rear exhaust

Animations: idle, fly, attack, hit, death
"""

import argparse
import math
import os

import numpy as np
import pygltflib
import trimesh
from trimesh.creation import annulus, box, cone, cylinder, icosphere, uv_sphere
from trimesh.transformations import rotation_matrix, translation_matrix

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "dist", "SentryDrone.glb")

# ---------------------------------------------------------------------------
# Materials: (base rgba, metallic, roughness, emissive rgb)
# ---------------------------------------------------------------------------
MATERIALS = {
    "gunmetal": ((0.16, 0.18, 0.21, 1), 0.8, 0.45, None),
    "steel": ((0.42, 0.44, 0.47, 1), 0.85, 0.35, None),
    "hazard": ((0.72, 0.55, 0.08, 1), 0.3, 0.6, None),
    "dark": ((0.05, 0.05, 0.06, 1), 0.5, 0.7, None),
    "rust": ((0.35, 0.16, 0.07, 1), 0.3, 0.9, None),
    "eye_hot": ((1.0, 0.15, 0.05, 1), 0.0, 0.2, (1.0, 0.13, 0.03)),
    "glow_orange": ((1.0, 0.42, 0.06, 1), 0.0, 0.3, (1.0, 0.38, 0.05)),
}

# ---------------------------------------------------------------------------
# Skeleton (bind-pose world positions; rotations are identity at bind)
# ---------------------------------------------------------------------------
ROTORS = {"FL": (-0.82, 0.12, 0.62), "FR": (0.82, 0.12, 0.62), "BL": (-0.82, 0.12, -0.62), "BR": (0.82, 0.12, -0.62)}
JOINTS = [
    ("root", None, (0, 0, 0)),
    ("body", "root", (0, 0, 0)),
    ("head", "body", (0, 0.02, 0.42)),
    ("antenna", "body", (0.12, 0.33, -0.12)),
    *[(f"rotor_{k}", "body", p) for k, p in ROTORS.items()],
    ("gun_L", "body", (-0.36, -0.3, 0.12)),
    ("muzzle_L", "gun_L", (-0.36, -0.34, 0.82)),
    ("gun_R", "body", (0.36, -0.3, 0.12)),
    ("muzzle_R", "gun_R", (0.36, -0.34, 0.82)),
    ("thruster", "body", (0, -0.02, -0.5)),
]
JOINT_INDEX = {name: i for i, (name, _, _) in enumerate(JOINTS)}
JOINT_POS = {name: np.array(p, dtype=float) for name, _, p in JOINTS}

parts = []  # (trimesh, joint, material)


def T(x=0.0, y=0.0, z=0.0):
    return translation_matrix([x, y, z])


def R(axis, deg):
    return rotation_matrix(math.radians(deg), {"x": [1, 0, 0], "y": [0, 1, 0], "z": [0, 0, 1]}[axis])


def add(mesh, joint, mat, *transforms, smooth=False):
    for t in transforms:
        mesh.apply_transform(t)
    if not smooth:
        mesh = mesh.copy()
        mesh.unmerge_vertices()  # hard edges, like the rest of the set
    parts.append((mesh, joint, mat))
    return mesh


# trimesh builds cylinders and cones along +Z
def cyl_z(r, h, sections=16):
    """Cylinder along Z (front/back)."""
    return cylinder(radius=r, height=h, sections=sections)


def cyl_y(r, h, sections=16):
    """Cylinder along Y (up)."""
    return cylinder(radius=r, height=h, sections=sections).apply_transform(R("x", -90))


def cone_y(r, h, sections=16):
    """Cone with its base at y=0 and the tip at +h."""
    return cone(radius=r, height=h, sections=sections).apply_transform(R("x", -90))


def rivet(joint, pos):
    add(icosphere(subdivisions=1, radius=0.028), joint, "steel", T(*pos), smooth=True)


# ---------------------------------------------------------------------------
# Hull
# ---------------------------------------------------------------------------
# octagonal core, a squashed dome on top and a keel underneath
add(cyl_y(0.46, 0.34, 8), "body", "gunmetal", R("y", 22.5))
add(uv_sphere(radius=0.44, count=[16, 16]), "body", "gunmetal", np.diag([1, 0.55, 1, 1]), T(0, 0.14, -0.02), smooth=True)
add(cyl_y(0.36, 0.14, 8), "body", "dark", R("y", 22.5), T(0, -0.22, 0))
add(cyl_y(0.22, 0.08, 8), "body", "steel", R("y", 22.5), T(0, -0.31, 0))
# hazard band around the waist
add(cyl_y(0.475, 0.07, 8), "body", "hazard", R("y", 22.5), T(0, 0.04, 0))
for a in range(8):
    add(box([0.07, 0.075, 0.02]), "body", "dark", T(0, 0.04, 0.47), R("y", a * 45 + 22.5))
# armor plates on the dome (with rivets) and a rust-streaked scrape
for side in (-1, 1):
    add(box([0.26, 0.05, 0.42]), "body", "steel", R("z", side * 24), T(side * 0.24, 0.3, -0.06))
    for z in (-0.2, 0.08):
        rivet("body", (side * 0.32, 0.31, z))
add(box([0.16, 0.012, 0.22]), "body", "rust", R("z", 24), T(0.26, 0.33, -0.1))
add(box([0.1, 0.012, 0.08]), "body", "rust", R("x", 20), T(-0.1, 0.12, 0.4))
# spine ridge + vents
add(box([0.1, 0.06, 0.55]), "body", "steel", T(0, 0.38, -0.08))
for z in (-0.3, -0.2, -0.1):
    add(box([0.3, 0.02, 0.05]), "body", "dark", R("x", -35), T(0, 0.3, z - 0.1))

# eye socket frame on the front face
add(box([0.46, 0.08, 0.1]), "body", "steel", T(0, 0.2, 0.4))
add(box([0.46, 0.06, 0.1]), "body", "steel", T(0, -0.16, 0.4))
for side in (-1, 1):
    add(box([0.08, 0.36, 0.1]), "body", "steel", T(side * 0.22, 0.02, 0.4))
    rivet("body", (side * 0.22, 0.17, 0.46))
    rivet("body", (side * 0.22, -0.12, 0.46))

# ---------------------------------------------------------------------------
# Eye turret (head)
# ---------------------------------------------------------------------------
hx, hy, hz = JOINT_POS["head"]
add(uv_sphere(radius=0.17, count=[16, 16]), "head", "dark", T(hx, hy, hz), smooth=True)
add(cyl_z(0.125, 0.06, 20), "head", "steel", T(hx, hy, hz + 0.14))
add(cyl_z(0.095, 0.04, 20), "head", "eye_hot", T(hx, hy, hz + 0.17), smooth=True)
add(cyl_z(0.035, 0.03, 12), "head", "dark", T(hx, hy, hz + 0.19), smooth=True)
add(box([0.3, 0.05, 0.16]), "head", "gunmetal", R("x", -18), T(hx, hy + 0.15, hz + 0.1))  # brow visor

# ---------------------------------------------------------------------------
# Antenna
# ---------------------------------------------------------------------------
ax, ay, az = JOINT_POS["antenna"]
add(cyl_y(0.035, 0.06, 8), "antenna", "steel", T(ax, ay + 0.03, az))
add(cyl_y(0.012, 0.34, 6), "antenna", "dark", T(ax, ay + 0.2, az))
add(box([0.08, 0.012, 0.012]), "antenna", "steel", T(ax, ay + 0.24, az))
add(box([0.06, 0.012, 0.012]), "antenna", "steel", T(ax, ay + 0.3, az))
add(icosphere(subdivisions=2, radius=0.035), "antenna", "glow_orange", T(ax, ay + 0.38, az), smooth=True)

# ---------------------------------------------------------------------------
# Rotor arms (on the body) + ducted fans (on the rotor joints)
# ---------------------------------------------------------------------------
for key, (rx, ry, rz) in ROTORS.items():
    joint = f"rotor_{key}"
    direction = np.array([rx, 0, rz]) / math.hypot(rx, rz)
    yaw = math.degrees(math.atan2(direction[0], direction[2]))
    # arm: tapered strut from hull to duct, with a hazard-striped knuckle
    length = math.hypot(rx, rz) - 0.3
    mid = direction * (0.36 + length / 2)
    add(box([0.1, 0.08, length]), "body", "gunmetal", R("y", yaw), T(mid[0], 0.06, mid[2]))
    add(box([0.12, 0.03, length * 0.6]), "body", "steel", R("y", yaw), T(mid[0], 0.115, mid[2]))
    knuckle = direction * 0.5
    add(icosphere(subdivisions=2, radius=0.075), "body", "steel", T(knuckle[0], 0.06, knuckle[2]), smooth=True)
    # duct ring, hazard lip, support cross-bars, motor
    add(annulus(r_min=0.27, r_max=0.33, height=0.13, sections=24), "body", "gunmetal", R("x", 90), T(rx, ry, rz), smooth=True)
    add(annulus(r_min=0.32, r_max=0.345, height=0.05, sections=24), "body", "hazard", R("x", 90), T(rx, ry + 0.045, rz), smooth=True)
    add(annulus(r_min=0.26, r_max=0.28, height=0.02, sections=24), "body", "dark", R("x", 90), T(rx, ry - 0.06, rz), smooth=True)
    for bar in (0, 90):
        add(box([0.56, 0.02, 0.03]), "body", "dark", R("y", bar + yaw), T(rx, ry - 0.05, rz))
    add(cyl_y(0.06, 0.1, 12), "body", "steel", T(rx, ry - 0.02, rz))
    for a in (0, 120, 240):
        rivet("body", (rx + 0.31 * math.cos(math.radians(a + 30)), ry + 0.07, rz + 0.31 * math.sin(math.radians(a + 30))))
    # spinning part: hub + three swept blades
    add(cyl_y(0.045, 0.05, 12), joint, "dark", T(rx, ry + 0.04, rz))
    add(cone_y(0.045, 0.05, 12), joint, "steel", T(rx, ry + 0.06, rz), smooth=True)
    for a in (0, 120, 240):
        add(box([0.22, 0.012, 0.07]), joint, "dark", R("x", 14), T(0.13, 0, 0), R("y", a), T(rx, ry + 0.035, rz))
        add(box([0.04, 0.014, 0.072]), joint, "hazard", R("x", 14), T(0.225, 0, 0), R("y", a), T(rx, ry + 0.035, rz))

# ---------------------------------------------------------------------------
# Under-slung blasters
# ---------------------------------------------------------------------------
for side, name in ((-1, "gun_L"), (1, "gun_R")):
    gx, gy, gz = JOINT_POS[name]
    add(box([0.1, 0.12, 0.1]), "body", "dark", T(gx * 0.85, -0.22, gz))  # hardpoint (stays on the hull)
    add(box([0.16, 0.15, 0.4]), name, "gunmetal", T(gx, gy - 0.04, gz + 0.12))
    add(box([0.165, 0.04, 0.3]), name, "hazard", T(gx, gy + 0.01, gz + 0.1))
    add(box([0.04, 0.1, 0.3]), name, "rust", T(gx + side * 0.075, gy - 0.05, gz + 0.06))
    add(cyl_z(0.045, 0.34, 12), name, "steel", T(gx, gy - 0.04, gz + 0.48), smooth=True)
    add(cyl_z(0.07, 0.08, 12), name, "dark", T(gx, gy - 0.04, gz + 0.36))
    add(cyl_z(0.062, 0.06, 12), name, "dark", T(gx, gy - 0.04, gz + 0.66))
    add(cyl_z(0.034, 0.01, 12), name, "glow_orange", T(gx, gy - 0.04, gz + 0.695), smooth=True)
    for k in range(3):
        add(box([0.02, 0.1, 0.03]), name, "dark", T(gx, gy + 0.05, gz - 0.04 + k * 0.06))

# ---------------------------------------------------------------------------
# Rear thruster
# ---------------------------------------------------------------------------
tx, ty, tz = JOINT_POS["thruster"]
add(cyl_z(0.13, 0.12, 16), "thruster", "steel", T(tx, ty, tz))
add(cone(radius=0.15, height=0.14, sections=16), "thruster", "dark", T(tx, ty, tz - 0.2))
add(cyl_z(0.09, 0.02, 16), "thruster", "glow_orange", T(tx, ty, tz - 0.12), smooth=True)
for side in (-1, 1):
    add(box([0.04, 0.2, 0.18]), "thruster", "gunmetal", T(tx + side * 0.16, ty, tz + 0.02))

# ---------------------------------------------------------------------------
# Animations: joint -> {"rotation": [(t, quat)], "translation": [(t, vec)]}
# ---------------------------------------------------------------------------


def quat(axis, deg):
    """(x, y, z, w) quaternion about a unit axis."""
    h = math.radians(deg) / 2
    ax = np.array({"x": [1, 0, 0], "y": [0, 1, 0], "z": [0, 0, 1]}[axis] if isinstance(axis, str) else axis, dtype=float)
    s = math.sin(h)
    return [ax[0] * s, ax[1] * s, ax[2] * s, math.cos(h)]


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ]


def euler(x=0, y=0, z=0):
    return qmul(quat("y", y), qmul(quat("x", x), quat("z", z)))


def sampled(duration, fps, fn):
    n = max(2, int(round(duration * fps)) + 1)
    return [(duration * i / (n - 1), fn(duration * i / (n - 1))) for i in range(n)]


def spin(duration, turns_per_sec, direction, ease=None):
    """Rotor rotation keys every 60 degrees so slerp never takes the short way round."""
    def angle_at(t):
        u = t if ease is None else ease(t)
        return direction * 360 * turns_per_sec * u
    total = abs(angle_at(duration))
    n = max(2, int(math.ceil(total / 60)) + 1)
    return [(duration * i / (n - 1), quat("y", angle_at(duration * i / (n - 1)))) for i in range(n)]


def rotor_tracks(duration, rate, ease=None):
    tracks = {}
    for key in ROTORS:
        direction = 1 if key in ("FL", "BR") else -1  # counter-rotating pairs
        tracks[f"rotor_{key}"] = {"rotation": spin(duration, rate, direction, ease)}
    return tracks


def rel(joint, offset):
    """Joint local translation = bind offset from parent + animated offset."""
    parent = next(p for n, p, _ in JOINTS if n == joint)
    base = JOINT_POS[joint] - (JOINT_POS[parent] if parent else 0)
    return list(base + np.array(offset, dtype=float))


def merge(*dicts):
    out = {}
    for d in dicts:
        for joint, channels in d.items():
            out.setdefault(joint, {}).update(channels)
    return out


def idle():
    d = 1.6
    w = 2 * math.pi / d
    return d, merge(
        rotor_tracks(d, 5),
        {
            "root": {"translation": sampled(d, 30, lambda t: rel("root", [0, 0.07 * math.sin(w * t), 0]))},
            "body": {"rotation": sampled(d, 30, lambda t: euler(x=2.5 * math.sin(w * t + 1), z=3 * math.sin(w * t)))},
            "head": {"rotation": sampled(d, 30, lambda t: euler(y=14 * math.sin(w * t), x=-5 * math.sin(2 * w * t)))},
            "antenna": {"rotation": sampled(d, 30, lambda t: euler(x=6 * math.sin(2 * w * t), z=5 * math.sin(w * t + 0.5)))},
        },
    )


def fly():
    d = 1.0
    w = 2 * math.pi / d
    return d, merge(
        rotor_tracks(d, 8),
        {
            "root": {"translation": sampled(d, 30, lambda t: rel("root", [0, 0.04 * math.sin(w * t), 0]))},
            "body": {"rotation": sampled(d, 30, lambda t: euler(x=16 + 2 * math.sin(w * t), z=2 * math.sin(w * t)))},
            "head": {"rotation": sampled(d, 30, lambda t: euler(x=-14))},
            "antenna": {"rotation": sampled(d, 30, lambda t: euler(x=-22 + 5 * math.sin(2 * w * t)))},
            "thruster": {"translation": sampled(d, 30, lambda t: rel("thruster", [0, 0, -0.02 * abs(math.sin(2 * w * t))]))},
        },
    )


def recoil(t, start, length=0.18):
    u = (t - start) / length
    if u < 0 or u > 1:
        return 0.0
    return -0.14 * (1 - u) ** 2 if u > 0.15 else -0.14 * (u / 0.15)


def attack():
    d = 0.6
    return d, merge(
        rotor_tracks(d, 5),
        {
            "body": {"rotation": sampled(d, 30, lambda t: euler(x=-4 * math.exp(-8 * t) - 4 * math.exp(-8 * max(0, t - 0.3)) * (t >= 0.3)))},
            "gun_L": {"translation": sampled(d, 60, lambda t: rel("gun_L", [0, 0, recoil(t, 0.0)]))},
            "gun_R": {"translation": sampled(d, 60, lambda t: rel("gun_R", [0, 0, recoil(t, 0.3)]))},
            "head": {"rotation": sampled(d, 30, lambda t: euler(x=-3))},
        },
    )


def hit():
    d = 0.45
    return d, merge(
        rotor_tracks(d, 5),
        {
            "root": {"translation": sampled(d, 30, lambda t: rel("root", [0.12 * math.sin(30 * t) * math.exp(-9 * t), 0.05 * math.exp(-9 * t), -0.18 * t * math.exp(-6 * t) * 6]))},
            "body": {"rotation": sampled(d, 30, lambda t: euler(x=-18 * math.exp(-8 * t), z=22 * math.sin(26 * t) * math.exp(-7 * t)))},
            "head": {"rotation": sampled(d, 30, lambda t: euler(y=25 * math.sin(20 * t) * math.exp(-6 * t)))},
            "antenna": {"rotation": sampled(d, 30, lambda t: euler(x=30 * math.sin(28 * t) * math.exp(-6 * t)))},
        },
    )


def death():
    d = 1.8
    ease_out = lambda t: d * (1 - (1 - t / d) ** 2) / 2  # rotors wind down
    def root_pos(t):
        fall = min(1.0, t / 1.5)
        return rel("root", [0.15 * math.sin(6 * t), -1.6 * fall * fall, 0])
    def body_rot(t):
        u = min(1.0, t / 1.5)
        return euler(x=35 * u + 6 * math.sin(20 * t) * (1 - u), y=200 * u * u, z=-65 * u + 10 * math.sin(24 * t) * (1 - u))
    return d, merge(
        rotor_tracks(d, 5, ease_out),
        {
            "root": {"translation": sampled(d, 30, root_pos)},
            "body": {"rotation": sampled(d, 30, body_rot)},
            "head": {"rotation": sampled(d, 30, lambda t: euler(x=40 * min(1, t / 0.8)))},
            "antenna": {"rotation": sampled(d, 30, lambda t: euler(x=-50 * min(1, t / 1.0), z=15 * math.sin(10 * t)))},
            "gun_L": {"rotation": sampled(d, 30, lambda t: euler(x=30 * min(1, t / 1.2)))},
            "gun_R": {"rotation": sampled(d, 30, lambda t: euler(x=-20 * min(1, t / 1.2), z=10 * min(1, t / 1.2)))},
        },
    )


ANIMATIONS = {"idle": idle(), "fly": fly(), "attack": attack(), "hit": hit(), "death": death()}

# ---------------------------------------------------------------------------
# GLB writer
# ---------------------------------------------------------------------------


class Blob:
    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accessors = []

    def add(self, array, component, kind, target=None, minmax=False):
        array = np.ascontiguousarray(array)
        while len(self.data) % 4:
            self.data.append(0)
        offset = len(self.data)
        self.data.extend(array.tobytes())
        self.views.append(pygltflib.BufferView(buffer=0, byteOffset=offset, byteLength=array.nbytes, target=target))
        count = array.shape[0]
        acc = pygltflib.Accessor(bufferView=len(self.views) - 1, componentType=component, count=count, type=kind)
        if minmax:
            flat = array.reshape(count, -1)
            acc.min = flat.min(axis=0).tolist()
            acc.max = flat.max(axis=0).tolist()
        self.accessors.append(acc)
        return len(self.accessors) - 1


def build(scale=1.0):
    blob = Blob()
    material_names = list(MATERIALS)
    materials = []
    for name in material_names:
        rgba, metal, rough, emissive = MATERIALS[name]
        m = pygltflib.Material(
            name=name,
            pbrMetallicRoughness=pygltflib.PbrMetallicRoughness(baseColorFactor=list(rgba), metallicFactor=metal, roughnessFactor=rough),
        )
        if emissive:
            m.emissiveFactor = list(emissive)
        materials.append(m)

    primitives = []
    triangles = 0
    for mi, name in enumerate(material_names):
        chunk = [(m, j) for m, j, mat in parts if mat == name]
        if not chunk:
            continue
        pos, nrm, jnt, idx = [], [], [], []
        base = 0
        for mesh, joint in chunk:
            pos.append(np.asarray(mesh.vertices, dtype=np.float32))
            nrm.append(np.asarray(mesh.vertex_normals, dtype=np.float32))
            jnt.append(np.full((len(mesh.vertices), 4), [JOINT_INDEX[joint], 0, 0, 0], dtype=np.uint16))
            idx.append(np.asarray(mesh.faces, dtype=np.uint32) + base)
            base += len(mesh.vertices)
        pos, nrm, jnt, idx = np.vstack(pos) * np.float32(scale), np.vstack(nrm), np.vstack(jnt), np.vstack(idx)
        weights = np.zeros((len(pos), 4), dtype=np.float32)
        weights[:, 0] = 1
        triangles += len(idx)
        attrs = pygltflib.Attributes(
            POSITION=blob.add(pos, pygltflib.FLOAT, pygltflib.VEC3, pygltflib.ARRAY_BUFFER, minmax=True),
            NORMAL=blob.add(nrm, pygltflib.FLOAT, pygltflib.VEC3, pygltflib.ARRAY_BUFFER),
            JOINTS_0=blob.add(jnt, pygltflib.UNSIGNED_SHORT, pygltflib.VEC4, pygltflib.ARRAY_BUFFER),
            WEIGHTS_0=blob.add(weights, pygltflib.FLOAT, pygltflib.VEC4, pygltflib.ARRAY_BUFFER),
        )
        primitives.append(pygltflib.Primitive(attributes=attrs, indices=blob.add(idx.reshape(-1), pygltflib.UNSIGNED_INT, pygltflib.SCALAR, pygltflib.ELEMENT_ARRAY_BUFFER), material=mi))

    nodes = []
    for name, parent, p in JOINTS:
        local = (JOINT_POS[name] - (JOINT_POS[parent] if parent else 0)) * scale
        nodes.append(pygltflib.Node(name=name, translation=[float(v) for v in local], children=[]))
    for i, (name, parent, _) in enumerate(JOINTS):
        if parent:
            nodes[JOINT_INDEX[parent]].children.append(i)
    inverse_bind = np.stack([np.linalg.inv(translation_matrix(JOINT_POS[n] * scale)).T.astype(np.float32) for n, _, _ in JOINTS])
    skin = pygltflib.Skin(name="SentryDroneRig", joints=list(range(len(JOINTS))), skeleton=0, inverseBindMatrices=blob.add(inverse_bind, pygltflib.FLOAT, pygltflib.MAT4))
    mesh_node = len(nodes)
    nodes.append(pygltflib.Node(name="sentry_drone_mesh", mesh=0, skin=0))

    animations = []
    for anim_name, (duration, tracks) in ANIMATIONS.items():
        samplers, channels = [], []
        for joint, chans in tracks.items():
            for path, keys in chans.items():
                times = np.array([k[0] for k in keys], dtype=np.float32)
                values = np.array([k[1] for k in keys], dtype=np.float32)
                if path == "translation":
                    values *= np.float32(scale)
                kind = pygltflib.VEC4 if path == "rotation" else pygltflib.VEC3
                samplers.append(pygltflib.AnimationSampler(input=blob.add(times, pygltflib.FLOAT, pygltflib.SCALAR, minmax=True), output=blob.add(values, pygltflib.FLOAT, kind), interpolation="LINEAR"))
                channels.append(pygltflib.AnimationChannel(sampler=len(samplers) - 1, target=pygltflib.AnimationChannelTarget(node=JOINT_INDEX[joint], path=path)))
        animations.append(pygltflib.Animation(name=anim_name, samplers=samplers, channels=channels))

    gltf = pygltflib.GLTF2(
        asset=pygltflib.Asset(generator="sentry_drone.py (trimesh + pygltflib)", version="2.0"),
        scene=0,
        scenes=[pygltflib.Scene(nodes=[0, mesh_node])],
        nodes=nodes,
        meshes=[pygltflib.Mesh(name="sentry_drone", primitives=primitives)],
        skins=[skin],
        materials=materials,
        animations=animations,
        accessors=blob.accessors,
        bufferViews=blob.views,
        buffers=[pygltflib.Buffer(byteLength=len(blob.data))],
    )
    gltf.set_binary_blob(bytes(blob.data))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    gltf.save_binary(OUT)
    all_pos = np.vstack([np.asarray(m.vertices) for m, _, _ in parts])
    size = (all_pos.max(axis=0) - all_pos.min(axis=0)) * scale
    print(f"wrote {os.path.normpath(OUT)}: {triangles} tris, {len(JOINTS)} joints, {len(animations)} animations, size {np.round(size, 2).tolist()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scale", type=float, default=1.0, help="uniform size multiplier (default 1.0, ~2.3 units across)")
    build(parser.parse_args().scale)
