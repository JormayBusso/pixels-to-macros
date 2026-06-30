import Foundation
import simd

/// Shared mesh post-processing used by BOTH the LiDAR (`DepthFusion`) and the
/// monocular (`MonocularVolumeEstimator`) reconstruction paths so a given food
/// renders with the SAME smooth look regardless of which sensor produced it.
/// LiDAR simply feeds a more accurate cage; the final surface treatment is
/// identical.
///
/// Two tools:
///   • `loopSubdivide` + `taubin` (via `smooth`) turn a coarse triangle cage
///     into a C²-ish organic surface — this is what removes the straight-line
///     facets the voxel/height-field cages leave behind (Loop subdivision is
///     the standard scheme for smooth triangle meshes).
///   • `roundBody` builds a clean parametric ellipsoid-of-revolution for foods
///     that are clearly round (a tomato, apple, orange…), so they reconstruct
///     as a smooth, consistent body every scan instead of a noisy measured hull.
enum MeshSmoothing {

    // MARK: – Round-food classification

    /// Foods that should reconstruct as an idealised smooth round body. Kept
    /// deliberately narrow (clearly spherical/ovoid produce) so irregular foods
    /// (bread, banana, chicken) still use their real measured silhouette.
    static func isClearlyRound(_ label: String) -> Bool {
        let l = label.lowercased()
        if l.contains("eggplant") { return false } // elongated, not round
        let round = [
            "tomato", "apple", "orange", "peach", "plum", "nectarine", "apricot",
            "mandarin", "clementine", "tangerine", "grapefruit", "lemon", "lime",
            "kiwi", "onion", "egg", "cherry", "grape", "melon", "cantaloupe",
        ]
        return round.contains { l.contains($0) }
    }

    // MARK: – Parametric round body (ellipsoid of revolution)

    /// A smooth closed ellipsoid. Half-extents come from the measured
    /// width/depth and height, so the silhouette (top-down ellipse) and the
    /// height both match the food while the surface is perfectly smooth and
    /// identical across scans. The center is explicit so the LiDAR path can
    /// place it at the cluster's real world position; the monocular path passes
    /// `centerY = halfHeightM` so the body rests on the plate (y = 0).
    static func roundBody(
        centerX: Float,
        centerY: Float,
        centerZ: Float,
        halfWidthM ax: Float,
        halfHeightM: Float,
        halfDepthM az: Float,
        longitude: Int = 48,
        latitude: Int = 24
    ) -> (vertices: [SIMD3<Float>], faces: [Int]) {
        let ay = max(Float(0.002), halfHeightM)
        let cx = centerX, cz = centerZ
        let cy = centerY
        let rings = max(3, latitude)
        let cols = max(4, longitude)

        var verts: [SIMD3<Float>] = []
        var idx = [[Int]](repeating: [Int](repeating: -1, count: cols), count: rings + 1)
        for i in 0...rings {
            let v = Float(i) / Float(rings)        // 0…1 (bottom→top)
            let phi = (-Float.pi / 2) + v * Float.pi // −π/2…π/2
            let sy = sin(phi), cyl = cos(phi)
            if i == 0 || i == rings {
                verts.append(SIMD3<Float>(cx, cy + ay * sy, cz)) // collapsed pole
                let p = verts.count - 1
                for j in 0..<cols { idx[i][j] = p }
                continue
            }
            for j in 0..<cols {
                let theta = Float(j) / Float(cols) * 2 * Float.pi
                verts.append(SIMD3<Float>(
                    cx + ax * cyl * cos(theta),
                    cy + ay * sy,
                    cz + az * cyl * sin(theta)
                ))
                idx[i][j] = verts.count - 1
            }
        }

        var faces: [Int] = []
        for i in 0..<rings {
            for j in 0..<cols {
                let j2 = (j + 1) % cols
                let a = idx[i][j], b = idx[i][j2]
                let c = idx[i + 1][j2], d = idx[i + 1][j]
                if i == 0 {
                    faces += [a, d, c] // bottom pole fan
                } else if i == rings - 1 {
                    faces += [a, b, c] // top pole fan
                } else {
                    faces += [a, b, c, a, c, d]
                }
            }
        }

        // Guarantee outward winding (SceneKit back-face culls): flip any
        // triangle whose normal points toward the body centre.
        let center = SIMD3<Float>(cx, cy, cz)
        var oriented: [Int] = []
        oriented.reserveCapacity(faces.count)
        var k = 0
        while k + 2 < faces.count {
            let i0 = faces[k], i1 = faces[k + 1], i2 = faces[k + 2]
            let p0 = verts[i0], p1 = verts[i1], p2 = verts[i2]
            let nrm = simd_cross(p1 - p0, p2 - p0)
            let cen = (p0 + p1 + p2) / 3
            if simd_dot(nrm, cen - center) >= 0 {
                oriented += [i0, i1, i2]
            } else {
                oriented += [i0, i2, i1]
            }
            k += 3
        }
        return (verts, oriented)
    }

    // MARK: – Smoothing (Loop subdivision + Taubin)

    /// Subdivide then Taubin-smooth a triangle mesh. The base (lowest few % of
    /// height) is pinned so the food stays grounded with a crisp footprint, and
    /// the result is re-grounded to y = 0 afterwards.
    static func smooth(
        vertices: [SIMD3<Float>],
        faces: [Int],
        subdivisionLevels: Int,
        taubinIterations: Int
    ) -> (vertices: [SIMD3<Float>], faces: [Int]) {
        var (v, f) = loopSubdivide(vertices: vertices, faces: faces, levels: subdivisionLevels)
        guard v.count > 4, f.count >= 3 else { return (v, f) }

        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        for p in v { minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let pinBelow = minY + max(Float(0.0006), (maxY - minY) * 0.03)
        var pinned = [Bool](repeating: false, count: v.count)
        for i in 0..<v.count where v[i].y <= pinBelow { pinned[i] = true }

        taubin(&v, faces: f, iterations: taubinIterations, pinned: pinned)

        var m = Float.greatestFiniteMagnitude
        for p in v { m = min(m, p.y) }
        if m != 0 { for i in 0..<v.count { v[i].y -= m } }
        return (v, f)
    }

    /// One or more levels of Loop subdivision on a triangle mesh.
    static func loopSubdivide(
        vertices vIn: [SIMD3<Float>],
        faces fIn: [Int],
        levels: Int
    ) -> (vertices: [SIMD3<Float>], faces: [Int]) {
        var verts = vIn
        var faces = fIn
        for _ in 0..<max(0, levels) {
            (verts, faces) = loopOnce(verts, faces)
        }
        return (verts, faces)
    }

    private struct Edge: Hashable {
        let a: Int
        let b: Int
        init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
    }

    private static func loopOnce(
        _ verts: [SIMD3<Float>],
        _ faces: [Int]
    ) -> ([SIMD3<Float>], [Int]) {
        let triCount = faces.count / 3
        guard triCount > 0 else { return (verts, faces) }

        // Edge → adjacent-triangle count + opposite vertices.
        var edgeFaceCount = [Edge: Int]()
        var edgeOpp = [Edge: [Int]]()
        @inline(__always) func record(_ x: Int, _ y: Int, _ o: Int) {
            let e = Edge(x, y)
            edgeFaceCount[e, default: 0] += 1
            edgeOpp[e, default: []].append(o)
        }
        for t in 0..<triCount {
            let a = faces[3 * t], b = faces[3 * t + 1], c = faces[3 * t + 2]
            record(a, b, c); record(b, c, a); record(c, a, b)
        }

        var neighbors = [Set<Int>](repeating: [], count: verts.count)
        var boundaryNeighbors = [Set<Int>](repeating: [], count: verts.count)
        var isBoundary = [Bool](repeating: false, count: verts.count)
        var newVerts = verts
        var edgePoint = [Edge: Int]()
        edgePoint.reserveCapacity(edgeFaceCount.count)

        for (e, count) in edgeFaceCount {
            neighbors[e.a].insert(e.b)
            neighbors[e.b].insert(e.a)
            let pa = verts[e.a], pb = verts[e.b]
            let opp = edgeOpp[e] ?? []
            let pos: SIMD3<Float>
            if count < 2 || opp.count < 2 {
                isBoundary[e.a] = true; isBoundary[e.b] = true
                boundaryNeighbors[e.a].insert(e.b)
                boundaryNeighbors[e.b].insert(e.a)
                pos = (pa + pb) * 0.5
            } else {
                let pc = verts[opp[0]], pd = verts[opp[1]]
                pos = (pa + pb) * (3.0 / 8.0) + (pc + pd) * (1.0 / 8.0)
            }
            edgePoint[e] = newVerts.count
            newVerts.append(pos)
        }

        // Reposition original vertices.
        for v in 0..<verts.count {
            if isBoundary[v] {
                let bn = boundaryNeighbors[v]
                if bn.count == 2 {
                    var s = SIMD3<Float>(repeating: 0)
                    for j in bn { s += verts[j] }
                    newVerts[v] = verts[v] * (3.0 / 4.0) + s * (1.0 / 8.0)
                }
            } else {
                let nb = neighbors[v]
                let n = nb.count
                if n >= 3 {
                    let fn = Float(n)
                    let t = (3.0 / 8.0) + (1.0 / 4.0) * cos(2.0 * Float.pi / fn)
                    let beta = (1.0 / fn) * ((5.0 / 8.0) - t * t)
                    var s = SIMD3<Float>(repeating: 0)
                    for j in nb { s += verts[j] }
                    newVerts[v] = verts[v] * (1.0 - beta * fn) + s * beta
                }
            }
        }

        var newFaces: [Int] = []
        newFaces.reserveCapacity(faces.count * 4)
        for t in 0..<triCount {
            let a = faces[3 * t], b = faces[3 * t + 1], c = faces[3 * t + 2]
            guard let ab = edgePoint[Edge(a, b)],
                  let bc = edgePoint[Edge(b, c)],
                  let ca = edgePoint[Edge(c, a)] else { continue }
            newFaces += [a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]
        }
        return (newVerts, newFaces)
    }

    /// Shrink-free Taubin smoothing (alternating λ / μ Laplacian passes).
    /// Pinned vertices never move.
    static func taubin(
        _ verts: inout [SIMD3<Float>],
        faces: [Int],
        iterations: Int,
        lambda: Float = 0.5,
        mu: Float = -0.53,
        pinned: [Bool]
    ) {
        let n = verts.count
        guard n > 4, faces.count >= 3 else { return }
        var adjacency = [[Int]](repeating: [], count: n)
        var seen = [Set<Int>](repeating: [], count: n)
        @inline(__always) func link(_ a: Int, _ b: Int) {
            guard a != b, a >= 0, a < n, b >= 0, b < n else { return }
            if !seen[a].contains(b) { seen[a].insert(b); adjacency[a].append(b) }
        }
        var i = 0
        while i + 2 < faces.count {
            let a = faces[i], b = faces[i + 1], c = faces[i + 2]
            link(a, b); link(a, c)
            link(b, a); link(b, c)
            link(c, a); link(c, b)
            i += 3
        }
        var scratch = verts
        @inline(__always) func pass(_ factor: Float) {
            for v in 0..<n {
                if v < pinned.count && pinned[v] { scratch[v] = verts[v]; continue }
                let nb = adjacency[v]
                if nb.isEmpty { scratch[v] = verts[v]; continue }
                var sum = SIMD3<Float>(repeating: 0)
                for j in nb { sum += verts[j] }
                let avg = sum / Float(nb.count)
                scratch[v] = verts[v] + (avg - verts[v]) * factor
            }
            swap(&verts, &scratch)
        }
        for _ in 0..<max(0, iterations) {
            pass(lambda)
            pass(mu)
        }
    }
}
