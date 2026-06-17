import CoreVideo
import Foundation

/// Orchestrates the scan pipeline:
///
///   recorded sweep → plate detection → preprocessing → segmentation
///   → table plane → tier-aware volume → JSON result
///
/// This is the single entry point called by `ScannerPlugin.runVideoInference`.
/// All steps run sequentially to stay within memory limits (Part 3).
final class InferencePipeline {

    // MARK: – Dependencies

    private let plateDetector       = PlateDetector()
    private let preprocessor        = FramePreprocessor()
    private let segmentationService = SegmentationService()
    private let volumeEngine        = FoodVolumeEngine()
    private let referenceEstimator  = ReferenceScaleEstimator()

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

    // MARK: – Video scan (tier-aware 3-D volume)

    /// Run the tier-aware pipeline from a recorded video sweep.
    ///
    /// Pipeline (identical for both tiers — only the geometry source differs):
    ///   1. Plate detection + segmentation on the top (first) frame.
    ///   2. Reference table plane captured live during recording.
    ///   3. `FoodVolumeEngine` integrates height-above-plane:
    ///        • LiDAR  → measured `sceneDepth`,
    ///        • camera → intrinsics-at-hold-distance + per-class height prior,
    ///          with the distance refined from a detected plate.
    ///   4. Serialise volumes + confidence to JSON.
    ///
    /// Returns the same JSON shape as `run(captureService:)`, plus tier fields.
    func runVideoScan(recorder: MultiFrameRecorder, strategy: ScanStrategy) throws -> String {
        guard let topFrame = recorder.topFrame else {
            throw PipelineError.noTopFrame
        }

        let imageW = CVPixelBufferGetWidth(topFrame.pixelBuffer)
        let imageH = CVPixelBufferGetHeight(topFrame.pixelBuffer)

        // ── 1. Plate detection ──────────────────────────────────────────
        let plate = plateDetector.detect(in: topFrame.pixelBuffer)
        let plateRect = plate.detected ? plate.rect
                                       : CGRect(x: 0, y: 0, width: 1, height: 1)
        let cropRect: CGRect? = plate.detected ? plate.rect : nil

        // ── 2. Preprocess top frame for CoreML ─────────────────────────
        guard let preprocessedRGB = autoreleasepool(invoking: {
            preprocessor.preprocess(
                pixelBuffer: topFrame.pixelBuffer,
                plateRect: cropRect
            )
        }) else {
            throw PipelineError.preprocessingFailed
        }

        // ── 3. Segmentation ─────────────────────────────────────────────
        let segments: [SegmentationService.SegmentedObject]
        do {
            segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            throw PipelineError.segmentationFailed(error)
        }
        guard !segments.isEmpty else { return "[]" }

        // ── 4. Reference table plane (captured live; virtual fallback) ──
        let plane = recorder.tablePlane ?? TablePlane.virtual(
            cameraTransform: topFrame.cameraTransform,
            distanceM: strategy.assumedDistanceM,
            source: .assumedDistance,
            confidence: 0.4
        )

        // ── 5. Camera tier: refine hold distance from the plate ─────────
        var refinedDistanceM: Float? = nil
        if !strategy.providesMeasuredDepth {
            let est = referenceEstimator.refineFromPlate(
                plate: plate,
                intrinsics: topFrame.cameraIntrinsics,
                defaultDistanceM: strategy.assumedDistanceM
            )
            refinedDistanceM = est.distanceM
        }

        // ── 6. Volume integration (tier-agnostic) ──────────────────────
        let estimates = volumeEngine.compute(
            objects:     segments,
            strategy:    strategy,
            plane:       plane,
            depthBuffer: topFrame.depthBuffer,
            intrinsics:  topFrame.cameraIntrinsics,
            transform:   topFrame.cameraTransform,
            plateRect:   plateRect,
            imageWidth:  imageW,
            imageHeight: imageH,
            maskWidth:   preprocessor.modelInputWidth,
            maskHeight:  preprocessor.modelInputHeight,
            refinedDistanceM: refinedDistanceM
        )

        // Publish surfaces so the 3-D model view can render this scan's food.
        FoodMeshStore.shared.update(estimates)

        // ── 7. Serialise to JSON ────────────────────────────────────────
        var payload = [[String: Any]]()
        for (seg, est) in zip(segments, estimates) {
            var d = [String: Any]()
            d["label"]        = est.label
            d["volume_cm3"]   = round(est.volumeCm3 * 10) / 10
            d["pixel_count"]  = seg.pixelCount
            d["confidence"]   = round(Double(est.confidence) * 1000) / 1000
            d["height_cm"]    = round(est.heightCm * 10) / 10
            d["scan_tier"]    = strategy.tier.rawValue
            d["plane_source"] = est.source.rawValue
            d["frames_used"]  = recorder.lightFrames.count
            payload.append(d)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }

        print("──────────── Video Scan Result ──────────")
        print("Tier: \(strategy.tier.rawValue), plane: \(plane.source.rawValue), "
            + "frames: \(recorder.lightFrames.count)")
        for est in estimates {
            print("  \(est.label): \(String(format: "%.1f", est.volumeCm3)) cm³, "
                + "h \(String(format: "%.1f", est.heightCm)) cm, "
                + "conf \(String(format: "%.2f", est.confidence))")
        }
        print("─────────────────────────────────────────")

        return json
    }
}
