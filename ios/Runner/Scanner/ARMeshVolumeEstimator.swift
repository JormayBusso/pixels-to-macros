import ARKit
import CoreVideo
import Foundation
import simd

/// EXPERIMENTAL (#4) — per-food volume from the ARKit LiDAR scene mesh.
///
/// Status: untested. It cannot be validated without a LiDAR device, so it is
/// **default-off** (`InferencePipeline.compareSceneMesh`) and runs only as a
/// non-destructive comparison: it logs mesh-derived volumes alongside the live
/// voxel-fusion volumes so they can be compared on a LiDAR device before this
/// ever replaces the shipping path.
///
/// Method (columnar, mirrors the voxel solidify): project every mesh vertex into
/// the top frame using the SAME convention as `DepthFusion.assignLabels`
/// (`cam = transform.inverse * p`, `u = fx·x/z + cx`), keep the ones that land
/// inside a food mask, bin them into a 1 cm horizontal (x,z) grid, and sum
/// `cellArea × heightAboveTable` where the table plane is the robust 5th-percentile
/// of in-food vertex heights.
final class ARMeshVolumeEstimator {

    private let quantM: Float = 0.01            // 1 cm horizontal grid
    private var cellAreaCm2: Double { Double(quantM * quantM) * 10_000.0 } // m²→cm²

    /// Compute per-food (label → cm³) volumes from the scene mesh. Returns an
    /// empty map when there is no usable mesh.
    func computeVolumes(
        meshAnchors: [ARMeshAnchor],
        segments: [SegmentationService.SegmentedObject],
        topTransform: simd_float4x4,
        topIntrinsics: simd_float3x3,
        imageWidth: Int,
        imageHeight: Int,
        maskWidth: Int,
        maskHeight: Int,
        plateRect: CGRect
    ) -> [String: Double] {
        guard !meshAnchors.isEmpty, !segments.isEmpty,
              imageWidth > 0, imageHeight > 0 else { return [:] }

        // 1) Per-pixel label grid: 0 = none, else segment index + 1.
        var labelGrid = [Int32](repeating: 0, count: maskWidth * maskHeight)
        for (i, seg) in segments.enumerated() {
            let tag = Int32(i + 1)
            for r in 0..<min(maskHeight, seg.mask.count) {
                let row = seg.mask[r]
                for c in 0..<min(maskWidth, row.count) where row[c] == 1 {
                    labelGrid[r * maskWidth + c] = tag
                }
            }
        }

        let fx = topIntrinsics.columns.0.x
        let fy = topIntrinsics.columns.1.y
        let cx = topIntrinsics.columns.2.x
        let cy = topIntrinsics.columns.2.y
        let camInv = topTransform.inverse

        let pRx = Float(plateRect.minX), pRy = Float(plateRect.minY)
        let pRw = Float(plateRect.width), pRh = Float(plateRect.height)
        guard pRw > 0.001, pRh > 0.001 else { return [:] }

        // 2) Bin in-food vertices: per label → (cellKey → max height world-Y),
        //    and collect heights to derive a robust table plane per label.
        struct Bin { var top: [Int64: Float] = [:]; var ys: [Float] = [] }
        var bins: [Int32: Bin] = [:]

        for anchor in meshAnchors {
            let verts = anchor.geometry.vertices
            guard verts.format == .float3 else { continue }
            let base = verts.buffer.contents()
            let stride = verts.stride
            let offset = verts.offset
            let aTransform = anchor.transform

            for vi in 0..<verts.count {
                let local = base.advanced(by: offset + stride * vi)
                    .assumingMemoryBound(to: simd_float3.self).pointee
                let world = aTransform * simd_float4(local, 1)

                let cam = camInv * world
                guard cam.z > 0 else { continue }
                let uN = (fx * cam.x / cam.z + cx) / Float(imageWidth)
                let vN = (fy * cam.y / cam.z + cy) / Float(imageHeight)
                guard uN >= 0, uN < 1, vN >= 0, vN < 1 else { continue }

                let pu = (uN - pRx) / pRw
                let pv = (vN - pRy) / pRh
                guard pu >= 0, pu < 1, pv >= 0, pv < 1 else { continue }

                let mu = Int(pu * Float(maskWidth))
                let mv = Int(pv * Float(maskHeight))
                guard mu >= 0, mu < maskWidth, mv >= 0, mv < maskHeight else { continue }

                let tag = labelGrid[mv * maskWidth + mu]
                guard tag > 0 else { continue }

                let gx = Int64((world.x / quantM).rounded(.towardZero))
                let gz = Int64((world.z / quantM).rounded(.towardZero))
                let cell = (gx &* 73_856_093) ^ (gz &* 19_349_663)

                var bin = bins[tag] ?? Bin()
                if let cur = bin.top[cell] {
                    if world.y > cur { bin.top[cell] = world.y }
                } else {
                    bin.top[cell] = world.y
                }
                bin.ys.append(world.y)
                bins[tag] = bin
            }
        }

        // 3) Volume = Σ cellArea × (cellTop − tablePlane), tablePlane = 5th pct.
        var result: [String: Double] = [:]
        for (tag, bin) in bins {
            guard bin.ys.count >= 20 else { continue }
            let sorted = bin.ys.sorted()
            let tableY = sorted[max(0, Int(Double(sorted.count) * 0.05))]
            var volume = 0.0
            for (_, topY) in bin.top {
                let hCm = Double(topY - tableY) * 100.0
                if hCm > 0, hCm < 30 { volume += cellAreaCm2 * hCm }
            }
            guard volume > 1 else { continue }
            let label = segments[Int(tag) - 1].label
            result[label, default: 0] += volume
        }
        return result
    }
}
