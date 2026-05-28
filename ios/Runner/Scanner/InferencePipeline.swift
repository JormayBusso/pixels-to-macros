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

    /// Stage 1 3-D exporter: turns the fused voxel grid into a USDZ (or OBJ)
    /// scene of textured per-food meshes.
    private let exporter           = Food3DExporter()

    /// File path of the most recently rendered scan overlay image.
    private(set) var lastScanImagePath: String?

    /// File path of the most recently exported 3-D model (USDZ / USDC / OBJ).
    /// `nil` when the last scan produced no exportable food clusters.
    private(set) var lastModel3DPath: String?

    /// Per-object metadata for the most recently exported 3-D model. Order
    /// matches the `MDLMesh` nodes in `lastModel3DPath` 1:1 so Flutter UI
    /// (the ingredient list) and the SceneKit viewer (selection / focus)
    /// can address the same objects by `id`. Empty when no 3-D export was
    /// produced. Each entry contains: `id`, `label`, `volume_cm3`,
    /// `voxel_count`, `confidence`.
    private(set) var lastModel3DObjects: [[String: Any]] = []

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

        // ── 10. Render and save scan thumbnail (plain cropped frame) ───
        renderAndSaveScanOverlay(
            topFrameBuffer: topFrame.pixelBuffer,
            plateRect: plate.rect
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
        // SINGLE SOURCE OF TRUTH: `clusterVolumes()` returns per-label
        // volume after plate subtraction + connected-components gating —
        // the same voxels used to build the 3-D mesh. The fallback
        // (`fallbackVolumes`) is ONLY applied to labels that produced no
        // surviving cluster, so voxel-derived numbers always win when they
        // exist. This guarantees the macro panel and the USDZ mesh never
        // disagree about how much food is on the plate.
        let fusedVolumes = fusion.totalOccupiedVoxels > 10
            ? fusion.clusterVolumes()
            : [:]
        let volumes: [String: Double]
        if !fusedVolumes.isEmpty {
            var mergedVolumes = fallbackVolumes(
                segments: segments,
                topFrame: topFrame,
                cropRect: cropRect
            )
            // Voxel-derived volume ALWAYS overrides the 2-D fallback when
            // a cluster survived plate subtraction + the min-voxel gate.
            for (label, volume) in fusedVolumes where volume > 0 {
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

        // ── 6b. Export fused voxels as a 3-D model (Stage 1+) ───────────
        // Reads the SAME clusters produced in step 6, so geometry and
        // volume can never drift. Surface Nets runs at most once per
        // cluster per scan (no redundant mesh passes).
        lastModel3DPath = nil
        lastModel3DObjects = []
        if fusion.totalOccupiedVoxels > 10 {
            let foodObjects = fusion.exportFoodObjects(
                topPixelBuffer: topFrame.pixelBuffer,
                topTransform:   topFrame.cameraTransform,
                topIntrinsics:  topFrame.cameraIntrinsics,
                imageWidth:     CVPixelBufferGetWidth(topFrame.pixelBuffer),
                imageHeight:    CVPixelBufferGetHeight(topFrame.pixelBuffer)
            )
            if foodObjects.isEmpty {
                // Validation gate (Stage 1+ rule #7): no cluster passed the
                // plate-subtraction + min-voxel-count check. Flutter side
                // will see `model3dPath == null` and fall back to the 2-D
                // thumbnail. Reason logged for debugging.
                print("[InferencePipeline] 3D export skipped: insufficient_voxel_density")
            } else {
                let baseName = "scan3d_\(Int(Date().timeIntervalSince1970 * 1000))"
                if let url = exporter.export(objects: foodObjects, baseName: baseName) {
                    lastModel3DPath = url.path
                    // Per-object metadata mirrors the MDLMesh order written
                    // by Food3DExporter. Each entry is bridge-ready: only
                    // JSON-safe primitives (String / Double / Int).
                    let segConfidence = Dictionary(
                        uniqueKeysWithValues: segments.map { ($0.label, Double($0.confidence)) }
                    )
                    lastModel3DObjects = foodObjects.map { obj -> [String: Any] in
                        return [
                            "id":           obj.id,
                            "label":        obj.label,
                            "volume_cm3":   round(obj.volumeCm3 * 10) / 10,
                            "voxel_count":  obj.voxelCount,
                            "confidence":   round((segConfidence[obj.label] ?? 1.0) * 1000) / 1000,
                        ]
                    }
                    print("[InferencePipeline] 3D model saved: \(url.path) " +
                          "(\(foodObjects.count) object\(foodObjects.count == 1 ? "" : "s"))")
                }
            }
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

        // Render and save scan thumbnail (plain cropped frame)
        renderAndSaveScanOverlay(
            topFrameBuffer: topFrame.pixelBuffer,
            plateRect: plate.rect
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

    /// Crop the top camera frame to the plate region and save it as a JPEG
    /// thumbnail for the scan-history UI. The pseudo-3D dot overlay was
    /// removed in Stage 1 — the real 3D output lives in `lastModel3DPath`.
    func renderAndSaveScanOverlay(
        topFrameBuffer: CVPixelBuffer,
        plateRect: CGRect?
    ) {
        lastScanImagePath = nil

        let ciBase = CIImage(cvPixelBuffer: topFrameBuffer)
        let imgWidth = CGFloat(CVPixelBufferGetWidth(topFrameBuffer))
        let imgHeight = CGFloat(CVPixelBufferGetHeight(topFrameBuffer))

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

        guard let jpegData = UIImage(cgImage: cgResult).jpegData(compressionQuality: 0.85) else {
            return
        }

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

}
