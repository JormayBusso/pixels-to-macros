import Foundation
import simd

/// A contour estimate, not an exact hidden-object reconstruction. Binary pixel
/// centres are observations; the zero contour between them is linearly estimated.
/// Intersecting the three fields separately retains sharp intersections (taking
/// their minimum before polygonising would bevel them). The transverse SIDE
/// projection is explicitly a symmetry assumption. No voxel surface is smoothed.
/// Following polyhedral visual-hull projection intersection (Matusik et al.,
/// 2001), tetrahedra are only a conforming numerical partition, not output voxels.
/// Numerical welding or Float precision failures require a retake; they never
/// authorize a thickness floor, sparse-depth fill, or raster/primitive fallback.
enum ContourVisualHull {
    enum HullError: Error, CustomStringConvertible {
        case invalidInput(String)
        case emptyIntersection
        case unsupportedObservation(String)
        case resourceLimit
        case nonManifold

        var description: String {
            switch self {
            case .invalidInput(let reason): return "invalid_contour_input:\(reason)"
            case .emptyIntersection: return "empty_contour_intersection"
            case .unsupportedObservation(let reason): return "unsupported_contour_observation:\(reason)"
            case .resourceLimit: return "contour_resource_limit"
            case .nonManifold: return "nonmanifold_contour_intersection"
            }
        }
    }

    struct Diagnostics {
        let visitedSurfaceCells: Int
        let triangleCount: Int
        let topOccupiedPixels: Int
        let sideOccupiedPixels: Int
        let missingCeilingPixels: Int
        /// Audit integral before coplanar consolidation; never the volume source.
        let partitionVolumeCm3: Double
        let peakTemporaryBoundaryEdges: Int
        let transverseSideIsSymmetryAssumption = true
        let contourIsInterpolatedMeasurement = true
    }

    struct Mesh {
        let vertices: [SIMD3<Float>]
        /// Outward-facing triangle indices.
        let faces: [Int]
        /// Computed from the returned metre-space Float triangles, not a proxy.
        let volumeCm3: Double
        let diagnostics: Diagnostics
    }

    /// X/Z offsets are metres, dimensions and measured ceilings are centimetres.
    /// TOP row/column coordinates passed to the ceiling closure are ORIGINAL
    /// source indices. Nil supplies no ADDITIONAL depth constraint: the mandatory
    /// SIDE measurement remains the height authority. An observed zero removes
    /// that source pixel's support. Ceiling interpolation is
    /// conservative: it cannot exceed the measurement of its containing pixel.
    static func build(
        top: [[UInt8]], side: [[UInt8]],
        sideHorizontalUsesRows: Bool = false,
        sideVerticalIncreasesUp: Bool = false,
        reversed: Bool = false,
        widthCm: Double, depthCm: Double, heightCm: Double,
        offsetX: Float = 0, offsetZ: Float = 0,
        measuredCeilingCm: ((Int, Int) -> Double?)? = nil
    ) throws -> Mesh {
        guard widthCm.isFinite, depthCm.isFinite, heightCm.isFinite,
              widthCm > 0, depthCm > 0, heightCm > 0,
              offsetX.isFinite, offsetZ.isFinite else {
            throw HullError.invalidInput("nonpositive_or_nonfinite_dimensions")
        }
        let tb = try bounds(top), sb = try bounds(side)
        let t = (tb.r0...tb.r1).map { r in
            (tb.c0...tb.c1).map { c in top[r][c] != 0 }
        }
        let horizontalCount = sideHorizontalUsesRows ? sb.r1 - sb.r0 + 1 : sb.c1 - sb.c0 + 1
        let verticalCount = sideHorizontalUsesRows ? sb.c1 - sb.c0 + 1 : sb.r1 - sb.r0 + 1
        var s = [[Bool]](repeating: [Bool](repeating: false, count: horizontalCount), count: verticalCount)
        for y in 0..<verticalCount {
            for h in 0..<horizontalCount {
                let sourceH = reversed ? horizontalCount - 1 - h : h
                let sourceV = sideVerticalIncreasesUp ? y : verticalCount - 1 - y
                s[y][h] = sideHorizontalUsesRows
                    ? side[sb.r0 + sourceH][sb.c0 + sourceV] != 0
                    : side[sb.r0 + sourceV][sb.c0 + sourceH] != 0
            }
        }
        let topField = BinaryField(t), sideField = BinaryField(s)
        var ceilings: [[Double]]?
        var missingCeilings = 0
        if let measuredCeilingCm {
            var samples = [[Double]](repeating: [Double](repeating: 1, count: t[0].count), count: t.count)
            for r in t.indices {
                for c in t[r].indices where t[r][c] {
                    if let value = measuredCeilingCm(tb.r0 + r, tb.c0 + c) {
                        guard value.isFinite, value >= 0 else {
                            throw HullError.invalidInput("nonfinite_or_negative_ceiling")
                        }
                        samples[r][c] = min(1, value / heightCm)
                    } else {
                        missingCeilings += 1
                    }
                }
            }
            ceilings = samples
        }
        // Keep every axis on which observations change. Removing identical
        // interior samples changes neither the field nor its contours.
        let tx = merged(axisNodes(t, rows: false), ceilings.map { ceilingAxisNodes($0, rows: false) } ?? [])
        let tz = merged(axisNodes(t, rows: true), ceilings.map { ceilingAxisNodes($0, rows: true) } ?? [])
        let sh = axisNodes(s, rows: false)
        let ys = axisNodes(s, rows: true)
        let xs = merged(tx, sh), zs = merged(tz, sh)
        let nx = xs.count - 1, nz = zs.count - 1, ny = ys.count - 1
        let topValues = zs.flatMap { z in xs.map { topField.sample($0, z) } }
        let xSide = xs.flatMap { x in ys.map { sideField.sample(x, $0) } }
        let zSide = zs.flatMap { z in ys.map { sideField.sample(z, $0) } }
        var validity: [Double] = [], ceilingValues: [Double] = []
        if let ceilings {
            for z in zs {
                for x in xs {
                    let sample = ceilingSample(ceilings, x, z)
                    validity.append(sample.validity)
                    ceilingValues.append(sample.height)
                }
            }
        }
        try verifyTopSupport(t, side: sideField, ceilings: ceilings)
        // Missing SIDE support is an observation conflict, not permission to
        // quietly lose a disconnected component in the symmetry intersection.
        try verifySideSupport(s, top: topField, side: sideField, zs: zs)

        let xBits = sideBits(xSide, horizontalNodes: xs.count, verticalNodes: ys.count)
        let zBits = sideBits(zSide, horizontalNodes: zs.count, verticalNodes: ys.count)
        var builder = SurfaceBuilder()
        let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        var visited = 0
        for z in 0..<nz {
            for x in 0..<nx {
                let ti = [z * xs.count + x, z * xs.count + x + 1,
                          (z + 1) * xs.count + x, (z + 1) * xs.count + x + 1]
                let top4 = ti.map { topValues[$0] }
                if top4.max()! <= 0 { continue }
                let valid4 = ceilings == nil ? [1.0, 1, 1, 1] : ti.map { validity[$0] }
                if valid4.max()! <= 0 { continue }
                let insideTop = top4.min()! > 0 && valid4.min()! > 0 &&
                    x > 0 && x < nx - 1 && z > 0 && z < nz - 1
                let ceiling4 = ceilings == nil ? [1.0, 1, 1, 1] : ti.map { ceilingValues[$0] }
                for word in xBits[x].possible.indices {
                    let possible = xBits[x].possible[word] & zBits[z].possible[word]
                    var candidates = insideTop
                        ? possible & (xBits[x].boundary[word] | zBits[z].boundary[word])
                        : possible
                    if ceilings != nil {
                        // A varying measured ceiling may cross several Y slabs.
                        // Only those slabs are added, never the dense interior.
                        let low = ceiling4.min()!, high = ceiling4.max()!
                        let start = word * 64, end = min(ny, start + 64)
                        for y in start..<end where ys[y] <= high && ys[y + 1] >= low {
                            candidates |= possible & (UInt64(1) << (y - start))
                        }
                    }
                    while candidates != 0 {
                        let bit = candidates.trailingZeroBitCount
                        candidates &= candidates - 1
                        let y = word * 64 + bit
                        guard y < ny else { continue }
                        visited += 1
                        guard visited <= 2_000_000 else { throw HullError.resourceLimit }
                        var cube: [ClipVertex] = []
                        for corner in 0..<8 {
                            let dx = corner & 1, dy = (corner >> 1) & 1, dz = (corner >> 2) & 1
                            let flat = dz * 2 + dx
                            let position = SIMD3<Double>(xs[x + dx], ys[y + dy], zs[z + dz])
                            var fields = [top4[flat],
                                          xSide[(x + dx) * ys.count + y + dy],
                                          zSide[(z + dz) * ys.count + y + dy]]
                            if ceilings != nil {
                                fields.append(valid4[flat])
                                fields.append(ceiling4[flat] - position.y)
                            }
                            cube.append(ClipVertex(p: position, fields: fields))
                        }
                        // Freudenthal tetrahedra have identical triangulations
                        // on neighbouring cell faces. Each constraint is affine
                        // within a tetrahedron and is clipped independently.
                        for order in permutations {
                            let a = 1 << order[0], b = a | (1 << order[1])
                            try builder.addTetrahedron([cube[0], cube[a], cube[b], cube[7]])
                        }
                    }
                }
            }
        }
        let result = try builder.finish(widthCm: widthCm, depthCm: depthCm, heightCm: heightCm,
                                        offsetX: offsetX, offsetZ: offsetZ)
        return Mesh(vertices: result.vertices, faces: result.faces, volumeCm3: result.volume,
                    diagnostics: Diagnostics(visitedSurfaceCells: visited, triangleCount: result.faces.count / 3,
                                             topOccupiedPixels: t.flatMap { $0 }.filter { $0 }.count,
                                             sideOccupiedPixels: s.flatMap { $0 }.filter { $0 }.count,
                                             missingCeilingPixels: missingCeilings,
                                             partitionVolumeCm3: builder.partitionVolume * widthCm * depthCm * heightCm,
                                             peakTemporaryBoundaryEdges: builder.peakBoundaryEdgeCount))
    }

    private struct Bounds { let r0: Int, r1: Int, c0: Int, c1: Int }

    private static func bounds(_ mask: [[UInt8]]) throws -> Bounds {
        guard !mask.isEmpty, let width = mask.first?.count, width > 0,
              mask.count <= 512, width <= 512, mask.allSatisfy({ $0.count == width }) else {
            throw HullError.invalidInput("ragged_empty_or_oversized_mask")
        }
        var r0 = mask.count, r1 = -1, c0 = width, c1 = -1
        for r in mask.indices {
            for c in mask[r].indices where mask[r][c] != 0 {
                r0 = min(r0, r); r1 = max(r1, r); c0 = min(c0, c); c1 = max(c1, c)
            }
        }
        guard r1 >= r0 else { throw HullError.invalidInput("empty_mask") }
        return Bounds(r0: r0, r1: r1, c0: c0, c1: c1)
    }

    private struct BinaryField {
        let mask: [[Bool]]
        let width: Int, height: Int
        init(_ mask: [[Bool]]) {
            self.mask = mask; width = mask[0].count; height = mask.count
        }

        func sample(_ u: Double, _ v: Double) -> Double {
            func interval(_ u: Double, _ n: Int) -> (Int, Int, Double) {
                let p = u * Double(n) - 0.5
                if p < 0 { return (-1, 0, u * Double(n) * 2) }
                if p >= Double(n - 1) { return (n - 1, n, (p - Double(n - 1)) * 2) }
                let lo = Int(floor(p))
                return (lo, lo + 1, p - Double(lo))
            }
            let (x0, x1, a) = interval(u, width), (z0, z1, b) = interval(v, height)
            func node(_ x: Int, _ z: Int) -> Double {
                let occupied = mask[min(height - 1, max(0, z))][min(width - 1, max(0, x))]
                if !occupied { return -1 }
                return 1
            }
            let low = node(x0, z0) * (1 - a) + node(x1, z0) * a
            let high = node(x0, z1) * (1 - a) + node(x1, z1) * a
            let value = low * (1 - b) + high * b
            return abs(value) < 1e-13 ? 0 : value
        }
    }

    private static func axisNodes(_ mask: [[Bool]], rows: Bool) -> [Double] {
        let count = rows ? mask.count : mask[0].count
        var kept: Set<Int> = [0, count - 1]
        for i in 1..<count {
            let changed = rows ? mask[i] != mask[i - 1]
                : mask.indices.contains { mask[$0][i] != mask[$0][i - 1] }
            if changed { kept.insert(i - 1); kept.insert(i) }
        }
        let nodes = [0.0, 1.0] + kept.map { (Double($0) + 0.5) / Double(count) }
        return merged(nodes, [])
    }

    private static func ceilingAxisNodes(_ samples: [[Double]], rows: Bool) -> [Double] {
        let count = rows ? samples.count : samples[0].count
        var nodes = [0.0, 1.0, 0.5 / Double(count), 1 - 0.5 / Double(count)]
        for i in 1..<count {
            let changed = rows ? samples[i] != samples[i - 1]
                : samples.indices.contains { samples[$0][i] != samples[$0][i - 1] }
            if changed {
                nodes += [(Double(i) - 0.5) / Double(count),
                          Double(i) / Double(count), (Double(i) + 0.5) / Double(count)]
            }
        }
        return merged(nodes, [])
    }

    private static func merged(_ a: [Double], _ b: [Double]) -> [Double] {
        var result: [Double] = []
        for value in (a + b).sorted() where result.last.map({ abs($0 - value) > 1e-12 }) ?? true {
            result.append(value)
        }
        return result
    }

    private static func ceilingSample(_ samples: [[Double]], _ u: Double, _ v: Double)
        -> (validity: Double, height: Double) {
        let width = samples[0].count, height = samples.count
        func touching(_ u: Double, _ n: Int) -> [Int] {
            let p = u * Double(n), rounded = p.rounded()
            if abs(p - rounded) < 1e-10 {
                return [Int(rounded) - 1, Int(rounded)].filter { $0 >= 0 && $0 < n }
            }
            return [min(n - 1, max(0, Int(p)))]
        }
        var values: [Double] = []
        for r in touching(v, height) {
            for c in touching(u, width) { values.append(samples[r][c]) }
        }
        let positive = values.filter { $0 > 0 }
        guard !positive.isEmpty else { return (-1, 0) }
        return (positive.count == values.count ? 1 : 0, positive.min()!)
    }

    private struct SideBits {
        var possible: [UInt64]
        var boundary: [UInt64]
    }

    private static func sideBits(_ values: [Double], horizontalNodes: Int, verticalNodes: Int) -> [SideBits] {
        let words = (verticalNodes - 1 + 63) / 64
        return (0..<(horizontalNodes - 1)).map { h in
            var bits = SideBits(possible: [UInt64](repeating: 0, count: words),
                                boundary: [UInt64](repeating: 0, count: words))
            for y in 0..<(verticalNodes - 1) {
                let v = [values[h * verticalNodes + y], values[h * verticalNodes + y + 1],
                         values[(h + 1) * verticalNodes + y], values[(h + 1) * verticalNodes + y + 1]]
                if v.max()! > 0 {
                    bits.possible[y / 64] |= UInt64(1) << (y % 64)
                    if v.min()! <= 0 || h == 0 || h == horizontalNodes - 2 || y == 0 || y == verticalNodes - 2 {
                        bits.boundary[y / 64] |= UInt64(1) << (y % 64)
                    }
                }
            }
            return bits
        }
    }

    private static func positiveRange(_ a: Double, _ b: Double) -> (Double, Double)? {
        if a <= 0 && b <= 0 { return nil }
        if a > 0 && b > 0 { return (0, 1) }
        let cut = a / (a - b)
        return a > 0 ? (0, cut) : (cut, 1)
    }

    private static func verifyTopSupport(_ top: [[Bool]], side: BinaryField, ceilings: [[Double]]?) throws {
        let ys = [0.0] + (0..<side.height).map { (Double($0) + 0.5) / Double(side.height) } + [1.0]
        for r in top.indices {
            for c in top[r].indices where top[r][c] {
                let limit = ceilings?[r][c] ?? 1
                if limit == 0 { continue }
                let x = (Double(c) + 0.5) / Double(top[r].count)
                let z = (Double(r) + 0.5) / Double(top.count)
                var supported = false
                for y in 0..<(ys.count - 1) where ys[y] < limit {
                    guard let a = positiveRange(side.sample(x, ys[y]), side.sample(x, ys[y + 1])),
                          let b = positiveRange(side.sample(z, ys[y]), side.sample(z, ys[y + 1])) else { continue }
                    let upper = min(a.1, b.1, (limit - ys[y]) / (ys[y + 1] - ys[y]))
                    if upper > max(a.0, b.0) + 1e-12 { supported = true; break }
                }
                if !supported { throw HullError.unsupportedObservation("top_pixel_\(r)_\(c)") }
            }
        }
    }

    private static func verifySideSupport(_ mask: [[Bool]], top: BinaryField, side: BinaryField, zs: [Double]) throws {
        for r in mask.indices {
            for c in mask[r].indices where mask[r][c] {
                let x = (Double(c) + 0.5) / Double(mask[r].count)
                let y = (Double(r) + 0.5) / Double(mask.count)
                var supported = false
                for i in 0..<(zs.count - 1) {
                    guard let a = positiveRange(top.sample(x, zs[i]), top.sample(x, zs[i + 1])),
                          let b = positiveRange(side.sample(zs[i], y), side.sample(zs[i + 1], y)) else { continue }
                    if min(a.1, b.1) > max(a.0, b.0) + 1e-12 { supported = true; break }
                }
                if !supported { throw HullError.unsupportedObservation("side_pixel_\(r)_\(c)") }
            }
        }
    }

    private struct ClipVertex {
        var p: SIMD3<Double>
        var fields: [Double]
        func interpolated(to other: ClipVertex, t: Double, constraint: Int) -> ClipVertex {
            var values = zip(fields, other.fields).map { $0 * (1 - t) + $1 * t }
            values[constraint] = 0
            return ClipVertex(p: p * (1 - t) + other.p * t, fields: values)
        }
    }

    private struct Polygon {
        var vertices: [ClipVertex]
        /// -1 is an internal tetrahedron face; other tags are silhouette planes.
        var constraint: Int
    }

    private struct VertexKey: Hashable, Comparable {
        // Losslessly pack the same three 34-bit, 1e-10-resolution coordinates.
        // Boundary hashing is the memory hot spot; no precision is discarded.
        private let low: UInt64, high: UInt64
        var x: UInt64 { low & ((1 << 34) - 1) }
        var y: UInt64 { (low >> 34) | ((high & 15) << 30) }
        var z: UInt64 { high >> 4 }
        init(_ p: SIMD3<Double>) {
            let x = UInt64((p.x * 1e10).rounded())
            let y = UInt64((p.y * 1e10).rounded())
            let z = UInt64((p.z * 1e10).rounded())
            low = x | ((y & ((1 << 30) - 1)) << 34)
            high = (y >> 30) | (z << 4)
        }
        static func < (a: VertexKey, b: VertexKey) -> Bool {
            if a.x != b.x { return a.x < b.x }
            if a.y != b.y { return a.y < b.y }
            return a.z < b.z
        }
        var point: SIMD3<Double> { SIMD3(Double(x), Double(y), Double(z)) / 1e10 }
    }

    private struct PlaneKey: Hashable, Comparable {
        let x: Int64, y: Int64, z: Int64, d: Int64
        init(_ n: SIMD3<Double>, _ offset: Double) {
            x = Int64((n.x * 1e8).rounded()); y = Int64((n.y * 1e8).rounded())
            z = Int64((n.z * 1e8).rounded()); d = Int64((offset * 1e8).rounded())
        }
        static func < (a: PlaneKey, b: PlaneKey) -> Bool {
            if a.x != b.x { return a.x < b.x }
            if a.y != b.y { return a.y < b.y }
            if a.z != b.z { return a.z < b.z }
            return a.d < b.d
        }
    }

    private struct SegmentKey: Hashable {
        let a: VertexKey, b: VertexKey
        init(_ a: VertexKey, _ b: VertexKey) {
            self.a = min(a, b); self.b = max(a, b)
        }
    }

    private final class PlanarPatch {
        let normal: SIMD3<Double>
        let offset: Double
        let axis: Int
        var edges: [SegmentKey: BoundaryEdge] = [:]
        init(normal: SIMD3<Double>, offset: Double, axis: Int) {
            self.normal = normal; self.offset = offset; self.axis = axis
        }
    }

    private struct BoundaryEdge {
        private let bits: UInt8
        var forward: Bool { bits & 1 != 0 }
        var orientation: Int { bits & 2 != 0 ? 1 : -1 }
        init(forward: Bool, orientation: Int) {
            bits = (forward ? 1 : 0) | (orientation > 0 ? 2 : 0)
        }
    }

    private struct PatchEdge {
        let a: VertexKey, b: VertexKey
        let orientation: Int
    }

    private struct TriangleKey: Hashable {
        let a: Int, b: Int, c: Int
        init(_ a: Int, _ b: Int, _ c: Int) {
            let values = [a, b, c].sorted()
            self.a = values[0]; self.b = values[1]; self.c = values[2]
        }
    }

    private struct Triangle {
        var a: Int
        let b: Int, c: Int
    }

    private struct EdgeKey: Hashable {
        let a: Int, b: Int
        init(_ a: Int, _ b: Int) { self.a = min(a, b); self.b = max(a, b) }
    }

    private struct SurfaceBuilder {
        // Stream polygon boundary cancellation BEFORE allocating mesh vertices
        // or triangles. These limits include temporary partition boundaries.
        // Texture seam splitting downstream is consequently bounded too.
        static let maxBoundaryEdges = 1_500_000
        static let maxOutputTriangles = 150_000
        var patches: [PlaneKey: [PlanarPatch]] = [:]
        var boundaryEdgeCount = 0
        var peakBoundaryEdgeCount = 0
        var partitionVolume = 0.0
        var positions: [SIMD3<Double>] = []
        var vertexIndices: [VertexKey: Int] = [:]
        var triangles: [Triangle] = []
        var triangleIndices: [TriangleKey: Int] = [:]

        mutating func index(_ p: SIMD3<Double>) throws -> Int {
            let key = VertexKey(p)
            if let old = vertexIndices[key] { return old }
            guard positions.count < 150_000 else { throw HullError.resourceLimit }
            let i = positions.count
            positions.append(p); vertexIndices[key] = i
            return i
        }

        mutating func triangle(_ a: Int, _ b: Int, _ c: Int) throws {
            guard a != b, b != c, c != a else { return }
            let normal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            guard simd_length_squared(normal) > 1e-28 else { return }
            let key = TriangleKey(a, b, c)
            if let previous = triangleIndices.removeValue(forKey: key) {
                let old = triangles[previous]
                guard old.a >= 0,
                      (old.a == a && old.b == c) || (old.b == a && old.c == c) || (old.c == a && old.a == c) else {
                    throw HullError.nonManifold
                }
                triangles[previous].a = -1
            } else {
                triangleIndices[key] = triangles.count
                triangles.append(Triangle(a: a, b: b, c: c))
            }
            guard triangles.count <= Self.maxOutputTriangles, positions.count <= 150_000 else {
                throw HullError.resourceLimit
            }
        }

        private static func projection(_ p: SIMD3<Double>, axis: Int) -> SIMD2<Double> {
            if axis == 0 { return SIMD2(p.y, p.z) }
            if axis == 1 { return SIMD2(p.z, p.x) }
            return SIMD2(p.x, p.y)
        }

        private static func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            a.x * b.y - a.y * b.x
        }

        mutating func triangulate(_ source: [Int], axis: Int) throws {
            var ids = source
            let projected = source.map { Self.projection(positions[$0], axis: axis) }
            var signedArea = 0.0
            for i in projected.indices { signedArea += Self.cross(projected[i], projected[(i + 1) % projected.count]) }
            let orientation = signedArea >= 0 ? 1.0 : -1.0
            var checks = 0
            while ids.count > 3 {
                var ear: Int?
                for i in ids.indices {
                    let a = ids[(i + ids.count - 1) % ids.count], b = ids[i], c = ids[(i + 1) % ids.count]
                    let pa = Self.projection(positions[a], axis: axis)
                    let pb = Self.projection(positions[b], axis: axis)
                    let pc = Self.projection(positions[c], axis: axis)
                    let area = Self.cross(pb - pa, pc - pb) * orientation
                    guard area > 2e-10 * max(simd_length(pb - pa), simd_length(pc - pb), simd_length(pa - pc)) else { continue }
                    var blocked = false
                    for other in ids where other != a && other != b && other != c {
                        checks += 1
                        guard checks <= 50_000_000 else { throw HullError.resourceLimit }
                        let p = Self.projection(positions[other], axis: axis)
                        if Self.cross(pb - pa, p - pa) * orientation >= -2e-10 * simd_length(pb - pa) &&
                            Self.cross(pc - pb, p - pb) * orientation >= -2e-10 * simd_length(pc - pb) &&
                            Self.cross(pa - pc, p - pc) * orientation >= -2e-10 * simd_length(pa - pc) {
                            blocked = true; break
                        }
                    }
                    if !blocked { ear = i; break }
                }
                guard let ear else { throw HullError.nonManifold }
                try triangle(ids[(ear + ids.count - 1) % ids.count], ids[ear], ids[(ear + 1) % ids.count])
                ids.remove(at: ear)
            }
            if ids.count == 3 { try triangle(ids[0], ids[1], ids[2]) }
        }

        mutating func addPolygon(_ vertices: [ClipVertex]) throws {
            let points = vertices.map(\.p)
            for i in 1..<(points.count - 1) {
                partitionVolume += simd_dot(points[0], simd_cross(points[i], points[i + 1])) / 6
            }
            var normal = SIMD3<Double>(repeating: 0)
            for i in 1..<(points.count - 1) {
                let candidate = simd_cross(points[i] - points[0], points[i + 1] - points[0])
                if simd_length_squared(candidate) > simd_length_squared(normal) { normal = candidate }
            }
            guard simd_length_squared(normal) > 1e-28 else { return }
            let axis = (0..<3).max { abs(normal[$0]) < abs(normal[$1]) }!
            let orientation = normal[axis] > 0 ? 1 : -1
            normal /= normal[axis]
            let offset = -simd_dot(normal, points[0])
            let key = PlaneKey(normal, offset)
            var bucket = patches[key] ?? []
            // The hash is only a lookup accelerator, never permission to merge
            // distinct planes. Tolerances are numerical welding precision, NOT
            // an angle/contour simplification threshold.
            let patch: PlanarPatch
            if let match = bucket.first(where: { candidate in
                simd_length(normal - candidate.normal) < 1e-9 &&
                    points.allSatisfy { abs(simd_dot(candidate.normal, $0) + candidate.offset) < 2e-10 }
            }) {
                patch = match
            } else {
                guard patches.count < 20_000, bucket.count < 16 else { throw HullError.resourceLimit }
                patch = PlanarPatch(normal: normal, offset: offset, axis: axis)
                bucket.append(patch); patches[key] = bucket
            }
            let keys = points.map(VertexKey.init)
            for i in keys.indices {
                let a = keys[i], b = keys[(i + 1) % keys.count]
                if a == b { continue }
                let edge = SegmentKey(a, b), forward = a < b
                if let old = patch.edges.removeValue(forKey: edge) {
                    guard old.forward != forward else { throw HullError.nonManifold }
                    boundaryEdgeCount -= 1
                } else {
                    guard boundaryEdgeCount < Self.maxBoundaryEdges else { throw HullError.resourceLimit }
                    patch.edges[edge] = BoundaryEdge(forward: forward, orientation: orientation)
                    boundaryEdgeCount += 1
                    peakBoundaryEdgeCount = max(peakBoundaryEdgeCount, boundaryEdgeCount)
                }
            }
        }

        mutating func addTetrahedron(_ tetra: [ClipVertex]) throws {
            let constraints = tetra[0].fields.count
            for k in 0..<constraints where tetra.allSatisfy({ $0.fields[k] <= 0 }) { return }
            if tetra.allSatisfy({ $0.fields.allSatisfy { $0 > 0 } }) &&
                !tetra.contains(where: { p in (0..<3).contains { p.p[$0] == 0 || p.p[$0] == 1 } }) { return }
            var polygons: [Polygon] = []
            for opposite in 0..<4 {
                var face = tetra.indices.filter { $0 != opposite }.map { tetra[$0] }
                let n = simd_cross(face[1].p - face[0].p, face[2].p - face[0].p)
                if simd_dot(n, tetra[opposite].p - face[0].p) > 0 { face.swapAt(1, 2) }
                polygons.append(Polygon(vertices: face, constraint: -1))
            }
            for k in 0..<constraints {
                let values = polygons.flatMap { $0.vertices }.map { $0.fields[k] }
                if values.allSatisfy({ $0 >= -1e-13 }) { continue }
                if values.allSatisfy({ $0 <= 1e-13 }) { return }
                var clipped: [Polygon] = [], cap: [ClipVertex] = []
                for polygon in polygons {
                    var result: [ClipVertex] = []
                    for i in polygon.vertices.indices {
                        let a = polygon.vertices[i], b = polygon.vertices[(i + 1) % polygon.vertices.count]
                        let va = abs(a.fields[k]) < 1e-13 ? 0 : a.fields[k]
                        let vb = abs(b.fields[k]) < 1e-13 ? 0 : b.fields[k]
                        if va >= 0 { result.append(a) }
                        if (va < 0 && vb > 0) || (va > 0 && vb < 0) {
                            let cut = a.interpolated(to: b, t: va / (va - vb), constraint: k)
                            result.append(cut); cap.append(cut)
                        }
                        if va == 0 { cap.append(a) }
                    }
                    result = uniqueCycle(result)
                    if result.count >= 3 { clipped.append(Polygon(vertices: result, constraint: polygon.constraint)) }
                }
                var unique: [VertexKey: ClipVertex] = [:]
                for point in cap { unique[VertexKey(point.p)] = point }
                var ring = unique.sorted { $0.key < $1.key }.map { $0.value }
                if ring.count >= 3 {
                    let centre = ring.reduce(SIMD3<Double>(repeating: 0)) { $0 + $1.p } / Double(ring.count)
                    var normal = SIMD3<Double>(repeating: 0)
                    for i in 1..<(ring.count - 1) {
                        normal = simd_cross(ring[i].p - ring[0].p, ring[i + 1].p - ring[0].p)
                        if simd_length_squared(normal) > 1e-28 { break }
                    }
                    guard simd_length_squared(normal) > 1e-28 else { return }
                    normal = simd_normalize(normal)
                    let inside = clipped.flatMap { $0.vertices }.first { $0.fields[k] > 1e-12 }
                    if let inside, simd_dot(normal, inside.p - centre) > 0 { normal = -normal }
                    let u = simd_normalize(ring[0].p - centre), v = simd_cross(normal, u)
                    ring.sort {
                        let a = $0.p - centre, b = $1.p - centre
                        return atan2(simd_dot(a, v), simd_dot(a, u)) < atan2(simd_dot(b, v), simd_dot(b, u))
                    }
                    clipped.append(Polygon(vertices: ring, constraint: k))
                }
                polygons = clipped
                if polygons.isEmpty { return }
            }
            for polygon in polygons {
                // Original tetrahedron faces are emitted only when they lie
                // ON a constraint. All other partition faces are invisible.
                let onBoundary = polygon.constraint >= 0 || (0..<3).contains { axis in
                    polygon.vertices.allSatisfy { $0.p[axis] == 0 } ||
                        polygon.vertices.allSatisfy { $0.p[axis] == 1 }
                } || (0..<constraints).contains { k in
                    polygon.vertices.allSatisfy { abs($0.fields[k]) < 1e-12 }
                }
                guard onBoundary else { continue }
                try addPolygon(polygon.vertices)
            }
        }

        private func uniqueCycle(_ points: [ClipVertex]) -> [ClipVertex] {
            var result: [ClipVertex] = []
            for point in points where result.last.map({ VertexKey($0.p) != VertexKey(point.p) }) ?? true {
                result.append(point)
            }
            if result.count > 1, VertexKey(result[0].p) == VertexKey(result.last!.p) { result.removeLast() }
            return result
        }

        private static func isCollinear(_ previous: VertexKey, _ current: VertexKey, _ next: VertexKey) -> Bool {
            let a = current.point - previous.point, b = next.point - current.point
            let chord = next.point - previous.point
            let length = simd_length(chord)
            return length > 0 && simd_dot(a, b) >= 0 && simd_length(simd_cross(a, chord)) / length <= 2e-10
        }

        private static func area(_ loop: [VertexKey], axis: Int) -> Double {
            var sum = 0.0
            for i in loop.indices {
                sum += cross(projection(loop[i].point, axis: axis),
                             projection(loop[(i + 1) % loop.count].point, axis: axis))
            }
            return sum / 2
        }

        private static func contains(_ loop: [VertexKey], _ p: SIMD2<Double>, axis: Int) -> Bool {
            var inside = false
            for i in loop.indices {
                let a = projection(loop[i].point, axis: axis)
                let b = projection(loop[(i + 1) % loop.count].point, axis: axis)
                if (a.y > p.y) != (b.y > p.y) {
                    let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                    if p.x < x { inside.toggle() }
                }
            }
            return inside
        }

        private static func segmentsIntersect(_ p: SIMD2<Double>, _ q: SIMD2<Double>,
                                              _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
            if max(p.x, q.x) < min(a.x, b.x) || max(a.x, b.x) < min(p.x, q.x) ||
                max(p.y, q.y) < min(a.y, b.y) || max(a.y, b.y) < min(p.y, q.y) { return false }
            let c1 = cross(q - p, a - p), c2 = cross(q - p, b - p)
            let c3 = cross(b - a, p - a), c4 = cross(b - a, q - a)
            return (c1 <= 1e-18 && c2 >= -1e-18 || c2 <= 1e-18 && c1 >= -1e-18) &&
                (c3 <= 1e-18 && c4 >= -1e-18 || c4 <= 1e-18 && c3 >= -1e-18)
        }

        private static func bridge(_ outer: [VertexKey], holes: [[VertexKey]], axis: Int) throws -> [VertexKey] {
            var result = outer
            var work = 0
            for hole in holes {
                var selected: (outer: Int, hole: Int)?
                var best = Double.infinity
                for i in result.indices {
                    for j in hole.indices {
                        let pKey = result[i], qKey = hole[j]
                        let p = projection(pKey.point, axis: axis), q = projection(qKey.point, axis: axis)
                        let distance = simd_length_squared(p - q)
                        if distance >= best { continue }
                        let midpoint = (p + q) / 2
                        if !contains(outer, midpoint, axis: axis) ||
                            holes.contains(where: { contains($0, midpoint, axis: axis) }) { continue }
                        var visible = true
                        for boundary in [result] + holes {
                            for k in boundary.indices {
                                work += 1
                                guard work <= 20_000_000 else { throw HullError.resourceLimit }
                                let a = boundary[k], b = boundary[(k + 1) % boundary.count]
                                if a == pKey || b == pKey || a == qKey || b == qKey { continue }
                                if segmentsIntersect(p, q, projection(a.point, axis: axis), projection(b.point, axis: axis)) {
                                    visible = false; break
                                }
                            }
                            if !visible { break }
                        }
                        if visible { best = distance; selected = (i, j) }
                    }
                }
                guard let selected else { throw HullError.nonManifold }
                let i = selected.outer, j = selected.hole
                let rotated = Array(hole[j...]) + Array(hole[..<j]) + [hole[j]]
                result = Array(result[...i]) + rotated + [result[i]] + Array(result[(i + 1)...])
            }
            return result
        }

        private mutating func consolidate() throws {
            var groups: [(axis: Int, loops: [[VertexKey]])] = []
            var mandatory: Set<VertexKey> = []
            for key in patches.keys.sorted() {
                for patch in patches[key]! where !patch.edges.isEmpty {
                    var edges: [PatchEdge] = []
                    for (edge, data) in patch.edges {
                        edges.append(PatchEdge(a: data.forward ? edge.a : edge.b,
                                               b: data.forward ? edge.b : edge.a,
                                               orientation: data.orientation))
                    }
                    edges.sort { $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a }
                    var outgoing: [VertexKey: [Int]] = [:], incoming: [VertexKey: Int] = [:]
                    for i in edges.indices {
                        outgoing[edges[i].a, default: []].append(i)
                        incoming[edges[i].b, default: 0] += 1
                    }
                    guard outgoing.allSatisfy({ incoming[$0.key] == $0.value.count }) else { throw HullError.nonManifold }
                    for (vertex, choices) in outgoing where choices.count > 1 { mandatory.insert(vertex) }
                    var remaining = Set(edges.indices), loops: [[VertexKey]] = []
                    while let first = remaining.min() {
                        let start = edges[first].a
                        var loop: [VertexKey] = [], current = first
                        repeat {
                            guard remaining.remove(current) != nil else { throw HullError.nonManifold }
                            let edge = edges[current]
                            loop.append(edge.a)
                            if edge.b == start { break }
                            let choices = (outgoing[edge.b] ?? []).filter {
                                remaining.contains($0) && edges[$0].orientation == edge.orientation
                            }
                            guard !choices.isEmpty else { throw HullError.nonManifold }
                            let direction = Self.projection(edge.b.point - edge.a.point, axis: patch.axis)
                            current = choices.max { a, b in
                                func turn(_ i: Int) -> Double {
                                    let next = Self.projection(edges[i].b.point - edge.b.point, axis: patch.axis)
                                    return atan2(Self.cross(direction, next), simd_dot(direction, next)) * Double(edge.orientation)
                                }
                                let ta = turn(a), tb = turn(b)
                                return ta == tb ? a > b : ta < tb
                            }!
                        } while true
                        guard loop.count >= 3 else { throw HullError.nonManifold }
                        for i in loop.indices {
                            if !Self.isCollinear(loop[(i + loop.count - 1) % loop.count], loop[i], loop[(i + 1) % loop.count]) {
                                mandatory.insert(loop[i])
                            }
                        }
                        loops.append(loop)
                    }
                    groups.append((patch.axis, loops))
                    patch.edges.removeAll(keepingCapacity: false)
                }
            }
            patches.removeAll(keepingCapacity: false)
            // Remove a straight seam vertex ONLY if it is redundant on EVERY
            // incident planar patch. All corners/intersections stay shared,
            // preventing T-junctions without moving or decimating contours.
            for group in groups {
                let loops = group.loops.map { $0.filter { mandatory.contains($0) } }
                let areas = loops.map { Self.area($0, axis: group.axis) }
                guard loops.allSatisfy({ $0.count >= 3 && $0.count <= 10_000 }),
                      areas.allSatisfy({ abs($0) > 1e-20 }) else { throw HullError.nonManifold }
                var parents = [Int?](repeating: nil, count: loops.count)
                for i in loops.indices {
                    let longest = loops[i].indices.max { a, b in
                        simd_length_squared(loops[i][(a + 1) % loops[i].count].point - loops[i][a].point) <
                            simd_length_squared(loops[i][(b + 1) % loops[i].count].point - loops[i][b].point)
                    }!
                    let a = Self.projection(loops[i][longest].point, axis: group.axis)
                    let b = Self.projection(loops[i][(longest + 1) % loops[i].count].point, axis: group.axis)
                    let direction = b - a
                    let inward = SIMD2(-direction.y, direction.x) * (areas[i] > 0 ? 1 : -1)
                    // A vertex may be shared by disjoint coplanar regions.
                    // Classify nesting with an interior point, never that vertex.
                    var interior: SIMD2<Double>?
                    var step = 1e-7
                    for _ in 0..<8 {
                        let candidate = (a + b) / 2 + inward * step
                        if Self.contains(loops[i], candidate, axis: group.axis) { interior = candidate; break }
                        step /= 10
                    }
                    guard let p = interior else { throw HullError.nonManifold }
                    for j in loops.indices where i != j && abs(areas[j]) > abs(areas[i]) {
                        if Self.contains(loops[j], p, axis: group.axis),
                           parents[i].map({ abs(areas[j]) < abs(areas[$0]) }) ?? true { parents[i] = j }
                    }
                }
                for i in loops.indices {
                    var depth = 0, ancestor = parents[i]
                    while let parent = ancestor {
                        depth += 1; ancestor = parents[parent]
                        guard depth <= loops.count else { throw HullError.nonManifold }
                    }
                    if depth % 2 != 0 { continue }
                    let children = loops.indices.filter { parents[$0] == i }
                    guard children.allSatisfy({ areas[$0] * areas[i] < 0 }) else { throw HullError.nonManifold }
                    let polygon = try Self.bridge(loops[i], holes: children.map { loops[$0] }, axis: group.axis)
                    let ids = try polygon.map { try index($0.point) }
                    try triangulate(ids, axis: group.axis)
                }
            }
        }

        mutating func finish(widthCm: Double, depthCm: Double, heightCm: Double, offsetX: Float, offsetZ: Float)
            throws -> (vertices: [SIMD3<Float>], faces: [Int], volume: Double) {
            try consolidate()
            let active = triangles.filter { $0.a >= 0 }
            guard !active.isEmpty else { throw HullError.emptyIntersection }
            var remap: [Int: Int] = [:], vertices: [SIMD3<Float>] = [], faces: [Int] = []
            for tri in active {
                for old in [tri.a, tri.b, tri.c] {
                    if remap[old] == nil {
                        let p = positions[old]
                        let value = SIMD3<Float>(Float((p.x - 0.5) * widthCm / 100) + offsetX,
                                                 Float(p.y * heightCm / 100),
                                                 Float((p.z - 0.5) * depthCm / 100) + offsetZ)
                        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
                            throw HullError.invalidInput("metric_vertex_overflow")
                        }
                        remap[old] = vertices.count; vertices.append(value)
                    }
                    faces.append(remap[old]!)
                }
            }
            var edges: [EdgeKey: (count: Int, balance: Int)] = [:]
            var volume = 0.0
            // A local origin avoids translation-induced cancellation.
            let origin = SIMD3<Double>(vertices[0])
            for i in stride(from: 0, to: faces.count, by: 3) {
                let a = faces[i], b = faces[i + 1], c = faces[i + 2]
                let pa = SIMD3<Double>(vertices[a]) - origin
                let pb = SIMD3<Double>(vertices[b]) - origin
                let pc = SIMD3<Double>(vertices[c]) - origin
                guard simd_length_squared(simd_cross(pb - pa, pc - pa)) > 0 else {
                    throw HullError.invalidInput("metric_float_precision_loss")
                }
                volume += simd_dot(pa, simd_cross(pb, pc)) / 6
                for (u, v) in [(a, b), (b, c), (c, a)] {
                    let key = EdgeKey(u, v), old = edges[key] ?? (0, 0)
                    edges[key] = (old.count + 1, old.balance + (u < v ? 1 : -1))
                }
            }
            guard edges.values.allSatisfy({ $0.count == 2 && $0.balance == 0 }) else { throw HullError.nonManifold }
            guard volume.isFinite, volume > 0 else { throw HullError.emptyIntersection }
            let expectedCm3 = partitionVolume * widthCm * depthCm * heightCm
            guard expectedCm3.isFinite, expectedCm3 > 0,
                  abs(volume * 1_000_000 - expectedCm3) <= max(expectedCm3 * 5e-6, 1e-12) else {
                throw HullError.nonManifold
            }
            return (vertices, faces, volume * 1_000_000)
        }
    }
}
