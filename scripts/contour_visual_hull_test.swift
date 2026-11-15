import Foundation
import simd

@main
struct ContourVisualHullTests {
    static func main() throws {
        setbuf(stdout, nil)
        try box()
        try disks()
        try thinAndDisconnected()
        try holes()
        try orientation()
        try ceiling()
        try invalid()
        try source512()
        print("PASS ContourVisualHull: 8 groups")
        if CommandLine.arguments.contains("--stress") {
            let start = Date()
            let mesh = try hull(disk(512), disk(512))
            validate(mesh)
            check(mesh.faces.count / 3 <= 150_000, "practical output cap")
            print("PASS 512 disk: \(mesh.diagnostics.visitedSurfaceCells) surface cells, \(mesh.faces.count / 3) triangles, \(mesh.vertices.count) vertices, \(mesh.diagnostics.peakTemporaryBoundaryEdges) peak temporary edges, \(Date().timeIntervalSince(start))s")
            let resourceStart = Date()
            do {
                _ = try ContourVisualHull.build(top: mask(128, 128), side: mask(9, 128),
                    widthCm: 10, depthCm: 8, heightCm: 4,
                    measuredCeilingCm: { r, c in 1 + Double((r * 37 + c * 71) % 97) / 97 })
                preconditionFailure("complex measured surface must reject before oversized output")
            } catch ContourVisualHull.HullError.resourceLimit {
                print("PASS practical resource rejection: \(Date().timeIntervalSince(resourceStart))s")
            }
        }
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func mask(_ rows: Int, _ cols: Int, _ occupied: (Int, Int) -> Bool = { _, _ in true }) -> [[UInt8]] {
        (0..<rows).map { r in (0..<cols).map { c in occupied(r, c) ? 1 : 0 } }
    }

    static func hull(_ top: [[UInt8]], _ side: [[UInt8]], height: Double = 4) throws -> ContourVisualHull.Mesh {
        try ContourVisualHull.build(top: top, side: side, widthCm: 10, depthCm: 8, heightCm: height)
    }

    static func validate(_ mesh: ContourVisualHull.Mesh) {
        check(mesh.volumeCm3 > 0 && mesh.volumeCm3.isFinite, "finite positive volume")
        check(abs(mesh.volumeCm3 - mesh.diagnostics.partitionVolumeCm3) <= max(mesh.volumeCm3 * 5e-6, 1e-12),
              "coplanar consolidation preserves unmerged partition volume")
        var edges: [String: (Int, Int)] = [:]
        for i in stride(from: 0, to: mesh.faces.count, by: 3) {
            let ids = Array(mesh.faces[i..<(i + 3)])
            let points = ids.map { mesh.vertices[$0] }
            check(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, "finite vertices")
            check(simd_length_squared(simd_cross(points[1] - points[0], points[2] - points[0])) > 0, "nondegenerate face")
            for j in 0..<3 {
                let a = ids[j], b = ids[(j + 1) % 3], key = "\(min(a, b)):\(max(a, b))"
                let old = edges[key] ?? (0, 0)
                edges[key] = (old.0 + 1, old.1 + (a < b ? 1 : -1))
            }
        }
        check(edges.values.allSatisfy { $0.0 == 2 && $0.1 == 0 }, "two opposite edge uses")
    }

    static func hasProjection(_ mesh: ContourVisualHull.Mesh, _ point: SIMD2<Double>, axes: (Int, Int)) -> Bool {
        func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
        for i in stride(from: 0, to: mesh.faces.count, by: 3) {
            let p = (0..<3).map { j -> SIMD2<Double> in
                let vertex = mesh.vertices[mesh.faces[i + j]]
                return SIMD2<Double>(Double(vertex[axes.0]), Double(vertex[axes.1]))
            }
            let area = cross(p[1] - p[0], p[2] - p[0])
            if abs(area) < 1e-18 { continue }
            let a = cross(p[1] - point, p[2] - point) / area
            let b = cross(p[2] - point, p[0] - point) / area
            let c = 1 - a - b
            if min(a, b, c) >= -1e-7 { return true }
        }
        return false
    }

    static func box() throws {
        let mesh = try hull(mask(12, 16), mask(9, 16))
        validate(mesh)
        check(abs(mesh.volumeCm3 - 320) < 0.0001, "box volume")
        check(abs(Double(mesh.vertices.map(\.x).max()! - mesh.vertices.map(\.x).min()!) - 0.1) < 1e-7, "box width")
        check(abs(Double(mesh.vertices.map(\.y).max()! - mesh.vertices.map(\.y).min()!) - 0.04) < 1e-7, "box height")
        for i in stride(from: 0, to: mesh.faces.count, by: 3) {
            let p = (0..<3).map { mesh.vertices[mesh.faces[i + $0]] }
            let n = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
            check([abs(n.x), abs(n.y), abs(n.z)].filter { $0 > 1e-5 }.count == 1, "box faces must stay sharp and planar")
        }
        print("PASS box")
    }

    static func disk(_ n: Int) -> [[UInt8]] {
        mask(n, n) { r, c in
            let x = Double(c) + 0.5 - Double(n) / 2, y = Double(r) + 0.5 - Double(n) / 2
            return x * x + y * y < pow(Double(n) / 2, 2)
        }
    }

    static func disks() throws {
        let mesh = try hull(disk(24), disk(24))
        validate(mesh)
        var sloped = 0
        for i in stride(from: 0, to: mesh.faces.count, by: 3) {
            let p = (0..<3).map { mesh.vertices[mesh.faces[i + $0]] }
            let n = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
            if abs(n.y) > 0.05 && abs(n.y) < 0.95 { sloped += 1 }
        }
        check(sloped > 8, "round silhouettes need sloped, not voxel-ledge faces")
        // Every projection remains within one source-pixel uncertainty of the
        // circle; this is not a claim of exact hidden spherical geometry.
        for p in mesh.vertices {
            let x = Double(p.x) / 0.1, z = Double(p.z) / 0.08, y = Double(p.y) / 0.04 - 0.5
            check(x * x + z * z <= pow(0.5 + 1.0 / 24, 2), "TOP contour fidelity")
            check(x * x + y * y <= pow(0.5 + 1.0 / 24, 2), "SIDE contour fidelity")
            check(z * z + y * y <= pow(0.5 + 1.0 / 24, 2), "symmetry contour fidelity")
            check(abs(x) <= 0.500001 && abs(z) <= 0.500001 && abs(y) <= 0.500001, "no bounding expansion")
        }
        let again = try hull(disk(24), disk(24))
        check(mesh.vertices == again.vertices && mesh.faces == again.faces, "deterministic mesh")
        for (topSize, sideSize) in [(17, 23), (32, 29)] {
            validate(try hull(disk(topSize), disk(sideSize)))
        }
        let source = disk(24)
        for r in source.indices {
            for c in source[r].indices where source[r][c] != 0 {
                let u = (Double(c) + 0.5) / 24 - 0.5, v = (Double(r) + 0.5) / 24 - 0.5
                check(hasProjection(mesh, SIMD2(u * 0.1, v * 0.08), axes: (0, 2)), "every TOP occupied pixel centre supported")
                check(hasProjection(mesh, SIMD2(u * 0.1, (0.5 - v) * 0.04), axes: (0, 1)), "every SIDE occupied pixel centre supported")
                check(hasProjection(mesh, SIMD2(u * 0.08, (0.5 - v) * 0.04), axes: (2, 1)), "every transverse SIDE centre supported")
            }
        }
        print("PASS disks")
    }

    static func thinAndDisconnected() throws {
        let thin = try hull(mask(1, 19), mask(1, 19), height: 0.000001)
        validate(thin)
        check(abs(thin.volumeCm3 - 0.00008) < 1e-10, "no artificial minimum thickness")
        let top = mask(9, 9) { r, c in (r < 3 || r >= 6) && (c < 3 || c >= 6) }
        let side = mask(5, 9) { _, c in c < 3 || c >= 6 }
        let pieces = try hull(top, side)
        validate(pieces)
        // A centre bridge would fill a disconnected component gap.
        check(!pieces.vertices.contains { abs($0.x) < 0.01 && abs($0.z) < 0.008 }, "disconnected support preserved")
        let cross = mask(9, 9) { r, c in r == 4 || c == 4 }
        validate(try hull(cross, mask(3, 9)))
        print("PASS thin/disconnected")
    }

    static func holes() throws {
        let ring = mask(13, 13) { r, c in !(4...8).contains(r) || !(4...8).contains(c) }
        let mesh = try hull(ring, mask(5, 13))
        validate(mesh)
        check(!mesh.vertices.contains { abs($0.x) < 0.01 && abs($0.z) < 0.008 }, "TOP hole retained")
        check(!hasProjection(mesh, .zero, axes: (0, 2)), "no triangles bridge the TOP hole")
        let sideHole = mask(13, 13) { r, c in !(4...8).contains(r) || !(4...8).contains(c) }
        validate(try hull(mask(13, 13), sideHole))
        print("PASS holes")
    }

    static func orientation() throws {
        let side = mask(7, 9) { r, c in r >= c / 3 }
        let base = try hull(mask(9, 9), side)
        let transpose = (0..<9).map { c in (0..<7).map { r in side[r][c] } }
        let transposed = try ContourVisualHull.build(top: mask(9, 9), side: transpose,
            sideHorizontalUsesRows: true, widthCm: 10, depthCm: 8, heightCm: 4)
        check(base.vertices == transposed.vertices && base.faces == transposed.faces, "transpose convention")
        let upsideDown = Array(side.reversed())
        let upright = try ContourVisualHull.build(top: mask(9, 9), side: upsideDown,
            sideVerticalIncreasesUp: true, widthCm: 10, depthCm: 8, heightCm: 4)
        check(base.vertices == upright.vertices && base.faces == upright.faces, "vertical convention")
        let reversed = try ContourVisualHull.build(top: mask(9, 9), side: side.map { Array($0.reversed()) },
            reversed: true, widthCm: 10, depthCm: 8, heightCm: 4)
        check(base.vertices == reversed.vertices && base.faces == reversed.faces, "horizontal reversal")
        print("PASS orientation")
    }

    static func ceiling() throws {
        let half = try ContourVisualHull.build(top: mask(5, 7), side: mask(9, 7),
            widthCm: 10, depthCm: 8, heightCm: 4, measuredCeilingCm: { _, _ in 2 })
        validate(half)
        check(abs(half.volumeCm3 - 160) < 0.001, "ceiling clips, never stretches")
        check(half.vertices.map(\.y).max()! <= 0.020001, "ceiling height")
        let slope = try ContourVisualHull.build(top: mask(5, 7), side: mask(9, 7),
            widthCm: 10, depthCm: 8, heightCm: 4,
            measuredCeilingCm: { _, c in 1 + Double(c) / 7 })
        validate(slope)
        let sparse = try ContourVisualHull.build(top: mask(7, 7), side: mask(9, 7),
            widthCm: 10, depthCm: 8, heightCm: 4,
            measuredCeilingCm: { r, c in (2...4).contains(r) && (2...4).contains(c) ? 0 : 2 })
        validate(sparse)
        check(sparse.diagnostics.missingCeilingPixels == 0, "observed zero is not a missing observation")
        check(!sparse.vertices.contains { abs($0.x) < 0.015 && abs($0.z) < 0.012 }, "no measured-zero hole fill")
        check(!hasProjection(sparse, .zero, axes: (0, 2)), "no triangles bridge observed-zero holes")
        let noDepth = try ContourVisualHull.build(top: mask(7, 7), side: mask(9, 7),
            widthCm: 10, depthCm: 8, heightCm: 4, measuredCeilingCm: { _, _ in nil })
        validate(noDepth)
        check(abs(noDepth.volumeCm3 - 320) < 0.001, "nil leaves independently measured SIDE hull unchanged")
        check(noDepth.diagnostics.missingCeilingPixels == 49, "missing observation diagnostics")
        let sparseDepth = try ContourVisualHull.build(top: mask(7, 7), side: mask(9, 7),
            widthCm: 10, depthCm: 8, heightCm: 4,
            measuredCeilingCm: { r, c in r == 0 && c == 0 ? 2 : nil })
        validate(sparseDepth)
        check(hasProjection(sparseDepth, .zero, axes: (0, 2)), "nil retains silhouette support")
        check(sparseDepth.volumeCm3 > 300 && sparseDepth.volumeCm3 < 320, "sparse depth is an additional local clip")
        let padded = mask(9, 11) { r, c in (2...6).contains(r) && (3...9).contains(c) }
        let cropped = try ContourVisualHull.build(top: padded, side: mask(9, 7),
            widthCm: 10, depthCm: 8, heightCm: 4, offsetX: 0.02, offsetZ: -0.03,
            measuredCeilingCm: { r, c in
                check((2...6).contains(r) && (3...9).contains(c), "original source ceiling coordinates")
                return 2
            })
        validate(cropped)
        check(abs(cropped.volumeCm3 - half.volumeCm3) < 0.001, "cropping and offsets preserve measured volume")
        print("PASS ceiling")
    }

    static func throwsError(_ body: () throws -> Void, _ message: String) {
        do { try body(); preconditionFailure(message) } catch is ContourVisualHull.HullError {} catch {
            preconditionFailure("unexpected error \(error)")
        }
    }

    static func invalid() throws {
        throwsError({ _ = try hull([], mask(3, 3)) }, "empty input")
        throwsError({ _ = try hull([[0, 0], [0, 0]], mask(3, 3)) }, "empty mask")
        throwsError({ _ = try hull([[1], [1, 1]], mask(3, 3)) }, "ragged input")
        throwsError({ _ = try hull(mask(3, 3), mask(3, 3), height: .nan) }, "nonfinite dimensions")
        throwsError({
            _ = try ContourVisualHull.build(top: mask(3, 3), side: mask(3, 3),
                widthCm: 10, depthCm: 8, heightCm: 4, measuredCeilingCm: { _, _ in .infinity })
        }, "nonfinite ceiling")
        throwsError({
            _ = try ContourVisualHull.build(top: mask(3, 3), side: mask(3, 3),
                widthCm: 10, depthCm: 8, heightCm: 4, measuredCeilingCm: { _, _ in -1 })
        }, "negative ceiling")
        throwsError({
            _ = try ContourVisualHull.build(top: mask(3, 3), side: mask(3, 3),
                widthCm: 10, depthCm: 8, heightCm: 4, measuredCeilingCm: { _, _ in 0 })
        }, "empty ceiling intersection")
        let top = mask(9, 9) { r, c in (r < 3 && c >= 6) || (r >= 6 && c < 3) }
        let side = mask(9, 9) { r, c in r / 3 == c / 3 }
        throwsError({ _ = try hull(top, side) }, "incompatible observations must retake, never disappear")
        print("PASS invalid/empty")
    }

    static func source512() throws {
        let mesh = try hull(mask(512, 512), mask(512, 512))
        validate(mesh)
        check(mesh.diagnostics.visitedSurfaceCells < 100, "uniform source grid must not become dense 512 cubed")
        let measured = try ContourVisualHull.build(top: mask(512, 512), side: mask(512, 512),
            widthCm: 10, depthCm: 8, heightCm: 4, measuredCeilingCm: { _, _ in 2 })
        validate(measured)
        check(measured.diagnostics.visitedSurfaceCells < 100, "constant ceiling must not force a dense grid")
        print("PASS 512 source")
    }
}
