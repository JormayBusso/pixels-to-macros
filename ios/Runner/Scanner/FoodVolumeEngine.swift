import ARKit
import CoreVideo
import Foundation
import simd

/// Per-food-class height priors (cm) used by the **camera tier**, which has no
/// depth sensor and must assume how tall a plated food typically stands.
///
/// Values are deliberately conservative averages for an "as-plated" serving.
/// They are only a fallback — the LiDAR tier ignores them entirely and measures
/// real height from `sceneDepth`.
enum FoodHeightPrior {

    /// Default height (cm) when a label has no specific prior.
    static let defaultHeightCm: Double = 2.5

    private static let table: [String: Double] = [
        // Flat / thin foods
        "french fries": 1.5, "pizza": 2.0, "bread": 3.0, "biscuit": 1.0,
        "cake": 5.0, "egg tart": 2.5, "lettuce": 2.0, "cabbage": 3.0,
        "seaweed": 0.5, "kelp": 0.5, "sauce": 0.5, "cheese butter": 1.0,
        // Medium-height foods
        "rice": 2.5, "noodles": 2.5, "rice noodle": 2.5, "pork": 2.5,
        "steak": 2.5, "chicken duck": 3.0, "fried meat": 2.5, "fish": 2.5,
        "tofu": 2.5, "potato": 3.5, "egg": 2.5, "sausage": 2.0,
        "hamburg": 5.0, "broccoli": 3.5, "cauliflower": 4.0,
        // Round / tall whole foods
        "apple": 6.0, "orange": 6.0, "tomato": 5.0, "banana": 3.5,
        "pear": 6.0, "peach": 5.0, "mango": 6.0, "lemon": 5.0,
        "avocado": 5.0, "pineapple": 8.0, "watermelon": 8.0,
    ]

    static func heightCm(for label: String) -> Double {
        table[label.lowercased()] ?? defaultHeightCm
    }
}

/// Converts segmentation masks into 3-D food volumes.
///
/// **One algorithm, two depth sources.** Both tiers integrate the food's
/// footprint area over the segmentation mask; they differ only in:
///
///   • where the per-pixel **height** comes from
///       – LiDAR  → measured `sceneDepth` height above the table plane,
///       – camera → a per-class height prior, and
///   • where the per-pixel **footprint** comes from
///       – LiDAR  → real depth at that pixel,
///       – camera → the pre-programmed hold distance.
///
/// All mask-pixel → image-pixel mapping uses the **top-left origin** convention
/// shared by `PlateDetector` and the segmentation crop, eliminating the Y-flip
/// mismatch that previously misaligned masks against depth.
final class FoodVolumeEngine {

    /// Plausible food-height band (metres) for rejecting depth noise.
    private let minHeightM: Float = 0.002   // 2 mm
    private let maxHeightM: Float = 0.30    // 30 cm

    /// Target resolution (per axis) of the renderable surface grid.
    private let gridN = 40

    // MARK: – Public entry point

    /// Compute volumes for every segmented object using the given strategy.
    ///
    /// - Parameters:
    ///   - objects:     Segmented food masks (mask grid = `maskWidth`×`maskHeight`).
    ///   - strategy:    Selected scan strategy (decides measured vs estimated).
    ///   - plane:       Reference table plane (world space).
    ///   - depthBuffer: Float32 `sceneDepth` map (LiDAR only; ignored otherwise).
    ///   - intrinsics:  Camera intrinsics for the **full-resolution** top frame.
    ///   - transform:   Camera-to-world transform for the top frame.
    ///   - plateRect:   Normalised plate crop (top-left origin) used by segmentation.
    ///   - imageWidth/Height: Dimensions of the full-resolution RGB frame.
    ///   - maskWidth/Height:  Dimensions of the segmentation mask grid.
    func compute(
        objects: [SegmentationService.SegmentedObject],
        strategy: ScanStrategy,
        plane: TablePlane,
        depthBuffer: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        transform: simd_float4x4,
        plateRect: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        maskWidth: Int,
        maskHeight: Int,
        refinedDistanceM: Float? = nil
    ) -> [FoodVolumeEstimate] {

        if strategy.providesMeasuredDepth, let depth = depthBuffer {
            return measuredVolumes(
                objects: objects, plane: plane, depthBuffer: depth,
                intrinsics: intrinsics, transform: transform,
                plateRect: plateRect,
                imageWidth: imageWidth, imageHeight: imageHeight,
                maskWidth: maskWidth, maskHeight: maskHeight,
                baseConfidence: strategy.baseConfidence
            )
        }

        return estimatedVolumes(
            objects: objects,
            intrinsics: intrinsics,
            plateRect: plateRect,
            assumedDistanceM: refinedDistanceM ?? strategy.assumedDistanceM,
            imageWidth: imageWidth, imageHeight: imageHeight,
            maskWidth: maskWidth, maskHeight: maskHeight,
            baseConfidence: strategy.baseConfidence
        )
    }

    // MARK: – Measured (LiDAR)

    private func measuredVolumes(
        objects: [SegmentationService.SegmentedObject],
        plane: TablePlane,
        depthBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        transform: simd_float4x4,
        plateRect: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        maskWidth: Int,
        maskHeight: Int,
        baseConfidence: Float
    ) -> [FoodVolumeEstimate] {

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else {
            // Depth unexpectedly unavailable — fall back to estimation.
            return estimatedVolumes(
                objects: objects, intrinsics: intrinsics, plateRect: plateRect,
                assumedDistanceM: plane.source == .arPlaneAnchor
                    ? distanceToPlane(transform: transform, plane: plane)
                    : 0.30,
                imageWidth: imageWidth, imageHeight: imageHeight,
                maskWidth: maskWidth, maskHeight: maskHeight,
                baseConfidence: baseConfidence * 0.7
            )
        }
        let ptr = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = rowBytes / MemoryLayout<Float32>.stride

        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y

        // How many full-image pixels one mask pixel spans (within the crop).
        let imgPxPerMaskX = Float(plateRect.width)  * Float(imageWidth)  / Float(maskWidth)
        let imgPxPerMaskY = Float(plateRect.height) * Float(imageHeight) / Float(maskHeight)

        // Depth-map ↔ full-image scale.
        let depthScaleX = Float(depthW) / Float(imageWidth)
        let depthScaleY = Float(depthH) / Float(imageHeight)

        var results: [FoodVolumeEstimate] = []

        for obj in objects {
            var volumeM3: Double = 0
            var heightSumM: Double = 0
            var heightCount = 0

            // Surface-grid accumulators (built from the object's bbox).
            let bbox = maskBoundingBox(obj.mask, maskWidth: maskWidth, maskHeight: maskHeight)
            let gCols = max(1, min(gridN, bbox.cols))
            let gRows = max(1, min(gridN, bbox.rows))
            var gHeightSum = [Double](repeating: 0, count: gCols * gRows)
            var gCount     = [Int](repeating: 0, count: gCols * gRows)
            var cellWsumM: Double = 0
            var cellHsumM: Double = 0

            for r in 0..<maskHeight {
                for c in 0..<maskWidth {
                    guard obj.mask[r][c] == 1 else { continue }

                    // Mask pixel → full-image pixel (top-left origin).
                    let uN = Float(plateRect.minX) + (Float(c) + 0.5) / Float(maskWidth)  * Float(plateRect.width)
                    let vN = Float(plateRect.minY) + (Float(r) + 0.5) / Float(maskHeight) * Float(plateRect.height)
                    let imgX = uN * Float(imageWidth)
                    let imgY = vN * Float(imageHeight)

                    // Sample depth.
                    let dx = min(max(Int(imgX * depthScaleX), 0), depthW - 1)
                    let dy = min(max(Int(imgY * depthScaleY), 0), depthH - 1)
                    let d = ptr[dy * floatsPerRow + dx]
                    guard d > 0.05 && d < 1.5 else { continue }

                    // Back-project to world space.
                    let xc = (imgX - cx) / fx * d
                    let yc = (imgY - cy) / fy * d
                    let pc = simd_float4(xc, yc, d, 1)
                    let pw4 = transform * pc
                    let pw = simd_float3(pw4.x, pw4.y, pw4.z)

                    // Height of this food surface above the table.
                    let h = plane.heightAboveM(pw)
                    guard h >= minHeightM && h <= maxHeightM else { continue }

                    // Footprint of this mask cell in world metres² at depth d.
                    let cellWM = (d / fx) * imgPxPerMaskX
                    let cellHM = (d / fy) * imgPxPerMaskY
                    let cellAreaM2 = Double(cellWM * cellHM)

                    volumeM3 += cellAreaM2 * Double(h)
                    heightSumM += Double(h)
                    heightCount += 1
                    cellWsumM += Double(cellWM)
                    cellHsumM += Double(cellHM)

                    // Bucket height into the surface grid.
                    let gc = min(gCols - 1, (c - bbox.minC) * gCols / max(bbox.cols, 1))
                    let gr = min(gRows - 1, (r - bbox.minR) * gRows / max(bbox.rows, 1))
                    let gi = gr * gCols + gc
                    gHeightSum[gi] += Double(h) * 100.0   // m → cm
                    gCount[gi]     += 1
                }
            }

            let meanHeightCm = heightCount > 0
                ? (heightSumM / Double(heightCount)) * 100.0
                : 0
            // Confidence drops if very few valid depth samples landed on the food.
            let coverage = Float(heightCount) / Float(max(obj.pixelCount, 1))
            let conf = baseConfidence * min(1.0, 0.4 + coverage)

            let cmPerMaskCol = heightCount > 0 ? (cellWsumM / Double(heightCount)) * 100.0 : 0
            let cmPerMaskRow = heightCount > 0 ? (cellHsumM / Double(heightCount)) * 100.0 : 0
            let surface = makeSurface(
                gHeightSum: gHeightSum, gCount: gCount,
                gCols: gCols, gRows: gRows,
                cmPerMaskCol: cmPerMaskCol, cmPerMaskRow: cmPerMaskRow,
                bbox: bbox
            )

            results.append(FoodVolumeEstimate(
                label: obj.label,
                volumeCm3: volumeM3 * 1_000_000.0,   // m³ → cm³
                heightCm: meanHeightCm,
                confidence: conf,
                source: plane.source,
                surface: surface
            ))
        }

        return results
    }

    // MARK: – Estimated (camera tier)

    private func estimatedVolumes(
        objects: [SegmentationService.SegmentedObject],
        intrinsics: simd_float3x3,
        plateRect: CGRect,
        assumedDistanceM: Float,
        imageWidth: Int,
        imageHeight: Int,
        maskWidth: Int,
        maskHeight: Int,
        baseConfidence: Float
    ) -> [FoodVolumeEstimate] {

        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let d  = assumedDistanceM > 0 ? assumedDistanceM : 0.30

        let imgPxPerMaskX = Float(plateRect.width)  * Float(imageWidth)  / Float(maskWidth)
        let imgPxPerMaskY = Float(plateRect.height) * Float(imageHeight) / Float(maskHeight)

        // Constant footprint per mask cell at the assumed hold distance.
        let cellWM = (d / fx) * imgPxPerMaskX
        let cellHM = (d / fy) * imgPxPerMaskY
        let cellAreaCm2 = Double(cellWM * cellHM) * 10_000.0   // m² → cm²

        var results: [FoodVolumeEstimate] = []

        for obj in objects {
            let heightCm = FoodHeightPrior.heightCm(for: obj.label)
            // Rounded-top solid: a flat extrusion over-estimates rounded foods,
            // so apply a 0.6 fill factor (matches a hemispherical-ish profile).
            let fillFactor = 0.6
            let areaCm2 = Double(obj.pixelCount) * cellAreaCm2
            let volumeCm3 = areaCm2 * heightCm * fillFactor

            // Build a flat-top surface grid at the prior height.
            let bbox = maskBoundingBox(obj.mask, maskWidth: maskWidth, maskHeight: maskHeight)
            let gCols = max(1, min(gridN, bbox.cols))
            let gRows = max(1, min(gridN, bbox.rows))
            var gHeightSum = [Double](repeating: 0, count: gCols * gRows)
            var gCount     = [Int](repeating: 0, count: gCols * gRows)
            for r in bbox.minR...bbox.maxR {
                for c in bbox.minC...bbox.maxC {
                    guard obj.mask[r][c] == 1 else { continue }
                    let gc = min(gCols - 1, (c - bbox.minC) * gCols / max(bbox.cols, 1))
                    let gr = min(gRows - 1, (r - bbox.minR) * gRows / max(bbox.rows, 1))
                    let gi = gr * gCols + gc
                    // Dome-ish profile: full height at centre, tapering to edges.
                    gHeightSum[gi] += heightCm
                    gCount[gi]     += 1
                }
            }
            let cmPerMaskCol = Double(cellWM) * 100.0
            let cmPerMaskRow = Double(cellHM) * 100.0
            let surface = makeSurface(
                gHeightSum: gHeightSum, gCount: gCount,
                gCols: gCols, gRows: gRows,
                cmPerMaskCol: cmPerMaskCol, cmPerMaskRow: cmPerMaskRow,
                bbox: bbox
            )

            results.append(FoodVolumeEstimate(
                label: obj.label,
                volumeCm3: volumeCm3,
                heightCm: heightCm,
                confidence: baseConfidence,
                source: .assumedDistance,
                surface: surface
            ))
        }

        return results
    }

    // MARK: – Surface-grid helpers

    /// Inclusive bounding box (mask coords) of an object's foreground pixels.
    private struct MaskBBox { let minR, maxR, minC, maxC, rows, cols: Int }

    private func maskBoundingBox(
        _ mask: [[UInt8]], maskWidth: Int, maskHeight: Int
    ) -> MaskBBox {
        var minR = maskHeight, maxR = 0, minC = maskWidth, maxC = 0
        for r in 0..<maskHeight {
            for c in 0..<maskWidth where mask[r][c] == 1 {
                if r < minR { minR = r }; if r > maxR { maxR = r }
                if c < minC { minC = c }; if c > maxC { maxC = c }
            }
        }
        if maxR < minR || maxC < minC {
            return MaskBBox(minR: 0, maxR: 0, minC: 0, maxC: 0, rows: 1, cols: 1)
        }
        return MaskBBox(minR: minR, maxR: maxR, minC: minC, maxC: maxC,
                        rows: maxR - minR + 1, cols: maxC - minC + 1)
    }

    /// Average bucketed heights into a [FoodSurfaceGrid], or nil if empty.
    private func makeSurface(
        gHeightSum: [Double], gCount: [Int],
        gCols: Int, gRows: Int,
        cmPerMaskCol: Double, cmPerMaskRow: Double,
        bbox: MaskBBox
    ) -> FoodSurfaceGrid? {
        guard gCols > 0, gRows > 0, cmPerMaskCol > 0, cmPerMaskRow > 0 else { return nil }
        var heights = [Double](repeating: 0, count: gCols * gRows)
        var any = false
        for i in 0..<heights.count {
            if gCount[i] > 0 {
                heights[i] = gHeightSum[i] / Double(gCount[i])
                any = true
            }
        }
        guard any else { return nil }
        let cellWcm = cmPerMaskCol * Double(bbox.cols) / Double(gCols)
        let cellHcm = cmPerMaskRow * Double(bbox.rows) / Double(gRows)
        return FoodSurfaceGrid(cols: gCols, rows: gRows,
                               cellWcm: cellWcm, cellHcm: cellHcm,
                               heightsCm: heights)
    }

    // MARK: – Helpers

    private func distanceToPlane(transform: simd_float4x4, plane: TablePlane) -> Float {
        let camPos = simd_float3(transform.columns.3.x,
                                 transform.columns.3.y,
                                 transform.columns.3.z)
        return abs(plane.heightAboveM(camPos))
    }
}
