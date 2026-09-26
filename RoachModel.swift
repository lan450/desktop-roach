// Procedural cockroach body. +Y forward, +Z up; the desktop sees the dorsal
// silhouette. All detail is attached to the existing FlyModel animation pivots.
import Cocoa
import SceneKit

// Palette keyed to the reference photo: deep red-brown/black carapace with
// amber kept for local accents only (pronotum flank band, humeral patch,
// abdominal tail bands) — the earlier all-over sand tone read as a beetle.
private let tegminaRed = NSColor(calibratedRed: 0.27, green: 0.095, blue: 0.038, alpha: 1)
private let bodyDark = NSColor(calibratedRed: 0.13, green: 0.05, blue: 0.026, alpha: 1)
private let rimTan = NSColor(calibratedRed: 0.64, green: 0.42, blue: 0.19, alpha: 1)
private let veinDark = NSColor(calibratedRed: 0.16, green: 0.06, blue: 0.026, alpha: 1)
private let femurRed = NSColor(calibratedRed: 0.38, green: 0.12, blue: 0.045, alpha: 1)
private let tibiaDark = NSColor(calibratedRed: 0.17, green: 0.07, blue: 0.035, alpha: 1)
private let wingBlack = NSColor(calibratedRed: 0.046, green: 0.023, blue: 0.019, alpha: 1)
private let pronotumBlack = NSColor(calibratedRed: 0.065, green: 0.055, blue: 0.052, alpha: 1)
private let edgeCopper = NSColor(calibratedRed: 0.74, green: 0.23, blue: 0.055, alpha: 1)

private func mixed(_ a: NSColor, _ b: NSColor, _ amount: CGFloat) -> NSColor {
    a.blended(withFraction: min(1, max(0, amount)), of: b) ?? a
}

/// Curved shells and fine appendages are batched into meshes rather than a
/// separate SceneKit node for every vein, flagellomere or tibial spine.
private struct RoachMesh {
    var vertices: [SCNVector3] = []
    var colors: [Float] = []
    var indices: [UInt32] = []

    @discardableResult
    mutating func vertex(_ p: SCNVector3, _ color: NSColor) -> UInt32 {
        let index = UInt32(vertices.count)
        vertices.append(p)
        let c = color.usingColorSpace(.deviceRGB) ?? color
        // SceneKit reads .color sources as linear; calibrated components are
        // sRGB-ish, so convert or every tone renders one gamma stop too light.
        func linear(_ v: CGFloat) -> Float {
            v <= 0.04045 ? Float(v / 12.92) : Float(pow((v + 0.055) / 1.055, 2.4))
        }
        colors.append(contentsOf: [linear(c.redComponent), linear(c.greenComponent),
                                   linear(c.blueComponent), Float(c.alphaComponent)])
        return index
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32, flip: Bool = false) {
        indices.append(contentsOf: flip ? [a, c, b] : [a, b, c])
    }

    mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, flip: Bool = false) {
        triangle(a, b, c, flip: flip)
        triangle(a, c, d, flip: flip)
    }

    mutating func tube(_ points: [SCNVector3], radii: [CGFloat], color: NSColor,
                       sides: Int = 6, ringContrast: CGFloat = 0) {
        guard points.count >= 2, points.count == radii.count else { return }
        let start = UInt32(vertices.count)
        func vector(_ p: SCNVector3) -> SIMD3<Float> {
            SIMD3(Float(p.x), Float(p.y), Float(p.z))
        }
        for i in points.indices {
            let p = vector(points[i])
            let tangent = simd_normalize(vector(points[min(i + 1, points.count - 1)])
                                        - vector(points[max(0, i - 1)]))
            let reference = abs(tangent.z) > 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, 1)
            let across = simd_normalize(simd_cross(tangent, reference))
            let up = simd_cross(tangent, across)
            let tint = mixed(color, bodyDark, i % 3 == 0 ? ringContrast : 0)
            for j in 0..<sides {
                let angle = Float(j) * 2 * .pi / Float(sides)
                let v = p + Float(radii[i]) * (cos(angle) * across + sin(angle) * up)
                vertex(SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)), tint)
            }
        }
        for i in 0..<(points.count - 1) {
            for j in 0..<sides {
                let a = start + UInt32(i * sides + j)
                let b = start + UInt32(i * sides + (j + 1) % sides)
                quad(a, b, b + UInt32(sides), a + UInt32(sides))
            }
        }
        let first = vertex(points[0], color)
        let last = vertex(points[points.count - 1], color)
        let end = start + UInt32((points.count - 1) * sides)
        for j in 0..<sides {
            triangle(first, start + UInt32((j + 1) % sides), start + UInt32(j))
            triangle(last, end + UInt32(j), end + UInt32((j + 1) % sides))
        }
    }

    func geometry(specular: CGFloat = 0.3, shininess: CGFloat = 0.45) -> SCNGeometry {
        var normals = Array(repeating: SIMD3<Float>(repeating: 0), count: vertices.count)
        func v(_ i: UInt32) -> SIMD3<Float> {
            let p = vertices[Int(i)]
            return SIMD3(Float(p.x), Float(p.y), Float(p.z))
        }
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = indices[i], b = indices[i + 1], c = indices[i + 2]
            let normal = simd_cross(v(b) - v(a), v(c) - v(a))
            normals[Int(a)] += normal; normals[Int(b)] += normal; normals[Int(c)] += normal
        }
        let normalSource = SCNGeometrySource(normals: normals.map {
            let n = simd_length_squared($0) > 1e-12 ? simd_normalize($0) : SIMD3<Float>(0, 0, 1)
            return SCNVector3(CGFloat(n.x), CGFloat(n.y), CGFloat(n.z))
        })
        let colorSource = SCNGeometrySource(data: colors.withUnsafeBytes { Data($0) },
            semantic: .color, vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: 4 * MemoryLayout<Float>.size)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), normalSource, colorSource],
                                   elements: [element])
        let material = mat(.white, specular: specular, shininess: shininess)
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }
}

private func ellipsoid(_ radii: SCNVector3, at position: SCNVector3,
                       color: NSColor, specular: CGFloat = 0.35) -> SCNNode {
    let sphere = SCNSphere(radius: 1)
    sphere.segmentCount = 24
    sphere.materials = [mat(color, specular: specular, shininess: 0.55)]
    let node = SCNNode(geometry: sphere)
    node.position = position
    node.scale = radii
    return node
}

/// A thin, bowed tegmen. The inner edge follows the dorsal seam; the rounded
/// tip ends off-centre so the pair does not form a beetle-like pointed shield.
private func tegmenPoint(side: CGFloat, t: CGFloat, u: CGFloat) -> SCNVector3 {
    let inner: CGFloat = 0
    let width = 3.8 * pow(max(0, 1 - pow(t, 4)), 1.05)
              + 1.0 * sin(.pi * t) * pow(1 - t, 0.35)
    let crown = 0.52 * sin(.pi * u) * sin(.pi * (0.12 + 0.88 * t))
    return SCNVector3(side * (inner + width * u), -20.5 * t,
                      0.15 - 0.18 * t + crown)
}

private func tegmenShape(side: CGFloat) -> SCNGeometry {
    var mesh = RoachMesh()
    let rows = 40, columns = 14
    let layerSize = (rows + 1) * (columns + 1)
    for layer in 0...1 {
        for i in 0...rows {
            let t = CGFloat(i) / CGFloat(rows)
            for j in 0...columns {
                let u = CGFloat(j) / CGFloat(columns)
                var point = tegmenPoint(side: side, t: t, u: u)
                if layer == 1 { point.z -= 0.12 }
                // The photograph is nearly black down the centre, with amber
                // confined to the humeral shoulder, side edges and rounded tip.
                let shoulder = exp(-pow((t - 0.115) / 0.16, 2))
                    * smoothstep((u - 0.68) / 0.23)
                let edge = smoothstep((u - 0.79) / 0.20)
                let tail = smoothstep((t - 0.77) / 0.21)
                let striae = 0.026 * sin(125 * u + 6 * t) * sin(36 * t)
                var color = mixed(wingBlack, tegminaRed, 0.13 + 0.16 * u + 0.10 * t + striae)
                color = mixed(color, rimTan, 0.70 * shoulder)
                color = mixed(color, edgeCopper,
                              (0.65 * edge * (0.55 + 0.45 * t)
                               + 0.82 * tail * (0.52 + 0.48 * u)))
                if layer == 1 { color = mixed(color, bodyDark, 0.4) }
                mesh.vertex(point, color)
            }
        }
    }
    for layer in 0...1 {
        for i in 0..<rows {
            for j in 0..<columns {
                let a = UInt32(layer * layerSize + i * (columns + 1) + j)
                mesh.quad(a, a + UInt32(columns + 1), a + UInt32(columns + 2), a + 1,
                          flip: (side < 0) != (layer == 1))
            }
        }
    }
    // Close the thin rim; top and bottom remain separate surfaces.
    var perimeter: [UInt32] = []
    for j in 0...columns { perimeter.append(UInt32(j)) }
    for i in 1...rows { perimeter.append(UInt32(i * (columns + 1) + columns)) }
    for j in stride(from: columns - 1, through: 0, by: -1) { perimeter.append(UInt32(rows * (columns + 1) + j)) }
    for i in stride(from: rows - 1, through: 1, by: -1) { perimeter.append(UInt32(i * (columns + 1))) }
    for i in perimeter.indices {
        let a = perimeter[i], b = perimeter[(i + 1) % perimeter.count]
        mesh.quad(a, b, b + UInt32(layerSize), a + UInt32(layerSize), flip: side < 0)
    }
    return mesh.geometry(specular: 0.56, shininess: 0.78)
}

private func buildVeins(side: CGFloat) -> SCNNode {
    var mesh = RoachMesh()
    func trace(t0: CGFloat, t1: CGFloat, u0: CGFloat, u1: CGFloat, radius: CGFloat) {
        var points: [SCNVector3] = []
        var radii: [CGFloat] = []
        for i in 0...22 {
            let f = CGFloat(i) / 22
            let t = t0 + (t1 - t0) * f
            let u = u0 + (u1 - u0) * (f * (2 - f))
            var p = tegmenPoint(side: side, t: t, u: u)
            p.z += radius * 0.65
            points.append(p)
            radii.append(radius * (1 - 0.60 * f))
        }
        mesh.tube(points, radii: radii, color: mixed(veinDark, tegminaRed, 0.35))
    }
    for i in 0..<8 {
        let u = 0.12 + CGFloat(i) * 0.105
        trace(t0: 0.045, t1: 0.91 - CGFloat(i) * 0.018,
              u0: 0.07 + CGFloat(i) * 0.048, u1: u,
              radius: i == 0 ? 0.017 : 0.011)
    }
    for i in 0..<10 {
        let t = 0.19 + CGFloat(i) * 0.071
        trace(t0: t, t1: min(0.91, t + 0.11), u0: 0.51, u1: 0.91, radius: 0.008)
    }
    return SCNNode(geometry: mesh.geometry(specular: 0.12, shininess: 0.24))
}

/// Folded hindwings fit within the forewing silhouette. Their existing pivots
/// still spread and beat in flight; nothing decorative becomes a third wing.
private func hindwingShape(side: CGFloat) -> SCNGeometry {
    let p = NSBezierPath()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: side * x, y: y) }
    p.move(to: point(0, 0))
    p.curve(to: point(2.3, -8.0), controlPoint1: point(1.7, -1.8), controlPoint2: point(2.6, -5.0))
    p.curve(to: point(0.6, -16.5), controlPoint1: point(2.4, -12.4), controlPoint2: point(1.8, -15.8))
    p.curve(to: point(-1.4, -12.0), controlPoint1: point(-0.4, -17.1), controlPoint2: point(-1.4, -15.5))
    p.curve(to: point(0, 0), controlPoint1: point(-2.0, -6.0), controlPoint2: point(-1.0, -1.5))
    p.close()
    p.transform(using: AffineTransform(rotationByRadians: -side * 0.13))
    p.flatness = 0.05
    let shape = SCNShape(path: p, extrusionDepth: 0.045)
    let material = mat(NSColor(calibratedRed: 0.43, green: 0.30, blue: 0.16, alpha: 0.34),
                       specular: 0.28, shininess: 0.55)
    material.isDoubleSided = true
    material.writesToDepthBuffer = false
    shape.materials = [material]
    return shape
}

/// Hood-shaped pronotum: a narrower curved front, projecting rear shoulders
/// and a gently flattened back edge over the tegmen hinges.
private func pronotumShape() -> SCNGeometry {
    var mesh = RoachMesh()
    let rings = 26, segments = 112
    // Around the hood from its front tip. Explicit rear corners and
    // three nearly level rear points give it a shield outline, not an ellipse.
    let outline: [(CGFloat, CGFloat)] = [
        (0, 4.15), (-1.85, 3.83), (-3.25, 2.80), (-4.18, 1.05),
        (-4.62, -1.30), (-4.55, -2.62), (-3.55, -3.48), (0, -3.50),
        (3.55, -3.48), (4.55, -2.62), (4.62, -1.30), (4.18, 1.05),
        (3.25, 2.80), (1.85, 3.83)
    ]
    func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat,
                     _ t: CGFloat) -> CGFloat {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * b) + (-a + c) * t
                      + (2 * a - 5 * b + 4 * c - d) * t2
                      + (-a + 3 * b - 3 * c + d) * t3)
    }
    func contour(_ j: Int) -> (CGFloat, CGFloat) {
        let location = CGFloat(j) * CGFloat(outline.count) / CGFloat(segments)
        let index = Int(location) % outline.count
        let t = location - CGFloat(Int(location))
        let a = outline[(index - 1 + outline.count) % outline.count]
        let b = outline[index]
        let c = outline[(index + 1) % outline.count]
        let d = outline[(index + 2) % outline.count]
        return (interpolate(a.0, b.0, c.0, d.0, t),
                interpolate(a.1, b.1, c.1, d.1, t))
    }
    for i in 0...rings {
        let r = CGFloat(i) / CGFloat(rings)
        for j in 0...segments {
            let (cx, cy) = contour(j)
            let x = r * cx, y = r * cy
            let nx = x / 4.62, ny = y / 4.15
            let z = 0.44 * (1 - r * r) - 0.07 * pow(r, 12)
            let edge = smoothstep((r - 0.76) / 0.18)
            let flanks = smoothstep((abs(nx) - 0.43) / 0.33)
            let warmEdge = edge * (0.02 + 0.62 * flanks)
            // The photo's ochre patches are broad and broken near the rear,
            // not a continuous high-contrast outline around the whole shield.
            let pairedAmber = exp(-pow((abs(nx) - 0.56) / 0.21, 2)
                                  - pow((ny + 0.54) / 0.26, 2)) * 0.88
            let ink = exp(-pow((abs(nx) - 0.28) / 0.24, 2)
                          - pow((ny - 0.14) / 0.52, 2)) * 0.62
            let rearDivide = exp(-pow(nx / 0.25, 2)
                                 - pow((ny + 0.72) / 0.33, 2)) * 0.94
            var color = mixed(pronotumBlack, tegminaRed, 0.24)
            color = mixed(color, rimTan, max(warmEdge, pairedAmber))
            color = mixed(color, pronotumBlack, max(ink, rearDivide))
            color = mixed(color, bodyDark, 0.55 * smoothstep((r - 0.97) / 0.03))
            mesh.vertex(SCNVector3(x, y, z), color)
        }
    }
    for i in 0..<rings {
        for j in 0..<segments {
            let a = UInt32(i * (segments + 1) + j)
            mesh.quad(a, a + UInt32(segments + 1), a + UInt32(segments + 2), a + 1)
        }
    }
    let bottom = mesh.vertex(SCNVector3(0, 0, -0.30), bodyDark)
    for j in 0..<segments {
        let a = UInt32(rings * (segments + 1) + j)
        mesh.triangle(bottom, a + 1, a)
    }
    return mesh.geometry(specular: 0.34, shininess: 0.82)
}

private func buildAntenna(side: CGFloat) -> SCNNode {
    var mesh = RoachMesh()
    var points: [SCNVector3] = []
    var radii: [CGFloat] = []
    // Both whips use the same curve mirrored across the body centreline.
    for i in 0...64 {
        let t = CGFloat(i) / 64
        let x = side * (17.5 * t + 0.6 * sin(.pi * t))
        let y = 11.5 * t + 1.4 * sin(.pi * t)
        points.append(SCNVector3(x, y, 0.7 * sin(.pi * t) - 0.28 * t))
        let radius = 0.115 * pow(1 - t, 0.8) + 0.012
        radii.append(radius * (i % 3 == 0 ? 0.91 : 1))
    }
    let copper = NSColor(calibratedRed: 0.64, green: 0.23, blue: 0.09, alpha: 1)
    mesh.tube(points, radii: radii, color: copper, sides: 7, ringContrast: 0.10)
    let root = SCNNode(geometry: mesh.geometry(specular: 0.26, shininess: 0.4))
    root.position = SCNVector3(side * 1.25, 8.25, 3.85)
    root.addChildNode(ellipsoid(SCNVector3(0.25, 0.42, 0.23),
                                at: SCNVector3(0, 0.1, 0), color: bodyDark))
    return root
}

private func buildCercus(side: CGFloat) -> SCNNode {
    var mesh = RoachMesh()
    var points: [SCNVector3] = []
    var radii: [CGFloat] = []
    for i in 0...14 {
        let t = CGFloat(i) / 14
        points.append(SCNVector3(side * (0.65 * t + 0.30 * t * t), -2.65 * t, -0.65 * t))
        radii.append((0.25 * (1 - t) + 0.025) * (i % 2 == 0 ? 1 : 0.85))
    }
    mesh.tube(points, radii: radii, color: mixed(bodyDark, rimTan, 0.18), ringContrast: 0.3)
    let node = SCNNode(geometry: mesh.geometry())
    node.position = SCNVector3(side * 2.1, -14.0, 3.1)
    return node
}

private func buildAbdomen() -> SCNNode {
    let pivot = SCNNode()
    pivot.position = SCNVector3(0, -6.5, 3.25)
    // The controller overwrites this scale to breathe. All anatomical shaping
    // is below the pivot, so the segmented abdomen survives those writes.
    pivot.scale = SCNVector3(0.9, 1.5, 0.75)
    pivot.addChildNode(ellipsoid(SCNVector3(5.45, 5.65, 0.95), at: SCNVector3(0, 0, -0.12), color: bodyDark))
    var mesh = RoachMesh()
    let rows = 4, columns = 24
    for plate in 0..<8 {
        let first = UInt32(mesh.vertices.count)
        for i in 0...rows {
            let f = CGFloat(i) / CGFloat(rows)
            let y = 5.4 - CGFloat(plate) * 1.36 - f * 1.30
            let width = 5.55 * sqrt(max(0.015, 1 - pow(y / 5.9, 2)))
            for j in 0...columns {
                let a = -.pi / 2 + CGFloat(j) * .pi / CGFloat(columns)
                let x = width * sin(a)
                let z = 1.08 * cos(a) + 0.08 * sin(.pi * f)
                let edge = pow(abs(sin(a)), 8)
                let tail: CGFloat = plate >= 6 ? 0.12 : 0
                var color = mixed(tegminaRed, rimTan, 0.13 + edge * 0.34 + tail)
                color = mixed(color, bodyDark, 0.20 + 0.30 * pow(f, 9) - tail * 0.25)
                mesh.vertex(SCNVector3(x, y, z), color)
            }
        }
        for i in 0..<rows {
            for j in 0..<columns {
                let a = first + UInt32(i * (columns + 1) + j)
                mesh.quad(a, a + UInt32(columns + 1), a + UInt32(columns + 2), a + 1)
            }
        }
    }
    pivot.addChildNode(SCNNode(geometry: mesh.geometry(specular: 0.28)))
    return pivot
}

/// Replace only the visible limb surfaces. The original pivots, segment
/// lengths, motor feedback and toe endpoint remain the shared Leg's contract.
/// The visible shafts take opposite bows on each side of the knee. Their ends
/// still meet the original animated pivots, keeping toe feedback unchanged.
private func detailLeg(_ leg: Leg, femur: CGFloat, tibia: CGFloat, tarsus: CGFloat) {
    for joint in [leg.root, leg.knee, leg.ankle] {
        for child in joint.childNodes where child.geometry != nil { child.removeFromParentNode() }
    }
    var thigh = RoachMesh()
    let frontThickness: CGFloat = leg.isFront ? 0.64 : 1
    // The visible knee is offset sideways from the mechanical pivot. Its
    // local x/z stay zero under the knee's y-axis rotation, so the femur tip
    // and tibia root meet through every motor pose without moving the toe.
    let isRear = femur > 5
    let kneeOffset = leg.swingSign * (leg.isFront ? -1 : 1)
                   * (leg.isFront ? 1.55 : (isRear ? 2.95 : 2.25))
    func femurY(_ t: CGFloat) -> CGFloat {
        kneeOffset * t
    }
    func tibiaY(_ t: CGFloat) -> CGFloat {
        kneeOffset * (1 - t)
    }
    thigh.tube([SCNVector3(0, 0, 0),
                SCNVector3(femur * 0.20, femurY(0.20), 0),
                SCNVector3(femur * 0.45, femurY(0.45), 0),
                SCNVector3(femur * 0.68, femurY(0.68), 0),
                SCNVector3(femur * 0.87, femurY(0.87), 0),
                SCNVector3(femur, kneeOffset, 0)],
               radii: [0.40, 0.62, 0.74, 0.66, 0.46, 0.27].map { $0 * frontThickness },
               color: femurRed, sides: 10)
    let thighLength = hypot(femur, kneeOffset)
    let thighNormal = (x: -kneeOffset / thighLength, y: femur / thighLength)
    for side in [CGFloat(-1), 1] {
        for i in 0..<(leg.isFront ? 3 : 5) {
            let t = 0.28 + CGFloat(i) * (leg.isFront ? 0.20 : 0.125)
            func spinePoint(_ forward: CGFloat, _ outward: CGFloat) -> SCNVector3 {
                let offset = side * outward * frontThickness
                return SCNVector3(femur * t + forward * femur / thighLength + offset * thighNormal.x,
                                  femurY(t) + forward * kneeOffset / thighLength + offset * thighNormal.y, 0)
            }
            thigh.tube([spinePoint(0, 0.42), spinePoint(0.15, 0.70),
                        spinePoint(0.32, 0.90 - t * 0.13)],
                       radii: [0.09, 0.055, 0.006].map { $0 * frontThickness },
                       color: bodyDark, sides: 5)
        }
    }
    leg.root.addChildNode(SCNNode(geometry: thigh.geometry(specular: 0.3)))
    leg.root.addChildNode(ellipsoid(SCNVector3(0.66, 0.46 * frontThickness,
                                               0.36 * frontThickness),
                                     at: SCNVector3(0.14, 0, 0), color: bodyDark))

    var shin = RoachMesh()
    shin.tube([SCNVector3(0, kneeOffset, 0),
               SCNVector3(tibia * 0.18, tibiaY(0.18), 0),
               SCNVector3(tibia * 0.43, tibiaY(0.43), 0),
               SCNVector3(tibia * 0.68, tibiaY(0.68), 0),
               SCNVector3(tibia * 0.87, tibiaY(0.87), 0),
               SCNVector3(tibia, 0, 0)],
              radii: [0.22, 0.20, 0.18, 0.15, 0.12, 0.085], color: tibiaDark, sides: 8)
    let shinLength = hypot(tibia, kneeOffset)
    let shinNormal = (x: kneeOffset / shinLength, y: tibia / shinLength)
    for side in [CGFloat(-1), 1] {
        for i in 0..<(leg.isFront ? 4 : 7) {
            let t = 0.13 + CGFloat(i) * (leg.isFront ? 0.22 : 0.125)
            let length: CGFloat = (0.53 + 0.35 * t) * (leg.isFront ? 0.85 : 1)
            func spinePoint(_ forward: CGFloat, _ outward: CGFloat) -> SCNVector3 {
                let offset = side * outward
                return SCNVector3(tibia * t + forward * tibia / shinLength + offset * shinNormal.x,
                                  tibiaY(t) - forward * kneeOffset / shinLength + offset * shinNormal.y, 0)
            }
            shin.tube([spinePoint(0, 0.18), spinePoint(0.20, 0.20 + length * 0.55),
                       spinePoint(0.38, 0.20 + length)],
                      radii: [0.09, 0.045, 0.004], color: bodyDark, sides: 5)
        }
    }
    leg.knee.addChildNode(SCNNode(geometry: shin.geometry(specular: 0.22)))
    leg.knee.addChildNode(ellipsoid(SCNVector3(0.34, 0.33, 0.32),
                                    at: SCNVector3(0, kneeOffset, 0), color: bodyDark))

    var foot = RoachMesh()
    for i in 0..<5 {
        let x0 = tarsus * CGFloat(i) / 5
        let x1 = tarsus * CGFloat(i + 1) / 5
        let radius = 0.135 - CGFloat(i) * 0.016
        foot.tube([SCNVector3(x0, 0, 0), SCNVector3(x0 + 0.09, 0, 0),
                   SCNVector3(x1 - 0.035, 0, 0), SCNVector3(x1, 0, 0)],
                  radii: [radius * 0.65, radius, radius * 0.70, radius * 0.50],
                  color: mixed(tibiaDark, femurRed, 0.25), sides: 7)
    }
    for side in [CGFloat(-1), 1] {
        foot.tube([SCNVector3(tarsus - 0.10, side * 0.04, 0),
                   SCNVector3(tarsus + 0.15, side * 0.18, 0.04),
                   SCNVector3(tarsus + 0.29, side * 0.11, -0.04)],
                  radii: [0.065, 0.042, 0.005], color: bodyDark)
    }
    leg.ankle.addChildNode(SCNNode(geometry: foot.geometry(specular: 0.18)))
}

func buildRoachModel() -> FlyModel {
    let root = SCNNode()
    root.scale = SCNVector3(FLY_SCALE, FLY_SCALE, FLY_SCALE)
    root.addChildNode(ellipsoid(SCNVector3(1.85, 1.70, 0.90),
                                at: SCNVector3(0, 7.9, 3.35), color: bodyDark))
    for side in [CGFloat(-1), 1] {
        root.addChildNode(ellipsoid(SCNVector3(0.42, 0.73, 0.44),
            at: SCNVector3(side * 1.58, 8.25, 3.78),
            color: NSColor(calibratedWhite: 0.035, alpha: 1), specular: 0.6))
        root.addChildNode(buildAntenna(side: side))
        var palp = RoachMesh()
        palp.tube([SCNVector3(side * 0.65, 8.7, 2.95), SCNVector3(side * 1.25, 9.4, 2.85),
                   SCNVector3(side * 1.05, 10.0, 2.9)],
                  radii: [0.16, 0.13, 0.08], color: mixed(bodyDark, rimTan, 0.2))
        root.addChildNode(SCNNode(geometry: palp.geometry()))
    }
    // The shallow thoracic underside joins head, leg roots and abdomen.
    root.addChildNode(ellipsoid(SCNVector3(4.25, 4.4, 1.0),
                                at: SCNVector3(0, 2.6, 3.1), color: bodyDark))
    let shield = SCNNode(geometry: pronotumShape())
    // The hood covers the bright wing shoulders all the way to its rear edge.
    shield.position = SCNVector3(0, 5.25, 5.48)
    shield.scale = SCNVector3(0.86, 0.86, 0.86)
    root.addChildNode(shield)
    let abdomen = buildAbdomen()
    root.addChildNode(abdomen)

    var legs: [Leg] = []
    let z: CGFloat = 3.6
    // RF, LF, RM, LM, RH, LH; retain the existing locomotor geometry.
    let specs: [(CGFloat, SCNVector3, CGFloat, CGFloat, Bool, CGFloat, CGFloat, CGFloat)] = [
        ( 1, SCNVector3( 3.8,  5.4, z),  1.00, 0.0, true,  4.0, 4.6, 3.0),
        (-1, SCNVector3(-3.8,  5.4, z),  1.00, 0.5, true,  4.0, 4.6, 3.0),
        ( 1, SCNVector3( 4.4,  1.9, z), -0.08, 0.5, false, 4.8, 5.6, 3.6),
        (-1, SCNVector3(-4.4,  1.9, z), -0.08, 0.0, false, 4.8, 5.6, 3.6),
        ( 1, SCNVector3( 3.9, -1.7, z), -1.05, 0.0, false, 6.0, 8.0, 5.2),
        (-1, SCNVector3(-3.9, -1.7, z), -1.05, 0.5, false, 6.0, 8.0, 5.2),
    ]
    for (side, attach, yaw, phase, front, f, t, ta) in specs {
        let leg = buildLeg(attach: attach, baseYaw: side > 0 ? yaw : (.pi - yaw),
                           swingSign: side, phase: phase, isFront: front,
                           femur: f, tibia: t, tarsus: ta)
        detailLeg(leg, femur: f, tibia: t, tarsus: ta)
        root.addChildNode(leg.root)
        legs.append(leg)
    }

    let foldedWings = SCNNode()
    for side in [CGFloat(-1), 1] {
        let wing = SCNNode(geometry: hindwingShape(side: side))
        wing.position = SCNVector3(side * 1.35, 1.4, 4.52)
        wing.eulerAngles = SCNVector3(0, 0, side * 0.13)
        foldedWings.addChildNode(wing)
    }
    root.addChildNode(foldedWings)
    var tegmina: [SCNNode] = []
    for side in [CGFloat(-1), 1] {
        let wing = SCNNode(geometry: tegmenShape(side: side))
        // Mirrored surfaces meet at the midline without overlapping polygons.
        wing.position = SCNVector3(0, 2.0, 5.0)
        wing.addChildNode(buildVeins(side: side))
        root.addChildNode(wing)
        tegmina.append(wing)
        root.addChildNode(buildCercus(side: side))
    }
    func blurWing(_ side: CGFloat) -> SCNNode {
        let node = ellipsoid(SCNVector3(6.4, 2.8, 0.3), at: SCNVector3(side * 7.2, -2.2, 5.0),
            color: NSColor(calibratedRed: 0.58, green: 0.40, blue: 0.21, alpha: 0.22))
        node.geometry?.firstMaterial?.lightingModel = .constant
        node.geometry?.firstMaterial?.writesToDepthBuffer = false
        node.eulerAngles = SCNVector3(0, 0, side * -0.45)
        node.isHidden = true
        return node
    }
    let bl = blurWing(-1), br = blurWing(1)
    root.addChildNode(bl)
    root.addChildNode(br)
    return FlyModel(root: root, legs: legs, foldedWings: foldedWings,
                    blurWingL: bl, blurWingR: br, abdomen: abdomen,
                    elytraL: tegmina[0], elytraR: tegmina[1], wingFlightSpread: 0.8)
}
