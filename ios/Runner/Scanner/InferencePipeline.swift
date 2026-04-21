import CoreVideo
import Foundation

/// Orchestrates the full scan pipeline:
///
///   captured frames → plate detection → preprocessing → segmentation
///   → depth mapping → volume calculation → JSON result
///
/// This is the single entry point called by `ScannerPlugin.runInference`.
/// All steps run sequentially to stay within memory limits (Part 3).
final class InferencePipeline {

    // MARK: – Dependencies

    private let plateDetector       = PlateDetector()
    private let preprocessor        = FramePreprocessor()
    private let segmentationService = SegmentationService()
    private let volumeCalculator    = VolumeCalculator()

    // MARK: – Types

    enum PipelineError: LocalizedError {
        case noTopFrame
        case preprocessingFailed
        case segmentationFailed(Error)
        case volumeFailed

        var errorDescription: String? {
            switch self {
            case .noTopFrame:            return "Top frame has not been captured"
            case .preprocessingFailed:   return "Frame preprocessing failed"
            case .segmentationFailed(let e): return "Segmentation failed: \(e.localizedDescription)"
            case .volumeFailed:          return "Volume calculation failed"
            }
        }
    }

    // MARK: – Run

    /// Execute the full pipeline using frames stored in `captureService`.
    /// Returns a JSON string: `[{"label":"rice","volume_cm3":200}, …]`
    func run(captureService: FrameCaptureService) throws -> String {
        // ── 1. Validate frames ──────────────────────────────────────────
        guard let topFrame = captureService.topFrame else {
            throw PipelineError.noTopFrame
        }

        let sideFrame = captureService.sideFrame // optional

        // ── 2. Plate detection (on top frame) ───────────────────────────
        let plate = plateDetector.detect(in: topFrame.pixelBuffer)
        let pxPerCm = plateDetector.pixelsPerCm(
            plate: plate,
            frameWidth: CVPixelBufferGetWidth(topFrame.pixelBuffer)
        )

        // ── 3. Preprocess RGB for CoreML ────────────────────────────────
        guard let preprocessedRGB = autoreleasepool(invoking: {
            preprocessor.preprocess(
                pixelBuffer: topFrame.pixelBuffer,
                plateRect: plate.rect
            )
        }) else {
            throw PipelineError.preprocessingFailed
        }

        // ── 4. Preprocess depth (if available) ──────────────────────────
        let depthSource = sideFrame?.depthBuffer ?? topFrame.depthBuffer
        let preprocessedDepth: CVPixelBuffer? = autoreleasepool {
            guard let depth = depthSource else { return nil }
            return preprocessor.preprocessDepth(
                depthBuffer: depth,
                plateRect: plate.rect,
                outputWidth: preprocessor.modelInputWidth,
                outputHeight: preprocessor.modelInputHeight
            )
        }

        // ── 5. Segmentation ─────────────────────────────────────────────
        let segments: [SegmentationService.SegmentedObject]
        do {
            segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            throw PipelineError.segmentationFailed(error)
        }

        guard !segments.isEmpty else {
            // No food detected — return empty list
            return "[]"
        }

        // ── 6. Volume calculation ───────────────────────────────────────
        let volumes = volumeCalculator.calculate(
            objects: segments,
            depthBuffer: preprocessedDepth,
            pixelsPerCm: pxPerCm,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )

        // ── 7. Serialise to JSON ────────────────────────────────────────
        let payload: [[String: Any]] = volumes.map { vol in
            [
                "label": vol.label,
                "volume_cm3": round(vol.volumeCm3 * 10) / 10,  // 1 decimal
                "pixel_count": vol.pixelCount,
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        // ── 8. Log for debug (Part 14) ──────────────────────────────────
        logResults(
            plate: plate,
            segments: segments,
            volumes: volumes,
            hasDepth: preprocessedDepth != nil
        )

        return json
    }

    // MARK: – Debug logging

    private func logResults(
        plate: PlateDetector.PlateResult,
        segments: [SegmentationService.SegmentedObject],
        volumes: [VolumeCalculator.FoodVolume],
        hasDepth: Bool
    ) {
        print("──────────── Inference Result ────────────")
        print("Plate detected: \(plate.detected), diameter: \(Int(plate.diameterPx)) px")
        print("Depth available: \(hasDepth)")
        for (seg, vol) in zip(segments, volumes) {
            print("  \(seg.label): \(seg.pixelCount) px, "
                + "conf \(String(format: "%.2f", seg.confidence)), "
                + "vol \(String(format: "%.1f", vol.volumeCm3)) cm³")
        }
        print("──────────────────────────────────────────")
    }
}
