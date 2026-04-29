import ARKit
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

    private struct VoxelKey: Hashable {
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
                pendingLabels.append((key: key, label: label))
            }
        }

        // Apply collected labels now that enumeration is complete.
        for pending in pendingLabels {
            grid[pending.key] = pending.label
        }
    }

    // MARK: – Volume queries

    /// Volume in cm³ for a named food label.
    func volume(for label: String) -> Double {
        guard let lIdx = labelMap[label] else { return 0 }
        let count = grid.values.filter { $0 == lIdx }.count
        let s = Double(voxelSizeM * 100)
        return Double(count) * s * s * s
    }

    /// All (label → volume cm³) pairs. Only labels with at least one voxel.
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
    var totalOccupiedVoxels: Int {
        grid.values.filter { $0 >= 0 }.count
    }

    func reset() {
        grid.removeAll()
        labelMap.removeAll()
        nextLabel = 1
    }
}
