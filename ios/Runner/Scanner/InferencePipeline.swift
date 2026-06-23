import CoreVideo
import CoreImage
import Foundation
import simd
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
    /// EXPERIMENTAL (#4): when true, compute ARKit scene-mesh volumes and log
    /// them next to the live voxel volumes for comparison. DEFAULT OFF — the
    /// mesh path is untested (needs a LiDAR device) and never replaces the
    /// shipping voxel-fusion output while this is false.
    static var compareSceneMesh = false
    private let meshVolumeEstimator = ARMeshVolumeEstimator()
    /// YOLO*-seg instance-segmentation path (upgraded branch). Used when a
    /// `*-seg.mlmodelc` is bundled; otherwise the dense SegFormer service runs.
    private let yoloSegmentationService = YOLOSegmentationService()
    /// Optional fine-grained food classifier (crop-and-classify hybrid). Runs
    /// once per scan over the largest instance crops to refine labels, then
    /// unloads before the memory-heavy 3-D phase. Inert until a classifier
    /// `.mlmodelc` is bundled.
    private let foodClassifier = FoodClassifierService()
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
        // `plate.rect` is the crop fed to segmentation AND the rect every
        // downstream consumer (assignLabels, monocular scale) uses to map masks
        // back to the image, so it must stay the single source of truth. When no
        // plate is found, `centerFallback` now returns a centred SQUARE region
        // (full short side) — no aspect distortion when resized to the square
        // model input, and it captures the whole frame height for off-centre or
        // plateless foods (e.g. a banana on a bare table).
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

        // ── 2b. ML Kit food labels (hint, not a hard gate) ──────────────
        // ML Kit's generic ~400-label model is weak on isolated produce: a
        // lone banana on a bare table often scores "Banana"/"Food" below the
        // 0.40 gate even though it clearly IS food. We therefore run it for its
        // label-override hints but DEFER the food-presence decision until after
        // our own (far more reliable) food-trained segmentation has run — see
        // step 3a. A confident YOLO-seg result is allowed to overrule the veto.
        let mlKitResult = mlKitValidator.validate(pixelBuffer: topFrame.pixelBuffer)
        print("[SCAN] mlKit: hasFood=\(mlKitResult.hasFood), labels=\(mlKitResult.labels.map { "\($0.normalised)(\(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", "))")

        // ── 3. Segmentation ─────────────────────────────────────────────
        // Observability: surface which backend actually ran. The YOLO path is
        // only active when a *-seg.mlmodelc is bundled; otherwise SegFormer runs.
        let useYolo = yoloSegmentationService.isAvailable
        print("[PIPELINE] segmentation backend: \(useYolo ? "YOLO-seg" : "SegFormer")")
        var segments: [SegmentationService.SegmentedObject]
        do {
            if useYolo {
                segments = try yoloSegmentationService.segment(pixelBuffer: preprocessedRGB)
            } else {
                segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
            }
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

        // ── 3a. Food-presence decision ──────────────────────────────────
        // Trust a confident, food-trained YOLO-seg detection over ML Kit's
        // generic veto. ML Kit can only abort the scan when the active backend
        // is NOT our food model (legacy SegFormer, which over-classifies and
        // genuinely needs the veto) OR when YOLO itself produced no confident
        // food instance.
        let yoloConfident = useYolo &&
            (segments.map { $0.confidence }.max() ?? 0) >= 0.35
        if !mlKitResult.hasFood && !yoloConfident {
            print("[SCAN] food-presence: REJECT (mlKit veto, no confident YOLO segment)")
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.noFoodDetected("mlkit_food_gate_rejected")
        }
        if !mlKitResult.hasFood {
            print("[SCAN] food-presence: ML Kit veto OVERRULED by confident YOLO segment (\(segments.first?.label ?? "?"), conf \(String(format: "%.2f", segments.first?.confidence ?? 0)))")
        }

        // Override the largest segment's label with ML Kit's best specific
        // food when available. See `applyMlKitLabelOverride` for the policy.
        segments = applyMlKitLabelOverride(segments: segments, mlKit: mlKitResult)

        // Crop-and-classify refinement: when a dedicated fine-grained food
        // classifier is bundled, run it ONCE on the top frame over the largest
        // instance crops for higher-accuracy names than whole-frame ML Kit.
        segments = refineLabelsWithClassifier(
            segments: segments,
            frame: preprocessedRGB,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )

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
            // Real side-view height (Task 1.2): when the user tilted to a side
            // view, segment that frame and measure the dominant food's true
            // vertical extent via the pinhole model, replacing the height prior.
            let measuredHeightCm = recorder.sideFrame.flatMap {
                frame in autoreleasepool { measureSideHeightCm(frame) }
            }
            let estimate = try monocularEstimator.estimate(
                segments: segments,
                topFrame: topFrame,
                sideFrame: recorder.sideFrame,
                maskWidth: preprocessor.modelInputWidth,
                maskHeight: preprocessor.modelInputHeight,
                measuredHeightCm: measuredHeightCm,
                preprocessedRGB: preprocessedRGB,
                tableDistanceCm: recorder.tableDistanceCm
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

        // EXPERIMENTAL (#4, default-off): compare scene-mesh volumes vs the live
        // voxel volumes. Pure telemetry — does not affect the exported result.
        if Self.compareSceneMesh, !recorder.meshAnchors.isEmpty {
            let meshVols = meshVolumeEstimator.computeVolumes(
                meshAnchors:  recorder.meshAnchors,
                segments:     segments,
                topTransform: topFrame.cameraTransform,
                topIntrinsics: topFrame.cameraIntrinsics,
                imageWidth:   CVPixelBufferGetWidth(topFrame.pixelBuffer),
                imageHeight:  CVPixelBufferGetHeight(topFrame.pixelBuffer),
                maskWidth:    preprocessor.modelInputWidth,
                maskHeight:   preprocessor.modelInputHeight,
                plateRect:    plate.rect
            )
            for obj in foodObjects {
                let m = meshVols[obj.label]
                print("[EVAL] mesh-compare label=\(obj.label) voxel_cm3=\(String(format: "%.1f", obj.volumeCm3)) mesh_cm3=\(m.map { String(format: "%.1f", $0) } ?? "nil")")
            }
        }

        let baseName = "scan3d_\(Int(Date().timeIntervalSince1970 * 1000))"
        guard let url = exporter.export(
            objects: foodObjects,
            baseName: baseName,
            textureSource: topFrame.pixelBuffer
        ) else {
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
            // [EVAL] one line per food for known-weight calibration (#3).
            print("[EVAL] label=\(obj.label) volume_cm3=\(String(format: "%.1f", obj.volumeCm3)) voxels=\(obj.voxelCount) mode=lidar_mesh")
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
        if avgConfidence < 0.35 {
            print("[SCAN] foodPresenceGate: REJECT avgConfidence < 0.35")
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

    /// Measure the dominant food's true vertical height (cm) from the side
    /// view. Segments the side frame, takes the largest food mask, measures its
    /// extent along the gravity-aligned image axis (robust to portrait OR
    /// landscape via the camera transform), and converts pixels → cm with the
    /// pinhole model (focal length × assumed 30 cm hold distance). Returns nil
    /// when there is no side frame / food, or the result is implausible — the
    /// estimator then falls back to the class height prior. Purely additive: it
    /// can never make the estimate worse than the prior-only path.
    private func measureSideHeightCm(
        _ sideFrame: FrameCaptureService.CapturedFrame
    ) -> Double? {
        guard let pre = preprocessor.preprocess(
            pixelBuffer: sideFrame.pixelBuffer, plateRect: nil
        ) else { return nil }

        let sideSegments: [SegmentationService.SegmentedObject]
        do {
            sideSegments = yoloSegmentationService.isAvailable
                ? try yoloSegmentationService.segment(pixelBuffer: pre)
                : try segmentationService.segment(pixelBuffer: pre)
        } catch {
            print("[PIPELINE] side-height: segmentation failed: \(error)")
            return nil
        }
        guard let largest = sideSegments.first, !largest.mask.isEmpty else {
            return nil
        }

        // Which image axis runs vertically? Project world-up onto the camera
        // basis: whichever of the camera's right/up vectors aligns more with
        // gravity tells us whether image columns or rows are the vertical axis.
        let t = sideFrame.cameraTransform
        let camRight = simd_normalize(
            simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
        let camUp = simd_normalize(
            simd_float3(t.columns.1.x, t.columns.1.y, t.columns.1.z))
        let worldUp = simd_float3(0, 1, 0)
        let useColumns =
            abs(simd_dot(camRight, worldUp)) >= abs(simd_dot(camUp, worldUp))

        // Food mask extent along the chosen (vertical) axis, in mask pixels.
        let maskH = largest.mask.count
        let maskW = largest.mask.first?.count ?? 0
        guard maskH > 0, maskW > 0 else { return nil }
        var minIdx = Int.max
        var maxIdx = -1
        if useColumns {
            for r in 0..<maskH {
                let row = largest.mask[r]
                for c in 0..<maskW where row[c] == 1 {
                    if c < minIdx { minIdx = c }
                    if c > maxIdx { maxIdx = c }
                }
            }
        } else {
            for r in 0..<maskH where largest.mask[r].contains(1) {
                if r < minIdx { minIdx = r }
                if r > maxIdx { maxIdx = r }
            }
        }
        guard maxIdx >= minIdx else { return nil }

        // Mask extent → full-frame pixels → cm via the pinhole model.
        let maskExtent = Double(maxIdx - minIdx + 1)
        let maskDim = Double(useColumns ? maskW : maskH)
        let fullDim = Double(useColumns
            ? CVPixelBufferGetWidth(sideFrame.pixelBuffer)
            : CVPixelBufferGetHeight(sideFrame.pixelBuffer))
        let pixelExtentFull = maskExtent * (fullDim / maskDim)

        let k = sideFrame.cameraIntrinsics
        let focal = Double(useColumns ? k.columns.0.x : k.columns.1.y)
        guard focal > 1 else { return nil }

        let distanceCm = 30.0 // guided hold distance (matches scan guidance)
        let heightCm = pixelExtentFull * distanceCm / focal

        guard heightCm >= 0.5, heightCm <= 25.0 else {
            print("[PIPELINE] side-height: \(String(format: "%.1f", heightCm)) cm out of range — ignoring")
            return nil
        }
        print("[PIPELINE] side-view measured height: \(String(format: "%.1f", heightCm)) cm (axis=\(useColumns ? "cols" : "rows"))")
        return heightCm
    }

    /// Replace low-trust segmentation labels with ML Kit's confident specific
    /// foods. ML Kit returns whole-frame labels (not per-instance), so we map
    /// its distinct specific foods onto the largest segments in confidence
    /// order: the most-confident food to the largest segment, the next to the
    /// second largest, and so on. This still fixes "my tomato got called
    /// chicken" on the foreground item, but no longer drops a strong secondary
    /// match (e.g. a banana beside a bigger plate of rice) just because it is
    /// not the single largest object. A segment keeps its original label when
    /// ML Kit has no confident specific food left for that slot.
    private func applyMlKitLabelOverride(
        segments: [SegmentationService.SegmentedObject],
        mlKit: MLKitFoodValidator.ValidationResult
    ) -> [SegmentationService.SegmentedObject] {
        guard !segments.isEmpty else { return segments }

        // Distinct specific foods (by canonical name), highest confidence
        // first, so two "banana" hints don't consume two segment slots.
        var seen = Set<String>()
        let candidates = mlKit.overrideCandidates.filter {
            seen.insert($0.normalised).inserted
        }
        guard !candidates.isEmpty else { return segments }

        // Segments arrive largest-first; assign one distinct food per segment.
        var out = segments
        let count = min(candidates.count, segments.count)
        for i in 0..<count {
            let food = candidates[i]
            let seg = out[i]
            // No-op when ML Kit and segmentation already agree.
            if seg.label.lowercased() == food.normalised { continue }
            out[i] = SegmentationService.SegmentedObject(
                label:      food.normalised,
                classIndex: seg.classIndex,
                mask:       seg.mask,
                pixelCount: seg.pixelCount,
                centroid:   seg.centroid,
                // Keep the higher of the two confidences — the segmentation
                // confidence is a per-pixel softmax max over only 10 classes,
                // unreliable for label identity, so ML Kit's score is usually a
                // better calibrated trust signal here.
                confidence: max(seg.confidence, food.confidence)
            )
            print("[InferencePipeline] ML Kit override [\(i)]: \(seg.label) → \(food.normalised) (conf \(food.confidence))")
        }
        return out
    }

    /// Crop-and-classify refinement (hybrid). For the few largest instances,
    /// crop the food region (via Vision `regionOfInterest`, no extra buffer)
    /// and replace the label with a dedicated classifier's high-accuracy guess.
    /// Bounded to `topK` crops and unloaded afterwards to protect RAM.
    private func refineLabelsWithClassifier(
        segments: [SegmentationService.SegmentedObject],
        frame: CVPixelBuffer,
        maskWidth: Int,
        maskHeight: Int
    ) -> [SegmentationService.SegmentedObject] {
        guard foodClassifier.isAvailable, !segments.isEmpty else { return segments }
        defer { foodClassifier.unload() }

        let topK = 3
        let confidenceFloor: Float = 0.45
        let order = segments.indices.sorted {
            segments[$0].pixelCount > segments[$1].pixelCount
        }
        var updated = segments
        for index in order.prefix(topK) {
            let segment = segments[index]
            guard let roi = Self.regionOfInterest(
                for: segment.mask, width: maskWidth, height: maskHeight
            ) else { continue }
            do {
                guard let (label, confidence) = try foodClassifier.classify(
                    pixelBuffer: frame, regionOfInterest: roi
                ), confidence >= confidenceFloor else { continue }
                updated[index] = SegmentationService.SegmentedObject(
                    label: label,
                    classIndex: segment.classIndex,
                    mask: segment.mask,
                    pixelCount: segment.pixelCount,
                    centroid: segment.centroid,
                    confidence: max(segment.confidence, confidence)
                )
                print("[Classifier] refined \(segment.label) → \(label) (\(String(format: "%.2f", confidence)))")
            } catch {
                print("[Classifier] classify failed: \(error)")
                break // model trouble — stop refining this scan
            }
        }
        return updated
    }

    /// Tight bounding box of a binary mask as a Vision region of interest
    /// (normalised, bottom-left origin), padded ~8% for classifier context.
    private static func regionOfInterest(
        for mask: [[UInt8]], width: Int, height: Int
    ) -> CGRect? {
        guard width > 0, height > 0, mask.count == height else { return nil }
        var minRow = height, maxRow = -1, minCol = width, maxCol = -1
        for r in 0..<height {
            let row = mask[r]
            if row.count != width { continue }
            for c in 0..<width where row[c] == 1 {
                if r < minRow { minRow = r }
                if r > maxRow { maxRow = r }
                if c < minCol { minCol = c }
                if c > maxCol { maxCol = c }
            }
        }
        guard maxRow >= minRow, maxCol >= minCol else { return nil }
        let padRow = Int(Double(maxRow - minRow + 1) * 0.08)
        let padCol = Int(Double(maxCol - minCol + 1) * 0.08)
        let r0 = max(0, minRow - padRow)
        let r1 = min(height - 1, maxRow + padRow)
        let c0 = max(0, minCol - padCol)
        let c1 = min(width - 1, maxCol + padCol)
        let w = Double(width)
        let h = Double(height)
        return CGRect(
            x: Double(c0) / w,
            y: 1.0 - Double(r1 + 1) / h, // flip to Vision's bottom-left origin
            width: Double(c1 - c0 + 1) / w,
            height: Double(r1 - r0 + 1) / h
        )
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
