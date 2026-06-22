import ARKit
import CoreVideo
import Foundation
import simd

/// Fuses depth maps from multiple ARKit frames into a sparse 3-D voxel grid,
/// then back-projects the top-frame segmentation to label each occupied voxel.
///
/// Coordinate convention
/// ─────────────────────
/// Voxel keys use ARKit world-space coordinates divided by `voxelSizeM`.
/// Camera intrinsics follow the ARKit convention: (0,0) is top-left of the
/// captured image, y increases downward — identical to CVPixelBuffer memory
/// layout. This matches the coordinate system used by `PlateDetector` and
/// `FramePreprocessor`, so no extra flipping is required.
final class DepthFusion {

    // MARK: – Configuration

    /// Side length of one voxel in metres. 0.01 m = 1 cm.
    private let voxelSizeM: Float = 0.01

    // MARK: – Internal types

    struct VoxelKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }

    /// Voxel values:  nil = empty, 0 = occupied-unlabelled, >0 = label index.
    private var grid: [VoxelKey: Int32] = [:]

    /// Label string → label index mapping (1-based).
    private(set) var labelMap: [String: Int32] = [:]
    private var nextLabel: Int32 = 1

    // MARK: – Depth integration

    /// Project one depth map into world space and mark occupied voxels.
    ///
    /// Samples every `stride` pixel to keep processing time bounded.
    func integrate(
        depthBuffer:      CVPixelBuffer,
        cameraTransform:  simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageWidth:  Int,
        imageHeight: Int,
        stride:      Int = 3
    ) {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let dW        = CVPixelBufferGetWidth(depthBuffer)
        let dH        = CVPixelBufferGetHeight(depthBuffer)
        let rowBytes  = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return }
        let ptr          = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = rowBytes / MemoryLayout<Float32>.stride

        // Scale intrinsics from full image resolution to depth-map resolution.
        let sx = Float(dW) / Float(imageWidth)
        let sy = Float(dH) / Float(imageHeight)
        let fx = cameraIntrinsics.columns.0.x * sx
        let fy = cameraIntrinsics.columns.1.y * sy
        let cx = cameraIntrinsics.columns.2.x * sx
        let cy = cameraIntrinsics.columns.2.y * sy
        guard abs(fx) > 0.0001, abs(fy) > 0.0001 else { return }

        for row in Swift.stride(from: 0, to: dH, by: stride) {
            for col in Swift.stride(from: 0, to: dW, by: stride) {
                let d = ptr[row * floatsPerRow + col]
                // Accept 5 cm – 150 cm range (discard sky / very close noise).
                guard d > 0.05 && d < 1.5 else { continue }

                // Back-project to camera space.
                // ARKit sceneDepth gives z-distance in metres.
                let xc = (Float(col) - cx) / fx * d
                let yc = (Float(row) - cy) / fy * d
                let zc = d

                // Transform to world space.
                let pw = cameraTransform * simd_float4(xc, yc, zc, 1)

                // Convert to integer voxel key.
                let vx = Int32((pw.x / voxelSizeM).rounded(.towardZero))
                let vy = Int32((pw.y / voxelSizeM).rounded(.towardZero))
                let vz = Int32((pw.z / voxelSizeM).rounded(.towardZero))

                let key = VoxelKey(x: vx, y: vy, z: vz)
                if grid[key] == nil {
                    grid[key] = 0   // occupied, not yet labelled
                }
            }
        }
    }

    // MARK: – Label assignment

    /// Project segmentation masks from the top frame back onto occupied voxels.
    ///
    /// - Parameters:
    ///   - segments:            Segmented objects (each has `.label` and `.mask[row][col]`).
    ///   - plateRect:           Normalised plate bounding rect in the top frame
    ///                          (**top-left origin**, same as `PlateDetector` output).
    ///   - topFrameTransform:   Camera-to-world 4×4 for the top frame.
    ///   - topFrameIntrinsics:  3×3 camera intrinsics for the full-resolution top frame.
    ///   - maskWidth/Height:    Dimensions of the segmentation output mask (model input size).
    ///   - imageWidth/Height:   Dimensions of the top frame's RGB pixel buffer.
    func assignLabels(
        segments:          [SegmentationService.SegmentedObject],
        plateRect:         CGRect,
        topFrameTransform: simd_float4x4,
        topFrameIntrinsics: simd_float3x3,
        topDepthBuffer:    CVPixelBuffer? = nil,
        maskWidth:  Int,
        maskHeight: Int,
        imageWidth:  Int,
        imageHeight: Int
    ) {
        // Build label index map.
        for seg in segments {
            if labelMap[seg.label] == nil {
                labelMap[seg.label] = nextLabel
                nextLabel += 1
            }
        }

        // Flatten all masks into a single pixel-label array at mask resolution.
        var combinedMask = [Int32](repeating: 0, count: maskWidth * maskHeight)
        for seg in segments {
            let lIdx = labelMap[seg.label]!
            for r in 0..<maskHeight {
                for c in 0..<maskWidth {
                    if seg.mask[r][c] == 1 && combinedMask[r * maskWidth + c] == 0 {
                        combinedMask[r * maskWidth + c] = lIdx
                    }
                }
            }
        }

        // Camera intrinsics for the full-resolution top frame.
        let fx = topFrameIntrinsics.columns.0.x
        let fy = topFrameIntrinsics.columns.1.y
        let cx = topFrameIntrinsics.columns.2.x
        let cy = topFrameIntrinsics.columns.2.y

        // World → camera transform (inverse of camera-to-world).
        let camInv = topFrameTransform.inverse

        // Plate rect in normalised top-left-origin coordinates.
        let pRx = Float(plateRect.minX)
        let pRy = Float(plateRect.minY)
        let pRw = Float(plateRect.width)
        let pRh = Float(plateRect.height)
        guard pRw > 0.001 && pRh > 0.001 else { return }

        var topDepthPtr: UnsafeMutablePointer<Float32>?
        var topDepthWidth = 0
        var topDepthHeight = 0
        var topDepthFloatsPerRow = 0
        if let topDepthBuffer {
            CVPixelBufferLockBaseAddress(topDepthBuffer, .readOnly)
            topDepthWidth = CVPixelBufferGetWidth(topDepthBuffer)
            topDepthHeight = CVPixelBufferGetHeight(topDepthBuffer)
            topDepthFloatsPerRow = CVPixelBufferGetBytesPerRow(topDepthBuffer) /
                MemoryLayout<Float32>.stride
            topDepthPtr = CVPixelBufferGetBaseAddress(topDepthBuffer)?
                .assumingMemoryBound(to: Float32.self)
        }
        defer {
            if let topDepthBuffer {
                CVPixelBufferUnlockBaseAddress(topDepthBuffer, .readOnly)
            }
        }

        // Collect pending label assignments — mutating a Dictionary during
        // for-in enumeration is undefined behaviour in Swift (can crash).
        var pendingLabels: [(key: VoxelKey, label: Int32)] = []

        for (key, value) in grid {
            guard value == 0 else { continue }   // skip already-labelled voxels

            // Voxel centre in world space.
            let wx = (Float(key.x) + 0.5) * voxelSizeM
            let wy = (Float(key.y) + 0.5) * voxelSizeM
            let wz = (Float(key.z) + 0.5) * voxelSizeM

            // Transform to top-frame camera space.
            let cam = camInv * simd_float4(wx, wy, wz, 1)
            guard cam.z > 0 else { continue }   // behind camera

            // Project to full-image pixel (top-left origin, y ↓).
            let u_px = fx * cam.x / cam.z + cx
            let v_px = fy * cam.y / cam.z + cy

            // Normalise to [0, 1].
            let u_n = u_px / Float(imageWidth)
            let v_n = v_px / Float(imageHeight)
            guard u_n >= 0 && u_n < 1 && v_n >= 0 && v_n < 1 else { continue }

            // Map into plate crop region (same top-left-origin convention).
            let pu = (u_n - pRx) / pRw
            let pv = (v_n - pRy) / pRh
            guard pu >= 0 && pu < 1 && pv >= 0 && pv < 1 else { continue }

            // Map to segmentation mask pixel.
            let mu = Int(pu * Float(maskWidth))
            let mv = Int(pv * Float(maskHeight))
            guard mu >= 0 && mu < maskWidth && mv >= 0 && mv < maskHeight else { continue }

            let label = combinedMask[mv * maskWidth + mu]
            if label > 0 {
                if let topDepthPtr, topDepthWidth > 0, topDepthHeight > 0 {
                    let du = min(max(Int(u_n * Float(topDepthWidth)), 0), topDepthWidth - 1)
                    let dv = min(max(Int(v_n * Float(topDepthHeight)), 0), topDepthHeight - 1)
                    let topDepth = topDepthPtr[dv * topDepthFloatsPerRow + du]
                    if topDepth > 0.05 && topDepth < 1.5 {
                        let delta = cam.z - topDepth
                        guard delta >= -0.025 && delta <= 0.08 else { continue }
                    }
                }
                pendingLabels.append((key: key, label: label))
            }
        }

        // Apply collected labels now that enumeration is complete.
        for pending in pendingLabels {
            grid[pending.key] = pending.label
        }
        let labelledCount = grid.values.filter { $0 > 0 }.count
        print("[SCAN] assignLabels: pendingAssigned=\(pendingLabels.count), totalLabelled=\(labelledCount), totalGrid=\(grid.count), labelMap=\(labelMap)")
    }

    // MARK: – Volume queries

    /// Volume in cm³ for a named food label, summed over every connected
    /// instance of that label that passes the plate-subtraction + minimum-
    /// voxel-count gate. This is the canonical number — it MUST be used in
    /// preference to `allVolumes()` in any code path that also consumes the
    /// 3-D export, otherwise mesh and macro numbers will diverge.
    func clusterVolumes(minVoxelCount: Int = DepthFusion.defaultMinVoxelsPerCluster) -> [String: Double] {
        var result: [String: Double] = [:]
        for cluster in voxelClusters(minVoxelCount: minVoxelCount) {
            result[cluster.label, default: 0] += cluster.volumeCm3
        }
        return result
    }

    /// Volume in cm³ for a named food label, derived from the RAW labelled
    /// voxel count (no plate subtraction, no instance gating). Kept for
    /// legacy callers and debug instrumentation only — production volume
    /// math should use `clusterVolumes()`.
    func volume(for label: String) -> Double {
        guard let lIdx = labelMap[label] else { return 0 }
        let count = grid.values.filter { $0 == lIdx }.count
        let s = Double(voxelSizeM * 100)
        return Double(count) * s * s * s
    }

    /// Raw per-label volumes (no plate subtraction). See `clusterVolumes()`.
    func allVolumes() -> [String: Double] {
        let s = Double(voxelSizeM * 100)
        let voxVol = s * s * s

        // Single O(V) pass: count occupied voxels per label index.
        var counts: [Int32: Int] = [:]
        for v in grid.values where v > 0 {
            counts[v, default: 0] += 1
        }

        // Build reverse map for O(1) label lookup.
        let indexToLabel = Dictionary(uniqueKeysWithValues: labelMap.map { ($1, $0) })

        var result: [String: Double] = [:]
        for (lIdx, count) in counts {
            if let label = indexToLabel[lIdx] {
                result[label] = Double(count) * voxVol
            }
        }
        return result
    }

    /// Total number of occupied voxels (labelled or unlabelled).
    /// Every entry in `grid` is an occupied voxel (values are 0 or a positive
    /// label index — never negative), so this is simply the map's size.
    var totalOccupiedVoxels: Int {
        grid.count
    }

    func reset() {
        grid.removeAll()
        labelMap.removeAll()
        nextLabel = 1
    }

    // MARK: – 3-D export (Stage 1+ hardened)
    //
    // Contract — these invariants are enforced in code and MUST hold:
    //   1. The SAME voxel set is the source of truth for both volume math
    //      (`clusterVolumes()`) and mesh export (`exportFoodObjects()`).
    //   2. Per-food separation is decided at the VOXEL level (connected
    //      components per label), not at the mesh / SceneKit level.
    //      Clusters are never merged downstream.
    //   3. Plate / table leakage is removed by `voxelClusters()` BEFORE
    //      either volume or mesh is derived from a cluster.
    //   4. Vertex colours are sampled only from the top-view pixel buffer.
    //   5. Each cluster passes through Surface Nets exactly once per scan.

    /// Minimum number of **measured surface** voxels a cluster must contain
    /// before it is solidified and exported. This is a noise floor applied to
    /// the raw depth shell (NOT the final volume): clusters with fewer skin
    /// voxels than this are almost always mis-segmentation or sensor noise.
    /// The reported `volumeCm3` is derived AFTER column solidification, so it
    /// is typically much larger than this count.
    static let defaultMinVoxelsPerCluster = 200

    /// Stable, post-plate-subtraction voxel cluster — one per food instance.
    /// A label like `"rice"` that appears as two physically separated piles
    /// produces two clusters: `rice_0` and `rice_1`.
    struct FoodVoxelCluster {
        /// Stable identifier of the form `"<label>_<instanceIndex>"`.
        let id: String
        let label: String
        let instanceIndex: Int
        /// Voxel keys in the ARKit world-space integer grid, AFTER plate
        /// subtraction AND column solidification. These are no longer the raw
        /// measured depth shell — every (x,z) column has been filled from the
        /// plate plane up to the measured surface so the set represents the
        /// solid food body, not just its visible skin.
        let voxelKeys: [VoxelKey]
        /// Volume in cm³, derived ONLY from `voxelKeys.count × voxelSize³`
        /// (i.e. the solidified column count, a true volume — not surface area).
        let volumeCm3: Double
    }

    /// One reconstructed food object: per-instance voxel cluster turned into
    /// a triangle mesh with per-vertex RGB colours sampled from the top
    /// frame. `volumeCm3` mirrors the source cluster's volume exactly.
    struct Food3DObject {
        /// Same stable id as the source `FoodVoxelCluster`.
        let id: String
        let label: String
        let instanceIndex: Int
        /// Vertex positions in ARKit world space (metres, +Y up).
        let vertices: [SIMD3<Float>]
        /// Triangle indices into `vertices` (length is multiple of 3).
        let faces: [Int]
        /// Per-vertex RGB, length == vertices.count * 3.
        let colors: [UInt8]
        /// Per-vertex texture coordinates (USD `st`, bottom-left origin),
        /// length == vertices.count. Projected from the top frame so the
        /// exporter can bake the real RGB photo onto the mesh as a baseColor
        /// texture — USDZ/RealityKit ignore per-vertex colours, which (together
        /// with the planar-YCbCr `capturedImage` defeating BGRA colour
        /// sampling) is why meshes rendered grey.
        let uvs: [SIMD2<Float>]
        /// Number of occupied voxels backing this object (post plate
        /// subtraction). Mirrors the source `FoodVoxelCluster.voxelKeys.count`
        /// so debug overlays can show voxel density alongside volume.
        let voxelCount: Int
        let volumeCm3: Double
    }

    /// Canonical clustering step. Performs (in order):
    ///   1. Bucket occupied voxels by class label.
    ///   2. Subtract plate / table leakage: estimate a plate plane Y from
    ///      the 5th percentile of food-voxel Y values (ARKit +Y is up, so
    ///      the LOWEST Y values are the plate). Any voxel whose centre lies
    ///      more than ε below this plane is discarded as noise.
    ///   3. Per label, split voxels into 6-connected components — every
    ///      component is a separate food instance.
    ///   4. Drop components whose measured surface shell is smaller than
    ///      `minVoxelCount` (noise gate, applied BEFORE solidification).
    ///   5. Solidify each surviving component: fill every (x,z) column from
    ///      the plate plane up to the measured surface so the cluster is a
    ///      true solid volume rather than a hollow depth shell.
    ///
    /// The returned clusters are the ONLY input to mesh export and
    /// canonical volume math.
    func voxelClusters(minVoxelCount: Int = defaultMinVoxelsPerCluster) -> [FoodVoxelCluster] {
        // 1. Bucket by class label.
        var keysByLabel: [Int32: [VoxelKey]] = [:]
        for (key, label) in grid where label > 0 {
            keysByLabel[label, default: []].append(key)
        }
        print("[SCAN] voxelClusters: totalOccupied=\(grid.count), labelled=\(keysByLabel.values.reduce(0) { $0 + $1.count }), labels=\(keysByLabel.count), minVoxelCount=\(minVoxelCount)")
        guard !keysByLabel.isEmpty else {
            print("[SCAN] voxelClusters: NO labelled voxels — returning empty")
            return []
        }

        // 2. Plate-plane subtraction.
        // Find the lowest stable Y across ALL labelled voxels (the plate
        // top) and drop anything more than `plateEpsilonVoxels` below it.
        let allKeys = keysByLabel.values.flatMap { $0 }
        let platePlaneVoxelY: Int32 = robustMinY(of: allKeys, percentile: 0.05)
        // ε = 1 voxel below the estimated plate plane. Voxels strictly
        // below this line are reflections / table noise.
        let plateCutoffY: Int32 = platePlaneVoxelY - 1

        let indexToName = Dictionary(uniqueKeysWithValues: labelMap.map { ($1, $0) })
        let voxVolCm3 = pow(Double(voxelSizeM * 100), 3)

        print("[SCAN] voxelClusters: plateCutoffY=\(plateCutoffY), platePlaneVoxelY=\(platePlaneVoxelY)")

        var clusters: [FoodVoxelCluster] = []
        // Deterministic ordering so cluster IDs are stable across runs with
        // identical input — Dictionary iteration order is not deterministic.
        let sortedLabelIdxs = keysByLabel.keys.sorted()
        for labelIdx in sortedLabelIdxs {
            guard let label = indexToName[labelIdx] else { continue }
            let rawKeys = keysByLabel[labelIdx] ?? []
            let pruned = rawKeys.filter { $0.y >= plateCutoffY }
            print("[SCAN] voxelClusters: label=\(label) raw=\(rawKeys.count) afterPlateSubtraction=\(pruned.count) threshold=\(minVoxelCount)")
            guard pruned.count >= minVoxelCount else {
                print("[SCAN] voxelClusters: DROPPED label=\(label) (\(pruned.count) < \(minVoxelCount))")
                continue
            }

            // 3. Connected components → per-instance clusters.
            let components = connectedComponents(of: pruned)
            print("[SCAN] voxelClusters: label=\(label) components=\(components.count) sizes=\(components.map { $0.count }.sorted(by: >).prefix(5))")
            // Largest-first so `instanceIndex = 0` is the dominant instance.
            let sorted = components.sorted { $0.count > $1.count }
            var instanceIndex = 0
            for comp in sorted {
                // Noise gate on the raw surface shell, BEFORE solidification.
                guard comp.count >= minVoxelCount else {
                    print("[SCAN] voxelClusters: DROPPED component \(label)_\(instanceIndex) (\(comp.count) < \(minVoxelCount))")
                    continue
                }
                // 5. Solidify: turn the measured depth shell into a true solid
                //    by integrating height per (x,z) column from the plate
                //    plane up to the surface. This is the source of truth for
                //    BOTH volume and the Surface-Nets mesh (contract rule #1).
                let solid = solidifyColumns(comp, platePlaneY: platePlaneVoxelY)
                guard !solid.isEmpty else { continue }
                let id = "\(label)_\(instanceIndex)"
                clusters.append(FoodVoxelCluster(
                    id: id,
                    label: label,
                    instanceIndex: instanceIndex,
                    voxelKeys: solid,
                    volumeCm3: Double(solid.count) * voxVolCm3
                ))
                instanceIndex += 1
            }
        }
        return clusters
    }

    /// Group occupied voxels into instance-level clusters (after plate
    /// subtraction), turn each into a Surface-Nets mesh, and sample per-
    /// vertex colours from the top frame.
    ///
    /// - Important: this method must NEVER re-derive voxel data — it is
    ///   strictly a consumer of `voxelClusters()`. See the contract above.
    ///
    /// - Parameters:
    ///   - topPixelBuffer: Top-frame BGRA buffer used for per-vertex color
    ///     sampling. Pass `nil` to skip coloring (vertices fall back to grey).
    ///     Colour sampling is LOCKED to this buffer — never blend across
    ///     frames, never re-sample in a later pass.
    ///   - topTransform/topIntrinsics/imageWidth/imageHeight: Same projection
    ///     parameters used by `assignLabels` — they MUST be the top frame's
    ///     full-resolution values so reprojection lines up with the camera.
    ///   - minVoxelCount: forwarded to `voxelClusters()`.
    func exportFoodObjects(
        topPixelBuffer: CVPixelBuffer?,
        topTransform: simd_float4x4,
        topIntrinsics: simd_float3x3,
        imageWidth: Int,
        imageHeight: Int,
        minVoxelCount: Int = defaultMinVoxelsPerCluster
    ) -> [Food3DObject] {
        // Single source of truth: clusters drive both volume + mesh output.
        let clusters = voxelClusters(minVoxelCount: minVoxelCount)
        guard !clusters.isEmpty else { return [] }

        // Lock the top frame's BGRA buffer once for colour sampling.
        // Sampling source is locked to topFrame — see contract rule #4.
        // ARKit's capturedImage is planar YCbCr, so reading it directly as BGRA
        // returns a nil base address and every vertex falls back to grey. Decode
        // to BGRA once so we sample the real food colour.
        let colorBuffer = topPixelBuffer.flatMap { Food3DTextureBaker.bgraCopy(of: $0) }
        var bgraBase: UnsafePointer<UInt8>?
        var bgraWidth = 0
        var bgraHeight = 0
        var bgraRowBytes = 0
        if let buffer = colorBuffer {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            bgraWidth = CVPixelBufferGetWidth(buffer)
            bgraHeight = CVPixelBufferGetHeight(buffer)
            bgraRowBytes = CVPixelBufferGetBytesPerRow(buffer)
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                bgraBase = UnsafePointer(base.assumingMemoryBound(to: UInt8.self))
            }
        }
        defer {
            if let buffer = colorBuffer {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            }
        }

        let camInv = topTransform.inverse
        let fx = topIntrinsics.columns.0.x
        let fy = topIntrinsics.columns.1.y
        let cx = topIntrinsics.columns.2.x
        let cy = topIntrinsics.columns.2.y
        let canProject = bgraBase != nil && bgraWidth > 0 && bgraHeight > 0
            && abs(fx) > 0.0001 && abs(fy) > 0.0001

        var objects: [Food3DObject] = []
        objects.reserveCapacity(clusters.count)

        for cluster in clusters {
            // Exactly ONE Surface Nets pass per cluster per scan.
            let mesh = SurfaceNets.build(voxels: cluster.voxelKeys, voxelSizeM: voxelSizeM)
            guard !mesh.vertices.isEmpty, mesh.faces.count >= 3 else { continue }

            var colors = [UInt8](repeating: 200, count: mesh.vertices.count * 3)
            if canProject, let ptr = bgraBase {
                for i in 0..<mesh.vertices.count {
                    let v = mesh.vertices[i]
                    let cam = camInv * simd_float4(v.x, v.y, v.z, 1)
                    guard cam.z > 0.001 else { continue }
                    let u = Int((fx * cam.x / cam.z + cx).rounded())
                    let vpx = Int((fy * cam.y / cam.z + cy).rounded())
                    guard u >= 0, u < bgraWidth, vpx >= 0, vpx < bgraHeight else { continue }
                    let off = vpx * bgraRowBytes + u * 4
                    // ARKit `capturedImage` is BGRA8.
                    colors[i * 3 + 0] = ptr[off + 2]
                    colors[i * 3 + 1] = ptr[off + 1]
                    colors[i * 3 + 2] = ptr[off + 0]
                }
            }

            // Per-vertex UVs: project each world vertex into the top frame so
            // the exporter can bake the real RGB photo as a baseColor texture.
            // Independent of the (BGRA) colour path above — UVs need only the
            // camera projection, so they work even when colour sampling can't
            // read the planar YCbCr buffer.
            var uvs = [SIMD2<Float>](repeating: SIMD2(0.5, 0.5),
                                     count: mesh.vertices.count)
            if abs(fx) > 0.0001, abs(fy) > 0.0001, imageWidth > 0, imageHeight > 0 {
                let iw = Float(imageWidth)
                let ih = Float(imageHeight)
                for i in 0..<mesh.vertices.count {
                    let v = mesh.vertices[i]
                    let cam = camInv * simd_float4(v.x, v.y, v.z, 1)
                    guard cam.z > 0.001 else { continue }
                    let upx = fx * cam.x / cam.z + cx
                    let vpx = fy * cam.y / cam.z + cy
                    let uu = min(max(upx / iw, 0), 1)
                    let vv = min(max(vpx / ih, 0), 1)
                    uvs[i] = SIMD2(uu, 1 - vv) // USD `st` origin is bottom-left
                }
            }

            objects.append(Food3DObject(
                id: cluster.id,
                label: cluster.label,
                instanceIndex: cluster.instanceIndex,
                vertices: mesh.vertices,
                faces: mesh.faces,
                colors: colors,
                uvs: uvs,
                voxelCount: cluster.voxelKeys.count,
                volumeCm3: cluster.volumeCm3
            ))
        }
        return objects
    }

    // MARK: – Cluster helpers (plate plane + solidify + connected components)

    /// Sparse (x, z) column identifier used by `solidifyColumns`.
    private struct ColumnKey: Hashable {
        let x: Int32
        let z: Int32
    }

    /// Convert a measured depth **shell** of voxels into a **solid** body by
    /// filling every (x, z) column from the plate plane up to the highest
    /// occupied voxel in that column (reference-plane height integration).
    ///
    /// Why this is necessary
    /// ─────────────────────
    /// A depth sensor only ever measures the *visible skin* of the food — the
    /// interior and the underside resting on the plate are never seen. Counting
    /// only those skin voxels makes volume scale with surface AREA, so a flat
    /// layer and a tall mound with the same footprint score almost identical
    /// volumes. Filling each column from the plate up to the measured surface
    /// reconstructs the solid between plate and skin, which is the quantity
    /// that maps to mass → calories.
    ///
    /// - Parameters:
    ///   - keys: surface voxels of a single connected food instance.
    ///   - platePlaneY: integer voxel Y of the estimated plate top (the food's
    ///     resting plane), produced by `robustMinY` in `voxelClusters`.
    /// - Returns: the filled, solid voxel set (always a superset of `keys`).
    private func solidifyColumns(_ keys: [VoxelKey], platePlaneY: Int32) -> [VoxelKey] {
        guard !keys.isEmpty else { return keys }

        // Highest measured voxel per (x, z) column = the food's top surface.
        var topYByColumn: [ColumnKey: Int32] = [:]
        topYByColumn.reserveCapacity(keys.count)
        for k in keys {
            let col = ColumnKey(x: k.x, z: k.z)
            if let top = topYByColumn[col] {
                if k.y > top { topYByColumn[col] = k.y }
            } else {
                topYByColumn[col] = k.y
            }
        }

        var filled: [VoxelKey] = []
        filled.reserveCapacity(keys.count * 3)
        for (col, topY) in topYByColumn {
            // The food sits on the plate, so each column starts at the plate
            // plane. Guard against the rare column whose surface dips a voxel
            // below the robust plate estimate.
            let bottomY = Swift.min(platePlaneY, topY)
            var y = bottomY
            while y <= topY {
                filled.append(VoxelKey(x: col.x, y: y, z: col.z))
                y += 1
            }
        }
        return filled
    }

    /// Robust lower-bound estimator on the Y coordinate of a voxel set. Sorts
    /// the Y values and returns the value at `percentile` (0…1). With
    /// `percentile = 0.05` and clean data this approximates the plate top.
    private func robustMinY(of keys: [VoxelKey], percentile: Double) -> Int32 {
        guard !keys.isEmpty else { return 0 }
        let ys = keys.map { $0.y }.sorted()
        let idx = min(ys.count - 1, max(0, Int(Double(ys.count - 1) * percentile)))
        return ys[idx]
    }

    /// 6-connected (face-adjacent) connected-components labelling on a
    /// sparse voxel set. Returns the components in input-order (largest is
    /// re-sorted by the caller).
    private func connectedComponents(of keys: [VoxelKey]) -> [[VoxelKey]] {
        if keys.isEmpty { return [] }
        let set = Set(keys)
        var visited = Set<VoxelKey>()
        visited.reserveCapacity(keys.count)
        var components: [[VoxelKey]] = []

        let neighbours: [(Int32, Int32, Int32)] = [
            ( 1, 0, 0), (-1, 0, 0),
            ( 0, 1, 0), ( 0,-1, 0),
            ( 0, 0, 1), ( 0, 0,-1),
        ]

        for seed in keys where !visited.contains(seed) {
            var stack: [VoxelKey] = [seed]
            var component: [VoxelKey] = []
            visited.insert(seed)
            while let cur = stack.popLast() {
                component.append(cur)
                for (dx, dy, dz) in neighbours {
                    let n = VoxelKey(x: cur.x + dx, y: cur.y + dy, z: cur.z + dz)
                    if set.contains(n) && !visited.contains(n) {
                        visited.insert(n)
                        stack.append(n)
                    }
                }
            }
            components.append(component)
        }
        return components
    }
}

// MARK: – Surface Nets (naive)

/// Naive Surface Nets implementation. Given a sparse set of occupied voxel
/// keys, produces a watertight-ish triangle mesh in ARKit world coordinates.
///
/// Algorithm summary:
///   1. Convert sparse voxels to a dense bool grid with 1-voxel padding.
///   2. For every cube cell whose 8 corners straddle the inside/outside
///      boundary, place ONE vertex at the average of the edge-crossing
///      midpoints (gives a smoother surface than marching cubes).
///   3. For every grid edge that crosses the boundary, emit a quad
///      (two triangles) joining the 4 cells that share that edge.
fileprivate enum SurfaceNets {

    struct Mesh {
        var vertices: [SIMD3<Float>]
        var faces: [Int]
    }

    /// Voxel-corner offsets for the 8 cube corners.
    private static let cornerOffsets: [(Int, Int, Int)] = [
        (0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0),
        (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)
    ]

    /// 12 cube edges as pairs of corner indices.
    private static let edgeCorners: [(Int, Int)] = [
        (0, 1), (2, 3), (4, 5), (6, 7),  // x-direction
        (0, 2), (1, 3), (4, 6), (5, 7),  // y-direction
        (0, 4), (1, 5), (2, 6), (3, 7)   // z-direction
    ]

    static func build(voxels: [DepthFusion.VoxelKey], voxelSizeM: Float) -> Mesh {
        guard !voxels.isEmpty else { return Mesh(vertices: [], faces: []) }

        // 1. Bounding box (in voxel-index space) with 1-voxel padding.
        var minX = Int32.max, minY = Int32.max, minZ = Int32.max
        var maxX = Int32.min, maxY = Int32.min, maxZ = Int32.min
        for k in voxels {
            if k.x < minX { minX = k.x }; if k.x > maxX { maxX = k.x }
            if k.y < minY { minY = k.y }; if k.y > maxY { maxY = k.y }
            if k.z < minZ { minZ = k.z }; if k.z > maxZ { maxZ = k.z }
        }
        minX -= 1; minY -= 1; minZ -= 1
        maxX += 1; maxY += 1; maxZ += 1

        let nx = Int(maxX - minX + 1)
        let ny = Int(maxY - minY + 1)
        let nz = Int(maxZ - minZ + 1)
        guard nx > 1, ny > 1, nz > 1 else { return Mesh(vertices: [], faces: []) }

        // Hard upper bound on cluster size to avoid pathological allocations
        // when depth fusion happens to capture an entire room. 256³ corners
        // is ~16 M bools = 16 MB which is the most we'll spend per food.
        let maxDim = 256
        guard nx <= maxDim, ny <= maxDim, nz <= maxDim else {
            print("[SurfaceNets] cluster too large (\(nx)x\(ny)x\(nz)) — skipping")
            return Mesh(vertices: [], faces: [])
        }

        var inside = [Bool](repeating: false, count: nx * ny * nz)
        let nxy = nx * ny
        @inline(__always) func cornerIdx(_ x: Int, _ y: Int, _ z: Int) -> Int {
            return x + y * nx + z * nxy
        }
        for k in voxels {
            let ix = Int(k.x - minX)
            let iy = Int(k.y - minY)
            let iz = Int(k.z - minZ)
            inside[cornerIdx(ix, iy, iz)] = true
        }

        // 2. Build cell-vertex grid. Cells indexed by (cx, cy, cz) in
        // 0..<(nx-1) etc.
        let cx = nx - 1
        let cy = ny - 1
        let cz = nz - 1
        let cxy = cx * cy
        @inline(__always) func cellIdx(_ x: Int, _ y: Int, _ z: Int) -> Int {
            return x + y * cx + z * cxy
        }

        var cellVertex = [Int32](repeating: -1, count: cx * cy * cz)
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(min(cx * cy * cz / 4, 65_536))

        for z in 0..<cz {
            for y in 0..<cy {
                for x in 0..<cx {
                    var cornerMask: UInt8 = 0
                    var cornerIn = [Bool](repeating: false, count: 8)
                    for i in 0..<8 {
                        let off = cornerOffsets[i]
                        let v = inside[cornerIdx(x + off.0, y + off.1, z + off.2)]
                        cornerIn[i] = v
                        if v { cornerMask |= UInt8(1 << i) }
                    }
                    // All-inside (0xFF) or all-outside (0x00) → no surface.
                    if cornerMask == 0 || cornerMask == 0xFF { continue }

                    // Average of midpoints of edges where corner signs differ.
                    var sum = SIMD3<Float>(0, 0, 0)
                    var count: Float = 0
                    for (a, b) in edgeCorners where cornerIn[a] != cornerIn[b] {
                        let oa = cornerOffsets[a]
                        let ob = cornerOffsets[b]
                        sum += SIMD3<Float>(
                            Float(2 * x + oa.0 + ob.0) * 0.5,
                            Float(2 * y + oa.1 + ob.1) * 0.5,
                            Float(2 * z + oa.2 + ob.2) * 0.5
                        )
                        count += 1
                    }
                    guard count > 0 else { continue }
                    let centerVox = sum / count

                    // Convert local-voxel coordinates → ARKit world (metres).
                    let wx = (centerVox.x + Float(minX)) * voxelSizeM
                    let wy = (centerVox.y + Float(minY)) * voxelSizeM
                    let wz = (centerVox.z + Float(minZ)) * voxelSizeM

                    cellVertex[cellIdx(x, y, z)] = Int32(vertices.count)
                    vertices.append(SIMD3<Float>(wx, wy, wz))
                }
            }
        }

        // 3. Emit quads (as two triangles) for every boundary-crossing edge.
        var faces: [Int] = []
        faces.reserveCapacity(vertices.count * 3)

        @inline(__always) func quad(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32, flip: Bool) {
            if a < 0 || b < 0 || c < 0 || d < 0 { return }
            let ai = Int(a), bi = Int(b), ci = Int(c), di = Int(d)
            if flip {
                faces.append(ai); faces.append(ci); faces.append(bi)
                faces.append(ai); faces.append(di); faces.append(ci)
            } else {
                faces.append(ai); faces.append(bi); faces.append(ci)
                faces.append(ai); faces.append(ci); faces.append(di)
            }
        }

        // x-direction edges between corners (x,y,z)-(x+1,y,z).
        // Shared cells: (x, y-1, z-1), (x, y, z-1), (x, y, z), (x, y-1, z).
        for z in 1..<cz {
            for y in 1..<cy {
                for x in 0..<cx {
                    let aIn = inside[cornerIdx(x, y, z)]
                    let bIn = inside[cornerIdx(x + 1, y, z)]
                    if aIn == bIn { continue }
                    quad(
                        cellVertex[cellIdx(x, y - 1, z - 1)],
                        cellVertex[cellIdx(x, y,     z - 1)],
                        cellVertex[cellIdx(x, y,     z)],
                        cellVertex[cellIdx(x, y - 1, z)],
                        flip: !aIn
                    )
                }
            }
        }

        // y-direction edges between corners (x,y,z)-(x,y+1,z).
        for z in 1..<cz {
            for y in 0..<cy {
                for x in 1..<cx {
                    let aIn = inside[cornerIdx(x, y, z)]
                    let bIn = inside[cornerIdx(x, y + 1, z)]
                    if aIn == bIn { continue }
                    quad(
                        cellVertex[cellIdx(x - 1, y, z - 1)],
                        cellVertex[cellIdx(x,     y, z - 1)],
                        cellVertex[cellIdx(x,     y, z)],
                        cellVertex[cellIdx(x - 1, y, z)],
                        flip: aIn
                    )
                }
            }
        }

        // z-direction edges between corners (x,y,z)-(x,y,z+1).
        for z in 0..<cz {
            for y in 1..<cy {
                for x in 1..<cx {
                    let aIn = inside[cornerIdx(x, y, z)]
                    let bIn = inside[cornerIdx(x, y, z + 1)]
                    if aIn == bIn { continue }
                    quad(
                        cellVertex[cellIdx(x - 1, y - 1, z)],
                        cellVertex[cellIdx(x,     y - 1, z)],
                        cellVertex[cellIdx(x,     y,     z)],
                        cellVertex[cellIdx(x - 1, y,     z)],
                        flip: !aIn
                    )
                }
            }
        }

        return Mesh(vertices: vertices, faces: faces)
    }
}
