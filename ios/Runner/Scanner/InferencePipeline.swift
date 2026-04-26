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

    // MARK: – Video scan (multi-frame 3-D reconstruction)

    /// Run the multi-frame pipeline from a recorded video sweep.
    ///
    /// Pipeline:
    ///   1. Plate detection + segmentation on the top (first) frame.
    ///   2. Depth fusion: project every recorded depth map into a shared
    ///      world-space voxel grid.
    ///   3. Label each occupied voxel using the top-frame segmentation masks.
    ///   4. Compute per-food volume = occupied labelled voxel count × voxel volume.
    ///   5. Fallback to single-frame plate-heuristic when no depth was available.
    ///
    /// Returns the same JSON format as `run(captureService:)`.
    func runVideoScan(recorder: MultiFrameRecorder) throws -> String {
        // If no top frame was captured (e.g. recording stopped immediately),
        // return empty rather than throwing — Dart will show "no food" UX.
        guard let topFrame = recorder.topFrame else {
            print("[InferencePipeline] runVideoScan: no top frame captured")
            return "[]"
        }

        // ── 1. Plate detection ──────────────────────────────────────────
        let plate    = plateDetector.detect(in: topFrame.pixelBuffer)
        let cropRect: CGRect? = plate.detected ? plate.rect : nil

        // ── 2. Preprocess top frame for CoreML ─────────────────────────
        guard let preprocessedRGB = autoreleasepool(invoking: {
            preprocessor.preprocess(
                pixelBuffer: topFrame.pixelBuffer,
                plateRect: cropRect
            )
        }) else {
            print("[InferencePipeline] runVideoScan: preprocessing failed")
            return "[]"
        }

        // ── 3. Segmentation ─────────────────────────────────────────────
        let segments: [SegmentationService.SegmentedObject]
        do {
            segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            print("[InferencePipeline] runVideoScan: segmentation failed: \(error)")
            throw PipelineError.segmentationFailed(error)
        }
        guard !segments.isEmpty else { return "[]" }

        // ── 4. Multi-frame depth fusion ─────────────────────────────────
        let fusion = DepthFusion()

        // Include top-frame depth first (if available).
        if let topDepth = topFrame.depthBuffer {
            fusion.integrate(
                depthBuffer:      topDepth,
                cameraTransform:  topFrame.cameraTransform,
                cameraIntrinsics: topFrame.cameraIntrinsics,
                imageWidth:  CVPixelBufferGetWidth(topFrame.pixelBuffer),
                imageHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer)
            )
        }

        // Fuse all recorded light frames.
        for frame in recorder.lightFrames {
            fusion.integrate(
                depthBuffer:      frame.depthBuffer,
                cameraTransform:  frame.cameraTransform,
                cameraIntrinsics: frame.cameraIntrinsics,
                imageWidth:  frame.imageWidth,
                imageHeight: frame.imageHeight
            )
        }

        // ── 5. Label voxels from top-frame segmentation ─────────────────
        let plateNormRect = plate.detected
            ? plate.rect
            : CGRect(x: 0, y: 0, width: 1, height: 1)

        fusion.assignLabels(
            segments:           segments,
            plateRect:          plateNormRect,
            topFrameTransform:  topFrame.cameraTransform,
            topFrameIntrinsics: topFrame.cameraIntrinsics,
            maskWidth:          preprocessor.modelInputWidth,
            maskHeight:         preprocessor.modelInputHeight,
            imageWidth:  CVPixelBufferGetWidth(topFrame.pixelBuffer),
            imageHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer)
        )

        // ── 6. Volumes ──────────────────────────────────────────────────
        let volumes: [String: Double]
        if fusion.totalOccupiedVoxels > 10 {
            volumes = fusion.allVolumes()
        } else {
            // No real depth data: fall back to single-frame plate heuristic.
            let pxPerCm = plateDetector.pixelsPerCm(
                plate: plate,
                frameWidth: CVPixelBufferGetWidth(topFrame.pixelBuffer)
            )
            let preprocessedDepth: CVPixelBuffer? = topFrame.depthBuffer.flatMap { depth in
                autoreleasepool {
                    preprocessor.preprocessDepth(
                        depthBuffer:  depth,
                        plateRect:    cropRect,
                        outputWidth:  preprocessor.modelInputWidth,
                        outputHeight: preprocessor.modelInputHeight
                    )
                }
            }
            let fallback = volumeCalculator.calculate(
                objects:    segments,
                depthBuffer: preprocessedDepth,
                pixelsPerCm: pxPerCm,
                maskWidth:  preprocessor.modelInputWidth,
                maskHeight: preprocessor.modelInputHeight
            )
            var vols: [String: Double] = [:]
            for v in fallback { vols[v.label, default: 0] += v.volumeCm3 }
            volumes = vols
        }

        // ── 7. Serialise to JSON ────────────────────────────────────────
        var payload = [[String: Any]]()
        for seg in segments {
            var d = [String: Any]()
            d["label"]       = seg.label
            d["volume_cm3"]  = round((volumes[seg.label] ?? 0) * 10) / 10
            d["pixel_count"] = seg.pixelCount
            d["confidence"]  = round(Double(seg.confidence) * 1000) / 1000
            d["frames_used"] = recorder.lightFrames.count
            d["depth_min_m"] = 0.0
            d["depth_max_m"] = 0.0
            d["depth_avg_m"] = 0.0
            payload.append(d)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }

        print("──────────── Video Scan Result ──────────")
        print("Frames: \(recorder.lightFrames.count), Voxels: \(fusion.totalOccupiedVoxels)")
        for seg in segments {
            let v = String(format: "%.1f", volumes[seg.label] ?? 0)
            print("  \(seg.label): \(v) cm³, conf \(String(format: "%.2f", seg.confidence))")
        }
        print("─────────────────────────────────────────")

        return json
    }
}
