// snapshot-scene.js — builds a small stage, mounts one posed body and hands
// the first rendered frame to the offscreen painter. Pose stepping follows
// the macOS snapshot poser in main.swift's runSnapshot().

import * as THREE from '../node_modules/three/build/three.module.js';
import { Fly, setBodyForm, SHADOWS_ENABLED } from '../src/flymodel.js';
import { makeSignals } from '../src/sim.js';

window.onerror = (msg) => { console.error('[scene] error:', msg); };

{
const params = new URLSearchParams(location.search);
const form = params.get('form') || 'roach';
const pose = params.get('pose') || 'idle';
const topDown = params.get('top') === '1';
const W = window.innerWidth, H = window.innerHeight;

setBodyForm(form);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x202830);

// Same light rig as the live overlay (SceneKit directional (-0.35, yaw, 0)
// equivalent), so the render predicts what users on the desktop see.
// keyLightPositionFor: the opposite-side placement of main.swift's
// (-0.35, yaw, 0) aim — yaw 0 for the roach, 0.30 for the other forms.
const KEY_POSITIONS = {
  roach: { x: 0, y: 0.3429 * 900, z: 0.9394 * 900 },
  fly: { x: 0.2955 * 900, y: 0.3276 * 900, z: 0.8974 * 900 },
};
const key = new THREE.DirectionalLight(0xffffff, 1.5);
key.position.set(KEY_POSITIONS[form].x, KEY_POSITIONS[form].y, KEY_POSITIONS[form].z);
key.target.position.set(0, 0, 0);
scene.add(key.target);
if (SHADOWS_ENABLED) {
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.radius = 3;
  key.shadow.bias = -0.0008;
  const c = key.shadow.camera;
  c.left = -140; c.right = 140; c.top = 140; c.bottom = -140;
  c.near = 1; c.far = 2200;
  c.updateProjectionMatrix();
}
scene.add(key);
scene.add(new THREE.AmbientLight(0xffffff, 0.82));

const stage = new THREE.Mesh(new THREE.PlaneGeometry(900, 900),
  new THREE.MeshPhongMaterial({ color: 0x2c3640 }));
stage.position.z = -0.6;
stage.receiveShadow = true;
scene.add(stage);

const bounds = { width: 1512, height: 982 };
const fly = new Fly({ x: 0, y: 0 });
scene.add(fly.node);
fly.state = 'idle';
fly.speed = 0;
if (pose === 'carry') {
  fly.carryingDays = 0.5;          // pose a carrying female
  fly.syncOotheca();
}

// 3/4 stage view, or the top-down orthographic desktop view.
const camera = topDown
  ? new THREE.OrthographicCamera(-60, 60, 60, -60, 1, 900)
  : new THREE.OrthographicCamera(-55, 55, 55, -55, 1, 900);
if (topDown) {
  camera.position.set(0, 0, 400);
} else {
  camera.position.set(120, -105, 150);
  camera.up.set(0, 0, 1);
}
camera.lookAt(0, -3, 6);
scene.add(camera);

// preserveDrawingBuffer keeps the canvas readable for toDataURL after render
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(W, H);
renderer.outputColorSpace = THREE.SRGBColorSpace;
if (SHADOWS_ENABLED) {
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
}
document.body.appendChild(renderer.domElement);

// let the pose settle like the desktop render loop would
const walkSignals = makeSignals();
walkSignals.walkDrive = 0.6;
const frames = pose === 'flying' ? 12 : (pose === 'walking' ? 40 : 4);
if (pose === 'flying') fly.startFlight(bounds, { effort: 0.8 });
for (let i = 0; i < frames; i++) {
  fly.update(1 / 60, bounds, null, pose === 'walking' ? walkSignals : null);
}
if (pose === 'flying') fly.land();

// Keep presenting frames: the offscreen painter only emits paints while the
// compositor has fresh content, and the main process captures one a few
// frames after ready. The posed body is static, so every frame is identical.
console.error('[scene] topDown=', topDown, 'cam pos=', JSON.stringify(camera.position),
  'fly pos=', JSON.stringify(fly.node.position), 'fly scale=', fly.node.scale.x);
console.error('[scene] rendering');
// --hide=12,34 / --only=12,34 isolate meshes (mesh index = traversal order,
// listed with --flat); --flat renders every mesh unlit to separate vertex-
// color questions from lighting questions.
const hideSet = new Set((params.get('hide') || '').split(',').filter(Boolean).map(Number));
const onlySet = new Set((params.get('only') || '').split(',').filter(Boolean).map(Number));
if (onlySet.size || hideSet.size) {
  let mi = 0;
  fly.node.traverse((o) => {
    if (o.isMesh) {
      if (onlySet.size && !onlySet.has(mi)) o.visible = false;
      else if (hideSet.has(mi)) o.visible = false;
      mi++;
    }
  });
}
if (params.get('flat') === '1') {
  // unlit pass: vertex colors as-is, no lights, no specular
  fly.node.traverse((o) => {
    if (o.isMesh) o.material = new THREE.MeshBasicMaterial({
      vertexColors: !!o.geometry.getAttribute('color'),
      color: o.geometry.getAttribute('color') ? 0xffffff : 0x888888,
      side: THREE.DoubleSide });
  });
}

renderer.render(scene, camera);
console.error('[scene] draw:', JSON.stringify(renderer.info.render),
  'scene children:', scene.children.length,
  'fly mesh count:', (() => { let n = 0; fly.node.traverse((o) => { if (o.isMesh) n++; }); return n; })(),
  'fly visible:', fly.node.visible, 'fly in scene:', !!fly.node.parent);
window.snapshotAPI.ready(renderer.domElement.toDataURL('image/png'));
(function loop() {
  renderer.render(scene, camera);
  requestAnimationFrame(loop);
})();
}
