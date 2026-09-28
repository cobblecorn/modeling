// Recreates Roblox part geometry in three.js so the built weapons can be
// inspected without opening Studio. Shared by the headless renderer and the
// interactive viewer.
import * as THREE from 'three';

export const MATERIALS = {
  Metal: { metalness: 0.8, roughness: 0.3 },
  DiamondPlate: { metalness: 0.7, roughness: 0.45 },
  CorrodedMetal: { metalness: 0.5, roughness: 0.7 },
  Foil: { metalness: 0.9, roughness: 0.2 },
  Leather: { metalness: 0, roughness: 0.7 },
  Fabric: { metalness: 0, roughness: 0.95 },
  Wood: { metalness: 0, roughness: 0.8 },
  WoodPlanks: { metalness: 0, roughness: 0.8 },
  SmoothPlastic: { metalness: 0, roughness: 0.45 },
  Plastic: { metalness: 0, roughness: 0.55 },
  Rubber: { metalness: 0, roughness: 0.9 },
  Glass: { metalness: 0.1, roughness: 0.05 },
};

export function cfMatrix(c) {
  const m = new THREE.Matrix4();
  m.set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
  return m;
}

export function rotX(a) { return new THREE.Matrix4().makeRotationX(a); }
export function rotY(a) { return new THREE.Matrix4().makeRotationY(a); }
export function rotZ(a) { return new THREE.Matrix4().makeRotationZ(a); }
export function tr(x, y, z) { return new THREE.Matrix4().makeTranslation(x, y, z); }
export function mul(...ms) { const r = new THREE.Matrix4(); for (const m of ms) r.multiply(m); return r; }

function wedgeGeometry(sx, sy, sz) {
  const x = sx / 2, y = sy / 2, z = sz / 2;
  const v = [
    [-x, -y, -z], [-x, -y, z], [-x, y, z],
    [x, -y, -z], [x, -y, z], [x, y, z],
  ];
  const tris = [
    [0, 2, 1], [3, 4, 5],
    [0, 1, 4], [0, 4, 3],
    [1, 2, 5], [1, 5, 4],
    [0, 3, 5], [0, 5, 2],
  ];
  const pos = [];
  for (const t of tris) for (const i of t) pos.push(...v[i]);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

const matCache = new Map();
function materialFor(p) {
  const key = `${p.material}|${p.color.join(',')}|${p.transparency}`;
  if (matCache.has(key)) return matCache.get(key);
  const color = new THREE.Color().setRGB(p.color[0], p.color[1], p.color[2], THREE.SRGBColorSpace);
  let mat;
  if (p.material === 'Neon') {
    mat = new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 1.6, roughness: 0.4 });
  } else {
    const m = MATERIALS[p.material] || { metalness: 0, roughness: 0.6 };
    mat = new THREE.MeshStandardMaterial({ color, metalness: m.metalness, roughness: m.roughness, flatShading: false });
  }
  if (p.transparency > 0) {
    mat.transparent = true;
    mat.opacity = 1 - p.transparency;
  }
  mat.side = THREE.DoubleSide;
  matCache.set(key, mat);
  return mat;
}

export function partMesh(p) {
  let g;
  const [sx, sy, sz] = p.size;
  if (p.shape === 'Wedge') {
    g = wedgeGeometry(sx, sy, sz);
  } else if (p.shape === 'Cylinder') {
    const d = Math.min(sy, sz);
    g = new THREE.CylinderGeometry(d / 2, d / 2, sx, 28);
    g.rotateZ(-Math.PI / 2);
  } else if (p.shape === 'Ball') {
    const d = Math.min(sx, sy, sz);
    g = new THREE.SphereGeometry(d / 2, 28, 18);
  } else if (p.mesh === 'Sphere') {
    g = new THREE.SphereGeometry(0.5, 28, 18);
    g.scale(sx, sy, sz);
  } else {
    g = new THREE.BoxGeometry(sx, sy, sz);
  }
  const mesh = new THREE.Mesh(g, materialFor(p));
  mesh.matrixAutoUpdate = false;
  mesh.matrix.copy(cfMatrix(p.cf));
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  return mesh;
}

function beamMesh(b, pa, pb) {
  const a = new THREE.Vector3().setFromMatrixPosition(pa);
  const c = new THREE.Vector3().setFromMatrixPosition(pb);
  const len = a.distanceTo(c);
  const g = new THREE.CylinderGeometry(b.width / 2, b.width / 2, len, 8);
  const color = new THREE.Color().setRGB(b.color[0], b.color[1], b.color[2], THREE.SRGBColorSpace);
  const mesh = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color, roughness: 0.6 }));
  mesh.position.copy(a.clone().add(c).multiplyScalar(0.5));
  mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), c.clone().sub(a).normalize());
  mesh.updateMatrix();
  mesh.matrixAutoUpdate = false;
  return mesh;
}

// Lune encodes empty Luau tables as {} rather than []
const list = (v) => (Array.isArray(v) ? v : v ? Object.values(v) : []);

// World matrices of every part, with Motor6D poses applied like Roblox does:
// Part1 = Part0 * C0 * Transform * C1^-1
export function posedMatrices(model, poseName) {
  const parts = list(model.parts);
  const byId = new Map(parts.map((p) => [p.id, p]));
  const cache = new Map();
  const get = (p) => {
    if (cache.has(p.id)) return cache.get(p.id);
    let m;
    const par = p.parent ? byId.get(p.parent) : null;
    if (!par) {
      m = cfMatrix(p.cf);
    } else if (p.joint) {
      const poses = p.joint.poses || {};
      const pose = poseName && poses[poseName] ? cfMatrix(poses[poseName]) : new THREE.Matrix4();
      m = mul(get(par), cfMatrix(p.joint.c0), pose, cfMatrix(p.joint.c1).invert());
    } else {
      m = mul(get(par), cfMatrix(par.cf).invert(), cfMatrix(p.cf));
    }
    cache.set(p.id, m);
    return m;
  };
  return { parts, get, byId };
}

export function poseNames(model) {
  const names = new Set();
  for (const p of list(model.parts)) for (const k of Object.keys((p.joint && p.joint.poses) || {})) names.add(k);
  return [...names];
}

export function modelGroup(model, poseName) {
  const g = new THREE.Group();
  const { parts, get, byId } = posedMatrices(model, poseName);
  for (const p of parts) {
    if (p.hidden) continue;
    const mesh = partMesh(p);
    mesh.matrix.copy(get(p));
    g.add(mesh);
  }
  for (const b of list(model.beams)) {
    const pa = mul(get(byId.get(b.a.part)), cfMatrix(b.a.cf));
    const pb = mul(get(byId.get(b.b.part)), cfMatrix(b.b.cf));
    g.add(beamMesh(b, pa, pb));
  }
  return g;
}

// Place a model group so its root sits at `worldRoot` (Matrix4).
export function placeModel(model, worldRoot, poseName) {
  const inner = modelGroup(model, poseName);
  const holder = new THREE.Group();
  holder.matrixAutoUpdate = false;
  holder.matrix.copy(mul(worldRoot, cfMatrix(model.root).invert()));
  holder.add(inner);
  return holder;
}

// ---------------------------------------------------------------------------
// A blocky R15-proportioned stand-in character with the attachments the
// runtime uses. Positions are approximate but good enough to judge scale.
// ---------------------------------------------------------------------------

const SKIN = new THREE.MeshStandardMaterial({ color: 0xb8bcc4, roughness: 0.8 });
const SHIRT = new THREE.MeshStandardMaterial({ color: 0x4a6fa5, roughness: 0.85 });
const PANTS = new THREE.MeshStandardMaterial({ color: 0x3b3f4a, roughness: 0.85 });

const SHOULDER_Y = 4.5;
const ARM_DROP = 0.4; // shoulder pivot to upper-arm centre

export function mannequin(pose = {}) {
  const group = new THREE.Group();
  const limbs = {};
  const add = (name, size, m, mat) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(...size), mat);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(m);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
    limbs[name] = { cf: m, size };
  };
  add('UpperTorso', [2, 1.6, 1], tr(0, 3.9, 0), SHIRT);
  add('LowerTorso', [2, 0.4, 1], tr(0, 2.9, 0), PANTS);
  add('Head', [1.2, 1.2, 1.2], tr(0, 5.35, 0), SKIN);
  for (const [side, sx] of [['Right', 1.5], ['Left', -1.5]]) {
    add(`${side}UpperLeg`, [1, 1.2, 1], tr(sx / 3, 2.1, 0), PANTS);
    add(`${side}LowerLeg`, [1, 1.2, 1], tr(sx / 3, 0.9, 0), PANTS);
    const armRot = pose[`${side}Arm`] || new THREE.Matrix4();
    const pivot = tr(sx, SHOULDER_Y, 0);
    const base = mul(pivot, armRot);
    add(`${side}UpperArm`, [1, 1.17, 1], mul(base, tr(0, -ARM_DROP, 0)), SHIRT);
    add(`${side}LowerArm`, [1, 1.05, 1], mul(base, tr(0, -ARM_DROP - 0.585 - 0.525, 0)), SKIN);
    add(`${side}Hand`, [1, 0.3, 1], mul(base, tr(0, -ARM_DROP - 0.585 - 1.05 - 0.15, 0)), SKIN);
  }
  return { group, limbs };
}

export const ATTACHMENTS = {
  RightGripAttachment: mul(tr(0, -0.15, 0), rotX(-Math.PI / 2)),
  LeftGripAttachment: mul(tr(0, -0.15, 0), rotX(-Math.PI / 2)),
  BodyBackAttachment: tr(0, 0, 0.5),
  BodyFrontAttachment: tr(0, 0, -0.5),
  RightCollarAttachment: tr(1, 0.8, 0),
  LeftCollarAttachment: tr(-1, 0.8, 0),
  WaistCenterAttachment: tr(0, 0, 0),
  WaistBackAttachment: tr(0, 0, 0.5),
  WaistFrontAttachment: tr(0, 0, -0.5),
};

export function mountFrame(limbs, limbName, attachment) {
  const limb = limbs[limbName];
  if (!limb) throw new Error('no limb ' + limbName);
  return mul(limb.cf, ATTACHMENTS[attachment] || new THREE.Matrix4());
}

// Adds every model of `weapon` to the mannequin, either held or holstered.
export function dress(man, weapon, mode, poseName) {
  for (const model of weapon.models) {
    const spec = mode === 'holster' && model.holster ? model.holster : model.rig;
    if (mode === 'holster' && !model.holster) continue;
    const frame = mul(mountFrame(man.limbs, spec.limb, spec.attachment), cfMatrix(spec.offset));
    man.group.add(placeModel(model, frame, poseName));
  }
}

export const HOLD_POSE = { RightArm: rotX(Math.PI / 2) };
