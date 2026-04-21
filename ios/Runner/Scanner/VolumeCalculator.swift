import CoreVideo
import Foundation

/// Computes per-food volume by mapping segmentation masks onto
/// the depth map (Part 10).
///
/// For each food pixel: Volume = Σ (pixel_area × depth).
/// Pixel area is derived from the plate scale (pixels → cm).
final class VolumeCalculator {

    // MARK: – Types

    /// Volume result for a single food item.
    struct FoodVolume {
        let label: String
        let volumeCm3: Double
        let pixelCount: Int
    }

    // MARK: – Public

    /// Calculate volume for each segmented object using the depth buffer.
    ///
    /// - Parameters:
    ///   - objects: Segmented food masks from `SegmentationService`.
    ///   - depthBuffer: The preprocessed depth map (Float32), same grid as masks.
    ///   - pixelsPerCm: Scale factor from `PlateDetector.pixelsPerCm`.
    ///   - maskWidth: Width of the segmentation mask grid.
    ///   - maskHeight: Height of the segmentation mask grid.
    func calculate(
        objects: [SegmentationService.SegmentedObject],
        depthBuffer: CVPixelBuffer?,
        pixelsPerCm: CGFloat,
        maskWidth: Int,
        maskHeight: Int
    ) -> [FoodVolume] {

        // If no depth → use heuristic flat-plate estimate
        guard let depthBuffer else {
            return estimateWithoutDepth(
                objects: objects,
                pixelsPerCm: pixelsPerCm,
                maskWidth: maskWidth,
                maskHeight: maskHeight
            )
        }

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let depthBase = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return estimateWithoutDepth(
                objects: objects,
                pixelsPerCm: pixelsPerCm,
                maskWidth: maskWidth,
                maskHeight: maskHeight
            )
        }

        let depthPtr = depthBase.assumingMemoryBound(to: Float32.self)
        let depthFloatsPerRow = depthRowBytes / MemoryLayout<Float32>.stride

        // Area of one mask pixel in cm²
        let pixelAreaCm2 = pow(1.0 / Double(pixelsPerCm), 2)

        // Scale factors from mask grid → depth grid
        let scaleX = Double(depthW) / Double(maskWidth)
        let scaleY = Double(depthH) / Double(maskHeight)

        var results: [FoodVolume] = []

        for obj in objects {
            var totalVolume: Double = 0

            for r in 0..<maskHeight {
                for c in 0..<maskWidth {
                    guard obj.mask[r][c] == 1 else { continue }

                    // Map mask coords → depth coords
                    let dx = min(Int(Double(c) * scaleX), depthW - 1)
                    let dy = min(Int(Double(r) * scaleY), depthH - 1)

                    let depthValue = Double(depthPtr[dy * depthFloatsPerRow + dx])

                    // Depth is in metres — convert to cm.
                    // Clamp unreasonable values (< 0.5 cm or > 30 cm food height).
                    let heightCm = max(0, min(depthValue * 100.0, 30.0))

                    totalVolume += pixelAreaCm2 * heightCm
                }
            }

            results.append(FoodVolume(
                label: obj.label,
                volumeCm3: totalVolume,
                pixelCount: obj.pixelCount
            ))
        }

        return results
    }

    // MARK: – Heuristic fallback (no depth)

    /// When depth data is unavailable, assume an average food height based
    /// on the area fraction of the plate (larger area → likely flatter food).
    private func estimateWithoutDepth(
        objects: [SegmentationService.SegmentedObject],
        pixelsPerCm: CGFloat,
        maskWidth: Int,
        maskHeight: Int
    ) -> [FoodVolume] {
        let totalPixels = maskWidth * maskHeight
        let pixelAreaCm2 = pow(1.0 / Double(pixelsPerCm), 2)

        return objects.map { obj in
            let areaFraction = Double(obj.pixelCount) / Double(max(totalPixels, 1))
            // Heuristic: bigger area → flatter (1-2 cm), smaller area → taller (2-4 cm)
            let estimatedHeightCm = areaFraction > 0.3 ? 1.5 : 3.0
            let areaCm2 = Double(obj.pixelCount) * pixelAreaCm2
            let volume = areaCm2 * estimatedHeightCm

            return FoodVolume(
                label: obj.label,
                volumeCm3: volume,
                pixelCount: obj.pixelCount
            )
        }
    }
}
