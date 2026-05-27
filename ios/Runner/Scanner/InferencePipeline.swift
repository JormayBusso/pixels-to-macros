import CoreVideo
import CoreImage
import Foundation
import UIKit

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
    /// Generic Google ML Kit Image Labeler used as (1) a hard food-presence
    /// gate before we trust segmentation, and (2) a label-override hint that
    /// fixes mislabelled foods that the bundled 10-class mini segmentation
    /// model cannot recognise (tomato, banana, broccoli, …).
    private let mlKitValidator     = MLKitFoodValidator()

    /// File path of the most recently rendered scan overlay image.
    private(set) var lastScanImagePath: String?

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

        // ── 4b. ML Kit food-presence gate ───────────────────────────────
        // Run on the ORIGINAL high-res top frame so ML Kit gets the best
        // possible pixels (it has its own internal resizing).
        let mlKitResult = mlKitValidator.validate(pixelBuffer: topFrame.pixelBuffer)
        guard mlKitResult.hasFood else {
            print("[InferencePipeline] ML Kit gate rejected scan — no food labels above threshold")
            return "[]"
        }

        // ── 5. Segmentation ─────────────────────────────────────────────
        var segments: [SegmentationService.SegmentedObject]
        do {
            segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            throw PipelineError.segmentationFailed(error)
        }

        // ── 5b. ML Kit fallback when segmentation returns empty ─────────
        // The bundled mini model has only 10 classes. For out-of-vocabulary
        // foods (banana, tomato, broccoli, …) the per-pixel confidence is
        // very low and buildObjects may filter everything out. When ML Kit
        // already validated food presence AND has a specific food label, we
        // synthesise a segment covering the non-background area so the scan
        // still returns a useful result with ML Kit's label.
        if segments.isEmpty, let bestFood = mlKitResult.bestSpecificFood {
            segments = [synthesiseFallbackSegment(
                preprocessedRGB: preprocessedRGB,
                label: bestFood.normalised,
                confidence: bestFood.confidence
            )]
            print("[InferencePipeline] Fallback: segmentation empty, using ML Kit label '\(bestFood.normalised)' (conf \(bestFood.confidence))")
        } else if segments.isEmpty, mlKitResult.hasFood,
                  let topLabel = mlKitResult.labels.first(where: { $0.isSpecificFood }) {
            // ML Kit has a specific food label but below override threshold —
            // still better than returning nothing.
            segments = [synthesiseFallbackSegment(
                preprocessedRGB: preprocessedRGB,
                label: topLabel.normalised,
                confidence: topLabel.confidence
            )]
            print("[InferencePipeline] Fallback: using lower-conf ML Kit label '\(topLabel.normalised)' (conf \(topLabel.confidence))")
        }

        guard !segments.isEmpty else {
            // No food detected — return empty list
            return "[]"
        }

        // Optionally override the label of the largest segment with ML Kit's
        // specific food guess. This fixes the common "mini model called my
        // tomato 'chicken'" failure mode while keeping the segmentation mask
        // and depth-derived volume unchanged.
        segments = applyMlKitLabelOverride(segments: segments, mlKit: mlKitResult)

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
        let maskPixelsPerCm = CGFloat(preprocessor.modelInputWidth) /
            PlateDetector.defaultDiameterCm
        let volumes = volumeCalculator.calculate(
            objects: segments,
            depthBuffer: preprocessedDepth,
            pixelsPerCm: maskPixelsPerCm,
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

        // ── 10. Render and save scan overlay image ─────────────────────
        renderAndSaveScanOverlay(
            topFrameBuffer: topFrame.pixelBuffer,
            segments: segments,
            plateRect: plate.rect,
            topDepthBuffer: topFrame.depthBuffer
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
        let cropRect: CGRect? = plate.rect

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

        // ── 2b. ML Kit food-presence gate ───────────────────────────────
        let mlKitResult = mlKitValidator.validate(pixelBuffer: topFrame.pixelBuffer)
        guard mlKitResult.hasFood else {
            print("[InferencePipeline] runVideoScan: ML Kit gate rejected — labels: \(mlKitResult.labels.map { $0.text })")
            return "[]"
        }

        // ── 3. Segmentation ─────────────────────────────────────────────
        var segments: [SegmentationService.SegmentedObject]
        do {
            segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            print("[InferencePipeline] runVideoScan: segmentation failed: \(error)")
            return "[]"
        }

        // ── 3b. ML Kit fallback for out-of-vocabulary foods ─────────────
        if segments.isEmpty, let bestFood = mlKitResult.bestSpecificFood {
            segments = [synthesiseFallbackSegment(
                preprocessedRGB: preprocessedRGB,
                label: bestFood.normalised,
                confidence: bestFood.confidence
            )]
            print("[InferencePipeline] runVideoScan fallback: ML Kit label '\(bestFood.normalised)'")
        } else if segments.isEmpty, mlKitResult.hasFood,
                  let topLabel = mlKitResult.labels.first(where: { $0.isSpecificFood }) {
            segments = [synthesiseFallbackSegment(
                preprocessedRGB: preprocessedRGB,
                label: topLabel.normalised,
                confidence: topLabel.confidence
            )]
            print("[InferencePipeline] runVideoScan fallback: lower-conf ML Kit '\(topLabel.normalised)'")
        }

        guard !segments.isEmpty else {
            return "[]"
        }

        // Override the largest segment's label with ML Kit's best specific
        // food when available. See `applyMlKitLabelOverride` for the policy.
        segments = applyMlKitLabelOverride(segments: segments, mlKit: mlKitResult)

        guard passesFoodPresenceGate(
            segments: segments,
            topFrame: topFrame,
            recorder: recorder,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        ) else {
            print("[InferencePipeline] runVideoScan: rejected as no-food / implausible food scene")
            return "[]"
        }

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

        // Fuse locked top-view depth first, then the side-view sweep.
        for frame in recorder.topViewFrames {
            fusion.integrate(
                depthBuffer:      frame.depthBuffer,
                cameraTransform:  frame.cameraTransform,
                cameraIntrinsics: frame.cameraIntrinsics,
                imageWidth:  frame.imageWidth,
                imageHeight: frame.imageHeight
            )
        }

        // Fuse recorded side-view light frames.
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
        let plateNormRect = plate.rect

        fusion.assignLabels(
            segments:           segments,
            plateRect:          plateNormRect,
            topFrameTransform:  topFrame.cameraTransform,
            topFrameIntrinsics: topFrame.cameraIntrinsics,
            topDepthBuffer:     topFrame.depthBuffer,
            maskWidth:          preprocessor.modelInputWidth,
            maskHeight:         preprocessor.modelInputHeight,
            imageWidth:  CVPixelBufferGetWidth(topFrame.pixelBuffer),
            imageHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer)
        )

        // ── 6. Volumes ──────────────────────────────────────────────────
        let fusedVolumes = fusion.totalOccupiedVoxels > 10 ? fusion.allVolumes() : [:]
        let volumes: [String: Double]
        if fusedVolumes.values.contains(where: { $0 > 1.0 }) {
            var mergedVolumes = fallbackVolumes(
                segments: segments,
                topFrame: topFrame,
                cropRect: cropRect
            )
            for (label, volume) in fusedVolumes where volume > 1.0 {
                mergedVolumes[label] = volume
            }
            volumes = mergedVolumes
        } else {
            volumes = fallbackVolumes(
                segments: segments,
                topFrame: topFrame,
                cropRect: cropRect
            )
        }

        // ── 7. Serialise to JSON ────────────────────────────────────────
        var payload = [[String: Any]]()
        for seg in segments {
            let volume = volumes[seg.label] ?? 0
            guard volume >= 3.0 else { continue }
            var d = [String: Any]()
            d["label"]       = seg.label
            d["volume_cm3"]  = round(volume * 10) / 10
            d["pixel_count"] = seg.pixelCount
            d["confidence"]  = round(Double(seg.confidence) * 1000) / 1000
            d["frames_used"] = recorder.lightFrames.count
            d["depth_min_m"] = 0.0
            d["depth_max_m"] = 0.0
            d["depth_avg_m"] = 0.0
            payload.append(d)
        }

        guard !payload.isEmpty else { return "[]" }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }

        print("──────────── Video Scan Result ──────────")
        print("Frames: \(recorder.frameCount), Voxels: \(fusion.totalOccupiedVoxels)")
        for seg in segments {
            let v = String(format: "%.1f", volumes[seg.label] ?? 0)
            print("  \(seg.label): \(v) cm³, conf \(String(format: "%.2f", seg.confidence))")
        }
        print("─────────────────────────────────────────")

        // Render and save scan overlay image
        renderAndSaveScanOverlay(
            topFrameBuffer: topFrame.pixelBuffer,
            segments: segments,
            plateRect: plate.rect,
            topDepthBuffer: topFrame.depthBuffer
        )

        return json
    }

    private func passesFoodPresenceGate(
        segments: [SegmentationService.SegmentedObject],
        topFrame: FrameCaptureService.CapturedFrame,
        recorder: MultiFrameRecorder,
        maskWidth: Int,
        maskHeight: Int
    ) -> Bool {
        let maskPixels = max(1, maskWidth * maskHeight)
        let foodPixels = segments.reduce(0) { $0 + $1.pixelCount }
        let foodFraction = Double(foodPixels) / Double(maskPixels)
        let largestFraction = Double(segments.first?.pixelCount ?? 0) / Double(maskPixels)
        let avgConfidence = segments.reduce(Float(0)) { $0 + $1.confidence } /
            Float(max(segments.count, 1))

        // Tightened thresholds (May 2026): the bundled mini model has only 10
        // food classes and force-classifies non-food regions, so we err on the
        // side of "no food" rather than serving up a hallucinated label.
        if foodFraction < 0.015 { return false }                  // was 0.025
        if foodFraction > 0.65 && segments.count >= 2 { return false }
        if segments.count >= 3 && largestFraction < foodFraction * 0.46 { return false }
        if avgConfidence < 0.45 { return false }                  // was 0.70
        // Reject "speckled" segmentations — many tiny disconnected blobs are
        // almost always noise rather than real foods.
        if segments.count >= 4 && largestFraction < 0.05 { return false }

        let hasDepth = topFrame.depthBuffer != nil || recorder.hasDepthData
        if hasDepth {
            guard let heightCm = estimateFoodHeightCmIfAvailable(
                topFrame: topFrame,
                recorder: recorder
            ) else { return false }
            if heightCm < 0.7 { return false }
        }

        return true
    }

    /// Replace the label of the largest segment with ML Kit's best specific
    /// food guess when one is available. We only override the *largest*
    /// segment because that is overwhelmingly the foreground food on the
    /// plate; lower-area segments may be sauces, garnish, or noise that the
    /// generic ML Kit labeler does not score highly. This is the single
    /// biggest fix for "my tomato got called chicken" hallucinations from the
    /// 10-class mini model.
    private func applyMlKitLabelOverride(
        segments: [SegmentationService.SegmentedObject],
        mlKit: MLKitFoodValidator.ValidationResult
    ) -> [SegmentationService.SegmentedObject] {
        guard let best = mlKit.bestSpecificFood, !segments.isEmpty else {
            return segments
        }
        let largest = segments[0]
        // No-op when ML Kit and segmentation already agree.
        if largest.label.lowercased() == best.normalised { return segments }
        let overridden = SegmentationService.SegmentedObject(
            label:      best.normalised,
            classIndex: largest.classIndex,
            mask:       largest.mask,
            pixelCount: largest.pixelCount,
            centroid:   largest.centroid,
            // Keep the higher of the two confidences — the segmentation
            // confidence is per-pixel softmax max over only 10 classes which
            // is unreliable for label identity, so ML Kit's score is usually
            // a better calibrated trust signal here.
            confidence: max(largest.confidence, best.confidence)
        )
        var out = segments
        out[0] = overridden
        print("[InferencePipeline] ML Kit override: \(largest.label) → \(best.normalised) (conf \(best.confidence))")
        return out
    }

    /// Synthesise a fallback segment when ML Kit identifies food but the
    /// bundled segmentation model returns nothing (out-of-vocabulary food).
    /// Creates a segment that covers the central 60% of the frame — a
    /// reasonable proxy when we know there IS food but the model doesn't
    /// have the right class.
    private func synthesiseFallbackSegment(
        preprocessedRGB: CVPixelBuffer,
        label: String,
        confidence: Float
    ) -> SegmentationService.SegmentedObject {
        let w = preprocessor.modelInputWidth
        let h = preprocessor.modelInputHeight

        // Create a mask covering the central 60% of the frame
        let marginX = Int(Double(w) * 0.2)
        let marginY = Int(Double(h) * 0.2)
        var mask = [[UInt8]](repeating: [UInt8](repeating: 0, count: w), count: h)
        var pixelCount = 0
        for r in marginY..<(h - marginY) {
            for c in marginX..<(w - marginX) {
                mask[r][c] = 1
                pixelCount += 1
            }
        }

        return SegmentationService.SegmentedObject(
            label: label,
            classIndex: -1,
            mask: mask,
            pixelCount: pixelCount,
            centroid: (row: h / 2, col: w / 2),
            confidence: confidence
        )
    }

    /// Fallback when voxel labelling cannot produce usable volumes. This still
    /// uses the top-frame segmentation mask plus depth/plate geometry, so the
    /// scan returns a useful editable estimate instead of a hard error.
    private func fallbackVolumes(
        segments: [SegmentationService.SegmentedObject],
        topFrame: FrameCaptureService.CapturedFrame,
        cropRect: CGRect?
    ) -> [String: Double] {
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

        let pixelsPerCm = CGFloat(preprocessor.modelInputWidth) /
            PlateDetector.defaultDiameterCm
        let fallback = volumeCalculator.calculate(
            objects:     segments,
            depthBuffer: preprocessedDepth,
            pixelsPerCm: pixelsPerCm,
            maskWidth:   preprocessor.modelInputWidth,
            maskHeight:  preprocessor.modelInputHeight
        )

        let pixelAreaCm2 = pow(1.0 / Double(pixelsPerCm), 2)
        var volumes: [String: Double] = [:]
        for volume in fallback {
            // Ensure tiny/flat depth maps still produce an editable portion.
            let minimumVolume = Double(volume.pixelCount) * pixelAreaCm2 * 1.0
            volumes[volume.label, default: 0] += max(volume.volumeCm3, minimumVolume)
        }
        return volumes
    }

    private func estimateFoodHeightCmIfAvailable(
        topFrame: FrameCaptureService.CapturedFrame,
        recorder: MultiFrameRecorder
    ) -> Double? {
        var heights: [Double] = []
        if let depth = topFrame.depthBuffer,
           let height = estimateHeightCm(from: depth) {
            heights.append(height)
        }
        for frame in recorder.lightFrames.prefix(6) {
            if let height = estimateHeightCm(from: frame.depthBuffer) {
                heights.append(height)
            }
        }
        return heights.max()
    }

    private func estimateHeightCm(from depthBuffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let ptr = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = rowBytes / MemoryLayout<Float32>.stride

        let minRow = height / 4
        let maxRow = height * 3 / 4
        let minCol = width / 4
        let maxCol = width * 3 / 4
        var values: [Float] = []
        for row in Swift.stride(from: minRow, to: maxRow, by: 4) {
            for col in Swift.stride(from: minCol, to: maxCol, by: 4) {
                let depth = ptr[row * floatsPerRow + col]
                if depth > 0.05 && depth < 1.5 {
                    values.append(depth)
                }
            }
        }

        guard values.count >= 20 else { return nil }
        values.sort()
        let near = values[max(0, values.count / 10)]
        let far = values[min(values.count - 1, values.count * 9 / 10)]
        let heightCm = Double(max(0, far - near) * 100.0)
        guard heightCm >= 0.5 else { return nil }
        return min(8.0, max(0.8, heightCm))
    }

    // MARK: – Scan Image Rendering

    /// Render the cropped camera frame with the pseudo-3D point-cloud overlay,
    /// save as JPEG, and store the path in `lastScanImagePath`.
    func renderAndSaveScanOverlay(
        topFrameBuffer: CVPixelBuffer,
        segments: [SegmentationService.SegmentedObject],
        plateRect: CGRect?,
        topDepthBuffer: CVPixelBuffer? = nil
    ) {
        lastScanImagePath = nil

        // 1. Create base image from the original camera frame
        let ciBase = CIImage(cvPixelBuffer: topFrameBuffer)
        let imgWidth = CGFloat(CVPixelBufferGetWidth(topFrameBuffer))
        let imgHeight = CGFloat(CVPixelBufferGetHeight(topFrameBuffer))

        // Crop to the plate region for a clean food-only view
        let cropRect: CGRect
        if let plate = plateRect {
            cropRect = CGRect(
                x: plate.origin.x * imgWidth,
                y: (1.0 - plate.origin.y - plate.height) * imgHeight,
                width: plate.width * imgWidth,
                height: plate.height * imgHeight
            )
        } else {
            cropRect = CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight)
        }

        var baseCropped = ciBase.cropped(to: cropRect)
        baseCropped = baseCropped.transformed(
            by: CGAffineTransform(
                translationX: -cropRect.origin.x,
                y: -cropRect.origin.y
            )
        )

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgResult = ciContext.createCGImage(baseCropped, from: baseCropped.extent) else {
            return
        }

        let croppedImage = UIImage(cgImage: cgResult)
        let previewImage: UIImage
        if let firstSeg = segments.first {
            let maskH = firstSeg.mask.count
            let maskW = maskH > 0 ? firstSeg.mask[0].count : 0
            if maskW > 0 && maskH > 0 {
                previewImage = renderPointCloudPreview(
                    baseImage: croppedImage,
                    segments: segments,
                    maskWidth: maskW,
                    maskHeight: maskH,
                    hasDepth: topDepthBuffer != nil
                )
            } else {
                previewImage = croppedImage
            }
        } else {
            previewImage = croppedImage
        }

        guard let jpegData = previewImage.jpegData(compressionQuality: 0.85) else { return }

        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let filename = "scan_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let url = docs.appendingPathComponent(filename)

        do {
            try jpegData.write(to: url)
            lastScanImagePath = url.path
            print("[InferencePipeline] Scan overlay saved: \(url.path)")
        } catch {
            print("[InferencePipeline] Failed to save scan overlay: \(error)")
        }
    }

    /// Adds a lightweight pseudo-3D point rendering over the real food pixels.
    /// Dots sample actual colors from the camera image so the preview resembles
    /// the scanned food, with a subtle depth-modulated lift for the 3-D aesthetic.
    private func renderPointCloudPreview(
        baseImage: UIImage,
        segments: [SegmentationService.SegmentedObject],
        maskWidth: Int,
        maskHeight: Int,
        hasDepth: Bool
    ) -> UIImage {
        let size = baseImage.size
        let renderer = UIGraphicsImageRenderer(size: size)

        // Pre-render the base into a CGImage so we can sample pixel colours.
        guard let baseCG = baseImage.cgImage else { return baseImage }
        let bitmapW = baseCG.width
        let bitmapH = baseCG.height
        let bytesPerPixel = 4
        let bytesPerRow = bitmapW * bytesPerPixel
        var bitmapData = [UInt8](repeating: 0, count: bitmapH * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapCtx = CGContext(
            data: &bitmapData,
            width: bitmapW,
            height: bitmapH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return baseImage }
        bitmapCtx.draw(baseCG, in: CGRect(x: 0, y: 0, width: bitmapW, height: bitmapH))

        func sampleColor(maskRow: Int, maskCol: Int) -> (UInt8, UInt8, UInt8) {
            let px = min(bitmapW - 1, max(0, maskCol * bitmapW / max(1, maskWidth)))
            let py = min(bitmapH - 1, max(0, maskRow * bitmapH / max(1, maskHeight)))
            let offset = py * bytesPerRow + px * bytesPerPixel
            return (bitmapData[offset], bitmapData[offset + 1], bitmapData[offset + 2])
        }

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            // Dark background behind the food cutout
            UIColor(white: 0.06, alpha: 1.0).setFill()
            context.cgContext.fill(rect)
            // Draw the real food image — this is the primary visual
            baseImage.draw(in: rect)

            let cg = context.cgContext
            cg.setBlendMode(.normal)

            for segment in segments {
                let stride = max(4, Int(sqrt(Double(max(segment.pixelCount, 1))) / 22.0))
                let dotSize = max(1.8, min(size.width, size.height) / 200.0)

                // Pass 1: subtle shadow under food region
                var minRow = maskHeight, maxRow = 0, minCol = maskWidth, maxCol = 0
                for row in 0..<min(maskHeight, segment.mask.count) {
                    let maskRow = segment.mask[row]
                    for col in 0..<min(maskWidth, maskRow.count) where maskRow[col] == 1 {
                        minRow = min(minRow, row); maxRow = max(maxRow, row)
                        minCol = min(minCol, col); maxCol = max(maxCol, col)
                    }
                }
                if minRow <= maxRow && minCol <= maxCol {
                    let shadowRect = CGRect(
                        x: CGFloat(minCol) / CGFloat(maskWidth) * size.width + dotSize,
                        y: CGFloat(minRow) / CGFloat(maskHeight) * size.height + dotSize * 1.5,
                        width: CGFloat(maxCol - minCol + 1) / CGFloat(maskWidth) * size.width,
                        height: CGFloat(maxRow - minRow + 1) / CGFloat(maskHeight) * size.height
                    )
                    UIColor.black.withAlphaComponent(0.12).setFill()
                    cg.fillEllipse(in: shadowRect.insetBy(dx: -dotSize, dy: -dotSize * 0.5))
                }

                // Pass 2: color-sampled dots with depth-based lift
                let maxLift: CGFloat = hasDepth ? 12.0 : 6.0
                for row in Swift.stride(from: 0, to: min(maskHeight, segment.mask.count), by: stride) {
                    let maskRow = segment.mask[row]
                    for col in Swift.stride(from: 0, to: min(maskWidth, maskRow.count), by: stride) where maskRow[col] == 1 {
                        let x = CGFloat(col) / CGFloat(maskWidth) * size.width
                        let y = CGFloat(row) / CGFloat(maskHeight) * size.height

                        // Depth-modulated lift: highest near centroid, tapers at edges
                        let dRow = abs(CGFloat(row - segment.centroid.row)) / max(1.0, CGFloat(maxRow - minRow) * 0.5)
                        let dCol = abs(CGFloat(col - segment.centroid.col)) / max(1.0, CGFloat(maxCol - minCol) * 0.5)
                        let dist = min(1.0, sqrt(dRow * dRow + dCol * dCol))
                        let lift = max(0.0, (1.0 - dist)) * maxLift

                        // Sample the actual food color from the camera image
                        let (sr, sg, sb) = sampleColor(maskRow: row, maskCol: col)

                        // Brighten sampled color slightly for the dot
                        let brighten: CGFloat = 1.12
                        let dotColor = UIColor(
                            red: min(1.0, CGFloat(sr) / 255.0 * brighten),
                            green: min(1.0, CGFloat(sg) / 255.0 * brighten),
                            blue: min(1.0, CGFloat(sb) / 255.0 * brighten),
                            alpha: 0.82
                        )

                        let pointRect = CGRect(
                            x: x - dotSize * 0.5,
                            y: y - lift - dotSize * 0.5,
                            width: dotSize,
                            height: dotSize
                        )
                        dotColor.setFill()
                        cg.fillEllipse(in: pointRect)
                    }
                }

                // Pass 3: crisp edge highlight using category color
                let (er, eg, eb) = rgbForLabel(segment.label)
                let edgeColor = UIColor(
                    red: CGFloat(er) / 255.0,
                    green: CGFloat(eg) / 255.0,
                    blue: CGFloat(eb) / 255.0,
                    alpha: 0.55
                )
                edgeColor.setStroke()
                cg.setLineWidth(max(0.8, min(size.width, size.height) / 280.0))
                for row in Swift.stride(from: 1, to: min(maskHeight - 1, segment.mask.count - 1), by: max(3, stride / 2)) {
                    let maskRow = segment.mask[row]
                    for col in Swift.stride(from: 1, to: min(maskWidth - 1, maskRow.count - 1), by: max(3, stride / 2)) where maskRow[col] == 1 {
                        let edge = segment.mask[row - 1][col] == 0 ||
                            segment.mask[row + 1][col] == 0 ||
                            maskRow[col - 1] == 0 ||
                            maskRow[col + 1] == 0
                        guard edge else { continue }
                        let x = CGFloat(col) / CGFloat(maskWidth) * size.width
                        let y = CGFloat(row) / CGFloat(maskHeight) * size.height
                        cg.strokeEllipse(in: CGRect(x: x - dotSize * 0.7, y: y - dotSize * 0.7, width: dotSize * 1.4, height: dotSize * 1.4))
                    }
                }
            }
        }
    }

    /// Map food labels to RGB colors for mask overlay rendering.
    private func rgbForLabel(_ label: String) -> (UInt8, UInt8, UInt8) {
        let lower = label.lowercased()
        if lower.contains("rice") || lower.contains("egg") { return (253, 230, 138) }
        if lower.contains("bread") || lower.contains("pasta") || lower.contains("potato") { return (217, 119, 6) }
        if lower.contains("chicken") || lower.contains("fish") || lower.contains("steak") || lower.contains("beef") { return (252, 165, 165) }
        if lower.contains("salad") || lower.contains("broccoli") || lower.contains("cucumber") { return (34, 197, 94) }
        if lower.contains("tomato") || lower.contains("apple") || lower.contains("berry") || lower.contains("strawberry") { return (239, 68, 68) }
        if lower.contains("banana") || lower.contains("corn") { return (250, 204, 21) }
        let hash = abs(label.hashValue)
        let palette: [(UInt8, UInt8, UInt8)] = [
            (56, 189, 248),
            (249, 115, 22),
            (167, 139, 250),
            (20, 184, 166),
            (251, 113, 133),
        ]
        return palette[hash % palette.count]
    }
}
