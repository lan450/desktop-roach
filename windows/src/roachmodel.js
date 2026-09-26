// roachmodel.js — port of RoachModel.swift: procedural American-cockroach
// body, the third skin on the shared FlyModel contract. +Y forward, +Z up;
// the desktop sees the dorsal silhouette. All detail is attached to the
// existing FlyModel animation pivots, so behavior code never branches on the
// body form.
//
// SceneKit -> three.js mapping (in addition to the one in flymodel.js):
//   RoachMesh (batched vertex-color triangles)
//                    -> BufferGeometry with position/normal/color attributes,
//                       one MeshPhongMaterial({vertexColors: true})
//   SCNSphere(r=1, segmentCount 24) scaled
//                    -> SphereGeometry(1, 24, 18) scaled
//   SCNShape(path, extrusionDepth: d)
//                    -> ExtrudeGeometry({depth: d, bevelEnabled: false}),
//                       translated back by d/2 (SCNShape extrudes symmetrically)
//   SCNShape path AffineTransform(rotationByRadians: r)
//                    -> geometry.rotateZ(r) before the depth recenter (rotating
//                       in the path plane leaves the extrusion axis alone)
//   material.isDoubleSided / writesToDepthBuffer = false
//                    -> side: THREE.DoubleSide / depthWrite: false
//   .constant lighting -> MeshBasicMaterial
//
// Colors are keyed to the reference photo: deep red-brown/black carapace with
// amber kept for local accents only (pronotum flank band, humeral patch,
// abdominal tail bands) — the earlier all-over sand tone read as a beetle.
// NSColor(calibrated...) components are sRGB. Mixing happens in that sRGB
// space (NSColor.blended semantics) and RoachMesh.vertex converts to the
// linear working space exactly once when writing the attribute, exactly like
// the Swift build's per-vertex linear() (skipping it renders every tone one
// gamma stop too light).

import * as THREE from '../node_modules/three/build/three.module.js';
import { Leg, buildLeg, mat, FLY_SCALE, SHADOWS_ENABLED } from './flymodel.js';
import { clampf, smoothstep } from './util.js';

// The palette stays in raw sRGB components on purpose: NSColor.blended mixes
// the calibrated (sRGB) components and only then converts per-vertex to
// linear, so mixing here must happen in sRGB too or every midtone drifts
// (linear-space lerp renders ~30-60% brighter at the same fraction).
const tegminaRed = [0.27, 0.095, 0.038];
const bodyDark = [0.13, 0.05, 0.026];
const rimTan = [0.64, 0.42, 0.19];
const veinDark = [0.16, 0.06, 0.026];
const femurRed = [0.38, 0.12, 0.045];
const tibiaDark = [0.17, 0.07, 0.035];
const wingBlack = [0.046, 0.023, 0.019];
const pronotumBlack = [0.065, 0.055, 0.052];
const edgeCopper = [0.74, 0.23, 0.055];

// NSColor.blended(withFraction:of:) — amount of b into a, in sRGB.
function mixed(a, b, amount) {
  const f = clampf(amount, 0, 1);
  return [a[0] + (b[0] - a[0]) * f,
          a[1] + (b[1] - a[1]) * f,
          a[2] + (b[2] - a[2]) * f];
}

// The same per-component sRGB->linear conversion RoachMesh.vertex does in
// Swift before writing the color source.
function linear(c) {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

// sRGB component array -> THREE.Color in the linear working space (for the
// few materials that take a plain color instead of vertex colors).
function toColor(c) {
  return new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);
}

// Curved shells and fine appendages are batched into meshes rather than a
// separate node for every vein, flagellomere or tibial spine.
class RoachMesh {
  constructor() {
    this.positions = [];
    this.colors = [];
    this.indices = [];
  }

  vertex(p, color) {
    const index = this.positions.length / 3;
    this.positions.push(p[0], p[1], p[2]);
    // color arrives as raw sRGB components (the Swift mixing space) and is
    // converted to the linear working space exactly once, here
    this.colors.push(linear(color[0]), linear(color[1]), linear(color[2]));
    return index;
  }

  triangle(a, b, c, flip = false) {
    if (flip) this.indices.push(a, c, b);
    else this.indices.push(a, b, c);
  }

  quad(a, b, c, d, flip = false) {
    this.triangle(a, b, c, flip);
    this.triangle(a, c, d, flip);
  }

  tube(points, radii, color, sides = 6, ringContrast = 0) {
    if (points.length < 2 || points.length !== radii.length) return;
    const start = this.positions.length / 3;
    const asVector = (p) => new THREE.Vector3(p[0], p[1], p[2]);
    for (let i = 0; i < points.length; i++) {
      const p = asVector(points[i]);
      const tangent = asVector(points[Math.min(i + 1, points.length - 1)])
        .sub(asVector(points[Math.max(0, i - 1)])).normalize();
      const reference = Math.abs(tangent.z) > 0.9
        ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(0, 0, 1);
      const across = new THREE.Vector3().crossVectors(tangent, reference).normalize();
      const up = new THREE.Vector3().crossVectors(tangent, across);
      const tint = mixed(color, bodyDark, i % 3 === 0 ? ringContrast : 0);
      for (let j = 0; j < sides; j++) {
        const angle = j * 2 * Math.PI / sides;
        const v = p.clone()
          .addScaledVector(across, radii[i] * Math.cos(angle))
          .addScaledVector(up, radii[i] * Math.sin(angle));
        this.vertex([v.x, v.y, v.z], tint);
      }
    }
    for (let i = 0; i < points.length - 1; i++) {
      for (let j = 0; j < sides; j++) {
        const a = start + i * sides + j;
        const b = start + i * sides + (j + 1) % sides;
        this.quad(a, b, b + sides, a + sides);
      }
    }
    const first = this.vertex(points[0], color);
    const last = this.vertex(points[points.length - 1], color);
    const end = start + (points.length - 1) * sides;
    for (let j = 0; j < sides; j++) {
      this.triangle(first, start + (j + 1) % sides, start + j);
      this.triangle(last, end + j, end + (j + 1) % sides);
    }
  }

  // Face-normal accumulation like the Swift version: every triangle's
  // (unnormalized) face normal is summed into its vertices, so ridges keep
  // their crease instead of the smooth vertex average computeVertexNormals
  // would give.
  geometry(specular = 0.3, shininess = 0.45) {
    const count = this.positions.length / 3;
    const normals = new Float32Array(this.positions.length);
    const ax = new THREE.Vector3(), bx = new THREE.Vector3(), cx = new THREE.Vector3();
    const face = new THREE.Vector3();
    for (let i = 0; i < this.indices.length; i += 3) {
      const a = this.indices[i], b = this.indices[i + 1], c = this.indices[i + 2];
      ax.set(this.positions[a * 3], this.positions[a * 3 + 1], this.positions[a * 3 + 2]);
      bx.set(this.positions[b * 3], this.positions[b * 3 + 1], this.positions[b * 3 + 2]);
      cx.set(this.positions[c * 3], this.positions[c * 3 + 1], this.positions[c * 3 + 2]);
      face.crossVectors(bx.sub(ax), cx.sub(ax));
      normals[a * 3] += face.x; normals[a * 3 + 1] += face.y; normals[a * 3 + 2] += face.z;
      normals[b * 3] += face.x; normals[b * 3 + 1] += face.y; normals[b * 3 + 2] += face.z;
      normals[c * 3] += face.x; normals[c * 3 + 1] += face.y; normals[c * 3 + 2] += face.z;
    }
    for (let i = 0; i < count; i++) {
      const x = normals[i * 3], y = normals[i * 3 + 1], z = normals[i * 3 + 2];
      const len2 = x * x + y * y + z * z;
      if (len2 > 1e-12) {
        const inv = 1 / Math.sqrt(len2);
        normals[i * 3] = x * inv; normals[i * 3 + 1] = y * inv; normals[i * 3 + 2] = z * inv;
      } else {
        normals[i * 3] = 0; normals[i * 3 + 1] = 0; normals[i * 3 + 2] = 1;
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(this.positions, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(this.colors, 3));
    geo.setIndex(this.indices);
    const material = new THREE.MeshPhongMaterial({
      vertexColors: true,
      specular: new THREE.Color(specular, specular, specular),
      shininess: shininess * 100,
      side: THREE.DoubleSide,
    });
    return new THREE.Mesh(geo, material);
  }
}

function ellipsoid(radii, at, color, specular = 0.06) {
  const node = new THREE.Mesh(new THREE.SphereGeometry(1, 24, 18), mat(toColor(color), specular, 0.35));
  node.position.set(at[0], at[1], at[2]);
  node.scale.set(radii[0], radii[1], radii[2]);
  return node;
}

// A thin, bowed tegmen. The inner edge follows the dorsal seam; the rounded
// tip ends off-centre so the pair does not form a beetle-like pointed shield.
function tegmenPoint(side, t, u) {
  const inner = 0;
  const width = 3.8 * Math.pow(Math.max(0, 1 - Math.pow(t, 4)), 1.05)
            + 1.0 * Math.sin(Math.PI * t) * Math.pow(1 - t, 0.35);
  const crown = 0.52 * Math.sin(Math.PI * u) * Math.sin(Math.PI * (0.12 + 0.88 * t));
  return [side * (inner + width * u), -20.5 * t, 0.15 - 0.18 * t + crown];
}

function tegmenShape(side) {
  const mesh = new RoachMesh();
  const rows = 40, columns = 14;
  const layerSize = (rows + 1) * (columns + 1);
  for (let layer = 0; layer <= 1; layer++) {
    for (let i = 0; i <= rows; i++) {
      const t = i / rows;
      for (let j = 0; j <= columns; j++) {
        const u = j / columns;
        const point = tegmenPoint(side, t, u);
        if (layer === 1) point[2] -= 0.12;
        // The photograph is nearly black down the centre, with amber
        // confined to the humeral shoulder, side edges and rounded tip.
        const shoulder = Math.exp(-Math.pow((t - 0.115) / 0.16, 2))
          * smoothstep((u - 0.68) / 0.23);
        const edge = smoothstep((u - 0.79) / 0.20);
        const tail = smoothstep((t - 0.77) / 0.21);
        const striae = 0.026 * Math.sin(125 * u + 6 * t) * Math.sin(36 * t);
        let color = mixed(wingBlack, tegminaRed, 0.13 + 0.16 * u + 0.10 * t + striae);
        color = mixed(color, rimTan, 0.70 * shoulder);
        color = mixed(color, edgeCopper,
          (0.65 * edge * (0.55 + 0.45 * t)
           + 0.82 * tail * (0.52 + 0.48 * u)));
        if (layer === 1) color = mixed(color, bodyDark, 0.4);
        mesh.vertex(point, color);
      }
    }
  }
  for (let layer = 0; layer <= 1; layer++) {
    for (let i = 0; i < rows; i++) {
      for (let j = 0; j < columns; j++) {
        const a = layer * layerSize + i * (columns + 1) + j;
        mesh.quad(a, a + columns + 1, a + columns + 2, a + 1,
          (side < 0) !== (layer === 1));
      }
    }
  }
  // Close the thin rim; top and bottom remain separate surfaces.
  const perimeter = [];
  for (let j = 0; j <= columns; j++) perimeter.push(j);
  for (let i = 1; i <= rows; i++) perimeter.push(i * (columns + 1) + columns);
  for (let j = columns - 1; j >= 0; j--) perimeter.push(rows * (columns + 1) + j);
  for (let i = rows - 1; i >= 1; i--) perimeter.push(i * (columns + 1));
  for (let i = 0; i < perimeter.length; i++) {
    const a = perimeter[i], b = perimeter[(i + 1) % perimeter.length];
    mesh.quad(a, b, b + layerSize, a + layerSize, side < 0);
  }
  return mesh.geometry(0.03, 0.5);
}

function buildVeins(side) {
  const mesh = new RoachMesh();
  function trace(t0, t1, u0, u1, radius) {
    const points = [];
    const radii = [];
    for (let i = 0; i <= 22; i++) {
      const f = i / 22;
      const t = t0 + (t1 - t0) * f;
      const u = u0 + (u1 - u0) * (f * (2 - f));
      const p = tegmenPoint(side, t, u);
      p[2] += radius * 0.65;
      points.push(p);
      radii.push(radius * (1 - 0.60 * f));
    }
    mesh.tube(points, radii, mixed(veinDark, tegminaRed, 0.35));
  }
  for (let i = 0; i < 8; i++) {
    const u = 0.12 + i * 0.105;
    trace(0.045, 0.91 - i * 0.018, 0.07 + i * 0.048, u, i === 0 ? 0.017 : 0.011);
  }
  for (let i = 0; i < 10; i++) {
    const t = 0.19 + i * 0.071;
    trace(t, Math.min(0.91, t + 0.11), 0.51, 0.91, 0.008);
  }
  return mesh.geometry(0.08, 0.3);
}

// Folded hindwings fit within the forewing silhouette. Their existing pivots
// still spread and beat in flight; nothing decorative becomes a third wing.
function hindwingShape(side) {
  // NSBezierPath control points; every x is mirrored by side.
  const p = (x, y) => [side * x, y];
  const shape = new THREE.Shape();
  const [x0, y0] = p(0, 0);
  shape.moveTo(x0, y0);
  let pts = p(2.3, -8.0);
  let c1 = p(1.7, -1.8), c2 = p(2.6, -5.0);
  shape.bezierCurveTo(c1[0], c1[1], c2[0], c2[1], pts[0], pts[1]);
  pts = p(0.6, -16.5); c1 = p(2.4, -12.4); c2 = p(1.8, -15.8);
  shape.bezierCurveTo(c1[0], c1[1], c2[0], c2[1], pts[0], pts[1]);
  pts = p(-1.4, -12.0); c1 = p(-0.4, -17.1); c2 = p(-1.4, -15.5);
  shape.bezierCurveTo(c1[0], c1[1], c2[0], c2[1], pts[0], pts[1]);
  pts = p(0, 0); c1 = p(-2.0, -6.0); c2 = p(-1.0, -1.5);
  shape.bezierCurveTo(c1[0], c1[1], c2[0], c2[1], pts[0], pts[1]);
  shape.closePath();
  const geo = new THREE.ExtrudeGeometry(shape,
    { depth: 0.045, bevelEnabled: false, curveSegments: 24 });
  // The outline is pre-rotated to cancel the fixed fold land() applies, so
  // folded wings stay tucked under the shell. Rotating the geometry in the
  // path plane equals the path AffineTransform; the extrusion axis is untouched.
  geo.rotateZ(-side * 0.13);
  geo.translate(0, 0, -0.045 / 2);
  // SceneKit's blinn shading renders this same spec/shininess pair as a
  // matte dark membrane; three.js Phong under the shared light rig turns it
  // into an opaque white mirror, so the film gets a hard specular near zero.
  // The SceneKit film reads nearly black against the shell under the same
  // reference; the raw 0.43 brown over this rig's ~2.2x exposure clips to
  // white, so the membrane keeps that darkness explicitly.
  const material = new THREE.MeshPhongMaterial({
    color: toColor([0.16, 0.11, 0.06]),
    specular: new THREE.Color(0.02, 0.02, 0.02),
    shininess: 8,
    transparent: true,
    opacity: 0.34,
    side: THREE.DoubleSide,
    depthWrite: false,
  });
  return new THREE.Mesh(geo, material);
}

// Hood-shaped pronotum: a narrower curved front, projecting rear shoulders
// and a gently flattened back edge over the tegmen hinges.
function pronotumShape() {
  const mesh = new RoachMesh();
  const rings = 26, segments = 112;
  // Around the hood from its front tip. Explicit rear corners and three
  // nearly level rear points give it a shield outline, not an ellipse.
  const outline = [
    [0, 4.15], [-1.85, 3.83], [-3.25, 2.80], [-4.18, 1.05],
    [-4.62, -1.30], [-4.55, -2.62], [-3.55, -3.48], [0, -3.50],
    [3.55, -3.48], [4.55, -2.62], [4.62, -1.30], [4.18, 1.05],
    [3.25, 2.80], [1.85, 3.83],
  ];
  function interpolate(a, b, c, d, t) {
    const t2 = t * t, t3 = t2 * t;
    return 0.5 * ((2 * b) + (-a + c) * t
                  + (2 * a - 5 * b + 4 * c - d) * t2
                  + (-a + 3 * b - 3 * c + d) * t3);
  }
  function contour(j) {
    const location = j * outline.length / segments;
    const index = Math.floor(location) % outline.length;
    const t = location - Math.floor(location);
    const a = outline[(index - 1 + outline.length) % outline.length];
    const b = outline[index];
    const c = outline[(index + 1) % outline.length];
    const d = outline[(index + 2) % outline.length];
    return [interpolate(a[0], b[0], c[0], d[0], t),
            interpolate(a[1], b[1], c[1], d[1], t)];
  }
  for (let i = 0; i <= rings; i++) {
    const r = i / rings;
    for (let j = 0; j <= segments; j++) {
      const [cx, cy] = contour(j);
      const x = r * cx, y = r * cy;
      const nx = x / 4.62, ny = y / 4.15;
      const z = 0.44 * (1 - r * r) - 0.07 * Math.pow(r, 12);
      const edge = smoothstep((r - 0.76) / 0.18);
      const flanks = smoothstep((Math.abs(nx) - 0.43) / 0.33);
      const warmEdge = edge * (0.02 + 0.62 * flanks);
      // The photo's ochre patches are broad and broken near the rear,
      // not a continuous high-contrast outline around the whole shield.
      const pairedAmber = Math.exp(-Math.pow((Math.abs(nx) - 0.56) / 0.21, 2)
                          - Math.pow((ny + 0.54) / 0.26, 2)) * 0.88;
      const ink = Math.exp(-Math.pow((Math.abs(nx) - 0.28) / 0.24, 2)
                  - Math.pow((ny - 0.14) / 0.52, 2)) * 0.62;
      const rearDivide = Math.exp(-Math.pow(nx / 0.25, 2)
                         - Math.pow((ny + 0.72) / 0.33, 2)) * 0.94;
      let color = mixed(pronotumBlack, tegminaRed, 0.24);
      color = mixed(color, rimTan, Math.max(warmEdge, pairedAmber));
      color = mixed(color, pronotumBlack, Math.max(ink, rearDivide));
      color = mixed(color, bodyDark, 0.55 * smoothstep((r - 0.97) / 0.03));
      mesh.vertex([x, y, z], color);
    }
  }
  for (let i = 0; i < rings; i++) {
    for (let j = 0; j < segments; j++) {
      const a = i * (segments + 1) + j;
      mesh.quad(a, a + segments + 1, a + segments + 2, a + 1);
    }
  }
  const bottom = mesh.vertex([0, 0, -0.30], bodyDark);
  for (let j = 0; j < segments; j++) {
    const a = rings * (segments + 1) + j;
    mesh.triangle(bottom, a + 1, a);
  }
  return mesh.geometry(0.03, 0.5);
}

function buildAntenna(side) {
  const mesh = new RoachMesh();
  const points = [];
  const radii = [];
  // Both whips use the same curve mirrored across the body centreline.
  for (let i = 0; i <= 64; i++) {
    const t = i / 64;
    const x = side * (17.5 * t + 0.6 * Math.sin(Math.PI * t));
    const y = 11.5 * t + 1.4 * Math.sin(Math.PI * t);
    points.push([x, y, 0.7 * Math.sin(Math.PI * t) - 0.28 * t]);
    const radius = 0.115 * Math.pow(1 - t, 0.8) + 0.012;
    radii.push(radius * (i % 3 === 0 ? 0.91 : 1));
  }
  const copper = [0.64, 0.23, 0.09];
  mesh.tube(points, radii, copper, 7, 0.10);
  const root = new THREE.Object3D();
  root.add(mesh.geometry(0.05, 0.5));
  root.position.set(side * 1.25, 8.25, 3.85);
  const bulb = ellipsoid([0.25, 0.42, 0.23], [0, 0.1, 0], bodyDark);
  root.add(bulb);
  return root;
}

function buildCercus(side) {
  const mesh = new RoachMesh();
  const points = [];
  const radii = [];
  for (let i = 0; i <= 14; i++) {
    const t = i / 14;
    points.push([side * (0.65 * t + 0.30 * t * t), -2.65 * t, -0.65 * t]);
    radii.push((0.25 * (1 - t) + 0.025) * (i % 2 === 0 ? 1 : 0.85));
  }
  mesh.tube(points, radii, mixed(bodyDark, rimTan, 0.18), 6, 0.3);
  const node = new THREE.Object3D();
  node.add(mesh.geometry(0.04, 0.5));
  node.position.set(side * 2.1, -14.0, 3.1);
  return node;
}

function buildAbdomen() {
  const pivot = new THREE.Object3D();
  pivot.position.set(0, -6.5, 3.25);
  // The controller overwrites this scale to breathe. All anatomical shaping
  // is below the pivot, so the segmented abdomen survives those writes.
  pivot.scale.set(0.9, 1.5, 0.75);
  pivot.add(ellipsoid([5.45, 5.65, 0.95], [0, 0, -0.12], bodyDark));
  const mesh = new RoachMesh();
  const rows = 4, columns = 24;
  for (let plate = 0; plate < 8; plate++) {
    const first = mesh.positions.length / 3;
    for (let i = 0; i <= rows; i++) {
      const f = i / rows;
      const y = 5.4 - plate * 1.36 - f * 1.30;
      const width = 5.55 * Math.sqrt(Math.max(0.015, 1 - Math.pow(y / 5.9, 2)));
      for (let j = 0; j <= columns; j++) {
        const a = -Math.PI / 2 + j * Math.PI / columns;
        const x = width * Math.sin(a);
        const z = 1.08 * Math.cos(a) + 0.08 * Math.sin(Math.PI * f);
        const edge = Math.pow(Math.abs(Math.sin(a)), 8);
        const tail = plate >= 6 ? 0.12 : 0;
        let color = mixed(tegminaRed, rimTan, 0.13 + edge * 0.34 + tail);
        color = mixed(color, bodyDark, 0.20 + 0.30 * Math.pow(f, 9) - tail * 0.25);
        mesh.vertex([x, y, z], color);
      }
    }
    for (let i = 0; i < rows; i++) {
      for (let j = 0; j < columns; j++) {
        const a = first + i * (columns + 1) + j;
        mesh.quad(a, a + columns + 1, a + columns + 2, a + 1);
      }
    }
  }
  pivot.add(mesh.geometry(0.04, 0.5));
  return pivot;
}

// Replace only the visible limb surfaces. The original pivots, segment
// lengths, motor feedback and toe endpoint remain the shared Leg's contract.
// The visible shafts take opposite bows on each side of the knee. Their ends
// still meet the original animated pivots, keeping toe feedback unchanged.
function detailLeg(leg, femur, tibia, tarsus) {
  for (const joint of [leg.root, leg.knee, leg.ankle]) {
    for (let i = joint.children.length - 1; i >= 0; i--) {
      const child = joint.children[i];
      if (child.isMesh) joint.remove(child);
    }
  }
  const frontThickness = leg.isFront ? 0.64 : 1;
  // The visible knee is offset sideways from the mechanical pivot. Its
  // local x/z stay zero under the knee's y-axis rotation, so the femur tip
  // and tibia root meet through every motor pose without moving the toe.
  const isRear = femur > 5;
  const kneeOffset = leg.swingSign * (leg.isFront ? -1 : 1)
    * (leg.isFront ? 1.55 : (isRear ? 2.95 : 2.25));
  const femurY = (t) => kneeOffset * t;
  const tibiaY = (t) => kneeOffset * (1 - t);

  const thigh = new RoachMesh();
  thigh.tube([[0, 0, 0],
              [femur * 0.20, femurY(0.20), 0],
              [femur * 0.45, femurY(0.45), 0],
              [femur * 0.68, femurY(0.68), 0],
              [femur * 0.87, femurY(0.87), 0],
              [femur, kneeOffset, 0]],
    [0.40, 0.62, 0.74, 0.66, 0.46, 0.27].map((r) => r * frontThickness),
    femurRed, 10);
  const thighLength = Math.hypot(femur, kneeOffset);
  const thighNormal = [-kneeOffset / thighLength, femur / thighLength];
  for (const side of [-1, 1]) {
    for (let i = 0; i < (leg.isFront ? 3 : 5); i++) {
      const t = 0.28 + i * (leg.isFront ? 0.20 : 0.125);
      const spinePoint = (forward, outward) => {
        const offset = side * outward * frontThickness;
        return [femur * t + forward * femur / thighLength + offset * thighNormal[0],
                femurY(t) + forward * kneeOffset / thighLength + offset * thighNormal[1], 0];
      };
      thigh.tube([spinePoint(0, 0.42), spinePoint(0.15, 0.70),
                  spinePoint(0.32, 0.90 - t * 0.13)],
        [0.09, 0.055, 0.006].map((r) => r * frontThickness),
        bodyDark, 5);
    }
  }
  leg.root.add(thigh.geometry(0.06, 0.5));
  leg.root.add(ellipsoid([0.66, 0.46 * frontThickness, 0.36 * frontThickness],
    [0.14, 0, 0], bodyDark));

  const shin = new RoachMesh();
  shin.tube([[0, kneeOffset, 0],
             [tibia * 0.18, tibiaY(0.18), 0],
             [tibia * 0.43, tibiaY(0.43), 0],
             [tibia * 0.68, tibiaY(0.68), 0],
             [tibia * 0.87, tibiaY(0.87), 0],
             [tibia, 0, 0]],
    [0.22, 0.20, 0.18, 0.15, 0.12, 0.085], tibiaDark, 8);
  const shinLength = Math.hypot(tibia, kneeOffset);
  const shinNormal = [kneeOffset / shinLength, tibia / shinLength];
  for (const side of [-1, 1]) {
    for (let i = 0; i < (leg.isFront ? 4 : 7); i++) {
      const t = 0.13 + i * (leg.isFront ? 0.22 : 0.125);
      const length = (0.53 + 0.35 * t) * (leg.isFront ? 0.85 : 1);
      const spinePoint = (forward, outward) => {
        const offset = side * outward;
        return [tibia * t + forward * tibia / shinLength + offset * shinNormal[0],
                tibiaY(t) - forward * kneeOffset / shinLength + offset * shinNormal[1], 0];
      };
      shin.tube([spinePoint(0, 0.18), spinePoint(0.20, 0.20 + length * 0.55),
                 spinePoint(0.38, 0.20 + length)],
        [0.09, 0.045, 0.004], bodyDark, 5);
    }
  }
  leg.knee.add(shin.geometry(0.05, 0.5));
  leg.knee.add(ellipsoid([0.34, 0.33, 0.32], [0, kneeOffset, 0], bodyDark));

  const foot = new RoachMesh();
  for (let i = 0; i < 5; i++) {
    const x0 = tarsus * i / 5;
    const x1 = tarsus * (i + 1) / 5;
    const radius = 0.135 - i * 0.016;
    foot.tube([[x0, 0, 0], [x0 + 0.09, 0, 0],
               [x1 - 0.035, 0, 0], [x1, 0, 0]],
      [radius * 0.65, radius, radius * 0.70, radius * 0.50],
      mixed(tibiaDark, femurRed, 0.25), 7);
  }
  for (const side of [-1, 1]) {
    foot.tube([[tarsus - 0.10, side * 0.04, 0],
               [tarsus + 0.15, side * 0.18, 0.04],
               [tarsus + 0.29, side * 0.11, -0.04]],
      [0.065, 0.042, 0.005], bodyDark);
  }
  leg.ankle.add(foot.geometry(0.04, 0.5));
}

export function buildRoachModel() {
  const root = new THREE.Object3D();
  root.scale.set(FLY_SCALE, FLY_SCALE, FLY_SCALE);
  root.add(ellipsoid([1.85, 1.70, 0.90], [0, 7.9, 3.35], bodyDark));
  for (const side of [-1, 1]) {
    root.add(ellipsoid([0.42, 0.73, 0.44],
      [side * 1.58, 8.25, 3.78], [0.035, 0.035, 0.035], 0.6));
    root.add(buildAntenna(side));
    const palp = new RoachMesh();
    palp.tube([[side * 0.65, 8.7, 2.95], [side * 1.25, 9.4, 2.85],
               [side * 1.05, 10.0, 2.9]],
      [0.16, 0.13, 0.08], mixed(bodyDark, rimTan, 0.2));
    root.add(palp.geometry(0.04, 0.5));
  }
  // The shallow thoracic underside joins head, leg roots and abdomen.
  root.add(ellipsoid([4.25, 4.4, 1.0], [0, 2.6, 3.1], bodyDark));
  const shield = pronotumShape();
  // The hood covers the bright wing shoulders all the way to its rear edge.
  shield.position.set(0, 5.25, 5.48);
  shield.scale.set(0.86, 0.86, 0.86);
  root.add(shield);
  const abdomen = buildAbdomen();
  root.add(abdomen);

  const legs = [];
  const z = 3.6;
  // RF, LF, RM, LM, RH, LH; retain the existing locomotor geometry.
  const specs = [
    [1, [3.8, 5.4, z], 1.00, 0.0, true, 4.0, 4.6, 3.0],
    [-1, [-3.8, 5.4, z], 1.00, 0.5, true, 4.0, 4.6, 3.0],
    [1, [4.4, 1.9, z], -0.08, 0.5, false, 4.8, 5.6, 3.6],
    [-1, [-4.4, 1.9, z], -0.08, 0.0, false, 4.8, 5.6, 3.6],
    [1, [3.9, -1.7, z], -1.05, 0.0, false, 6.0, 8.0, 5.2],
    [-1, [-3.9, -1.7, z], -1.05, 0.5, false, 6.0, 8.0, 5.2],
  ];
  for (const [side, attach, yaw, phase, front, f, t, ta] of specs) {
    const leg = buildLeg(attach, side > 0 ? yaw : (Math.PI - yaw),
      side, phase, front, f, t, ta);
    detailLeg(leg, f, t, ta);
    root.add(leg.root);
    legs.push(leg);
  }

  const foldedWings = new THREE.Object3D();
  for (const side of [-1, 1]) {
    const wing = hindwingShape(side);
    wing.position.set(side * 1.35, 1.4, 4.52);
    wing.rotation.set(0, 0, side * 0.13);
    foldedWings.add(wing);
  }
  root.add(foldedWings);
  const tegmina = [];
  for (const side of [-1, 1]) {
    const wing = tegmenShape(side);
    // Mirrored surfaces meet at the midline without overlapping polygons.
    wing.position.set(0, 2.0, 5.0);
    wing.add(buildVeins(side));
    root.add(wing);
    tegmina.push(wing);
    root.add(buildCercus(side));
  }
  function blurWing(side) {
    const n = new THREE.Mesh(new THREE.SphereGeometry(1.0, 16, 12),
      new THREE.MeshBasicMaterial({
        color: toColor([0.58, 0.40, 0.21]),
        transparent: true,
        opacity: 0.22,
        side: THREE.DoubleSide,
        depthWrite: false,
      }));
    n.position.set(side * 7.2, -2.2, 5.0);
    n.scale.set(6.4, 2.8, 0.3);
    n.rotation.set(0, 0, side * -0.45);
    n.visible = false;
    return n;
  }
  const bl = blurWing(-1), br = blurWing(1);
  root.add(bl);
  root.add(br);

  if (SHADOWS_ENABLED) {
    root.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    bl.castShadow = false;
    br.castShadow = false;
  }

  return { root, legs, foldedWings, blurWingL: bl, blurWingR: br, abdomen,
    elytraL: tegmina[0], elytraR: tegmina[1], wingFlightSpread: 0.8 };
}
