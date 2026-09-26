// DesktopRoach — DesktopFly's brain driving a procedural American-cockroach
// body. Same real FlyWire v783 escape-circuit LIF simulation (LC4/LPLC2
// looming detectors -> DNp01 giant fiber, DNa02 steering, MDN backward walk)
// and MaleCNS locomotor circuit; the fly / stag-beetle / cockroach bodies are
// interchangeable skins over one `FlyModel` contract (see RoachModel.swift).
//
// Forked from desktop-fly at 32b0001 (v1.1.0) + its local color customizations;
// that project is untouched.
//
// Build:  ./build.sh
// Run:    ./DesktopRoach                   (menu-bar 🪳; brain window shows live spikes)
//         ./DesktopRoach --snapshot out.png [--top] [--flying] [--beetle] [--roach]  (offscreen body)
//         ./DesktopRoach --brainshot out.png (offscreen brain window render)
//         ./DesktopRoach --simtest           (headless circuit test: spontaneous + loom)

import Cocoa
import SceneKit

// MARK: - Desktop overlay scene

func buildScene(bounds: CGSize) -> SCNScene {
    let scene = SCNScene()

    let camera = SCNCamera()
    camera.usesOrthographicProjection = true
    camera.orthographicScale = Double(bounds.height / 2)
    camera.zNear = 1
    camera.zFar = 600
    let camNode = SCNNode()
    camNode.name = "camera"
    camNode.camera = camera
    camNode.position = SCNVector3(0, 0, 300)
    scene.rootNode.addChildNode(camNode)

    let key = SCNLight()
    key.type = .directional
    key.intensity = 1000
    if SHADOWS_ENABLED {
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.30)
        key.shadowRadius = 6
        key.shadowSampleCount = 8
    }
    let keyNode = SCNNode()
    keyNode.name = "bodyKeyLight"
    keyNode.light = key
    keyNode.eulerAngles = SCNVector3(-0.35, BODY_FORM == .roach ? 0 : 0.30, 0)
    scene.rootNode.addChildNode(keyNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 550
    ambient.color = NSColor(calibratedWhite: 1.0, alpha: 1)
    let ambNode = SCNNode()
    ambNode.light = ambient
    scene.rootNode.addChildNode(ambNode)

    if SHADOWS_ENABLED {
        // fixed size: large enough for any display the fly may be moved to
        let plane = SCNPlane(width: 6000, height: 6000)
        let m = SCNMaterial()
        m.colorBufferWriteMask = []
        m.writesToDepthBuffer = true
        plane.materials = [m]
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, -0.6)
        scene.rootNode.addChildNode(planeNode)
    }

    return scene
}

// MARK: - Offscreen render modes

func offscreenRender(_ scene: SCNScene, camNode: SCNNode, size: CGSize, path: String) {
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = camNode
    let img = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    savePNG(img, to: path)
    print("snapshot written to \(path)")
}

/// `topDown: true` reproduces the desktop overlay's own view — orthographic,
/// straight down, same key light. That is the only view users actually see, so
/// it is the one to check body geometry against.
func runSnapshot(path: String, topDown: Bool = false, flying: Bool = false, walking: Bool = false,
                 brood: Bool = false, transparent: Bool = false) {
    let scene = SCNScene()
    if !transparent { scene.background.contents = NSColor(calibratedWhite: 0.94, alpha: 1) }
    let fly = Fly(at: .zero)
    fly.heading = .pi / 2
    if brood { fly.carryingDays = 0.5; fly.syncOotheca() }   // pose a carrying female
    if walking {
        guard let data = loadBrainData() else { fputs("missing/invalid brain data\n", stderr); exit(1) }
        let sim = LIFSim(circuit: data.circuit, spikeBus: nil, locomotorCircuit: data.locomotor)
        let builder = SignalBuilder()
        sim.stimulate(sim.fwd, strength: 0.15, durationMs: 3000)
        for frame in 0..<300 {
            sim.legFeedback = fly.legFeedback
            sim.step(frame % 3 == 2 ? 9 : 8)
            var signals = builder.make(sim, dt: SimulationClock.tick)
            signals.escape = false; signals.groomDrive = 0; signals.nervous = 0; signals.arousal = 0
            fly.update(dt: SimulationClock.tick, bounds: CGSize(width: 1400, height: 1400), mouse: nil, signals: signals)
        }
        fly.pos = .zero; fly.heading = .pi / 2
    }
    if flying {
        fly.state = .idle
        fly.startFlight(bounds: CGSize(width: 1400, height: 1400), effort: 0.9)
        for _ in 0..<40 where fly.state == .flying {
            fly.update(dt: 1.0 / 60, bounds: CGSize(width: 1400, height: 1400),
                       mouse: nil, signals: BrainSignals())
        }
        fly.pos = .zero
        fly.heading = .pi / 2
    }
    for (i, leg) in fly.model.legs.enumerated() where !walking {
        if BODY_FORM == .roach {
            leg.angle = [0.18, 0.18, -0.12, -0.12, 0.10, 0.10][i]
            leg.lift = [0.15, 0.15, 0, 0, 0.08, 0.08][i]
        } else {
            leg.angle = [0.25, -0.2, -0.22, 0.28, 0.2, -0.25][i]
            leg.lift = [0.35, 0, 0, 0.3, 0, 0.35][i]
        }
        leg.apply()
    }
    fly.syncNode()
    scene.rootNode.addChildNode(fly.node)
    let camera = SCNCamera()
    camera.fieldOfView = 42
    let camNode = SCNNode()
    camNode.camera = camera
    camNode.position = SCNVector3(30, -58, 42)
    let lookAt = SCNLookAtConstraint(target: fly.node)
    lookAt.isGimbalLockEnabled = true
    camNode.constraints = [lookAt]
    if topDown {
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 30
        camera.zNear = 1
        camera.zFar = 400
        camNode.constraints = nil
        camNode.position = SCNVector3(0, 0, 150)
        camNode.eulerAngles = SCNVector3(0, 0, 0)
    }
    scene.rootNode.addChildNode(camNode)
    let key = SCNLight(); key.type = .directional; key.intensity = 1100
    let keyNode = SCNNode(); keyNode.light = key
    let lightYaw: CGFloat = BODY_FORM == .roach ? 0 : (topDown ? 0.30 : 0.5)
    keyNode.eulerAngles = SCNVector3(topDown ? -0.35 : -0.9, lightYaw, 0)
    scene.rootNode.addChildNode(keyNode)
    let amb = SCNLight(); amb.type = .ambient; amb.intensity = 500
    let ambNode = SCNNode(); ambNode.light = amb
    scene.rootNode.addChildNode(ambNode)
    offscreenRender(scene, camNode: camNode, size: CGSize(width: 720, height: 720), path: path)
}

func runBrainshot(path: String) {
    guard let data = loadBrainData() else { fputs("no data/ — run etl.py first\n", stderr); exit(1) }
    let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
    let bs = buildBrainScene(points: data.points, sim: sim)
    bs.brainGroup.removeAllActions()
    bs.brainGroup.eulerAngles = SCNVector3(-0.15, 0.5, 0)
    // decorate with a burst of fake spikes so the preview shows the live look
    let driver = BrainRenderDriver(sim: sim, flashPool: bs.flashPool)
    for _ in 0..<40 { driver.flash(neuron: Int.random(in: 0..<sim.n), isGF: false) }
    if let gfIdx = sim.gf.first { driver.flash(neuron: gfIdx, isGF: true) }
    for node in bs.flashPool { node.removeAllActions() }   // freeze mid-flash
    offscreenRender(bs.scene, camNode: bs.cameraNode, size: CGSize(width: 720, height: 560), path: path)
}

func runSimtest() {
    let seed = TestRandom.reset()
    print("test RNG: desktop-fly-tests, seed 0x\(String(seed, radix: 16))")
    guard let data = loadBrainData() else { fputs("no data/ — run etl.py first\n", stderr); exit(1) }
    let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
    print("circuit: \(sim.n) neurons | loom L/R: \(sim.loomLeft.count)/\(sim.loomRight.count)"
          + " | GF: \(sim.gf.count) | DNa L/R: \(sim.dnaL.count)/\(sim.dnaR.count) | MDN: \(sim.mdn.count)"
          + " | DNp09: \(sim.fwd.count) | DNg11: \(sim.groom.count) | escW: \(sim.escw.count)"
          + " | ascend: \(sim.ascend.count) | sens: \(sim.sens.count)")

    // Phase 1: 4 s spontaneous activity
    var gfSpont = 0
    for _ in 0..<40 { sim.step(100); if sim.consumeGF() { gfSpont += 1 } }
    let popHz = Float(sim.totalSpikes) / 4.0 / Float(sim.n)
    print(String(format: "spontaneous 4s: pop %.2f Hz/neuron, LC %.1f Hz, DNa02 L/R %.1f/%.1f Hz, "
                 + "MDN %.1f Hz, GF spikes: %d", popHz, sim.rateLoom, sim.rateDNaL, sim.rateDNaR,
                 sim.rateMDN, gfSpont))

    // Phase 2: abrupt loom, as produced by a cursor lunge (step, not ramp)
    var gfLatencyMs = -1
    var gfLoom = 0
    for ms in 0..<400 {
        sim.loomL = 1.0
        sim.loomR = 0.5
        sim.step(1)
        if sim.consumeGF() {
            gfLoom += 1
            if gfLatencyMs < 0 { gfLatencyMs = ms }
        }
    }
    sim.loomL = 0; sim.loomR = 0
    print(String(format: "abrupt loom 0.4s: LC rate %.1f Hz, GF spikes %d, first at %d ms",
                 sim.rateLoom, gfLoom, gfLatencyMs))

    // Phase 3: 20 s with walking proprioception; do behavior states emerge?
    var walkOn = 0, groomOn = 0, samples = 0
    var fwdMin = Float.greatestFiniteMagnitude, fwdMax: Float = 0
    for ms in 0..<20_000 {
        sim.gaitDrive = 0.5
        sim.gaitPhase = Float(ms % 125) / 125    // 8 Hz gait
        sim.step(1)
        if ms % 10 == 0 {
            samples += 1
            if sim.rateFwd / 10 > 0.22 { walkOn += 1 }
            if sim.rateGroom / 8 > 0.5 { groomOn += 1 }
            fwdMin = min(fwdMin, sim.rateFwd); fwdMax = max(fwdMax, sim.rateFwd)
        }
    }
    print(String(format: "behavior 20s: walk-drive on %.0f%%, groom-drive on %.0f%%, "
                 + "DNp09 %.1f-%.1f Hz, pop %.1f Hz", 100 * Float(walkOn) / Float(samples),
                 100 * Float(groomOn) / Float(samples), fwdMin, fwdMax, sim.ratePop))

    // Phase 3b: midday siesta must slow the fly down, not paralyze it
    sim.activityScale = 1 - (1 - 0.55) * 0.35   // = 0.84, the compressed siesta scale
    var siestaWalkOn = 0, siestaSamples = 0
    for ms in 0..<15_000 {
        sim.step(1)
        if ms % 10 == 0 {
            siestaSamples += 1
            if sim.rateFwd / 10 > 0.22 { siestaWalkOn += 1 }
        }
    }
    sim.activityScale = 1
    let siestaPct = 100 * Float(siestaWalkOn) / Float(siestaSamples)
    print(String(format: "siesta 15s (scale 0.84): walk-drive on %.0f%%", siestaPct))

    // Phase 4: air puff (fast cursor whoosh) for 1 s — wind startle pathway
    var gfPuff = 0
    for _ in 0..<1000 {
        sim.airPuff = 1.0
        sim.step(1)
        if sim.consumeGF() { gfPuff += 1 }
    }
    sim.airPuff = 0
    print("air puff 1s: GF spikes \(gfPuff)")

    // Phase 5: gentle left-eye-only loom 1 s — steering response probe
    for _ in 0..<500 { sim.step(1); _ = sim.consumeGF() }   // settle
    let diff0 = sim.rateDNaL - sim.rateDNaR
    for _ in 0..<1000 {
        sim.loomL = 0.30; sim.loomR = 0
        sim.step(1)
        _ = sim.consumeGF()
    }
    let diff1 = sim.rateDNaL - sim.rateDNaR
    sim.loomL = 0
    print(String(format: "left-eye loom: DNa L-R rate diff %+.1f -> %+.1f Hz, LC %.1f Hz",
                 diff0, diff1, sim.rateLoom))

    // Phase 6: click-stimulation probes (what the interactive brain window does)
    sim.stimulate(sim.gf, strength: 0.5, durationMs: 40)
    sim.step(60)
    let gfStim = sim.consumeGF()
    sim.stimulate(sim.groom, strength: 0.25, durationMs: 400)
    sim.step(400)
    let groomStim = sim.rateGroom
    _ = sim.consumeGF()
    print(String(format: "click probes: GF cluster -> spike %@, DNg11 cluster -> groom rate %.0f Hz",
                 gfStim ? "yes" : "NO", groomStim))

    let pass = gfSpont == 0 && gfLoom > 0 && walkOn > 0 && gfStim && siestaPct > 3
    print(pass ? "PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive"
               : "FAIL: tune weights/noise")
    exit(pass ? 0 : 1)
}

// MARK: - Behavior test (headless sim -> 3D body end-to-end)

func runBehaviorTest() {
    print("test RNG: FNV-1a(test name), LCG32")
    guard let data = loadBrainData() else { fputs("no data/ — run etl.py first\n", stderr); exit(1) }
    let bounds = CGSize(width: 1512, height: 982)
    let dt: CGFloat = 1.0 / 60.0
    var failures = 0

    func scenario(_ name: String, stim: (LIFSim) -> Void, hold: CGFloat,
                  setup: ((Fly) -> Void)? = nil,
                  filterSignals: ((inout BrainSignals) -> Void)? = nil,
                  check: (Fly) -> Bool, describe: (Fly) -> String) {
        TestRandom.reset(name)
        let sim = LIFSim(circuit: data.circuit, spikeBus: nil)
        let builder = SignalBuilder()
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.speed = 0
        setup?(fly)
        // settle the network, drain any startup GF latch
        sim.step(400)
        _ = sim.consumeGF()
        stim(sim)
        var passed = false
        var frames = Int(hold / dt)
        while frames > 0 {
            frames -= 1
            sim.step(Int((dt * 1000).rounded()))
            var s = builder.make(sim, dt: dt)
            filterSignals?(&s)
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s)
            if check(fly) { passed = true; break }
        }
        if !passed { failures += 1 }
        print("\(passed ? "PASS" : "FAIL")  \(name): \(describe(fly))")
    }

    scenario("GF stim -> escape flight",
             stim: { $0.stimulate($0.gf, strength: 0.5, durationMs: 40) }, hold: 0.5,
             check: { $0.state == .flying },
             describe: { "state=\($0.state)" })

    scenario("DNg11 stim -> grooming",
             stim: { $0.stimulate($0.groom, strength: 0.25, durationMs: 600) }, hold: 1.5,
             check: { $0.state == .grooming },
             describe: { "state=\($0.state)" })

    scenario("DNp09 stim -> walks, speed rises (capped)",
             stim: { $0.stimulate($0.fwd, strength: 0.25, durationMs: 1200) }, hold: 1.5,
             // Background DNg11 can win the idle-state transition and consume
             // this stimulus window grooming. Isolate the forward response;
             // DNg11's independent grooming response is checked just above.
             filterSignals: { $0.groomDrive = 0 },
             check: { $0.state == .walking && $0.speed > 40 && $0.speed < 100 },
             describe: { "state=\($0.state) speed=\(Int($0.speed))" })

    scenario("MDN stim (from idle) -> backward walk",
             stim: { $0.stimulate($0.mdn, strength: 0.3, durationMs: 600) }, hold: 1.2,
             check: { $0.backwardTimer > 0 },
             describe: { "backwardTimer=\(String(format: "%.2f", $0.backwardTimer))" })

    var heading0: CGFloat = 0
    scenario("DNa-left stim -> left (CCW) turn while walking",
             stim: { $0.stimulate($0.dnaL, strength: 0.3, durationMs: 900) }, hold: 1.4,
             setup: { fly in
                 fly.state = .walking
                 fly.speed = 30
                 fly.heading = 0
                 heading0 = 0
             },
             check: { $0.heading - heading0 > 0.25 },
             describe: { "heading change \(String(format: "%+.2f", $0.heading - heading0)) rad" })

    scenario("moderate loom -> fear response (dart or escape)",
             stim: { sim in
                 sim.loomL = 0.45; sim.loomR = 0.45
             }, hold: 1.0,
             check: { ($0.state == .walking && $0.speed > 100) || $0.state == .flying },
             describe: { "state=\($0.state) speed=\(Int($0.speed))" })

    scenario("tap near fly -> startle escape via sensory pathway",
             stim: { $0.stimulate($0.sens, strength: 0.45, durationMs: 150) }, hold: 0.8,
             check: { $0.state == .flying },
             describe: { "state=\($0.state)" })

    // ---- body-level environment checks (hand-built signals, no sim) ----
    func bodyCheck(_ name: String, _ run: () -> (Bool, String)) {
        TestRandom.reset(name)
        let (ok, detail) = run()
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name): \(detail)")
    }
    var walkSignals = BrainSignals()
    walkSignals.walkDrive = 0.6

    bodyCheck("ledge attach + follow window edge") {
        let fly = Fly(at: CGPoint(x: 0, y: -55))
        fly.state = .walking; fly.speed = 30; fly.heading = 0
        fly.terrain = [Ledge(y: -40, x0: -300, x1: 300, id: 1)]
        for _ in 0..<240 {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: walkSignals)
            if fly.ledge != nil && abs(fly.pos.y + 40) < 8 { return (true, "attached, y=\(Int(fly.pos.y))") }
        }
        return (false, "state=\(fly.state) y=\(Int(fly.pos.y)) ledge=\(fly.ledge != nil)")
    }

    bodyCheck("window closes underfoot -> takeoff") {
        let fly = Fly(at: CGPoint(x: 0, y: -40))
        fly.state = .walking; fly.speed = 25; fly.heading = 0
        fly.terrain = [Ledge(y: -40, x0: -300, x1: 300, id: 1)]
        fly.ledge = fly.terrain[0]
        fly.terrain = []
        for _ in 0..<60 {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: walkSignals)
            if fly.state == .flying { return (true, "took off") }
        }
        return (false, "state=\(fly.state)")
    }

    bodyCheck("sleep signal -> sleeping; wake -> grooming") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        var s = BrainSignals(); s.sleep = true
        for _ in 0..<60 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s) }
        guard fly.state == .sleeping else { return (false, "no sleep: \(fly.state)") }
        s.sleep = false
        fly.update(dt: dt, bounds: bounds, mouse: nil, signals: s)
        return (fly.state == .grooming, "woke to \(fly.state)")
    }

    bodyCheck("thermal tempo scales walking speed") {
        let fly = Fly(at: .zero)
        fly.state = .walking; fly.speed = 20; fly.heading = 0
        var cool = walkSignals; cool.tempo = 1.0
        for _ in 0..<120 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: cool) }
        let coolSpeed = fly.speed
        var hot = walkSignals; hot.tempo = 1.5
        for _ in 0..<120 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: hot) }
        let hotSpeed = fly.speed
        return (fly.state == .walking && hotSpeed > coolSpeed + 10,
                "cool \(Int(coolSpeed)) -> hot \(Int(hotSpeed)) pt/s")
    }

    bodyCheck("flight: altitude drives scale; escape flies higher than casual") {
        func flight(escape: Bool, effort: CGFloat?) -> (alt: CGFloat, scale: CGFloat) {
            let fly = Fly(at: .zero)
            fly.state = .idle
            fly.startFlight(bounds: bounds, escape: escape, effort: effort)
            var maxAlt: CGFloat = 0, maxScale: CGFloat = 0
            var frames = 0
            while fly.state == .flying && frames < 400 {
                frames += 1
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
                maxAlt = max(maxAlt, fly.alt)
                maxScale = max(maxScale, fly.node.scale.x)
            }
            return (maxAlt, maxScale)
        }
        let esc = flight(escape: true, effort: nil)
        let casual = flight(escape: false, effort: 0.45)
        let ok = esc.alt > casual.alt + 0.15 && esc.scale > FLY_SCALE * 1.5
            && abs(esc.scale - FLY_SCALE * (1 + 0.8 * esc.alt)) < 0.15
        return (ok, String(format: "escape alt %.2f scale %.2f | casual alt %.2f scale %.2f",
                           esc.alt, esc.scale, casual.alt, casual.scale))
    }

    bodyCheck("flight: wings actually beat") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.startFlight(bounds: bounds, effort: 0.8)
        var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
        for _ in 0..<30 where fly.state == .flying {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
            let z = fly.model.foldedWings.childNodes[0].eulerAngles.z
            lo = min(lo, z); hi = max(hi, z)
        }
        return (hi - lo > 0.25, String(format: "wing sweep %.2f rad over 0.5 s", hi - lo))
    }

    bodyCheck("escape-DN activity mid-flight raises wing-beat effort") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.startFlight(bounds: bounds, effort: 0.5)
        let calm = BrainSignals()
        for _ in 0..<12 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: calm) }
        let calmEffort = fly.effortCurrent
        var hot = BrainSignals(); hot.wingDrive = 1.0; hot.arousal = 0.6
        for _ in 0..<12 where fly.state == .flying {
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: hot)
        }
        let hotEffort = fly.effortCurrent
        return (fly.state == .flying && hotEffort > calmEffort + 0.2,
                String(format: "effort %.2f -> %.2f", calmEffort, hotEffort))
    }

    bodyCheck("threat while grounded raises the wings (no takeoff)") {
        let fly = Fly(at: .zero)
        fly.state = .walking; fly.speed = 20
        fly.dartCooldown = 99   // isolate the posture from darting
        var threat = BrainSignals(); threat.wingDrive = 0.9; threat.walkDrive = 0.4
        for _ in 0..<40 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: threat) }
        let x = fly.model.foldedWings.childNodes[0].eulerAngles.x
        return (fly.state != .flying && fly.wingRaise > 0.6 && x < -0.2,
                String(format: "raise %.2f, wing tilt %.2f rad", fly.wingRaise, x))
    }

    bodyCheck("landing is smooth: no scale/height snap at touchdown") {
        let fly = Fly(at: .zero)
        fly.state = .idle
        fly.startFlight(bounds: bounds, escape: true)
        var prevScale = fly.node.scale.x, prevZ = fly.node.position.z
        var maxDS: CGFloat = 0, maxDZ: CGFloat = 0
        var post = 20, frames = 0
        var landed = false
        while post > 0 && frames < 600 {
            frames += 1
            fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
            maxDS = max(maxDS, abs(fly.node.scale.x - prevScale))
            maxDZ = max(maxDZ, abs(fly.node.position.z - prevZ))
            prevScale = fly.node.scale.x; prevZ = fly.node.position.z
            if fly.state != .flying { landed = true; post -= 1 }
        }
        return (landed && maxDS < 0.2 && maxDZ < 25,
                String(format: "landed=%@, max per-frame Δscale %.2f, Δz %.1f",
                       landed ? "yes" : "NO", maxDS, maxDZ))
    }

    bodyCheck("circadian curve: siesta + night dips, dawn/dusk peaks") {
        let night = circadianActivity(hour: 3), dawn = circadianActivity(hour: 9)
        let siesta = circadianActivity(hour: 14), dusk = circadianActivity(hour: 18)
        let ok = night < 0.4 && dawn > 0.9 && siesta < 0.7 && siesta > 0.3 && dusk > 0.9
        return (ok, String(format: "3h %.2f, 9h %.2f, 14h %.2f, 18h %.2f", night, dawn, siesta, dusk))
    }

    // Guards both halves of the frame-rate fix. Before it, the first check was off
    // by 27% at the 50 ms dt cap and the second differed by sqrt(2) between a
    // 60 Hz and a 120 Hz display.
    bodyCheck("body timestep is frame-rate independent") {
        // 0. at the rate the constants were tuned at, lag() must reproduce the old
        //    `min(1, k * dt)` value exactly, or this stops being a pure bug fix
        var exact60 = true
        for k in [0.05, 0.9, 3, 4, 6, 8, 9, 10] as [CGFloat] {
            exact60 = exact60 && abs(lag(k, 1 / TUNED_HZ) - k / TUNED_HZ) < 1e-12
        }
        // 1. a first-order lag must give the same result however it is subdivided
        var fine: CGFloat = 0, coarse: CGFloat = 0
        for _ in 0..<8 { fine += (1 - fine) * lag(10, 0.1 / 8) }
        coarse += (1 - coarse) * lag(10, 0.1)
        // 2. the heading random walk must have the same spread at any frame rate
        func spread(_ dt: CGFloat) -> CGFloat {
            var sum: CGFloat = 0
            for _ in 0..<4000 {
                var h: CGFloat = 0, t: CGFloat = 0
                while t < 2 { h += rnd(-1...1) * WANDER_JITTER * sqrt(dt); t += dt }
                sum += h * h
            }
            return sqrt(sum / 4000)
        }
        let s60 = spread(1.0 / 60), s120 = spread(1.0 / 120)
        let ok = exact60 && abs(fine - coarse) < 1e-6 && abs(s60 - s120) / s60 < 0.1
        return (ok, String(format: "60Hz exact=%@, lag 8x12.5ms %.6f vs 1x100ms %.6f, wander sd %.3f @60Hz vs %.3f @120Hz",
                           exact60 ? "yes" : "NO", fine, coarse, s60, s120))
    }

    // ---- body form: stag-beetle / roach geometry (behavior layer untouched) ----
    let defaultForm = BODY_FORM
    for form in [BodyForm.beetle, BodyForm.roach] {
        bodyCheck("[\(form.rawValue)] wing cases spread in flight and hold steady") {
            BODY_FORM = form
            let fly = Fly(at: .zero)
            guard let elytron = fly.model.elytraL, fly.model.elytraR != nil else {
                return (false, "\(form.rawValue) model exposes no wing cases")
            }
            fly.state = .idle
            for _ in 0..<20 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals()) }
            let closed = elytron.eulerAngles.z

            fly.startFlight(bounds: bounds, effort: 0.8)
            var open = closed, openDrive: CGFloat = 0
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            var sampled = 0, i = 0
            while i < 40 && fly.state == .flying {
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
                if i >= 20 && fly.state == .flying {      // past the open-up transient
                    open = elytron.eulerAngles.z
                    openDrive = fly.elytraOpen
                    lo = min(lo, open); hi = max(hi, open); sampled += 1
                }
                i += 1
            }
            // the elytra must sit at a steady open angle, NOT buzz with the 20 Hz wingbeat
            let jitter = sampled > 1 ? hi - lo : 999
            return (openDrive > 0.8 && abs(open - closed) > 0.3 && jitter < 0.05,
                    String(format: "closed %.2f -> open %.2f rad, drive %.2f, jitter %.3f",
                           closed, open, openDrive, jitter))
        }
    }

    bodyCheck("beetle: threat opens the elytra without takeoff") {
        BODY_FORM = .beetle
        var detail = "no attempt ran"
        // brainBehavior runs a 0.005/s spontaneous-takeoff lottery while walking,
        // which ends the window early ~0.3% of the time for reasons unrelated to
        // the posture. Retry rather than weaken the no-takeoff assertion: a real
        // regression that launches the fly on threat loses all three attempts.
        for _ in 0..<3 {
            let fly = Fly(at: .zero)
            guard let elytron = fly.model.elytraL else { return (false, "no elytra") }
            fly.state = .walking; fly.speed = 20
            fly.dartCooldown = 99   // isolate the posture from darting
            let closed = elytron.eulerAngles.z
            var threat = BrainSignals(); threat.wingDrive = 0.9; threat.walkDrive = 0.4
            var tookOff = false
            for _ in 0..<40 {
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: threat)
                if fly.state == .flying { tookOff = true; break }
            }
            detail = String(format: "open %.2f, elytron %.2f -> %.2f rad%@",
                            fly.elytraOpen, closed, elytron.eulerAngles.z,
                            tookOff ? " (spontaneous takeoff, retried)" : "")
            if !tookOff && fly.elytraOpen > 0.5
                && abs(elytron.eulerAngles.z - closed) > 0.2 { return (true, detail) }
        }
        return (false, detail)
    }

    bodyCheck("body swap keeps behavior state, position and the model contract") {
        BODY_FORM = .fly
        let fly = Fly(at: CGPoint(x: 40, y: -20))
        fly.state = .walking; fly.speed = 33; fly.heading = 1.2
        for _ in 0..<30 { fly.update(dt: dt, bounds: bounds, mouse: nil, signals: walkSignals) }
        let (st, sp, hd, p) = (fly.state, fly.speed, fly.heading, fly.pos)
        let flyHadElytra = fly.model.elytraL != nil
        let holder = SCNNode()
        holder.addChildNode(fly.node)
        let oldRoot = fly.node

        for target in [BodyForm.beetle, BodyForm.roach] {
            BODY_FORM = target
            fly.swapBody()

            let contract = fly.model.legs.count == 6
                && fly.model.foldedWings.childNodes.count == 2
                && fly.model.elytraL != nil && fly.model.elytraR != nil
            let kept = fly.state == st && fly.speed == sp && fly.heading == hd && fly.pos == p
            let reparented = fly.node !== oldRoot && oldRoot.parent == nil
                && fly.node.parent === holder
            if !(contract && kept && reparented && !flyHadElytra) {
                return (false, "\(target.rawValue): contract=\(contract) state kept=\(kept) "
                    + "reparented=\(reparented) fly form had elytra=\(flyHadElytra)")
            }
        }
        return (true, "beetle + roach swaps kept state, position and the contract")
    }

    bodyCheck("roach: threat opens the tegmina without takeoff") {
        BODY_FORM = .roach
        var detail = "no attempt ran"
        for _ in 0..<3 {
            let fly = Fly(at: .zero)
            guard let tegmen = fly.model.elytraL else { return (false, "no tegmina") }
            fly.state = .walking; fly.speed = 20
            fly.dartCooldown = 99
            let closed = tegmen.eulerAngles.z
            var threat = BrainSignals(); threat.wingDrive = 0.9; threat.walkDrive = 0.4
            var tookOff = false
            for _ in 0..<40 {
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: threat)
                if fly.state == .flying { tookOff = true; break }
            }
            detail = String(format: "open %.2f, tegmen %.2f -> %.2f rad%@",
                            fly.elytraOpen, closed, tegmen.eulerAngles.z,
                            tookOff ? " (spontaneous takeoff, retried)" : "")
            if !tookOff && fly.elytraOpen > 0.5
                && abs(tegmen.eulerAngles.z - closed) > 0.2 { return (true, detail) }
        }
        return (false, detail)
    }

    bodyCheck("body factory: 48 clones stay within a frame budget") {
        BODY_FORM = .roach
        let t0 = Date()
        var models: [FlyModel] = []
        for _ in 0..<48 { models.append(BodyFactory.instantiate(.roach)) }
        let ms = Date().timeIntervalSince(t0) * 1000
        let contract = models.allSatisfy { $0.legs.count == 6
            && $0.foldedWings.childNodes.count == 2 && $0.elytraL != nil }
        // the clones must share geometry: one master build, not 48
        return (ms < 150 && contract,
                String(format: "48 clones in %.0f ms, contract ok=%@", ms, contract ? "yes" : "NO"))
    }

    bodyCheck("size: explicit size scales the body; nymphs grow monotonically") {
        let small = Fly(at: .zero, size: 0.5, adultTarget: 1.0)
        let scaleOK = abs(small.node.scale.x - FLY_SCALE * 0.5) < 0.001
        var monotonic = true
        var last = small.sizeScale
        small.ageDays = 85                     // jump near adulthood
        for _ in 0..<20 {                      // a few ticks past maturity
            small.update(dt: 0.2, bounds: bounds, mouse: nil, signals: BrainSignals())
            if small.sizeScale < last - 1e-9 { monotonic = false }
            last = small.sizeScale
        }
        let grownOK = small.sizeScale > 0.93 && small.sizeScale <= 1.0 + 1e-6
        return (scaleOK && monotonic && grownOK,
                String(format: "scale0=%@ monotonic=%@ size %.3f at ~86d",
                       scaleOK ? "yes" : "NO", monotonic ? "yes" : "NO", small.sizeScale))
    }

    bodyCheck("breeding speed slider compresses the colony clock") {
        let f = Fly(at: .zero, size: 0.5, adultTarget: 1.0)
        let age0 = f.ageDays
        RoachBreeding.speedMultiplier = 100
        defer { RoachBreeding.speedMultiplier = 1 }   // other checks run at 1x
        for _ in 0..<60 {                             // 12 s real
            f.update(dt: 0.2, bounds: bounds, mouse: nil, signals: BrainSignals())
        }
        let gained = f.ageDays - age0                 // 12/(30/100) = 40 d at 100x
        return (gained > 20 && gained < 60,
                String(format: "age +%.1f d over 12 s real at 100x (expect ~40)", gained))
    }

    bodyCheck("breeding: ready adults court, carry, and plan a nymph brood") {
        let a = Fly(at: .zero), b = Fly(at: CGPoint(x: 20, y: 0))
        guard a.isAdult && b.isAdult else { return (false, "default roaches not adult") }
        guard a.tryFertilize(b) else { return (false, "ready pair refused to mate") }
        guard a.carryingDays >= 0 && a.carryingDays < RoachBreeding.oothecaDays,
              b.carryingDays < 0 else { return (false, "no ootheca on one roach") }
        guard !a.tryFertilize(b) else { return (false, "re-fertilized while carrying") }
        b.state = .sleeping
        let sleeper = Fly(at: .zero)
        guard !sleeper.tryFertilize(b) else { return (false, "mated with a sleeper") }
        a.carryingDays = RoachBreeding.oothecaDays + 1         // term exceeded
        let brood = RoachBrood.planHatch(from: a)
        let countOK = RoachBreeding.eggsRange.contains(brood.count)
        let sizeOK = brood.allSatisfy { RoachBreeding.nymphSize.contains($0.size)
            && $0.target > $0.size }
        a.hatchDone()
        return (countOK && sizeOK && a.carryingDays < 0,
                "n=\(brood.count) in \(RoachBreeding.eggsRange), sizes ok=\(sizeOK)")
    }

    for form in [BodyForm.fly, BodyForm.beetle, BodyForm.roach] {
        bodyCheck("[\(form.rawValue)] gait advances and the wings still beat") {
            BODY_FORM = form
            let fly = Fly(at: .zero)
            fly.state = .walking; fly.speed = 40
            let phase0 = fly.gaitPhasePublic
            // amplitude over the window, not a single frame: an alternating
            // tripod puts every leg through 0 at the same instant twice a cycle
            var swing: CGFloat = 0
            for _ in 0..<30 {
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: walkSignals)
                swing = max(swing, fly.model.legs.map { abs($0.angle) }.max() ?? 0)
            }
            let gaitMoved = fly.gaitPhasePublic != phase0
            let legsSwing = swing > 0.15

            fly.state = .idle
            fly.startFlight(bounds: bounds, effort: 0.8)
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            var i = 0
            while i < 30 && fly.state == .flying {
                fly.update(dt: dt, bounds: bounds, mouse: nil, signals: BrainSignals())
                let z = fly.model.foldedWings.childNodes[0].eulerAngles.z
                lo = min(lo, z); hi = max(hi, z)
                i += 1
            }
            return (gaitMoved && legsSwing && hi - lo > 0.25,
                    String(format: "gait moved=%@ leg swing %.2f rad, wing sweep %.2f rad",
                           gaitMoved ? "yes" : "NO", swing, hi - lo))
        }
    }
    BODY_FORM = defaultForm

    print(failures == 0 ? "ALL BEHAVIOR TESTS PASS" : "\(failures) FAILURES")
    exit(failures == 0 ? 0 : 1)
}

// MARK: - Signals

// Converts sim population rates into body commands. Shared by the app loop
// and --behaviortest so both exercise the identical mapping.
final class SignalBuilder {
    private var dnaBaseline: Float = 0

    func make(_ sim: LIFSim, dt: CGFloat) -> BrainSignals {
        let diff = sim.rateDNaL - sim.rateDNaR
        // Slow adaptation (tau ~8 s): the connectome's persistent left/right
        // wiring asymmetry is adapted out, so steady-state walking is straight
        // and only transient DNa asymmetries (visual, stimulation) steer.
        dnaBaseline += (diff - dnaBaseline) * Float(lag(1.0 / 8, dt))
        var s = BrainSignals()
        s.escape = sim.consumeGF()
        s.nervous = clampf(CGFloat(sim.rateLoom) / 80, 0, 1)
        s.turnBias = clampf(CGFloat(diff - dnaBaseline) * 0.04, -1.0, 1.0)
        s.backward = sim.rateMDN > 8
        s.walkDrive = clampf(CGFloat(sim.rateFwd) / 10, 0, 1.3)
        s.groomDrive = CGFloat(sim.rateGroom) / 8
        s.wingDrive = clampf(CGFloat(sim.rateEscW) / 10, 0, 1.3)
        s.arousal = clampf(CGFloat(sim.ratePop) / 20, 0, 1)
        s.legCommands = sim.locomotor?.commands
        return s
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, SCNSceneRendererDelegate {
    let scene: SCNScene
    var bounds: CGSize
    var flies: [Fly] = []
    var lastTime: TimeInterval?
    var mouseScene: CGPoint?
    private let lock = NSLock()
    private var pending: [(Coordinator) -> Void] = []

    /// Window-layer experiment: roach #1 (the brain carrier) lives on the
    /// floating overlay; the colony can live down in the regular window
    /// layers, where user windows cover and reveal them.
    enum WindowLayerMode {
        case topPetOnly       // default: #1 on the overlay, the rest in windows
        case petsInWindows    // every roach inside the window layers
        case alwaysOnTop      // the original floating-overlay behaviour
    }
    var layerMode: WindowLayerMode = .topPetOnly
    let underScene: SCNScene

    func sceneFor(_ index: Int) -> SCNScene {
        switch layerMode {
        case .alwaysOnTop: return scene
        case .topPetOnly: return index == 0 ? scene : underScene
        case .petsInWindows: return underScene
        }
    }

    func rehomeAll() {
        for (i, fly) in flies.enumerated() {
            let target = sceneFor(i).rootNode
            if fly.node.parent !== target {
                fly.node.removeFromParentNode()
                target.addChildNode(fly.node)
            }
        }
        // the roach key light follows the body form in both scenes
        let yaw: CGFloat = BODY_FORM == .roach ? 0 : 0.30
        for scn in [scene, underScene] {
            scn.rootNode.childNode(withName: "bodyKeyLight", recursively: false)?
                .eulerAngles = SCNVector3(-0.35, yaw, 0)
        }
    }

    func setLayerMode(_ mode: WindowLayerMode) {
        enqueue { c in
            guard c.layerMode != mode else { return }
            c.layerMode = mode
            c.rehomeAll()
        }
    }

    let sim: LIFSim?
    private let fpsLog = ProcessInfo.processInfo.environment["DESKTOPFLY_FPS"] != nil
    private var fpsFrames = 0
    private var fpsWindowStart: TimeInterval = 0
    private let signalBuilder = SignalBuilder()
    private var msAccumulator: Double = 0
    private let simulationClock = SimulationClock()
    private var prevMouse: CGPoint?
    private var mouseVel = CGPoint.zero
    private var mouseVelRaw = CGPoint.zero   // last measurement, held between samples
    private var mouseSampleDt: CGFloat = 0   // real time since that measurement
    private var loomOverride: CGFloat = 0

    /// Main-thread snapshot for the menu status row (flies mutate on the
    /// render thread; Int/CGFloat reads are torn-safe in practice, the pair
    /// scan runs on whatever last state was committed).
    func breedingStatus() -> (count: Int, nearest: CGFloat?, asleep: Int) {
        lock.lock(); defer { lock.unlock() }
        let n = flies.count
        var nearest: CGFloat? = nil
        var asleep = 0
        for i in 0..<n { for j in (i + 1)..<n {
            let dx = flies[i].pos.x - flies[j].pos.x, dy = flies[i].pos.y - flies[j].pos.y
            let d = (dx * dx + dy * dy).squareRoot()
            nearest = min(nearest ?? d, d)
        }}
        for f in flies where f.state == .sleeping { asleep += 1 }
        return (n, nearest, asleep)
    }

    // environment senses (written from main-thread timers, read in render loop)
    private var terrain: [Ledge] = []
    private var typingLevel: CGFloat = 0
    private var sleepy = false
    private var tempo: CGFloat = 1
    private var activity: Float = 1
    private var windowLoomL: Float = 0
    private var windowLoomR: Float = 0
    private(set) var lastFlyPos = CGPoint.zero

    init(bounds: CGSize, sim: LIFSim?, demoPair: Bool = false) {
        self.bounds = bounds
        self.sim = sim
        self.scene = buildScene(bounds: bounds)
        self.underScene = buildScene(bounds: bounds)
        super.init()
        enqueue { $0.addFlyNow() }
        if demoPair {
            // breeding demo: a ready companion beside roach #1 and a fast
            // colony clock, so the whole cycle plays out in about a minute
            enqueue { $0.addFlyNow(); $0.addFlyNow() }
            enqueue { _ in RoachBreeding.speedMultiplier = 20 }
        }
    }

    func enqueue(_ action: @escaping (Coordinator) -> Void) {
        lock.lock(); pending.append(action); lock.unlock()
    }

    private func addFlyNow() {
        // roach #1 carries the brain and keeps the canonical size; every roach
        // added later varies around it, as real colony members do
        let size: CGFloat = flies.isEmpty ? 1.0 : rnd(0.65...1.4)
        let pos: CGPoint
        if let anchor = flies.randomElement()?.pos {
            // land near an existing roach (straddling the courtship radius) —
            // screen-wide random placement meant a fresh pair never met
            let a = rnd(0...(2 * .pi)), r = rnd(40...75)
            let hw = bounds.width / 2 - 60, hh = bounds.height / 2 - 60
            pos = CGPoint(x: clampf(anchor.x + cos(a) * r, -hw, hw),
                          y: clampf(anchor.y + sin(a) * r, -hh, hh))
        } else {
            let hw = bounds.width / 2 - 100, hh = bounds.height / 2 - 100
            pos = CGPoint(x: rnd(-hw...hw), y: rnd(-hh...hh))
        }
        let fly = Fly(at: pos, size: size)
        sceneFor(flies.count).rootNode.addChildNode(fly.node)
        flies.append(fly)
    }

    func addFly() { enqueue { $0.addFlyNow() } }
    /// Colony breeding switch, toggled from the menu bar; on by default.
    var breedingOn = true
    func setBreeding(_ on: Bool) { enqueue { $0.breedingOn = on } }
    func setBreedingSpeed(_ v: CGFloat) {
        enqueue { _ in RoachBreeding.speedMultiplier = max(1, v) }
    }
    func setColonyCap(_ v: Int) {
        enqueue { _ in RoachBreeding.colonyCap = max(2, v) }
    }
    /// Debug/test lever: fertilize the closest ready pair regardless of the
    /// sleep gate (the circadian night puts every roach to sleep, which would
    /// otherwise block courtship for hours of real time).
    func forceMating() {
        enqueue { c in
            let ready = c.flies.filter { $0.isAdult && $0.carryingDays < 0 }
            guard ready.count >= 2 else { return }
            var best: (Int, Int, CGFloat)?
            for i in 0..<ready.count {
                for j in (i + 1)..<ready.count {
                    let dx = ready[i].pos.x - ready[j].pos.x, dy = ready[i].pos.y - ready[j].pos.y
                    let d = (dx * dx + dy * dy).squareRoot()
                    if best == nil || d < best!.2 { best = (i, j, d) }
                }
            }
            guard let (i, j, d) = best else { return }
            ready[i].carryingDays = 0
            ready[i].broodCooldownDays = RoachBreeding.intervalDays
            ready[j].broodCooldownDays = RoachBreeding.intervalDays * 0.5
            fputs("[breed] forced pair, dist \(Int(d))\n", stderr)
        }
    }
    /// Per-tick colony dynamics: hatch carried oothecae past their term, then
    /// let nearby ready adults court. Everything below RoachBreeding's cap.
    private var breedLogAccum: CGFloat = 0
    private func breedingTick(_ dt: CGFloat) {
        guard breedingOn else { return }
        breedLogAccum += dt
        if breedLogAccum >= 5 {
            breedLogAccum = 0
            var nearest: CGFloat?
            for i in 0..<flies.count { for j in (i + 1)..<flies.count {
                let dx = flies[i].pos.x - flies[j].pos.x, dy = flies[i].pos.y - flies[j].pos.y
                nearest = min(nearest ?? .greatestFiniteMagnitude, (dx * dx + dy * dy).squareRoot())
            }}
            let states = flies.map { String(describing: $0.state).replacingOccurrences(of: "DesktopRoach.Fly.State.", with: "") }.joined(separator: ",")
            fputs(String(format: "[breed] n=%d canMate=%d nearest=%.0f speed=%.0f states=[%@]\n",
                         flies.count, flies.filter(\.canMate).count,
                         nearest ?? -1, RoachBreeding.speedMultiplier, states), stderr)
        }
        var mothers: [Fly] = []
        for fly in flies where fly.carryingDays >= RoachBreeding.oothecaDays {
            mothers.append(fly)
        }
        for mother in mothers {
            for (p, size, target) in RoachBrood.planHatch(from: mother) {
                guard flies.count < RoachBreeding.colonyCap else { break }
                let nymph = Fly(at: p, size: size, adultTarget: target)
                sceneFor(flies.count).rootNode.addChildNode(nymph.node)
                flies.append(nymph)
            }
            fputs("[breed] hatched, colony now \(flies.count)\n", stderr)
            mother.hatchDone()
        }
        guard flies.count < RoachBreeding.colonyCap else { return }
        for i in flies.indices where flies[i].canMate {
            var mated = false
            for j in (i + 1)..<flies.count where flies[j].canMate {
                let dx = flies[i].pos.x - flies[j].pos.x, dy = flies[i].pos.y - flies[j].pos.y
                if dx * dx + dy * dy < RoachBreeding.pairDistance * RoachBreeding.pairDistance,
                   rnd(0...1) < min(1, RoachBreeding.chancePerSecond * RoachBreeding.speedMultiplier * dt),
                   flies[i].tryFertilize(flies[j]) {
                    mated = true
                    fputs("[breed] mated #\(i)-#\(j)\n", stderr)
                    break
                }
            }
            if mated { break }   // one courtship event per tick keeps the cadence readable
        }
    }
    func removeFly() {
        enqueue { c in
            guard c.flies.count > 1 else { return }   // fly #1 carries the brain
            c.flies.removeLast().node.removeFromParentNode()
        }
    }
    func scareAll() {
        enqueue { c in
            c.loomOverride = 0.6   // real stimulus into the real circuit for fly #1
            for fly in c.flies.dropFirst() where fly.state != .flying {
                fly.startFlight(bounds: c.bounds)
            }
        }
    }
    func escapeTest() { enqueue { $0.loomOverride = 0.6 } }
    func setBodyForm(_ form: BodyForm) {
        enqueue { c in
            guard BODY_FORM != form else { return }
            BODY_FORM = form
            for fly in c.flies { fly.swapBody() }
            let yaw: CGFloat = form == .roach ? 0 : 0.30
            for scn in [c.scene, c.underScene] {
                scn.rootNode.childNode(withName: "bodyKeyLight", recursively: false)?
                    .eulerAngles = SCNVector3(-0.35, yaw, 0)
            }
        }
    }
    func setMouse(_ p: CGPoint?) { lock.lock(); mouseScene = p; lock.unlock() }

    func setTerrain(_ ledges: [Ledge]) { enqueue { $0.terrain = ledges } }

    // the fly moved to a different display: new bounds + camera extent
    func retarget(size: CGSize) {
        enqueue { c in
            c.bounds = size
            c.terrain = []   // stale until the next window poll
            if let camNode = c.scene.rootNode.childNode(withName: "camera", recursively: false) {
                camNode.camera?.orthographicScale = Double(size.height / 2)
            }
            // keep flies inside the new display
            for fly in c.flies {
                fly.ledge = nil
                fly.pos.x = clampf(fly.pos.x, -size.width / 2 + 40, size.width / 2 - 40)
                fly.pos.y = clampf(fly.pos.y, -size.height / 2 + 40, size.height / 2 - 40)
            }
        }
    }
    func setAmbient(typing: CGFloat, sleepy: Bool, tempo: CGFloat, activity: Float) {
        enqueue { c in
            c.typingLevel = typing; c.sleepy = sleepy; c.tempo = tempo; c.activity = activity
        }
    }
    func flyPosition() -> CGPoint { lock.lock(); defer { lock.unlock() }; return lastFlyPos }

    // a window appeared near the fly: a real looming object
    func injectWindowLoom(strength: CGFloat, at p: CGPoint) {
        enqueue { c in
            guard let fly = c.flies.first else { return }
            let rel = CGPoint(x: p.x - fly.pos.x, y: p.y - fly.pos.y)
            let dist = max(1, hypot(rel.x, rel.y))
            let f = CGPoint(x: cos(fly.heading), y: sin(fly.heading))
            let crossZ = (f.x * rel.y - f.y * rel.x) / dist
            c.windowLoomL = max(c.windowLoomL, Float(strength * clampf(0.5 + 0.5 * crossZ, 0.12, 1)))
            c.windowLoomR = max(c.windowLoomR, Float(strength * clampf(0.5 - 0.5 * crossZ, 0.12, 1)))
        }
    }

    // a global mouse click: a tap on the fly's substrate -> sensory pathway
    func injectTap(at p: CGPoint) {
        enqueue { c in
            guard let sim = c.sim, let fly = c.flies.first else { return }
            let d = hypot(p.x - fly.pos.x, p.y - fly.pos.y)
            let strength = Float(clampf(1 - d / 520, 0, 1))
            if strength > 0.05 {
                sim.stimulate(sim.sens, strength: 0.15 + strength * 0.35, durationMs: 130)
            }
        }
    }

    // Cursor kinematics -> looming drive for each eye of fly #1 + air puff.
    // This is the sensory transduction step; everything downstream of the
    // LC4/LPLC2 population is the real connectome.
    private func computeLoom(fly: Fly, mouse: CGPoint?, dt: CGFloat) -> (l: Float, r: Float, puff: Float) {
        guard let m = mouse else { return (0, 0, 0) }
        if let pm = prevMouse, dt > 0 {
            // The cursor is sampled by a 30 Hz timer while this runs once per
            // rendered frame (up to 120), so most frames see the same position.
            // Dividing by the render dt turned one 30 Hz step into a spike whose
            // height scaled with refresh rate; measure over the real interval
            // between samples instead, and re-measure if the cursor goes quiet so
            // a stopped cursor decays to zero rather than holding its last speed.
            mouseSampleDt += dt
            if m != pm || mouseSampleDt >= 1.0 / 30 {
                mouseVelRaw = CGPoint(x: (m.x - pm.x) / mouseSampleDt,
                                      y: (m.y - pm.y) / mouseSampleDt)
                prevMouse = m
                mouseSampleDt = 0
            }
            // Smoothing runs every frame, frame-rate-corrected: 24/60 = the old
            // fixed per-frame 0.4, so 60 Hz is unchanged.
            let k = lag(24, dt)
            mouseVel.x += (mouseVelRaw.x - mouseVel.x) * k
            mouseVel.y += (mouseVelRaw.y - mouseVel.y) * k
        } else {
            prevMouse = m
            mouseSampleDt = 0
        }
        let rel = CGPoint(x: m.x - fly.pos.x, y: m.y - fly.pos.y)
        let dist = max(20, hypot(rel.x, rel.y))
        // radial approach speed (positive = cursor closing in)
        let approach = -(rel.x * mouseVel.x + rel.y * mouseVel.y) / dist
        // loom ~ rate of angular expansion, attenuated with distance
        var loom = clampf(approach / dist * 6, 0, 1) * clampf(1 - dist / 800, 0, 1)
        loom += clampf((130 - dist) / 130, 0, 1) * 0.5          // hovering close = big object
        loom = clampf(loom + loomOverride, 0, 1)
        // split between eyes by bearing relative to heading
        let f = CGPoint(x: cos(fly.heading), y: sin(fly.heading))
        let rd = CGPoint(x: rel.x / dist, y: rel.y / dist)
        let crossZ = f.x * rd.y - f.y * rd.x                     // >0: threat on the left
        let lw = clampf(0.5 + 0.5 * crossZ, 0.12, 1)
        let rw = clampf(0.5 - 0.5 * crossZ, 0.12, 1)
        let puff = clampf(hypot(mouseVel.x, mouseVel.y) / 1500, 0, 1) * clampf(1 - dist / 500, 0, 1)
        return (Float(loom * lw), Float(loom * rw), Float(puff))
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime t: TimeInterval) {
        if fpsLog {
            if fpsWindowStart == 0 { fpsWindowStart = t }
            fpsFrames += 1
            if t - fpsWindowStart >= 5 {
                fputs(String(format: "fps: %.1f\n", Double(fpsFrames) / (t - fpsWindowStart)), stderr)
                fpsFrames = 0
                fpsWindowStart = t
            }
        }
        lock.lock()
        let actions = pending; pending.removeAll()
        let mouse = mouseScene
        lock.unlock()
        for a in actions { a(self) }

        guard let last = lastTime else { lastTime = t; return }
        let dt = CGFloat(min(0.05, max(0, t - last)))
        lastTime = t

        simulationClock.advance(dt) { self.advanceSimulation(dt: $0, mouse: mouse) }
    }

    private func advanceSimulation(dt: CGFloat, mouse: CGPoint?) {
        var signals: BrainSignals? = nil
        if let sim = sim, let first = flies.first {
            let sensory = computeLoom(fly: first, mouse: mouse, dt: dt)
            let decayF = Float(exp(-4 * Double(dt)))
            windowLoomL *= decayF
            windowLoomR *= decayF
            sim.loomL = max(sensory.l, windowLoomL)
            sim.loomR = max(sensory.r, windowLoomR)
            sim.airPuff = max(sensory.puff, Float(typingLevel * 0.30))
            // body -> brain: leg proprioception from the current gait
            sim.gaitDrive = Float(first.walkingIntensity)
            sim.gaitPhase = Float(first.gaitPhasePublic)
            sim.legFeedback = first.legFeedback
            // circadian + sleep neuromodulation. Compressed: the LIF neurons sit
            // just below threshold, so a raw multiplier silences them entirely —
            // siesta should mean "less active", not comatose.
            sim.activityScale = (1 - (1 - activity) * 0.35) * (sleepy ? 0.75 : 1)
            sim.sensoryGate = sleepy ? 0.55 : 1
            loomOverride = max(0, loomOverride - dt * 1.2)   // override decays
            msAccumulator += Double(dt) * 1000
            let steps = min(50, Int(msAccumulator + 1e-6))
            msAccumulator -= Double(steps)
            sim.step(steps)

            var s = signalBuilder.make(sim, dt: dt)
            s.tempo = tempo
            s.sleep = sleepy
            signals = s
        }

        for (i, fly) in flies.enumerated() {
            fly.terrain = terrain
            fly.update(dt: dt, bounds: bounds, mouse: mouse, signals: i == 0 ? signals : nil)
        }
        breedingTick(dt)
        if let first = flies.first {
            lock.lock(); lastFlyPos = first.pos; lock.unlock()
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Titles are assigned ONLY when they actually change: rewriting an
        // item's title while the menu is open forces a relayout that can
        // re-enter this callback and stall the main thread (the frozen
        // slider). The status itself is precomputed on the 0.7 s timer.
        guard let s = lastBreedingStatus else { return }
        if let item = breedingItem, coordinator.breedingOn {
            let t = "Breeding: On (\(s.count) roaches)"
            if item.title != t { item.title = t }
            let status = s.nearest == nil ? "no pair yet"
                : String(format: "nearest pair %.0f pt (mate <%.0f) · %d asleep",
                         s.nearest!, RoachBreeding.pairDistance, s.asleep)
            if let st = breedingStatusItem, st.title != status { st.title = status }
        } else if let item = breedingItem {
            if item.title != "Breeding: Off" { item.title = "Breeding: Off" }
            if let st = breedingStatusItem, st.title != "colony paused" { st.title = "colony paused" }
        }
        // only offer the display hop when there is somewhere to hop to
        moveDisplayItem?.isHidden = NSScreen.screens.count < 2
    }

    var window: NSWindow!
    var scnView: SCNView!
    var underWindow: NSWindow!
    var underView: SCNView!
    var lastFrontWindowNumber: Int = -1
    var crawlDescendWork: DispatchWorkItem?
    var lastBreedingStatus: (count: Int, nearest: CGFloat?, asleep: Int)?
    var coordinator: Coordinator!
    var statusItem: NSStatusItem!
    var mouseTimer: Timer?
    var windowTimer: Timer?
    var clickMonitor: Any?
    let windowSense = WindowSense()
    var typingLevel: CGFloat = 0
    var paused = false
    var brainWC: BrainWindowController?
    var dataInfo = "no data — run etl.py"
    var screenFrame = NSRect.zero
    var moveDisplayItem: NSMenuItem?
    var brainFullscreenItem: NSMenuItem?
    var brainHintItem: NSMenuItem?
    var bodyItem: NSMenuItem?
    var breedingItem: NSMenuItem?
    var requestedBody: BodyForm = BODY_FORM

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { fatalError("no screen") }
        let frame = screen.frame
        screenFrame = frame

        var sim: LIFSim? = nil
        let spikeBus = SpikeBus()
        var brainPoints: BrainPointsFile? = nil
        if let data = loadBrainData() {
            sim = LIFSim(circuit: data.circuit, spikeBus: spikeBus, locomotorCircuit: data.locomotor)
            brainPoints = data.points
            dataInfo = "FlyWire v783 · \(data.points.points.count) somas · circuit \(data.circuit.neurons.count)n/\(data.circuit.edges.count)e"
                + " · MaleCNS \(data.locomotor.neurons.count)n/\(data.locomotor.edges.count)e"
        }

        coordinator = Coordinator(bounds: frame.size, sim: sim,
                                  demoPair: args.contains("--demo-pair"))

        window = NSWindow(contentRect: frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        scnView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        scnView.scene = coordinator.scene
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 120   // ProMotion; caps at display refresh
        if ProcessInfo.processInfo.environment["DESKTOPFLY_FPS"] != nil {
            fputs("display max fps: \(NSScreen.main?.maximumFramesPerSecond ?? 0)\n", stderr)
        }
        scnView.delegate = coordinator
        scnView.isPlaying = true
        window.contentView = scnView
        window.orderFrontRegardless()

        // the window-layer overlay: same clear click-through scene, but at
        // .normal level so user windows cover and reveal the colony
        underWindow = NSWindow(contentRect: frame, styleMask: [.borderless],
                               backing: .buffered, defer: false)
        underWindow.isOpaque = false
        underWindow.backgroundColor = .clear
        underWindow.hasShadow = false
        underWindow.level = .normal
        underWindow.ignoresMouseEvents = true
        underWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        underView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        underView.scene = coordinator.underScene
        underView.backgroundColor = .clear
        underView.antialiasingMode = .multisampling4X
        underView.preferredFramesPerSecond = 60
        underView.isPlaying = true
        underWindow.contentView = underView
        underWindow.orderFrontRegardless()

        if let sim = sim, let pts = brainPoints {
            let wc = BrainWindowController(points: pts, sim: sim, screen: screen)
            wc.onFullscreenChange = { [weak self] in self?.syncFullscreenItem() }
            // hidden until "Show/Hide Brain" — the spike wall is a lot on
            // first launch
            brainWC = wc
        }

        setupStatusItem()

        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            self.coordinator.setMouse(CGPoint(x: loc.x - self.screenFrame.midX,
                                              y: loc.y - self.screenFrame.midY))
            // typing = substrate vibration (when, never what)
            let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            self.typingLevel += ((keyIdle < 0.6 ? 1.0 : 0.0) - self.typingLevel) * 0.15
            // circadian hour + sleep from user idleness + thermal tempo
            let idle = userIdleSeconds()
            let now = Date()
            let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
            let h = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
            let sleepy = (idle > 600 && (h >= 22 || h < 6)) || idle > 1800
            self.coordinator.setAmbient(typing: self.typingLevel, sleepy: sleepy,
                                        tempo: thermalTempo(), activity: circadianActivity(hour: h))
        }

        // window terrain + new-window looms, ~1.4 Hz
        windowTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            lastBreedingStatus = coordinator.breedingStatus()
            pollFrontWindow()
            let snap = self.windowSense.poll(screen: self.screenFrame)
            self.coordinator.setTerrain(snap.ledges)
            let flyPos = self.coordinator.flyPosition()
            for nw in snap.newWindows {
                let d = hypot(nw.center.x - flyPos.x, nw.center.y - flyPos.y)
                let strength = clampf(1 - d / 480, 0, 1) * 0.75
                if strength > 0.08 {
                    self.coordinator.injectWindowLoom(strength: strength, at: nw.center)
                }
            }
        }

        // global mouse clicks = taps on the fly's substrate (mouse monitors are permission-free)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            self.coordinator.injectTap(at: CGPoint(x: loc.x - self.screenFrame.midX,
                                                   y: loc.y - self.screenFrame.midY))
        }

        // if the current display disappears, retreat to the main screen
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !NSScreen.screens.contains(where: { $0.frame == self.screenFrame }),
               let main = NSScreen.main {
                self.move(to: main)
            }
        }
    }

    func move(to screen: NSScreen) {
        screenFrame = screen.frame
        window.setFrame(screen.frame, display: true)
        scnView.frame = NSRect(origin: .zero, size: screen.frame.size)
        underWindow?.setFrame(screen.frame, display: true)
        underView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        coordinator.retarget(size: screen.frame.size)
        brainWC?.move(to: screen)
    }

    @objc func moveToNextDisplay() {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        let idx = screens.firstIndex(where: { $0.frame == screenFrame }) ?? 0
        move(to: screens[(idx + 1) % screens.count])
    }

    /// The frontmost regular (layer-0) window that is not ours. When it
    /// changes — the user clicked or switched to another window — the colony
    /// overlay crawls UP above all regular windows for two seconds (the pets
    /// wander across the newly revealed surface), then sinks back beneath
    /// them; the window actually in use stays on top of them.
    func pollFrontWindow() {
        guard coordinator.layerMode != .alwaysOnTop, let under = underWindow else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int ?? 0) == 0 else { continue }   // front-to-back order
            if (w[kCGWindowOwnerPID as String] as? Int ?? 0) == pid { continue }      // skip our own overlays
            let num = w[kCGWindowNumber as String] as? Int ?? -1
            if num != lastFrontWindowNumber {
                let first = lastFrontWindowNumber == -1
                lastFrontWindowNumber = num
                if !first { crawlOnFocusChange() }
            }
            break   // only the topmost non-self regular window matters
        }
    }

    func crawlOnFocusChange() {
        guard let under = underWindow else { return }
        crawlDescendWork?.cancel()
        under.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        under.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let under = self.underWindow else { return }
            under.level = .normal
            under.orderBack(nil)   // sink beneath every regular window again
        }
        crawlDescendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🪳"
        let menu = NSMenu()
        menu.addItem(withTitle: "Desktop Roach", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: dataInfo, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            it.target = self
            return it
        }
        menu.addItem(item("Pause", #selector(togglePause(_:)), "p"))
        menu.addItem(item("Show/Hide Brain", #selector(toggleBrain), "b"))
        let full = item("Fullscreen Brain", #selector(toggleBrainFullscreen), "f")
        menu.addItem(full)
        brainFullscreenItem = full
        let hint = item("Hide Brain Hint", #selector(toggleBrainHint), "h")
        menu.addItem(hint)
        brainHintItem = hint
        menu.addItem(item("Escape Test (loom)", #selector(escapeTest), "e"))
        let move = item("Move to Next Display", #selector(moveToNextDisplay), "d")
        menu.addItem(move)
        moveDisplayItem = move
        menu.delegate = self
        menu.addItem(item("Add Pet", #selector(addFly), "a"))
        menu.addItem(item("Remove Pet", #selector(removeFly), "r"))
        menu.addItem(item("Scare Pets", #selector(scareAll), "s"))
        let breeding = item("Breeding: On", #selector(toggleBreeding), "b")
        breedingItem = breeding
        menu.addItem(breeding)
        // sliders hosted inside the menu. Frame layout on purpose: menu item
        // views have no auto-layout pass, a stack view here collapsed to zero
        // height and the slider was invisible.
        let speedRow = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        let speedLabel = NSTextField(labelWithString: "Speed ×1")
        speedLabel.font = NSFont.menuFont(ofSize: 0)
        speedLabel.frame = NSRect(x: 14, y: 4, width: 112, height: 15)
        breedingSpeedLabel = speedLabel
        let speedSlider = NSSlider(value: 1, minValue: 1, maxValue: 100,
                                   target: self, action: #selector(breedingSpeedChanged(_:)))
        speedSlider.isContinuous = true
        speedSlider.frame = NSRect(x: 130, y: 3, width: 140, height: 18)
        speedRow.addSubview(speedLabel)
        speedRow.addSubview(speedSlider)
        let speedItem = NSMenuItem()
        speedItem.view = speedRow
        menu.addItem(speedItem)

        let capRow = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        let capLabel = NSTextField(labelWithString: "Colony cap: 48")
        capLabel.font = NSFont.menuFont(ofSize: 0)
        capLabel.frame = NSRect(x: 14, y: 4, width: 112, height: 15)
        colonyCapLabel = capLabel
        let capSlider = NSSlider(value: 48, minValue: 2, maxValue: 200,
                                 target: self, action: #selector(colonyCapChanged(_:)))
        capSlider.isContinuous = true
        capSlider.frame = NSRect(x: 130, y: 3, width: 140, height: 18)
        capRow.addSubview(capLabel)
        capRow.addSubview(capSlider)
        let capItem = NSMenuItem()
        capItem.view = capRow
        menu.addItem(capItem)
        // where the pets live: overlay vs window layers
        let layerMenu = NSMenu()
        layerMenu.addItem(withTitle: "Top Pet Only", action: #selector(layerTopPetOnly), keyEquivalent: "")
        layerMenu.addItem(withTitle: "Pets in Windows", action: #selector(layerPetsInWindows), keyEquivalent: "")
        layerMenu.addItem(withTitle: "All Always On Top", action: #selector(layerAlwaysOnTop), keyEquivalent: "")
        for it in layerMenu.items { it.target = self }
        layerMenu.items[0].state = NSControl.StateValue.on
        layerSubmenu = layerMenu
        let layerItem = NSMenuItem(title: "Window Layer", action: nil, keyEquivalent: "")
        layerItem.submenu = layerMenu
        menu.addItem(layerItem)
        let status = NSMenuItem(title: "no pair yet", action: nil, keyEquivalent: "")
        status.isEnabled = false
        breedingStatusItem = status
        menu.addItem(status)
        menu.addItem(item("Introduce Pair", #selector(forceMating), ""))
        let body = item("Body: Fruit Fly", #selector(toggleBody), "y")
        bodyItem = body
        menu.addItem(body)
        refreshBodyItem()
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        scnView.isPlaying = !paused
        coordinator.lastTime = nil
        sender.title = paused ? "Resume" : "Pause"
    }
    @objc func toggleBrain() {
        guard let wc = brainWC else { return }
        wc.isVisible ? wc.hide() : wc.show()
    }
    @objc func toggleBrainFullscreen() {
        guard let wc = brainWC else { return }
        wc.toggleFullscreen()
        syncFullscreenItem()
    }
    @objc func toggleBrainHint() {
        guard let wc = brainWC else { return }
        wc.toggleHint()
        brainHintItem?.title = wc.isHintVisible ? "Hide Brain Hint" : "Show Brain Hint"
    }
    func syncFullscreenItem() {
        guard let wc = brainWC else { return }
        brainFullscreenItem?.title = wc.isFullscreen ? "Exit Fullscreen Brain" : "Fullscreen Brain"
    }
    @objc func escapeTest() { coordinator.escapeTest() }
    @objc func forceMating() { coordinator.forceMating() }
    @objc func toggleBreeding() {
        coordinator.setBreeding(!coordinator.breedingOn)
        breedingItem?.title = "Breeding: \(coordinator.breedingOn ? "On" : "Off")"
    }
    var breedingSpeedLabel: NSTextField?
    var colonyCapLabel: NSTextField?
    var breedingStatusItem: NSMenuItem?
    var layerSubmenu: NSMenu?
    @objc func breedingSpeedChanged(_ sender: NSSlider) {
        let v = sender.doubleValue
        coordinator.setBreedingSpeed(CGFloat(v))
        breedingSpeedLabel?.stringValue = String(format: "Speed ×%.0f", v)
    }
    @objc func layerTopPetOnly() { setLayerMode(.topPetOnly) }
    @objc func layerPetsInWindows() { setLayerMode(.petsInWindows) }
    @objc func layerAlwaysOnTop() { setLayerMode(.alwaysOnTop) }
    private func setLayerMode(_ mode: Coordinator.WindowLayerMode) {
        coordinator.setLayerMode(mode)
        syncLayerMenu()
    }
    private func syncLayerMenu() {
        guard let layerMenu = layerSubmenu else { return }
        let states: [NSControl.StateValue] = [
            coordinator.layerMode == .topPetOnly ? .on : .off,
            coordinator.layerMode == .petsInWindows ? .on : .off,
            coordinator.layerMode == .alwaysOnTop ? .on : .off,
        ]
        for (i, it) in layerMenu.items.enumerated() { it.state = states[i] }
    }
    @objc func colonyCapChanged(_ sender: NSSlider) {
        let v = Int(sender.doubleValue)
        coordinator.setColonyCap(v)
        colonyCapLabel?.stringValue = "Colony cap: \(v)"
    }
    @objc func addFly() { coordinator.addFly() }
    @objc func removeFly() { coordinator.removeFly() }
    @objc func scareAll() { coordinator.scareAll() }
    @objc func toggleBody() {
        // BODY_FORM itself is only ever mutated on the render thread (see the
        // threading model); the menu tracks what it asked for, for the label.
        requestedBody = nextForm(requestedBody)
        coordinator.setBodyForm(requestedBody)
        refreshBodyItem()
    }
    private func refreshBodyItem() {
        // the item offers the NEXT form, so it reads as an action
        bodyItem?.title = "Body: " + bodyName(nextForm(requestedBody))
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot") {
    if args.contains("--beetle") { BODY_FORM = .beetle }
    if args.contains("--roach") { BODY_FORM = .roach }  // after --beetle, so --roach wins if both are given
    runSnapshot(path: args.count > i + 1 ? args[i + 1] : "preview.png",
                topDown: args.contains("--top"), flying: args.contains("--flying"),
                walking: args.contains("--walking"), brood: args.contains("--brood"),
                transparent: args.contains("--transparent"))
    exit(0)
}
if let i = args.firstIndex(of: "--brainshot") {
    runBrainshot(path: args.count > i + 1 ? args[i + 1] : "brain.png")
    exit(0)
}
if args.contains("--simtest") {
    runSimtest()
}
if args.contains("--behaviortest") {
    runBehaviorTest()
}
if args.contains("--locomotortest") {
    exit(runLocomotorTests() ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
