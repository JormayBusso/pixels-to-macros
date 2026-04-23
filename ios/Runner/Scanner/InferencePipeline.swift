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

        // ── 6. Depth statistics (Part 14 — debug logging) ───────────────
        var depthMin: Float = Float.greatestFiniteMagnitude
        var depthMax: Float = 0
        var depthSum: Float = 0
        var depthCount: Int = 0
        if let db = preprocessedDepth {
            CVPixelBufferLockBaseAddress(db, .readOnly)
            let dW = CVPixelBufferGetWidth(db)
            let dH = CVPixelBufferGetHeight(db)
            let dRowBytes = CVPixelBufferGetBytesPerRow(db)
            if let dBase = CVPixelBufferGetBaseAddress(db) {
                let dPtr = dBase.assumingMemoryBound(to: Float32.self)
                let dFloatsPerRow = dRowBytes / MemoryLayout<Float32>.stride
                for r in stride(from: 0, to: dH, by: 4) {
                    for c in stride(from: 0, to: dW, by: 4) {
                        let v = dPtr[r * dFloatsPerRow + c]
                        if v > 0.01 && v < 5.0 {
                            depthMin = min(depthMin, v)
                            depthMax = max(depthMax, v)
                            depthSum += v
                            depthCount += 1
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(db, .readOnly)
        }
        let depthAvg = depthCount > 0 ? depthSum / Float(depthCount) : 0

        // ── 7. Volume calculation ───────────────────────────────────────
        let volumes = volumeCalculator.calculate(
            objects: segments,
            depthBuffer: preprocessedDepth,
            pixelsPerCm: pxPerCm,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )

        // ── 8. Serialise to JSON ────────────────────────────────────────
        var payload = [[String: Any]]()
        for i in 0..<segments.count {
            let entry = makeSegmentDict(
                seg: segments[i], vol: volumes[i],
                depthMin: depthMin, depthMax: depthMax, depthAvg: depthAvg
            )
            payload.append(entry)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        // ── 9. Log for debug (Part 14) ──────────────────────────────────
        logResults(
            plate: plate,
            segments: segments,
            volumes: volumes,
            hasDepth: preprocessedDepth != nil
        )

        return json
    }

    // MARK: – Debug logging

    /// Extracted to help the Swift type-checker with a complex dictionary literal.
    private func makeSegmentDict(
        seg: SegmentationService.SegmentedObject,
        vol: VolumeCalculator.FoodVolume,
        depthMin: Float,
        depthMax: Float,
        depthAvg: Float
    ) -> [String: Any] {
        var d = [String: Any]()
        d["label"]       = vol.label
        d["volume_cm3"]  = round(vol.volumeCm3 * 10) / 10
        d["pixel_count"] = vol.pixelCount
        d["confidence"]  = round(Double(seg.confidence) * 1000) / 1000
        d["depth_min_m"] = round(Double(depthMin) * 1000) / 1000
        d["depth_max_m"] = round(Double(depthMax) * 1000) / 1000
        d["depth_avg_m"] = round(Double(depthAvg) * 1000) / 1000
        return d
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
            let conf = String(format: "%.2f", seg.confidence)
            let v = String(format: "%.1f", vol.volumeCm3)
            print("  \(seg.label): \(seg.pixelCount) px, conf \(conf), vol \(v) cm³")
        }
        print("──────────────────────────────────────────")
    }
}
