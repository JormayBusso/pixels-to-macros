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
    /// Optional open-vocabulary recogniser (MobileCLIP). When its image encoder
    /// + label-embedding table are bundled, it names crops by nearest food in
    /// the app vocabulary — covering foods outside the segmenter's class list.
    /// Runs once per scan and unloads like the classifier. Inert until bundled.
    private let mobileClip = MobileCLIPService()
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
        case dualSilhouetteFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .noTopFrame:            return "Top frame has not been captured"
            case .noFoodDetected(let reason): return "No food detected. (\(reason))"
            case .preprocessingFailed:   return "Frame preprocessing failed"
            case .segmentationFailed(let e): return "Segmentation failed: \(e.localizedDescription)"
            case .volumeFailed:          return "Volume calculation failed"
            case .model3DExportFailed(let reason):
                return "3D scan failed. Please rescan. (\(reason))"
            case .dualSilhouetteFailed(let reason, _):
                return "Dual-silhouette reconstruction failed. (\(reason))"
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
        print("[SCAN] build=2026-07-18e (reverted MobileSAM refiner + depth-relief → exact dual-silhouette; colour from photos)")
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
            (segments.map { $0.confidence }.max() ?? 0) >= 0.25
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

        // Box-prompted MobileSAM mask refinement: when the encoder+decoder are
        // bundled, tighten each coarse food mask into a pixel-exact silhouette so
        // the top/side reconstruction has cleaner outlines. Fully fail-safe — any
        // per-segment failure keeps the original mask. Inert until bundled.
        if MobileSamRefiner.shared.isAvailable {
            segments = MobileSamRefiner.shared.refine(
                segments: segments,
                pixelBuffer: preprocessedRGB
            )
        }

        // Crop-and-classify refinement: when a dedicated fine-grained food
        // classifier is bundled, run it ONCE on the top frame over the largest
        // instance crops for higher-accuracy names than whole-frame ML Kit.
        segments = refineLabelsWithClassifier(
            segments: segments,
            frame: preprocessedRGB,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )

        // Open-vocabulary refinement (MobileCLIP): names crops by nearest food
        // in the app vocabulary, so composite/regional foods the fixed class
        // lists miss still get a usable label. Runs after the classifier and
        // unloads its encoder before the 3-D phase.
        segments = refineLabelsWithOpenVocab(
            segments: segments,
            frame: preprocessedRGB,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )

        // Colour sanity: the ML models ignore colour, so a green cucumber can be
        // named "ice cream" / "chocolate cake". Read each segment's real mean
        // colour from the mask-aligned frame, log it, and correct labels that
        // grossly contradict it. The [COLOR] log also reveals a wrong mask (one
        // sitting on a white plate reads family=white/grey).
        segments = applyColorSanity(
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
        // top-view segmentation mask, using the side view only when its
        // silhouette validates as a profile for those top-view objects.
        if !recorder.hasDepthData {
            var sideProfiles: [MonocularVolumeEstimator.SideProfile] = []
            if let sideFrame = recorder.sideFrame {
                let extractedProfiles = autoreleasepool {
                    extractSideProfiles(from: sideFrame, topFrame: topFrame)
                }
                let check = monocularEstimator.validateDualSilhouette(
                    segments: segments, sideProfiles: extractedProfiles)
                let debug = dualSilhouetteDebugJSON(
                    topValid: check.topValid, sideValid: check.sideValid,
                    alignment: check.alignmentScore, segConfTop: check.segConfTop,
                    segConfSide: check.segConfSide, attempt: 1, reason: check.reason)
                print("[DUALHULL] \(debug)")
                if check.valid {
                    sideProfiles = extractedProfiles
                    print("[PIPELINE] camera fallback: accepted sideProfiles=\(sideProfiles.count)")
                } else {
                    print("[PIPELINE] camera fallback: side invalid (\(check.reason)); using top-mask fallback")
                }
            } else {
                let dbg = dualSilhouetteDebugJSON(
                    topValid: true, sideValid: false, alignment: 0,
                    segConfTop: segments.map { $0.confidence }.max() ?? 0,
                    segConfSide: 0, attempt: 1, reason: "missing_side_view")
                print("[DUALHULL] \(dbg)")
                print("[PIPELINE] camera fallback: missing side view; using top-mask fallback")
            }
            let estimate = try monocularEstimator.estimate(
                segments: segments,
                topFrame: topFrame,
                sideFrame: recorder.sideFrame,
                sideProfiles: sideProfiles,
                maskWidth: preprocessor.modelInputWidth,
                maskHeight: preprocessor.modelInputHeight,
                measuredHeightCm: nil,
                preprocessedRGB: preprocessedRGB,
                tableDistanceCm: recorder.tableDistanceCm
            )
            lastModel3DPath = estimate.modelPath
            lastModel3DObjects = estimate.objects
            print("[PIPELINE] camera estimate success: true")
            print("[PIPELINE] model3dPath: \(estimate.modelPath)")
            print("[PIPELINE] file exists: \(FileManager.default.fileExists(atPath: estimate.modelPath))")
            return estimate.json
        }

        // ── 3c. Bowl on a LiDAR device ──────────────────────────────────
        // A food in a bowl is occluded: neither the side camera NOR LiDAR depth
        // can see the food's hidden underside (the food surface blocks the view
        // straight down into the bowl). So a detected bowl is reconstructed with
        // the SAME rounded-cavity model as the non-LiDAR path — this keeps the
        // 3-D model identical on both sensor paths and avoids meshing the
        // container walls as food. Only fires when the conservative bowl
        // heuristic matches; every other LiDAR scan is unchanged and still runs
        // DepthFusion below.
        if monocularEstimator.isBowlScene(
            segments: segments,
            topFrame: topFrame,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        ) {
            print("[PIPELINE] LiDAR bowl detected — routing to rounded-cavity reconstruction")
            let estimate = try monocularEstimator.estimate(
                segments: segments,
                topFrame: topFrame,
                sideFrame: nil,
                sideProfiles: [],
                maskWidth: preprocessor.modelInputWidth,
                maskHeight: preprocessor.modelInputHeight,
                measuredHeightCm: nil,
                preprocessedRGB: preprocessedRGB,
                tableDistanceCm: recorder.tableDistanceCm
            )
            lastModel3DPath = estimate.modelPath
            lastModel3DObjects = estimate.objects
            print("[PIPELINE] LiDAR bowl estimate success: true, path=\(estimate.modelPath)")
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
            imageHeight:    CVPixelBufferGetHeight(topFrame.pixelBuffer),
            sidePixelBuffer: recorder.sideFrame?.pixelBuffer,
            sideTransform: recorder.sideFrame?.cameraTransform,
            sideIntrinsics: recorder.sideFrame?.cameraIntrinsics,
            sideImageWidth: recorder.sideFrame.map { CVPixelBufferGetWidth($0.pixelBuffer) } ?? 0,
            sideImageHeight: recorder.sideFrame.map { CVPixelBufferGetHeight($0.pixelBuffer) } ?? 0
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
            baseName: baseName
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
            let dims = Self.meshDimensionsCm(obj.vertices)
            return [
                "id":           obj.id,
                "label":        obj.label,
                "volume_cm3":   round(obj.volumeCm3 * 10) / 10,
                "voxel_count":  obj.voxelCount,
                "confidence":   round(confidence * 1000) / 1000,
                "scan_mode":    "lidar_mesh",
                "volume_source": "display_mesh",
                "display_mesh_volume_cm3": round(obj.volumeCm3 * 10) / 10,
                "mesh_volume_cm3": round(obj.volumeCm3 * 10) / 10,
                "surface_extraction_mode": "lidar_surface_nets",
                "width_cm": round(dims.width * 10) / 10,
                "depth_cm": round(dims.depth * 10) / 10,
                "height_cm": round(dims.height * 10) / 10,
                "estimated":    false,
            ]
        }

        // ── 7. Serialise ONLY exported 3-D objects to JSON ──────────────
        var payload = [[String: Any]]()
        for obj in foodObjects {
            let seg = segByLabel[obj.label]
            let confidence = Double(seg?.confidence ?? 1.0)
            let dims = Self.meshDimensionsCm(obj.vertices)
            var d = [String: Any]()
            d["id"]          = obj.id
            d["label"]       = obj.label
            d["volume_cm3"]  = round(obj.volumeCm3 * 10) / 10
            d["voxel_count"] = obj.voxelCount
            d["pixel_count"] = seg?.pixelCount ?? obj.voxelCount
            d["confidence"]  = round(confidence * 1000) / 1000
            d["frames_used"] = recorder.lightFrames.count
            d["scan_mode"] = "lidar_mesh"
            d["volume_source"] = "display_mesh"
            d["display_mesh_volume_cm3"] = round(obj.volumeCm3 * 10) / 10
            d["mesh_volume_cm3"] = round(obj.volumeCm3 * 10) / 10
            d["surface_extraction_mode"] = "lidar_surface_nets"
            d["width_cm"] = round(dims.width * 10) / 10
            d["depth_cm"] = round(dims.depth * 10) / 10
            d["height_cm"] = round(dims.height * 10) / 10
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

    private static func meshDimensionsCm(_ vertices: [SIMD3<Float>]) -> (width: Double, depth: Double, height: Double) {
        guard let first = vertices.first else { return (0, 0, 0) }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        var minZ = first.z, maxZ = first.z
        for vertex in vertices.dropFirst() {
            minX = min(minX, vertex.x); maxX = max(maxX, vertex.x)
            minY = min(minY, vertex.y); maxY = max(maxY, vertex.y)
            minZ = min(minZ, vertex.z); maxZ = max(maxZ, vertex.z)
        }
        return (
            width: Double(maxX - minX) * 100.0,
            depth: Double(maxZ - minZ) * 100.0,
            height: Double(maxY - minY) * 100.0
        )
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

        if foodFraction < 0.008 {
            print("[SCAN] foodPresenceGate: REJECT foodFraction < 0.008")
            return false
        }
        // A CONFIDENT, food-filled frame is a real (possibly multi-item) plate —
        // a slice of bread with cucumber, peppers and egg on the side is many
        // segments with no single dominant item, which must NOT be mistaken for
        // speckle noise. The "speckled / many-tiny / fills-the-frame" rejections
        // below therefore only fire when confidence is ALSO weak (true
        // hallucination on a non-food scene). This is what lets multi-item
        // plates scan instead of being thrown away.
        let confidentScene = avgConfidence >= 0.50
        let strongTopSilhouette = (segments.first?.pixelCount ?? 0) >= 400 &&
            largestFraction >= 0.004 && foodFraction >= 0.008
        if avgConfidence < 0.25 {
            if strongTopSilhouette {
                print("[SCAN] foodPresenceGate: ALLOW low-confidence but clear top silhouette")
            } else {
                print("[SCAN] foodPresenceGate: REJECT avgConfidence < 0.32")
                return false
            }
        }
        if foodFraction > 0.80 && segments.count >= 2 && !confidentScene {
            print("[SCAN] foodPresenceGate: REJECT foodFraction > 0.80 with multiple low-confidence segments")
            return false
        }
        if segments.count >= 3 && largestFraction < foodFraction * 0.46 && !confidentScene {
            print("[SCAN] foodPresenceGate: REJECT speckled (3+ low-confidence segs, largest too small)")
            return false
        }
        if segments.count >= 5 && largestFraction < 0.03 && !confidentScene {
            print("[SCAN] foodPresenceGate: REJECT 5+ low-confidence segments all tiny")
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

    /// Per-attempt dual-silhouette diagnostics. Emitted to the log and returned
    /// to Flutter (as the FlutterError details) so the failure UI can explain
    /// what to fix. Mirrors the fields the spec requires.
    private func dualSilhouetteDebugJSON(
        topValid: Bool, sideValid: Bool, alignment: Double,
        segConfTop: Float, segConfSide: Float, attempt: Int, reason: String
    ) -> String {
        let dict: [String: Any] = [
            "top_silhouette_valid": topValid,
            "side_silhouette_valid": sideValid,
            "alignment_score": (alignment * 1000).rounded() / 1000,
            "segmentation_confidence_top": (Double(segConfTop) * 1000).rounded() / 1000,
            "segmentation_confidence_side": (Double(segConfSide) * 1000).rounded() / 1000,
            "attempt_number": attempt,
            "failure_reason": reason,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{\"failure_reason\":\"\(reason)\",\"attempt_number\":\(attempt)}"
    }

    /// Extract real side-view silhouette profiles for the monocular visual-hull
    /// estimator. This is the important non-LiDAR shape path: the top frame
    /// supplies the plate footprint and this side frame supplies the vertical
    /// contour across the matching top-footprint axis.
    private func extractSideProfiles(
        from sideFrame: FrameCaptureService.CapturedFrame,
        topFrame: FrameCaptureService.CapturedFrame
    ) -> [MonocularVolumeEstimator.SideProfile] {
        guard let pre = preprocessor.preprocess(
            pixelBuffer: sideFrame.pixelBuffer, plateRect: nil
        ) else { return [] }

        let sideSegments: [SegmentationService.SegmentedObject]
        do {
            sideSegments = yoloSegmentationService.isAvailable
                ? try yoloSegmentationService.segment(pixelBuffer: pre)
                : try segmentationService.segment(pixelBuffer: pre)
        } catch {
            print("[PIPELINE] side-profile: segmentation failed: \(error)")
            return []
        }
        guard !sideSegments.isEmpty else {
            print("[PIPELINE] side-profile: no side segments")
            return []
        }

        let axes = sideProfileAxes(sideFrame: sideFrame, topFrame: topFrame)
        let imageWidth = CVPixelBufferGetWidth(sideFrame.pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(sideFrame.pixelBuffer)
        let profiles = sideSegments.prefix(4).compactMap { segment in
            makeSideProfile(
                segment: segment,
                axes: axes,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
        }
        print("[PIPELINE] side-profile: profiles=\(profiles.count), " +
              profiles.map { "\($0.label)(axis=\($0.topAxis.rawValue)\($0.reversed ? "R" : ""), ar=\(String(format: "%.2f", $0.aspectRatio)), fill=\(String(format: "%.2f", $0.meanNormalizedHeight)))" }.joined(separator: ", "))
        return profiles
    }

    private typealias SideProfileAxes = (
        verticalUsesColumns: Bool,
        topAxis: MonocularVolumeEstimator.SideProfile.TopAxis,
        reversed: Bool
    )

    private func sideProfileAxes(
        sideFrame: FrameCaptureService.CapturedFrame,
        topFrame: FrameCaptureService.CapturedFrame
    ) -> SideProfileAxes {
        func normalized(_ v: simd_float3) -> simd_float3? {
            let len = simd_length(v)
            guard len > 0.0001 else { return nil }
            return v / len
        }
        func tableProjected(_ v: simd_float3) -> simd_float3? {
            normalized(simd_float3(v.x, 0, v.z))
        }

        let worldUp = simd_float3(0, 1, 0)
        let sideT = sideFrame.cameraTransform
        let sideRight = normalized(simd_float3(sideT.columns.0.x, sideT.columns.0.y, sideT.columns.0.z)) ?? simd_float3(1, 0, 0)
        let sideUp = normalized(simd_float3(sideT.columns.1.x, sideT.columns.1.y, sideT.columns.1.z)) ?? simd_float3(0, 1, 0)

        // Image columns follow camera-right; image rows increase downward, so
        // rows follow -camera-up. Whichever image axis best aligns with gravity
        // is the side-mask vertical axis. The other is the side horizontal axis.
        let verticalUsesColumns = abs(simd_dot(sideRight, worldUp)) >= abs(simd_dot(sideUp, worldUp))
        let sideHorizontal = verticalUsesColumns ? -sideUp : sideRight

        let topT = topFrame.cameraTransform
        let topCols = tableProjected(simd_float3(topT.columns.0.x, topT.columns.0.y, topT.columns.0.z)) ?? simd_float3(1, 0, 0)
        let topRows = tableProjected(-simd_float3(topT.columns.1.x, topT.columns.1.y, topT.columns.1.z)) ?? simd_float3(0, 0, 1)
        let sideHorizontalProjected = tableProjected(sideHorizontal) ?? topCols

        let dotCols = simd_dot(sideHorizontalProjected, topCols)
        let dotRows = simd_dot(sideHorizontalProjected, topRows)
        if abs(dotCols) >= abs(dotRows) {
            return (verticalUsesColumns, .columns, dotCols < 0)
        }
        return (verticalUsesColumns, .rows, dotRows < 0)
    }

    private func makeSideProfile(
        segment: SegmentationService.SegmentedObject,
        axes: SideProfileAxes,
        imageWidth: Int,
        imageHeight: Int
    ) -> MonocularVolumeEstimator.SideProfile? {
        let mask = segment.mask
        let maskH = mask.count
        let maskW = mask.first?.count ?? 0
        guard maskH > 0, maskW > 0, segment.pixelCount > 0 else { return nil }

        var minHorizontal = Int.max
        var maxHorizontal = -1
        var minVertical = Int.max
        var maxVertical = -1

        for r in 0..<maskH {
            let row = mask[r]
            for c in 0..<maskW where row[c] == 1 {
                let horizontal = axes.verticalUsesColumns ? r : c
                let vertical = axes.verticalUsesColumns ? c : r
                minHorizontal = min(minHorizontal, horizontal)
                maxHorizontal = max(maxHorizontal, horizontal)
                minVertical = min(minVertical, vertical)
                maxVertical = max(maxVertical, vertical)
            }
        }
        guard maxHorizontal >= minHorizontal, maxVertical >= minVertical else { return nil }

        let horizontalExtent = maxHorizontal - minHorizontal + 1
        let verticalExtent = maxVertical - minVertical + 1
        let sampleCount = min(192, max(24, horizontalExtent))
        var heights = [Double](repeating: 0, count: sampleCount)
        var bottoms = [Double](repeating: 0, count: sampleCount)
        var tops = [Double](repeating: 0, count: sampleCount)
        var hasSample = [Bool](repeating: false, count: sampleCount)

        for sampleIndex in 0..<sampleCount {
            let h0 = minHorizontal + Int((Double(sampleIndex) * Double(horizontalExtent) / Double(sampleCount)).rounded(.down))
            let h1 = minHorizontal + max(0, Int((Double(sampleIndex + 1) * Double(horizontalExtent) / Double(sampleCount)).rounded(.up)) - 1)
            var localMinV = Int.max
            var localMaxV = -1

            if axes.verticalUsesColumns {
                for r in max(0, h0)...min(maskH - 1, h1) {
                    let row = mask[r]
                    for c in 0..<maskW where row[c] == 1 {
                        localMinV = min(localMinV, c)
                        localMaxV = max(localMaxV, c)
                    }
                }
            } else {
                for r in 0..<maskH {
                    let row = mask[r]
                    for c in max(0, h0)...min(maskW - 1, h1) where row[c] == 1 {
                        localMinV = min(localMinV, r)
                        localMaxV = max(localMaxV, r)
                    }
                }
            }

            if localMaxV >= localMinV {
                heights[sampleIndex] = Double(localMaxV - localMinV + 1) / Double(max(1, verticalExtent))
                // Image vertical axis can be rows or columns depending on how
                // the phone is held in landscape. Normalize from bottom-up:
                // 0 = visible side-mask bottom, 1 = visible side-mask top.
                let bottomOffset = Double(maxVertical - localMaxV) / Double(max(1, verticalExtent))
                let topOffset = Double(maxVertical - localMinV + 1) / Double(max(1, verticalExtent))
                bottoms[sampleIndex] = min(1.0, max(0.0, bottomOffset))
                tops[sampleIndex] = min(1.0, max(0.0, topOffset))
                hasSample[sampleIndex] = true
            }
        }

        // Interpolate tiny segmentation gaps inside the side silhouette, but
        // keep true endpoints tapered. This avoids a notch in the exported mesh
        // when the side mask has a one-column dropout.
        for i in 0..<sampleCount where !hasSample[i] {
            var left: Int?
            var right: Int?
            if i > 0 {
                for j in stride(from: i - 1, through: 0, by: -1) where hasSample[j] {
                    left = j
                    break
                }
            }
            if i + 1 < sampleCount {
                for j in (i + 1)..<sampleCount where hasSample[j] {
                    right = j
                    break
                }
            }
            switch (left, right) {
            case let (l?, r?):
                let t = Double(i - l) / Double(r - l)
                heights[i] = heights[l] * (1.0 - t) + heights[r] * t
                bottoms[i] = bottoms[l] * (1.0 - t) + bottoms[r] * t
                tops[i] = tops[l] * (1.0 - t) + tops[r] * t
            case let (l?, nil):
                heights[i] = heights[l] * 0.35
                bottoms[i] = bottoms[l]
                tops[i] = max(bottoms[i], bottoms[i] + heights[i])
            case let (nil, r?):
                heights[i] = heights[r] * 0.35
                bottoms[i] = bottoms[r]
                tops[i] = max(bottoms[i], bottoms[i] + heights[i])
            default:
                heights[i] = 0
                bottoms[i] = 0
                tops[i] = 0
            }
        }

        // Keep the side silhouette as extracted from the photo. We still fill
        // tiny missing interior samples above, but we do not blur the contour;
        // smoothing here made the displayed mesh prettier while moving the side
        // outline away from the exact captured mask.
        let exactHeights = heights.map { min(1.0, max(0.0, $0)) }
        let exactBottoms = bottoms.map { min(1.0, max(0.0, $0)) }
        let exactTops = tops.map { min(1.0, max(0.0, $0)) }

        let verticalMaskDim = Double(axes.verticalUsesColumns ? maskW : maskH)
        let horizontalMaskDim = Double(axes.verticalUsesColumns ? maskH : maskW)
        let verticalFullDim = Double(axes.verticalUsesColumns ? imageWidth : imageHeight)
        let horizontalFullDim = Double(axes.verticalUsesColumns ? imageHeight : imageWidth)
        let verticalFullPx = Double(verticalExtent) * verticalFullDim / max(1.0, verticalMaskDim)
        let horizontalFullPx = Double(horizontalExtent) * horizontalFullDim / max(1.0, horizontalMaskDim)
        let aspectRatio = verticalFullPx / max(1.0, horizontalFullPx)
        let coverage = Double(segment.pixelCount) / Double(max(1, maskW * maskH))
        guard aspectRatio > 0.05, aspectRatio < 4.0, coverage > 0.001 else { return nil }

        return MonocularVolumeEstimator.SideProfile(
            label: segment.label,
            classIndex: segment.classIndex,
            topAxis: axes.topAxis,
            reversed: axes.reversed,
            normalizedHeights: exactHeights,
            normalizedBottoms: exactBottoms,
            normalizedTops: exactTops,
            aspectRatio: aspectRatio,
            coverage: coverage,
            confidence: segment.confidence,
            pixelCount: segment.pixelCount,
            textureHorizontalUsesRows: axes.verticalUsesColumns,
            textureHorizontalMin: Double(minHorizontal) / max(1.0, horizontalMaskDim),
            textureHorizontalMax: Double(maxHorizontal + 1) / max(1.0, horizontalMaskDim),
            textureVerticalMin: Double(minVertical) / max(1.0, verticalMaskDim),
            textureVerticalMax: Double(maxVertical + 1) / max(1.0, verticalMaskDim)
        )
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
            let segmentationTrusted = seg.confidence >= 0.35
            let mlKitMuchStronger = food.confidence >= max(0.72, seg.confidence + 0.22)
            if segmentationTrusted && !mlKitMuchStronger {
                print("[InferencePipeline] ML Kit hint kept as hint [\(i)]: seg=\(seg.label) conf=\(String(format: "%.2f", seg.confidence)) hint=\(food.normalised) conf=\(String(format: "%.2f", food.confidence))")
                continue
            }
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
            print("[InferencePipeline] ML Kit override [\(i)]: \(seg.label) conf=\(String(format: "%.2f", seg.confidence)) -> \(food.normalised) conf=\(String(format: "%.2f", food.confidence))")
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
        guard !segments.isEmpty else { return segments }
        guard foodClassifier.isAvailable else {
            print("[Classifier] unavailable; keeping segmentation labels")
            return segments
        }
        defer { foodClassifier.unload() }

        let topK = min(6, max(4, segments.count))
        // The dedicated Food-101 classifier is useful, but its label space is
        // incomplete for raw produce. Only strong or same-family predictions
        // can rename a segment; medium guesses are diagnostics, not truth.
        let confidenceFloor: Float = 0.35
        let unsureSegmentation: Float = 0.32
        let strongOverride: Float = 0.68
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
                let segmentationUnsure = segment.confidence < unsureSegmentation
                let classifierStrong = confidence >= strongOverride
                let sameFood = Self.labelsCompatible(segment.label, label)
                // Never let a multi-ingredient composite dish rename a clear
                // single whole food (e.g. a tomato → "caprese salad").
                if Self.isCompositeDish(label), Self.isWholeProduce(segment.label), !sameFood {
                    print("[Classifier] blocked composite \(label) from overriding produce \(segment.label)")
                    continue
                }
                // The Food-101 classifier has NO raw produce classes, so any
                // attempt to rename a whole-produce segment to a (non-matching)
                // Food-101 dish is wrong by construction — block it outright.
                if Self.isWholeProduce(segment.label), !sameFood {
                    print("[Classifier] blocked \(label) from renaming whole produce \(segment.label)")
                    continue
                }
                let usableCorrection = classifierStrong ||
                    (segmentationUnsure && confidence >= 0.50) ||
                    (sameFood && confidence >= 0.45)
                guard usableCorrection else {
                    print("[Classifier] kept \(segment.label) (seg \(String(format: "%.2f", segment.confidence))) over \(label) (\(String(format: "%.2f", confidence)); strong=\(classifierStrong); same=\(sameFood))")
                    continue
                }
                let chosenLabel = sameFood && !classifierStrong && !segmentationUnsure
                    ? segment.label
                    : label
                updated[index] = SegmentationService.SegmentedObject(
                    label: chosenLabel,
                    classIndex: segment.classIndex,
                    mask: segment.mask,
                    pixelCount: segment.pixelCount,
                    centroid: segment.centroid,
                    confidence: max(segment.confidence, confidence)
                )
                print("[Classifier] \(chosenLabel == segment.label ? "confirmed" : "refined") \(segment.label) → \(chosenLabel) (\(String(format: "%.2f", confidence)))")
            } catch {
                print("[Classifier] classify failed: \(error)")
                break // model trouble — stop refining this scan
            }
        }
        return updated
    }

    /// Open-vocabulary refinement via MobileCLIP. For the few largest instances,
    /// crop the food region and name it by nearest food in the app vocabulary.
    /// MobileCLIP's labels are already app-vocabulary words, so the result maps
    /// straight to nutrition. Bounded to `topK` crops; encoder unloaded after.
    private func refineLabelsWithOpenVocab(
        segments: [SegmentationService.SegmentedObject],
        frame: CVPixelBuffer,
        maskWidth: Int,
        maskHeight: Int
    ) -> [SegmentationService.SegmentedObject] {
        guard !segments.isEmpty else { return segments }
        guard mobileClip.isAvailable else {
            print("[MobileCLIP] unavailable; keeping current labels")
            return segments
        }
        defer { mobileClip.unload() }

        let topK = min(8, max(4, segments.count))
        let confidenceFloor: Float = 0.25
        let unsureSegmentation: Float = 0.32
        let strongConfidence: Float = 0.64
        let strongMargin: Float = 0.025
        let veryStrongConfidence: Float = 0.78
        let veryStrongMargin: Float = 0.045
        let order = segments.indices.sorted {
            segments[$0].pixelCount > segments[$1].pixelCount
        }
        var updated = segments
        for index in order.prefix(topK) {
            let segment = updated[index]
            guard let roi = Self.regionOfInterest(
                for: segment.mask, width: maskWidth, height: maskHeight
            ) else { continue }
            do {
                let candidates = try mobileClip.classifyTopK(
                    pixelBuffer: frame,
                    regionOfInterest: roi,
                    limit: 5
                )
                guard let best = candidates.first,
                      best.confidence >= confidenceFloor else { continue }
                let runnerUpCosine = candidates.dropFirst().first?.cosine ?? best.cosine
                let margin = max(0, best.cosine - runnerUpCosine)
                let segmentationUnsure = segment.confidence < unsureSegmentation
                let sameFood = Self.labelsCompatible(segment.label, best.label)
                // Never let a multi-ingredient composite dish rename a clear
                // single whole food (e.g. a tomato → "caprese salad"). A red
                // produce blob is a classic false match for tomato-based dishes.
                if Self.isCompositeDish(best.label), Self.isWholeProduce(segment.label), !sameFood {
                    print("[MobileCLIP] blocked composite \(best.label) from overriding produce \(segment.label)")
                    continue
                }
                let clipStrong = best.confidence >= strongConfidence && margin >= strongMargin
                let clipVeryStrong = best.confidence >= veryStrongConfidence && margin >= veryStrongMargin
                let topSummary = candidates.prefix(3)
                    .map { candidate in
                        "\(candidate.label)(p=\(String(format: "%.2f", candidate.confidence)),cos=\(String(format: "%.3f", candidate.cosine)))"
                    }
                    .joined(separator: ", ")
                // A confident open-vocabulary name may correct a WRONG base
                // label on non-produce items. Cooked, meat and composite foods
                // are exactly where the base segmenter mislabels (a beige
                // tuna-mayo filling read as "pork"), and where a strong CLIP
                // match is trustworthy. Whole produce is intentionally excluded
                // here — it still needs a very-strong match to be renamed, so a
                // red blob can never become "caprese salad".
                let correctsNonProduce = !Self.isWholeProduce(segment.label) && clipStrong
                let usableCorrection = sameFood || clipVeryStrong || correctsNonProduce || (segmentationUnsure && clipStrong)
                guard usableCorrection else {
                    print("[MobileCLIP] kept \(segment.label) (seg \(String(format: "%.2f", segment.confidence))) over \(best.label) margin=\(String(format: "%.3f", margin)) top=[\(topSummary)]")
                    continue
                }
                let chosenLabel = sameFood && !clipVeryStrong && !segmentationUnsure && !correctsNonProduce
                    ? segment.label
                    : best.label
                updated[index] = SegmentationService.SegmentedObject(
                    label: chosenLabel,
                    classIndex: segment.classIndex,
                    mask: segment.mask,
                    pixelCount: segment.pixelCount,
                    centroid: segment.centroid,
                    confidence: max(segment.confidence, best.confidence)
                )
                print("[MobileCLIP] \(chosenLabel == segment.label ? "confirmed" : "refined") \(segment.label) → \(chosenLabel) margin=\(String(format: "%.3f", margin)) top=[\(topSummary)]")
            } catch {
                print("[MobileCLIP] classify failed: \(error)")
                break
            }
        }
        return updated
    }

    /// Colour-consistency guard. The base models have no notion of colour, so a
    /// green cucumber can be mislabelled "ice cream" / "chocolate cake". Read
    /// each segment's mean colour from the (mask-aligned) preprocessed frame,
    /// log it, and when a label grossly contradicts the colour, replace it with
    /// a colour-consistent produce label. The [COLOR] log also exposes a wrong
    /// mask — one that sits on the white plate reads family=white/grey.
    private func applyColorSanity(
        segments: [SegmentationService.SegmentedObject],
        frame: CVPixelBuffer,
        maskWidth: Int,
        maskHeight: Int
    ) -> [SegmentationService.SegmentedObject] {
        guard !segments.isEmpty,
              let bgra = Food3DTextureBaker.bgraCopy(of: frame) else { return segments }
        CVPixelBufferLockBaseAddress(bgra, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(bgra, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(bgra) else { return segments }
        let w = CVPixelBufferGetWidth(bgra)
        let h = CVPixelBufferGetHeight(bgra)
        let rowBytes = CVPixelBufferGetBytesPerRow(bgra)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var updated = segments
        for i in segments.indices {
            let seg = segments[i]
            let mh = seg.mask.count
            let mw = seg.mask.first?.count ?? 0
            guard mh > 0, mw > 0 else { continue }
            let step = max(1, max(mw, mh) / 48)
            var rSum = 0.0, gSum = 0.0, bSum = 0.0, n = 0.0
            var r = 0
            while r < mh {
                var c = 0
                while c < mw {
                    if seg.mask[r][c] == 1 {
                        let x = min(w - 1, c * w / max(mw, 1))
                        let y = min(h - 1, r * h / max(mh, 1))
                        let off = y * rowBytes + x * 4
                        rSum += Double(ptr[off + 2])
                        gSum += Double(ptr[off + 1])
                        bSum += Double(ptr[off])
                        n += 1
                    }
                    c += step
                }
                r += step
            }
            guard n > 0 else { continue }
            let rr = rSum / n, gg = gSum / n, bb = bSum / n
            let family = Self.colorFamily(r: rr, g: gg, b: bb)
            print("[COLOR] seg#\(i) \(seg.label): rgb=(\(Int(rr)),\(Int(gg)),\(Int(bb))) family=\(family)")
            if let corrected = Self.colorCorrectedLabel(currentLabel: seg.label, family: family),
               corrected != seg.label.lowercased() {
                print("[COLOR] corrected \(seg.label) -> \(corrected) (colour=\(family))")
                updated[i] = SegmentationService.SegmentedObject(
                    label: corrected,
                    classIndex: seg.classIndex,
                    mask: seg.mask,
                    pixelCount: seg.pixelCount,
                    centroid: seg.centroid,
                    confidence: seg.confidence
                )
            }
        }
        return updated
    }

    private static func colorFamily(r: Double, g: Double, b: Double) -> String {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        // Near-grey (plate/background, cream/white foods): no hue to judge.
        if maxC - minC < 26 { return maxC > 165 ? "white" : (maxC < 70 ? "dark" : "grey") }
        if g > r * 1.12 && g >= b * 1.02 && g > 55 { return "green" }
        if r > g * 1.25 && r > b * 1.2 && r > 70 { return "red" }
        if r > 150 && g > 85 && g < 195 && b < 95 { return "orange" }
        return "other"
    }

    private static func colorCorrectedLabel(currentLabel: String, family: String) -> String? {
        let l = currentLabel.lowercased()
        switch family {
        case "green":
            let ok = ["cucumber", "lettuce", "broccoli", "salad", "spinach",
                      "pea", "bean", "zucchini", "avocado", "kale", "celery",
                      "lime", "kiwi", "asparagus", "cabbage", "herb", "pepper",
                      "pickle", "edamame", "sprout", "green"]
            return ok.contains(where: { l.contains($0) }) ? nil : "cucumber"
        case "red":
            let ok = ["tomato", "strawberr", "apple", "pepper", "cherry",
                      "radish", "beet", "raspberr", "watermelon", "pomegranate",
                      "chili", "red"]
            return ok.contains(where: { l.contains($0) }) ? nil : "tomato"
        case "orange":
            let ok = ["carrot", "orange", "pumpkin", "sweet potato", "mango",
                      "apricot", "peach", "squash", "cantaloupe", "papaya"]
            return ok.contains(where: { l.contains($0) }) ? nil : "carrot"
        default:
            return nil
        }
    }

    private static let recognitionDescriptorWords: Set<String> = [
        "baked", "black", "boiled", "brown", "chopped", "cooked", "diced",
        "fresh", "fried", "green", "grilled", "large", "organic", "plain",
        "raw", "red", "roasted", "sliced", "small", "steamed", "white",
        "whole", "yellow",
    ]

    /// Multi-ingredient composite dishes. Their weight and nutrition bear no
    /// resemblance to a raw ingredient, so they must never silently rename a
    /// clearly single whole food (see `isWholeProduce`).
    private static let compositeDishLabels: Set<String> = [
        "caprese", "salad", "bruschetta", "pizza", "sandwich", "burger",
        "taco", "burrito", "wrap", "lasagna", "casserole", "stew", "curry",
        "soup", "platter", "skewer", "kebab", "quesadilla", "nachos",
        "sushi", "risotto", "paella", "omelette", "frittata", "parmigiana",
    ]

    /// Whole, single foods (mostly raw produce) that are visually uniform and a
    /// classic false match for composite dishes built around them.
    private static let wholeProduceLabels: Set<String> = [
        "tomato", "apple", "orange", "banana", "egg", "onion", "potato",
        "peach", "plum", "lemon", "lime", "cherry", "grape", "strawberry",
        "carrot", "cucumber", "pepper", "mushroom", "avocado", "pear",
        "mango", "kiwi", "melon", "watermelon", "pineapple", "broccoli",
        "cauliflower", "radish", "beet", "corn", "zucchini", "eggplant",
    ]

    private static func isCompositeDish(_ label: String) -> Bool {
        !recognitionTokens(label).isDisjoint(with: compositeDishLabels)
    }

    private static func isWholeProduce(_ label: String) -> Bool {
        !recognitionTokens(label).isDisjoint(with: wholeProduceLabels)
    }

    private static func labelsCompatible(_ first: String, _ second: String) -> Bool {
        let firstTokens = recognitionTokens(first)
        let secondTokens = recognitionTokens(second)
        guard !firstTokens.isEmpty, !secondTokens.isEmpty else { return false }
        return !firstTokens.intersection(secondTokens).isEmpty
    }

    private static func recognitionTokens(_ label: String) -> Set<String> {
        let words = label.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { singularRecognitionToken($0) }
            .filter { token in
                token.count > 2 && !recognitionDescriptorWords.contains(token)
            }
        return Set(words)
    }

    private static func singularRecognitionToken(_ rawToken: String) -> String {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasSuffix("ies"), token.count > 4 {
            token = String(token.dropLast(3)) + "y"
        } else if token.hasSuffix("oes"), token.count > 4 {
            token = String(token.dropLast(2))
        } else if token.hasSuffix("s"), token.count > 3 {
            token = String(token.dropLast())
        }
        return token
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
