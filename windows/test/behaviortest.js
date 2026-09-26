// behaviortest.js — port of runBehaviorTest() from main.swift.
// 18 end-to-end sim -> body checks. MUST pass after any behavior change.
//   node test/behaviortest.js

import * as THREE from '../node_modules/three/build/three.module.js';
import { resetRandom } from './random.js';
import { loadBrainData } from '../src/data.js';
import { LIFSim, makeSignals } from '../src/sim.js';
import { SignalBuilder } from '../src/signals.js';
import { Fly, FLY_SCALE, WANDER_JITTER, warmBodyTemplates, BODY_FORM_CYCLE,
  setBodyForm, getBodyForm, nextForm, bodyName, RoachBreeding, RoachBrood,
  BodyFactory } from '../src/flymodel.js';
import { circadianActivity, makeLedge } from '../src/environment.js';
import { rnd, lag, TUNED_HZ } from '../src/util.js';

const data = loadBrainData();
if (!data) { process.stderr.write('no data/ — run etl.py first\n'); process.exit(1); }

// Build both body templates before the first seeded stream: three.js
// geometry constructors draw from Math.random, and a lazily built template
// would shift the streams by a form-dependent amount (see warmBodyTemplates).
warmBodyTemplates();

const bounds = { width: 1512, height: 982 };
const dt = 1 / 60;
let failures = 0;
const f = (x, d = 2) => x.toFixed(d);
const sign = (x, d = 2) => (x >= 0 ? '+' : '') + x.toFixed(d);

function scenario(name, { stim, hold, setup = null, isolateForward = false, check, describe }) {
  resetRandom(name);
  const sim = new LIFSim(data.circuit, null);
  const builder = new SignalBuilder();
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'idle';
  fly.speed = 0;
  if (setup) setup(fly);
  // settle the network, drain any startup GF latch
  sim.step(400);
  sim.consumeGF();
  stim(sim);
  let passed = false;
  let frames = Math.floor(hold / dt);
  while (frames > 0) {
    frames--;
    sim.step(Math.round(dt * 1000));
    const s = builder.make(sim, dt);
    // Isolate forward recruitment from a competing spontaneous grooming bout;
    // the separate DNg11 scenario still verifies the grooming pathway.
    if (isolateForward) s.groomDrive = 0;
    fly.update(dt, bounds, null, s);
    if (check(fly)) { passed = true; break; }
  }
  if (!passed) failures++;
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}: ${describe(fly)}`);
}

scenario('GF stim -> escape flight', {
  stim: (s) => s.stimulate(s.gf, 0.5, 40),
  hold: 0.5,
  check: (fly) => fly.state === 'flying',
  describe: (fly) => `state=${fly.state}`,
});

scenario('DNg11 stim -> grooming', {
  stim: (s) => s.stimulate(s.groom, 0.25, 600),
  hold: 1.5,
  check: (fly) => fly.state === 'grooming',
  describe: (fly) => `state=${fly.state}`,
});

scenario('DNp09 stim -> walks, speed rises (capped)', {
  isolateForward: true,
  stim: (s) => s.stimulate(s.fwd, 0.25, 1200),
  hold: 1.5,
  check: (fly) => fly.state === 'walking' && fly.speed > 40 && fly.speed < 100,
  describe: (fly) => `state=${fly.state} speed=${Math.trunc(fly.speed)}`,
});

scenario('MDN stim (from idle) -> backward walk', {
  stim: (s) => s.stimulate(s.mdn, 0.3, 600),
  hold: 1.2,
  check: (fly) => fly.backwardTimer > 0,
  describe: (fly) => `backwardTimer=${f(fly.backwardTimer)}`,
});

let heading0 = 0;
scenario('DNa-left stim -> left (CCW) turn while walking', {
  stim: (s) => s.stimulate(s.dnaL, 0.3, 900),
  hold: 1.4,
  setup: (fly) => {
    fly.state = 'walking';
    fly.speed = 30;
    fly.heading = 0;
    heading0 = 0;
  },
  check: (fly) => fly.heading - heading0 > 0.25,
  describe: (fly) => `heading change ${sign(fly.heading - heading0)} rad`,
});

scenario('moderate loom -> fear response (dart or escape)', {
  stim: (s) => { s.loomL = 0.45; s.loomR = 0.45; },
  hold: 1.0,
  check: (fly) => (fly.state === 'walking' && fly.speed > 100) || fly.state === 'flying',
  describe: (fly) => `state=${fly.state} speed=${Math.trunc(fly.speed)}`,
});

scenario('tap near fly -> startle escape via sensory pathway', {
  stim: (s) => s.stimulate(s.sens, 0.45, 150),
  hold: 0.8,
  check: (fly) => fly.state === 'flying',
  describe: (fly) => `state=${fly.state}`,
});

// ---- body-level environment checks (hand-built signals, no sim) ----
function bodyCheck(name, run) {
  resetRandom(name);
  const [ok, detail] = run();
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}: ${detail}`);
}

const walkSignals = makeSignals();
walkSignals.walkDrive = 0.6;

bodyCheck('ledge attach + follow window edge', () => {
  const fly = new Fly({ x: 0, y: -55 });
  fly.state = 'walking'; fly.speed = 30; fly.heading = 0;
  fly.terrain = [makeLedge(-40, -300, 300, 1)];
  for (let i = 0; i < 240; i++) {
    fly.update(dt, bounds, null, walkSignals);
    if (fly.ledge && Math.abs(fly.pos.y + 40) < 8) {
      return [true, `attached, y=${Math.trunc(fly.pos.y)}`];
    }
  }
  return [false, `state=${fly.state} y=${Math.trunc(fly.pos.y)} ledge=${!!fly.ledge}`];
});

bodyCheck('window closes underfoot -> takeoff', () => {
  const fly = new Fly({ x: 0, y: -40 });
  fly.state = 'walking'; fly.speed = 25; fly.heading = 0;
  fly.terrain = [makeLedge(-40, -300, 300, 1)];
  fly.ledge = fly.terrain[0];
  fly.terrain = [];
  for (let i = 0; i < 60; i++) {
    fly.update(dt, bounds, null, walkSignals);
    if (fly.state === 'flying') return [true, 'took off'];
  }
  return [false, `state=${fly.state}`];
});

bodyCheck('sleep signal -> sleeping; wake -> grooming', () => {
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'idle';
  const s = makeSignals(); s.sleep = true;
  for (let i = 0; i < 60; i++) fly.update(dt, bounds, null, s);
  if (fly.state !== 'sleeping') return [false, `no sleep: ${fly.state}`];
  s.sleep = false;
  fly.update(dt, bounds, null, s);
  return [fly.state === 'grooming', `woke to ${fly.state}`];
});

bodyCheck('thermal tempo scales walking speed', () => {
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'walking'; fly.speed = 20; fly.heading = 0;
  const cool = { ...walkSignals, tempo: 1.0 };
  for (let i = 0; i < 120; i++) fly.update(dt, bounds, null, cool);
  const coolSpeed = fly.speed;
  const hot = { ...walkSignals, tempo: 1.5 };
  for (let i = 0; i < 120; i++) fly.update(dt, bounds, null, hot);
  const hotSpeed = fly.speed;
  return [fly.state === 'walking' && hotSpeed > coolSpeed + 10,
          `cool ${Math.trunc(coolSpeed)} -> hot ${Math.trunc(hotSpeed)} pt/s`];
});

bodyCheck('flight: altitude drives scale; escape flies higher than casual', () => {
  function flight(escape, effort) {
    const fly = new Fly({ x: 0, y: 0 });
    fly.state = 'idle';
    fly.startFlight(bounds, { escape, effort });
    let maxAlt = 0, maxScale = 0;
    let frames = 0;
    while (fly.state === 'flying' && frames < 400) {
      frames++;
      fly.update(dt, bounds, null, makeSignals());
      maxAlt = Math.max(maxAlt, fly.alt);
      maxScale = Math.max(maxScale, fly.node.scale.x);
    }
    return { alt: maxAlt, scale: maxScale };
  }
  const esc = flight(true, null);
  const casual = flight(false, 0.45);
  const ok = esc.alt > casual.alt + 0.15 && esc.scale > FLY_SCALE * 1.5
    && Math.abs(esc.scale - FLY_SCALE * (1 + 0.8 * esc.alt)) < 0.15;
  return [ok, `escape alt ${f(esc.alt)} scale ${f(esc.scale)} | `
    + `casual alt ${f(casual.alt)} scale ${f(casual.scale)}`];
});

bodyCheck('flight: wings actually beat', () => {
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'idle';
  fly.startFlight(bounds, { effort: 0.8 });
  let lo = Infinity, hi = -Infinity;
  for (let i = 0; i < 30 && fly.state === 'flying'; i++) {
    fly.update(dt, bounds, null, makeSignals());
    const z = fly.model.foldedWings.children[0].rotation.z;
    lo = Math.min(lo, z); hi = Math.max(hi, z);
  }
  return [hi - lo > 0.25, `wing sweep ${f(hi - lo)} rad over 0.5 s`];
});

bodyCheck('escape-DN activity mid-flight raises wing-beat effort', () => {
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'idle';
  fly.startFlight(bounds, { effort: 0.5 });
  const calm = makeSignals();
  for (let i = 0; i < 12; i++) fly.update(dt, bounds, null, calm);
  const calmEffort = fly.effortCurrent;
  const hot = makeSignals(); hot.wingDrive = 1.0; hot.arousal = 0.6;
  for (let i = 0; i < 12 && fly.state === 'flying'; i++) fly.update(dt, bounds, null, hot);
  const hotEffort = fly.effortCurrent;
  return [fly.state === 'flying' && hotEffort > calmEffort + 0.2,
          `effort ${f(calmEffort)} -> ${f(hotEffort)}`];
});

bodyCheck('threat while grounded raises the wings (no takeoff)', () => {
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'walking'; fly.speed = 20;
  fly.dartCooldown = 99;   // isolate the posture from darting
  const threat = makeSignals(); threat.wingDrive = 0.9; threat.walkDrive = 0.4;
  for (let i = 0; i < 40; i++) fly.update(dt, bounds, null, threat);
  const x = fly.model.foldedWings.children[0].rotation.x;
  return [fly.state !== 'flying' && fly.wingRaise > 0.6 && x < -0.2,
          `raise ${f(fly.wingRaise)}, wing tilt ${f(x)} rad`];
});

bodyCheck('landing is smooth: no scale/height snap at touchdown', () => {
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'idle';
  fly.startFlight(bounds, { escape: true });
  let prevScale = fly.node.scale.x, prevZ = fly.node.position.z;
  let maxDS = 0, maxDZ = 0;
  let post = 20, frames = 0;
  let landed = false;
  while (post > 0 && frames < 600) {
    frames++;
    fly.update(dt, bounds, null, makeSignals());
    maxDS = Math.max(maxDS, Math.abs(fly.node.scale.x - prevScale));
    maxDZ = Math.max(maxDZ, Math.abs(fly.node.position.z - prevZ));
    prevScale = fly.node.scale.x; prevZ = fly.node.position.z;
    if (fly.state !== 'flying') { landed = true; post--; }
  }
  return [landed && maxDS < 0.2 && maxDZ < 25,
          `landed=${landed ? 'yes' : 'NO'}, max per-frame dScale ${f(maxDS)}, dz ${f(maxDZ, 1)}`];
});

// ---- body forms: roach geometry on the shared behavior layer ----
bodyCheck('wings beat and threat-raise under every body form', () => {
  const saved = getBodyForm();
  const detail = [];
  let ok = true;
  for (const form of BODY_FORM_CYCLE) {
    setBodyForm(form);
    resetRandom(`wings beat ${form}`);
    const flier = new Fly({ x: 0, y: 0 });
    flier.state = 'idle';
    flier.startFlight(bounds, { effort: 0.8 });
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < 30 && flier.state === 'flying'; i++) {
      flier.update(dt, bounds, null, makeSignals());
      const z = flier.model.foldedWings.children[0].rotation.z;
      lo = Math.min(lo, z); hi = Math.max(hi, z);
    }
    const beatOK = hi - lo > 0.25;
    const threat = new Fly({ x: 0, y: 0 });
    threat.state = 'walking'; threat.speed = 20;
    threat.dartCooldown = 99;
    const hot = makeSignals(); hot.wingDrive = 0.9; hot.walkDrive = 0.4;
    for (let i = 0; i < 40; i++) threat.update(dt, bounds, null, hot);
    const raiseOK = threat.state !== 'flying' && threat.wingRaise > 0.6
      && threat.model.foldedWings.children[0].rotation.x < -0.2;
    ok = ok && beatOK && raiseOK;
    detail.push(`${form}: beat ${f(beatOK ? hi - lo : 0)} raise ${f(threat.wingRaise)}`);
  }
  setBodyForm(saved);
  return [ok, detail.join(' | ')];
});

bodyCheck('[roach] tegmina spread in flight and hold a steady angle', () => {
  setBodyForm('roach');
  const fly = new Fly({ x: 0, y: 0 });
  fly.state = 'idle';
  for (let i = 0; i < 20; i++) fly.update(dt, bounds, null, makeSignals());
  if (!fly.model.elytraL || !fly.model.elytraR) return [false, 'no tegmina'];
  const closed = fly.model.elytraL.rotation.z;
  fly.startFlight(bounds, { effort: 0.8 });
  let open = closed, openDrive = 0;
  let lo = Infinity, hi = -Infinity, sampled = 0, i = 0;
  while (i < 40 && fly.state === 'flying') {
    fly.update(dt, bounds, null, makeSignals());
    if (i >= 20 && fly.state === 'flying') {      // past the open-up transient
      open = fly.model.elytraL.rotation.z;
      openDrive = fly.elytraOpen;
      lo = Math.min(lo, open); hi = Math.max(hi, open);
      sampled++;
    }
    i++;
  }
  // the tegmina must sit at a steady open angle, NOT buzz with the wingbeat
  const jitter = sampled > 1 ? hi - lo : 999;
  const ok = openDrive > 0.8 && Math.abs(open - closed) > 0.3 && jitter < 0.05;
  return [ok, `closed ${f(closed)} -> open ${f(open)} rad, drive ${f(openDrive)}, jitter ${f(jitter, 3)}`];
});

bodyCheck('[roach] threat opens the tegmina without takeoff', () => {
  setBodyForm('roach');
  let detail = 'no attempt ran';
  // brainBehavior runs a 0.005/s spontaneous-takeoff lottery while walking,
  // which ends the window early ~0.3% of the time for reasons unrelated to
  // the posture. Retry rather than weaken the no-takeoff assertion.
  for (let attempt = 0; attempt < 3; attempt++) {
    resetRandom(`roach threat ${attempt}`);
    const fly = new Fly({ x: 0, y: 0 });
    if (!fly.model.elytraL) return [false, 'no tegmina'];
    fly.state = 'walking'; fly.speed = 20;
    fly.dartCooldown = 99;
    const closed = fly.model.elytraL.rotation.z;
    const threat = makeSignals(); threat.wingDrive = 0.9; threat.walkDrive = 0.4;
    let tookOff = false;
    for (let i = 0; i < 40; i++) {
      fly.update(dt, bounds, null, threat);
      if (fly.state === 'flying') { tookOff = true; break; }
    }
    detail = `open ${f(fly.elytraOpen)}, tegmen ${f(closed)} -> ${f(fly.model.elytraL.rotation.z)} rad${tookOff ? ' (spontaneous takeoff, retried)' : ''}`;
    if (!tookOff && fly.elytraOpen > 0.5
      && Math.abs(fly.model.elytraL.rotation.z - closed) > 0.2) return [true, detail];
  }
  return [false, detail];
});

bodyCheck('body swap keeps behavior state, position and the model contract', () => {
  setBodyForm('fly');
  const fly = new Fly({ x: 40, y: -20 });
  fly.state = 'walking'; fly.speed = 33; fly.heading = 1.2;
  for (let i = 0; i < 30; i++) fly.update(dt, bounds, null, walkSignals);
  const st = fly.state, sp = fly.speed, hd = fly.heading, p = { ...fly.pos };
  const flyHadElytra = fly.model.elytraL !== null;
  const holder = new THREE.Object3D();
  holder.add(fly.node);
  const oldRoot = fly.node;

  for (const target of ['roach', 'fly']) {
    setBodyForm(target);
    fly.swapBody();
    const contract = fly.model.legs.length === 6
      && fly.model.foldedWings.children.length === 2
      && (target === 'roach') === (fly.model.elytraL !== null)
      && (target === 'roach') === (fly.model.elytraR !== null);
    const kept = fly.state === st && fly.speed === sp && fly.heading === hd
      && fly.pos.x === p.x && fly.pos.y === p.y;
    const reparented = fly.node !== oldRoot && !oldRoot.parent
      && fly.node.parent === holder;
    if (!(contract && kept && reparented && !flyHadElytra)) {
      return [false, `${target}: contract=${contract} state kept=${kept} `
        + `reparented=${reparented} fly form had elytra=${flyHadElytra}`];
    }
  }
  return [true, 'roach + fly swaps kept state, position and the contract'];
});

bodyCheck('body factory: 48 clones stay within a frame budget and share geometry', () => {
  setBodyForm('roach');
  const t0 = Date.now();
  const models = [];
  for (let i = 0; i < 48; i++) models.push(BodyFactory.instantiate('roach'));
  const ms = Date.now() - t0;
  const contract = models.every((m) => m.legs.length === 6
    && m.foldedWings.children.length === 2 && m.elytraL !== null);
  // the clones must share geometry: one master build, not 48
  const meshOf = (m) => m.legs[0].root.children.find((c) => c.isMesh);
  const shared = meshOf(models[0]).geometry === meshOf(models[47]).geometry;
  const blurPrivate = models[0].blurWingL.material !== models[1].blurWingL.material;
  return [ms < 150 && contract && shared && blurPrivate,
    `48 clones in ${ms} ms, contract ok=${contract ? 'yes' : 'NO'}, `
    + `geometry shared=${shared ? 'yes' : 'NO'}, blur material private=${blurPrivate ? 'yes' : 'NO'}`];
});

bodyCheck('size: explicit size scales the body; nymphs grow monotonically', () => {
  setBodyForm('roach');
  const small = new Fly({ x: 0, y: 0 }, 0.5, 1.0);
  const scaleOK = Math.abs(small.node.scale.x - FLY_SCALE * 0.5) < 0.001;
  let monotonic = true;
  let last = small.sizeScale;
  small.ageDays = 85;                    // jump near adulthood
  for (let i = 0; i < 20; i++) {         // a few ticks past maturity
    small.update(dt, bounds, null, makeSignals());
    if (small.sizeScale < last - 1e-9) monotonic = false;
    last = small.sizeScale;
  }
  const grownOK = small.sizeScale > 0.93 && small.sizeScale <= 1.0 + 1e-6;
  return [scaleOK && monotonic && grownOK,
    `scale0=${scaleOK ? 'yes' : 'NO'} monotonic=${monotonic ? 'yes' : 'NO'} size ${f(small.sizeScale, 3)} at ~86d`];
});

bodyCheck('breeding speed slider compresses the colony clock', () => {
  const savedSpeed = RoachBreeding.speedMultiplier;
  RoachBreeding.speedMultiplier = 100;
  const getterOK = Math.abs(RoachBreeding.daySecondsNow - 0.3) < 1e-9;
  // 12 s of real time must age a roach ~40 simulated days (the Swift suite
  // runs the same probe), so a lost multiplier inside update() cannot hide
  const roach = new Fly({ x: 0, y: 0 });
  roach.state = 'idle';
  const age0 = roach.ageDays;
  for (let i = 0; i < 60; i++) roach.update(0.2, bounds, null, makeSignals());
  const aged = roach.ageDays - age0;
  RoachBreeding.speedMultiplier = savedSpeed;   // other checks run at 1x
  const ok = getterOK && aged > 20 && aged < 60;
  return [ok, `100x -> day ${f(RoachBreeding.daySecondsNow, 2)} s, aged ${f(aged, 1)} sim-days in 12 s`];
});

bodyCheck('breeding: ready adults court, carry, and plan a nymph brood', () => {
  setBodyForm('roach');
  const a = new Fly({ x: 0, y: 0 });
  const b = new Fly({ x: 20, y: 0 });
  if (!a.tryFertilize(b)) return [false, 'ready pair refused to mate'];
  // the mother is drawn randomly between the two partners
  const mother = a.carryingDays >= 0 ? a : b;
  const partner = mother === a ? b : a;
  if (!(mother.carryingDays >= 0 && mother.carryingDays < RoachBreeding.oothecaDays)) {
    return [false, 'no ootheca started on the mother'];
  }
  if (partner.carryingDays >= 0) return [false, 'both partners started a brood'];
  if (!(partner.broodCooldownDays > 0 && mother.broodCooldownDays > 0)) {
    return [false, 'cooldowns not set after courtship'];
  }
  if (mother.tryFertilize(partner)) return [false, 're-fertilized while carrying'];
  const sleeper = new Fly({ x: -20, y: 0 });
  sleeper.state = 'sleeping';
  if (sleeper.tryFertilize(partner)) return [false, 'mated with a sleeper'];
  const cooling = new Fly({ x: -40, y: 0 });
  cooling.broodCooldownDays = 1;   // awake, adult, but resting between broods
  if (cooling.canMate) return [false, 'cooldown does not gate canMate'];
  if (cooling.tryFertilize(partner)) return [false, 'mated while cooling down'];
  mother.carryingDays = RoachBreeding.oothecaDays + 1;    // term exceeded
  const brood = RoachBrood.planHatch(mother);
  const countOK = brood.length >= RoachBreeding.eggsRange[0]
    && brood.length <= RoachBreeding.eggsRange[1];
  const sizeOK = brood.every((n) => n.size >= RoachBreeding.nymphSize[0]
    && n.size <= RoachBreeding.nymphSize[1]
    && n.target >= RoachBreeding.adultSize[0] && n.target <= RoachBreeding.adultSize[1]);
  mother.hatchDone();
  const formOK = nextForm('roach') === 'fly' && nextForm('fly') === 'roach'
    && bodyName('roach') === 'Cockroach';
  return [countOK && sizeOK && mother.carryingDays < 0 && formOK,
    `n=${brood.length} in [${RoachBreeding.eggsRange}], sizes ok=${sizeOK ? 'yes' : 'NO'}, form cycle ok=${formOK ? 'yes' : 'NO'}`];
});

bodyCheck('form cycle: swap restores the identical geometry contract each round', () => {
  const fly = new Fly({ x: 0, y: 0 });
  // carrying a brood across swaps: the case must reattach to every new root
  fly.carryingDays = 0.5;
  fly.syncOotheca();
  for (const target of ['fly', 'roach', 'fly', 'roach']) {
    setBodyForm(target);
    fly.swapBody();
    const contract = fly.model.legs.length === 6
      && fly.model.foldedWings.children.length === 2
      && (target === 'roach') === (fly.model.elytraL !== null);
    if (!contract) return [false, `${target}: contract broken`];
  }
  const attached = fly.carryingDays >= 0 && fly.ootheca
    && fly.ootheca.parent === fly.model.root && fly.ootheca.visible;
  fly.hatchDone();
  return [attached && fly.ootheca === null,
    `ootheca reattached through swaps=${attached ? 'yes' : 'NO'}`];
});

bodyCheck('circadian curve: siesta + night dips, dawn/dusk peaks', () => {
  const night = circadianActivity(3), dawn = circadianActivity(9);
  const siesta = circadianActivity(14), dusk = circadianActivity(18);
  const ok = night < 0.4 && dawn > 0.9 && siesta < 0.7 && siesta > 0.3 && dusk > 0.9;
  return [ok, `3h ${f(night)}, 9h ${f(dawn)}, 14h ${f(siesta)}, 18h ${f(dusk)}`];
});

// Guards both halves of the frame-rate fix (mirrors the Swift suite). Before
// it, the first check was off by 27% at the 50 ms dt cap and the second
// differed by sqrt(2) between a 60 Hz and a 120 Hz display.
bodyCheck('body timestep is frame-rate independent', () => {
  // 0. at the rate the constants were tuned at, lag() must reproduce the old
  //    `Math.min(1, k * dt)` value exactly, or this stops being a pure bug fix
  let exact60 = true;
  for (const k of [0.05, 0.9, 3, 4, 6, 8, 9, 10]) {
    exact60 = exact60 && Math.abs(lag(k, 1 / TUNED_HZ) - k / TUNED_HZ) < 1e-12;
  }
  // 1. a first-order lag must give the same result however it is subdivided
  let fine = 0, coarse = 0;
  for (let i = 0; i < 8; i++) fine += (1 - fine) * lag(10, 0.1 / 8);
  coarse += (1 - coarse) * lag(10, 0.1);
  // 2. the heading random walk must have the same spread at any frame rate
  function spread(sdt) {
    let sum = 0;
    for (let i = 0; i < 4000; i++) {
      let h = 0, t = 0;
      while (t < 2) { h += rnd(-1, 1) * WANDER_JITTER * Math.sqrt(sdt); t += sdt; }
      sum += h * h;
    }
    return Math.sqrt(sum / 4000);
  }
  const s60 = spread(1 / 60), s120 = spread(1 / 120);
  const ok = exact60 && Math.abs(fine - coarse) < 1e-6 && Math.abs(s60 - s120) / s60 < 0.1;
  return [ok, `60Hz exact=${exact60 ? 'yes' : 'NO'}, lag 8x12.5ms ${fine.toFixed(6)} `
    + `vs 1x100ms ${coarse.toFixed(6)}, wander sd ${s60.toFixed(3)} @60Hz vs ${s120.toFixed(3)} @120Hz`];
});

console.log(failures === 0 ? 'ALL BEHAVIOR TESTS PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
