import CoreVideo
import CoreImage
import Foundation
import UIKit

/// Orchestrates the full 3-D scan pipeline:
///
///   captured frames → plate detection → preprocessing → segmentation
///   → voxel fusion → 3-D export → JSON result
///
/// This is the single entry point called by `ScannerPlugin.runVideoInference`.
/// All steps run sequentially to stay within memory limits (Part 3).
final class InferencePipeline {

    // MARK: – Dependencies

    private let plateDetector       = PlateDetector()
    private let preprocessor        = FramePreprocessor()
    private let segmentationService = SegmentationService()
    /// Generic Google ML Kit Image Labeler used as (1) a hard food-presence
    /// gate before we trust segmentation, and (2) a label-override hint that
    /// fixes mislabelled foods that the bundled 10-class mini segmentation
    /// model cannot recognise (tomato, banana, broccoli, …).
    private let mlKitValidator     = MLKitFoodValidator()

    /// Stage 1 3-D exporter: turns the fused voxel grid into a USDZ (or OBJ)
    /// scene of textured per-food meshes.
    private let exporter           = Food3DExporter()

    /// Non-LiDAR fallback: camera-only scale estimation + generated 3-D mesh.
    private let monocularEstimator = MonocularVolumeEstimator()

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
        case noFoodDetected(String)
        case preprocessingFailed
        case segmentationFailed(Error)
        case volumeFailed
        case model3DExportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noTopFrame:            return "Top frame has not been captured"
            case .noFoodDetected(let reason): return "No food detected. (\(reason))"
            case .preprocessingFailed:   return "Frame preprocessing failed"
            case .segmentationFailed(let e): return "Segmentation failed: \(e.localizedDescription)"
            case .volumeFailed:          return "Volume calculation failed"
            case .model3DExportFailed(let reason):
                return "3D scan failed. Please rescan. (\(reason))"
            }
        }
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
    ///   5. Export the labelled voxel clusters as a real 3-D model file.
    ///
    /// Returns JSON metadata only after the exported model exists on disk.
    func runVideoScan(recorder: MultiFrameRecorder) throws -> String {
        lastModel3DPath = nil
        lastModel3DObjects = []

        print("[SCAN] ═══════════ VIDEO SCAN START ═══════════")
        print("[SCAN] recorder: topFrame=\(recorder.topFrame != nil), topViewFrames=\(recorder.topViewFrames.count), lightFrames=\(recorder.lightFrames.count), frameCount=\(recorder.frameCount)")

        // If no top frame was captured (e.g. recording stopped immediately),
        // fail hard. Successful video scans must produce a valid 3-D model.
        guard let topFrame = recorder.topFrame else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("no_top_frame")
        }

        // ── 1. Plate detection ──────────────────────────────────────────
        let plate    = plateDetector.detect(in: topFrame.pixelBuffer)
        let cropRect: CGRect? = plate.rect
        print("[SCAN] plate: detected=\(plate.detected), rect=\(plate.rect), diameterPx=\(Int(plate.diameterPx))")
        print("[SCAN] topFrame: pixelBuffer=\(CVPixelBufferGetWidth(topFrame.pixelBuffer))x\(CVPixelBufferGetHeight(topFrame.pixelBuffer)), depthBuffer=\(topFrame.depthBuffer != nil)")

        // ── 2. Preprocess top frame for CoreML ─────────────────────────
        guard let preprocessedRGB = autoreleasepool(invoking: {
            preprocessor.preprocess(
                pixelBuffer: topFrame.pixelBuffer,
                plateRect: cropRect
            )
        }) else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("preprocessing_failed")
        }

        // ── 2b. ML Kit food-presence gate ───────────────────────────────
        let mlKitResult = mlKitValidator.validate(pixelBuffer: topFrame.pixelBuffer)
        print("[SCAN] mlKit: hasFood=\(mlKitResult.hasFood), labels=\(mlKitResult.labels.map { "\($0.normalised)(\(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", "))")
        guard mlKitResult.hasFood else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.noFoodDetected("mlkit_food_gate_rejected")
        }

        // ── 3. Segmentation ─────────────────────────────────────────────
        var segments: [SegmentationService.SegmentedObject]
        do {
            segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            print("[SCAN] segmentation THREW: \(error)")
            throw PipelineError.segmentationFailed(error)
        }
        print("[SCAN] segmentation: \(segments.count) objects — \(segments.map { "\($0.label)(\($0.pixelCount)px, conf \(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", "))")

        guard !segments.isEmpty else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.noFoodDetected("segmentation_empty")
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
            let maskPixels = max(1, preprocessor.modelInputWidth * preprocessor.modelInputHeight)
            let foodPixels = segments.reduce(0) { $0 + $1.pixelCount }
            let foodFraction = Double(foodPixels) / Double(maskPixels)
            let avgConf = segments.reduce(Float(0)) { $0 + $1.confidence } / Float(max(segments.count, 1))
            print("[SCAN] foodPresenceGate FAILED: foodFraction=\(String(format: "%.4f", foodFraction)), avgConf=\(String(format: "%.3f", avgConf)), hasDepth=\(topFrame.depthBuffer != nil || recorder.hasDepthData)")
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.noFoodDetected("food_presence_gate_failed")
        }
        print("[SCAN] foodPresenceGate PASSED")

        // ── 3b. Non-LiDAR camera fallback ──────────────────────────────
        // If ARKit did not provide scene depth, do NOT force the device
        // through DepthFusion. Generate an estimated 3-D object from the
        // segmentation mask, plate/intrinsics scale, and food shape priors.
        if !recorder.hasDepthData {
            let estimate = try monocularEstimator.estimate(
                segments: segments,
                topFrame: topFrame,
                sideFrame: recorder.sideFrame,
                maskWidth: preprocessor.modelInputWidth,
                maskHeight: preprocessor.modelInputHeight
            )
            lastModel3DPath = estimate.modelPath
            lastModel3DObjects = estimate.objects
            print("[PIPELINE] camera estimate success: true")
            print("[PIPELINE] model3dPath: \(estimate.modelPath)")
            return estimate.json
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
            print("[SCAN] integrated topFrame depth: voxels now \(fusion.totalOccupiedVoxels)")
        } else {
            print("[SCAN] topFrame has NO depth buffer")
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
        print("[SCAN] after topViewFrames(\(recorder.topViewFrames.count)): voxels=\(fusion.totalOccupiedVoxels)")

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
        print("[SCAN] after lightFrames(\(recorder.lightFrames.count)): voxels=\(fusion.totalOccupiedVoxels)")

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

        // ── 6. Voxel clusters + 3-D export (hard contract) ─────────────
        // A successful scan exists ONLY if these voxels produce a real file
        // on disk. No 2-D volume substitute, no thumbnail success path.
        print("[PIPELINE] depth clusters: occupied_voxels=\(fusion.totalOccupiedVoxels), " +
              "top_frames=\(recorder.topViewFrames.count), side_frames=\(recorder.lightFrames.count)")
        guard fusion.totalOccupiedVoxels > 10 else {
            print("[PIPELINE] voxel clusters: 0")
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("no_voxel_grid")
        }

        let voxelClusters = fusion.voxelClusters()
        print("[PIPELINE] voxel clusters: \(voxelClusters.count) " +
              voxelClusters.map { "\($0.id)=\($0.voxelKeys.count)" }.joined(separator: ", "))
        guard !voxelClusters.isEmpty else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("insufficient_voxel_density")
        }

        let foodObjects = fusion.exportFoodObjects(
            topPixelBuffer: topFrame.pixelBuffer,
            topTransform:   topFrame.cameraTransform,
            topIntrinsics:  topFrame.cameraIntrinsics,
            imageWidth:     CVPixelBufferGetWidth(topFrame.pixelBuffer),
            imageHeight:    CVPixelBufferGetHeight(topFrame.pixelBuffer)
        )
        print("[SCAN] exportFoodObjects: \(foodObjects.count) meshes — \(foodObjects.map { "\($0.id)(v=\($0.vertices.count),f=\($0.faces.count/3))" }.joined(separator: ", "))")
        guard !foodObjects.isEmpty else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("mesh_reconstruction_empty")
        }

        let baseName = "scan3d_\(Int(Date().timeIntervalSince1970 * 1000))"
        guard let url = exporter.export(objects: foodObjects, baseName: baseName) else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("exporter_failed")
        }

        let modelExists = FileManager.default.fileExists(atPath: url.path)
        print("[PIPELINE] export success: \(modelExists)")
        print("[PIPELINE] model3dPath: \(url.path)")
        print("[PIPELINE] file exists: \(modelExists)")
        guard modelExists else {
            throw PipelineError.model3DExportFailed("exported_file_missing")
        }

        lastModel3DPath = url.path
        var segByLabel: [String: SegmentationService.SegmentedObject] = [:]
        for seg in segments where segByLabel[seg.label] == nil {
            segByLabel[seg.label] = seg
        }
        lastModel3DObjects = foodObjects.map { obj -> [String: Any] in
            let confidence = Double(segByLabel[obj.label]?.confidence ?? 1.0)
            return [
                "id":           obj.id,
                "label":        obj.label,
                "volume_cm3":   round(obj.volumeCm3 * 10) / 10,
                "voxel_count":  obj.voxelCount,
                "confidence":   round(confidence * 1000) / 1000,
                "scan_mode":    "lidar_mesh",
                "estimated":    false,
            ]
        }

        // ── 7. Serialise ONLY exported 3-D objects to JSON ──────────────
        var payload = [[String: Any]]()
        for obj in foodObjects {
            let seg = segByLabel[obj.label]
            let confidence = Double(seg?.confidence ?? 1.0)
            var d = [String: Any]()
            d["id"]          = obj.id
            d["label"]       = obj.label
            d["volume_cm3"]  = round(obj.volumeCm3 * 10) / 10
            d["voxel_count"] = obj.voxelCount
            d["pixel_count"] = seg?.pixelCount ?? obj.voxelCount
            d["confidence"]  = round(confidence * 1000) / 1000
            d["frames_used"] = recorder.lightFrames.count
            d["scan_mode"] = "lidar_mesh"
            d["estimated"] = false
            d["depth_min_m"] = 0.0
            d["depth_max_m"] = 0.0
            d["depth_avg_m"] = 0.0
            payload.append(d)
        }

        guard !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8)
        else {
            throw PipelineError.model3DExportFailed("json_serialisation_failed")
        }

        print("──────────── Video 3D Scan Result ────────")
        print("Frames: \(recorder.frameCount), Voxels: \(fusion.totalOccupiedVoxels)")
        for obj in foodObjects {
            print("  \(obj.id): \(String(format: "%.1f", obj.volumeCm3)) cm³, " +
                  "voxels \(obj.voxelCount)")
        }
        print("─────────────────────────────────────────")

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

        print("[SCAN] foodPresenceGate: foodFraction=\(String(format: "%.4f", foodFraction)), " +
              "largestFraction=\(String(format: "%.4f", largestFraction)), " +
              "avgConf=\(String(format: "%.3f", avgConfidence)), " +
              "segments=\(segments.count)")

        if foodFraction < 0.015 {
            print("[SCAN] foodPresenceGate: REJECT foodFraction < 0.015")
            return false
        }
        if foodFraction > 0.65 && segments.count >= 2 {
            print("[SCAN] foodPresenceGate: REJECT foodFraction > 0.65 with multiple segments")
            return false
        }
        if segments.count >= 3 && largestFraction < foodFraction * 0.46 {
            print("[SCAN] foodPresenceGate: REJECT speckled (3+ segs, largest too small)")
            return false
        }
        if avgConfidence < 0.45 {
            print("[SCAN] foodPresenceGate: REJECT avgConfidence < 0.45")
            return false
        }
        if segments.count >= 4 && largestFraction < 0.05 {
            print("[SCAN] foodPresenceGate: REJECT 4+ segments all tiny")
            return false
        }

        let hasDepth = topFrame.depthBuffer != nil || recorder.hasDepthData
        if hasDepth {
            let heightCm = estimateFoodHeightCmIfAvailable(
                topFrame: topFrame,
                recorder: recorder
            )
            print("[SCAN] foodPresenceGate: heightCm=\(heightCm.map { String(format: "%.2f", $0) } ?? "nil")")
            // Only reject if we got a definitive height reading that's too flat.
            // nil means depth data was too sparse to estimate — allow the scan to proceed.
            if let h = heightCm, h < 0.5 {
                print("[SCAN] foodPresenceGate: REJECT food too flat (height < 0.5 cm)")
                return false
            }
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

}
