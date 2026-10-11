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

    /// Per-scan bookkeeping for the "we're not sure what this is" signal. Keyed
    /// by a segment's mask centroid (stable across every refinement pass, which
    /// all copy `centroid`). `refinementCandidatesByKey` collects the plausible
    /// classifier / open-vocab guesses that the confidence gate rejected;
    /// `confirmedLabelKeys` records segments whose label a refinement pass DID
    /// confidently correct/confirm. Reset at the start of every scan.
    private var refinementCandidatesByKey: [String: [String]] = [:]
    private var confirmedLabelKeys: Set<String> = []

    /// On-device exemplar learning. `segmentEmbeddingsByKey` caches each
    /// segment's L2-normalised MobileCLIP image embedding (captured during the
    /// open-vocab pass, keyed by mask centroid) so it can be serialised into the
    /// scan JSON — letting a later user label correction be stored locally as an
    /// exemplar. `labelSourceByKey` records segments whose name was resolved by
    /// matching such a stored exemplar (`"user_exemplar"`). `userExemplars` are
    /// the user's locally-stored (label, embedding) corrections, passed in from
    /// Dart per scan; they never leave the device. All reset per scan.
    private var segmentEmbeddingsByKey: [String: [Float]] = [:]
    private var labelSourceByKey: [String: String] = [:]
    private var userExemplars: [UserExemplar] = []

    /// A single user label correction learned on-device: the corrected food
    /// name and the L2-normalised MobileCLIP image embedding of the crop it was
    /// corrected on.
    struct UserExemplar {
        let label: String
        let vector: [Float]
    }

    /// Cosine floor for accepting a stored user exemplar as the label of a new
    /// scan's segment. This is an IMAGE-to-IMAGE comparison in MobileCLIP's
    /// embedding space, which sits far higher than the image-to-TEXT floors the
    /// open-vocab pass uses (`minimumCosineSimilarity` 0.25, strong 0.24, very
    /// strong 0.30): those cross-modal numbers do NOT transfer to same-modality
    /// matching. Empirically, CLIP image-image cosine is ~0.8–1.0 for the same
    /// object, ~0.4–0.7 for merely related items, and ~0.1–0.4 for different
    /// objects; near-duplicate detection commonly uses 0.85–0.9. We deliberately
    /// pick the conservative 0.85 so a learned label is auto-applied ONLY in the
    /// "same food" regime — anything weaker still asks the user, honouring the
    /// "prefer asking over guessing wrong" rule.
    static let userExemplarCosineFloor: Float = 0.85

    /// Below this segmentation confidence a still-unconfirmed label is treated
    /// as an uncertain guess worth asking the user about. Mirrors the
    /// classifier's 0.35 rejection floor: below it the base label is essentially
    /// a coin-flip.
    private static let needsUserLabelConfidenceFloor: Float = 0.35

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
        /// LiDAR with too little fused depth and no usable side silhouette.
        /// Retake guidance; non-LiDAR keeps an explicitly unmeasured top sheet.
        case sideViewRequired(String)

        /// Verbatim message surfaced to Dart with FlutterError code
        /// `SIDE_VIEW_REQUIRED`.
        static let sideViewRequiredMessage = "Side photo did not show the food clearly; retake a level side photo."

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
            case .sideViewRequired:
                return PipelineError.sideViewRequiredMessage
            }
        }
    }

    /// Monocular gate: the side photo must exist AND contain at least one food
    /// silhouette, or no height can be measured. Returns the failure reason, or
    /// nil when side evidence exists. Non-LiDAR scans can still export an
    /// explicitly unmeasured top sheet; LiDAR uses this to explain a retake.
    static func monocularSideViewFailure(sideFrameCaptured: Bool, sideProfileCount: Int) -> String? {
        if !sideFrameCaptured { return "missing_side_capture" }
        if sideProfileCount <= 0 { return "no_side_food_mask" }
        return nil
    }

    /// LiDAR gate for a top food that has neither enough fused depth nor a
    /// usable side-silhouette hull (`DepthFusion.lastUnresolvedFoods`).
    /// Side-related reasons ask for a retake of the side photo; anything else
    /// is a measurement failure. Pure for unit tests.
    static func lidarUnresolvedFailure(
        _ food: DepthFusion.UnresolvedFood,
        sideFrameCaptured: Bool,
        sideProfileCount: Int
    ) -> PipelineError {
        let prefix = "lidar_food#\(food.topIndex)_insufficient_depth"
        switch food.reason {
        case "no_side_silhouette", "unmatched_side_silhouette":
            if let missing = monocularSideViewFailure(
                sideFrameCaptured: sideFrameCaptured, sideProfileCount: sideProfileCount) {
                return .sideViewRequired("\(prefix)_\(missing)")
            }
            return .sideViewRequired("\(prefix)_no_side_silhouette")
        case "invalid_side_silhouette", "empty_top_side_intersection", "empty_side_hull":
            return .sideViewRequired("\(prefix)_\(food.reason)")
        case "no_measured_support_plane":
            return .model3DExportFailed("no_measured_support_plane")
        default:
            return .model3DExportFailed("\(prefix)_\(food.reason)")
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
    /// Load the user's locally-stored label corrections for this scan so the
    /// pipeline can recognise foods the user has already taught it. Each entry
    /// is `["label": String, "embedding": [Double|NSNumber]]` from the local
    /// SQLite exemplar table. Vectors are defensively L2-normalised so on-device
    /// cosine == dot product. This data is 100% on-device — it arrives via the
    /// MethodChannel from local storage and is never sent anywhere.
    func setUserExemplars(_ raw: [[String: Any]]) {
        var parsed: [UserExemplar] = []
        parsed.reserveCapacity(raw.count)
        for entry in raw {
            guard let label = (entry["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !label.isEmpty,
                let rawVec = entry["embedding"] as? [Any],
                !rawVec.isEmpty
            else { continue }
            var v = [Float]()
            v.reserveCapacity(rawVec.count)
            for value in rawVec {
                if let n = value as? NSNumber { v.append(n.floatValue) }
            }
            guard !v.isEmpty else { continue }
            var norm: Float = 0
            for x in v { norm += x * x }
            norm = norm.squareRoot()
            guard norm > 0 else { continue }
            for i in 0..<v.count { v[i] /= norm }
            parsed.append(UserExemplar(label: label, vector: v))
        }
        userExemplars = parsed
        print("[EXEMPLAR] loaded \(userExemplars.count) user exemplars across " +
              "\(Set(userExemplars.map { $0.label }).count) labels")
    }

    func runVideoScan(recorder: MultiFrameRecorder) throws -> String {
        lastModel3DPath = nil
        lastModel3DObjects = []

        print("[SCAN] ═══════════ VIDEO SCAN START ═══════════")
        print("[SCAN] build=2026-10-11-merge (monocular missing side = unmeasured top sheet; LiDAR height = fused depth, else exact side-silhouette hull; no borrowed silhouettes or priors)")
        print("[CAPTUREPAIR] inference id=\(recorder.captureID) top=\(recorder.topFrame?.timestamp.description ?? "none") side=\(recorder.sideFrame?.timestamp.description ?? "none")")
        print("[SCAN] recorder: topFrame=\(recorder.topFrame != nil), sideFrame=\(recorder.sideFrame != nil), topViewFrames=\(recorder.topViewFrames.count), lightFrames=\(recorder.lightFrames.count), frameCount=\(recorder.frameCount)")

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
        guard let preprocessed = autoreleasepool(invoking: {
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
        guard let preprocessedRGB = captureROIFrame(from: preprocessed, shape: .circle) else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("capture_circle_mask_failed")
        }
        let topROI = ScanMaskGeometry.ROI(
            width: CVPixelBufferGetWidth(preprocessedRGB),
            height: CVPixelBufferGetHeight(preprocessedRGB),
            shape: .circle)
        print("[ROI] view=top \(topROI.logDescription) crop=\(plate.detected ? "plate_rect" : "centred_square") cropRect=\(String(format: "%.3f,%.3f,%.3f,%.3f", cropRect?.minX ?? 0, cropRect?.minY ?? 0, cropRect?.width ?? 1, cropRect?.height ?? 1)) buffer=\(CVPixelBufferGetWidth(topFrame.pixelBuffer))x\(CVPixelBufferGetHeight(topFrame.pixelBuffer)); outside pixels ignored")

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
        let rawTopInstanceCount = segments.count
        segments = constrainToCaptureROI(segments, shape: .circle)
        let inROITopInstanceCount = segments.count
        // Mask-overlap NMS: duplicate / partial detections of ONE food (same
        // class with high IoU or containment, or any class on the same region)
        // collapse into one instance before anything counts them.
        segments = mergeOverlappingInstances(segments, view: "top")
        let mergedTopInstanceCount = segments.count
        print("[SCAN] segmentation: \(segments.count) objects — \(segments.map { "\($0.label)(\($0.pixelCount)px, conf \(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", "))")

        guard !segments.isEmpty else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.noFoodDetected("segmentation_empty")
        }

        // Split any segment whose mask is several genuinely SEPARATE, substantial
        // blobs (a handful of peanuts the segmenter grouped into one instance)
        // into one segment per blob, so each item gets its own silhouette,
        // border and 3-D object. Stem / highlight / shadow fragments of one food
        // stay with it (see `ScanMaskGeometry.planSplit`).
        segments = splitDisconnectedInstances(
            segments,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )
        print("[INSTANCES] view=top raw=\(rawTopInstanceCount) inROI=\(inROITopInstanceCount) afterMerge=\(mergedTopInstanceCount) split=\(segments.count) — \(segments.map { "\($0.label)(\($0.pixelCount)px)" }.joined(separator: ", "))")

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

        // Map ML Kit's distinct, confident specific-food hints across all
        // largest-first segments. See `applyMlKitLabelOverride` for the policy.
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
        refinementCandidatesByKey.removeAll()
        confirmedLabelKeys.removeAll()
        segmentEmbeddingsByKey.removeAll()
        labelSourceByKey.removeAll()
        segments = refineLabelsWithClassifier(
            segments: segments,
            frame: preprocessedRGB,
            maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight
        )

        // Colour-contradiction pre-pass: a produce label that must be a
        // saturated colour (tomato, cucumber, carrot…) but reads beige/brown/
        // dark is demoted so the open-vocab pass below re-names it from the real
        // crop — this is what stops a beige pile of peanuts keeping "tomato".
        segments = demoteColorContradictingProduce(
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

        // On-device exemplar learning (read/match): before we decide a segment
        // is unnameable, check it against the foods the user has already
        // corrected on this device. A strong image-to-image match (see
        // `userExemplarCosineFloor`) uses the learned label instead of asking
        // again. 100% local — exemplars arrive from local SQLite via the
        // MethodChannel and are never uploaded. Runs before the flagging pass so
        // a matched food is not surfaced as "unknown".
        segments = applyUserExemplarLabels(segments)

        // Uncertainty signal: any segment that survived both refinement passes
        // still carrying only a generic / low-confidence guess (nothing
        // confidently confirmed it) is flagged so the UI asks the user what it
        // is instead of silently showing a guess. Additive only.
        segments = annotateSegmentsNeedingUserLabel(segments)

        // Stamp the cached MobileCLIP embedding + label provenance onto each
        // segment so BOTH the LiDAR and monocular serialisers emit them
        // identically (embedding → enables learning a future correction;
        // label_source → drives the "learned" UI marker).
        segments = stampLabelMetadata(segments)

        // Second NMS pass on the REFINED labels: two overlapping instances the
        // raw model named differently (apple vs peach) but the refiners agree
        // on are one food. Disjoint split pieces never overlap, so they stay.
        let beforeRefinedMerge = segments.count
        segments = mergeOverlappingInstances(segments, view: "top_refined")
        if segments.count != beforeRefinedMerge {
            print("[INSTANCES] view=top refinedMerge before=\(beforeRefinedMerge) after=\(segments.count)")
        }

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

        // ── 3b. Non-LiDAR dual-photo visual hull ───────────────────────
        // If ARKit did not provide scene depth, do NOT force the device
        // through DepthFusion. Every food is reconstructed from its top mask ∩
        // its matched side silhouette (mirrored). Without a usable side
        // silhouette, preserve the top-mask sheet as explicitly unmeasured.
        var capturedSideProfiles: [MonocularVolumeEstimator.SideProfile] = []
        var capturedSideRGB: CVPixelBuffer?
        if !recorder.hasDepthData || recorder.sideFrame != nil {
            var sideProfiles: [MonocularVolumeEstimator.SideProfile] = []
            var sidePreprocessedRGB: CVPixelBuffer?
            if let sideFrame = recorder.sideFrame {
                // SIDE ROI: a centred rounded rectangle in the SAME normalisation
                // as the TOP circle — the side buffer is cropped to its centred
                // square (no aspect squash, like the top's no-plate crop) and the
                // rectangle's long side follows the world-horizontal image axis.
                let sideAxes = sideProfileAxes(sideFrame: sideFrame, topFrame: topFrame)
                let sideBufferW = CVPixelBufferGetWidth(sideFrame.pixelBuffer)
                let sideBufferH = CVPixelBufferGetHeight(sideFrame.pixelBuffer)
                let sideCrop = ScanMaskGeometry.centredSquareCrop(width: sideBufferW, height: sideBufferH)
                let sideShape = ScanMaskGeometry.ROIShape.roundedRect(
                    longAxisAlongColumns: !sideAxes.verticalUsesColumns)
                let sideCapture = autoreleasepool {
                    preprocessor.preprocess(pixelBuffer: sideFrame.pixelBuffer, plateRect: sideCrop)
                        .flatMap { captureROIFrame(from: $0, shape: sideShape) }
                }
                if let sideCapture {
                    let sideROI = ScanMaskGeometry.ROI(
                        width: CVPixelBufferGetWidth(sideCapture),
                        height: CVPixelBufferGetHeight(sideCapture),
                        shape: sideShape)
                    print("[ROI] view=side \(sideROI.logDescription) crop=centred_square cropRect=\(String(format: "%.3f,%.3f,%.3f,%.3f", sideCrop.minX, sideCrop.minY, sideCrop.width, sideCrop.height)) buffer=\(sideBufferW)x\(sideBufferH) verticalAxis=\(sideAxes.verticalUsesColumns ? "columns" : "rows") verticalIndexIncreasesUp=\(sideAxes.verticalIndexIncreasesUp)")
                }
                sidePreprocessedRGB = sideCapture
                let extractedProfiles = sideCapture.map {
                    extractSideProfiles(
                        preprocessedRGB: $0,
                        topSegments: segments,
                        axes: sideAxes,
                        roiShape: sideShape,
                        cropSidePx: min(sideBufferW, sideBufferH),
                        calibration: recorder.tableDistanceCm.map {
                            MonocularVolumeEstimator.PhotoCalibration(
                                topTransform: topFrame.cameraTransform,
                                topIntrinsics: topFrame.cameraIntrinsics,
                                topWidth: CVPixelBufferGetWidth(topFrame.pixelBuffer),
                                topHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer),
                                topCrop: plate.rect,
                                sideTransform: sideFrame.cameraTransform,
                                sideIntrinsics: sideFrame.cameraIntrinsics,
                                sideWidth: sideBufferW, sideHeight: sideBufferH, sideCrop: sideCrop,
                                tableY: topFrame.cameraTransform.columns.3.y - Float($0 / 100))
                        }
                    )
                } ?? []
                let check = monocularEstimator.validateDualSilhouette(
                    segments: segments, sideProfiles: extractedProfiles)
                let debug = dualSilhouetteDebugJSON(
                    topValid: check.topValid, sideValid: check.sideValid,
                    alignment: check.alignmentScore, segConfTop: check.segConfTop,
                    segConfSide: check.segConfSide, attempt: 1, reason: check.reason)
                print("[DUALHULL] \(debug)")
                // Primary-object validation is telemetry, not a plate-wide veto.
                // Each estimator object independently validates its own profile.
                sideProfiles = extractedProfiles.compactMap {
                    monocularEstimator.usableSideProfile($0, for: $0.label)
                }
                print("[PIPELINE] side profiles preserved individually=\(sideProfiles.count) primaryCheck=\(check.reason)")
            } else {
                let dbg = dualSilhouetteDebugJSON(
                    topValid: true, sideValid: false, alignment: 0,
                    segConfTop: segments.map { $0.confidence }.max() ?? 0,
                    segConfSide: 0, attempt: 1, reason: "missing_side_view")
                print("[DUALHULL] \(dbg)")
                print("[PIPELINE] missing side view: top-only geometry, volume unmeasured; retake a level side photo")
            }
            capturedSideProfiles = sideProfiles
            capturedSideRGB = sidePreprocessedRGB
        }
        if !recorder.hasDepthData {
            let estimate: MonocularVolumeEstimator.Result
            do {
                estimate = try monocularEstimator.estimate(
                    segments: segments,
                    topFrame: topFrame,
                    sideFrame: recorder.sideFrame,
                    sideProfiles: capturedSideProfiles,
                    maskWidth: preprocessor.modelInputWidth,
                    maskHeight: preprocessor.modelInputHeight,
                    measuredHeightCm: nil,
                    preprocessedRGB: preprocessedRGB,
                    sidePreprocessedRGB: capturedSideRGB,
                    tableDistanceCm: recorder.tableDistanceCm
                )
            } catch MonocularVolumeEstimator.EstimateError.sideViewRequired(let reason) {
                print("[PIPELINE] SIDE_VIEW_REQUIRED reason=\(reason)")
                throw PipelineError.sideViewRequired(reason)
            }
            lastModel3DPath = estimate.modelPath
            lastModel3DObjects = estimate.objects
            print("[PIPELINE] camera estimate success: true")
            print("[PIPELINE] model3dPath: \(estimate.modelPath)")
            print("[PIPELINE] file exists: \(FileManager.default.fileExists(atPath: estimate.modelPath))")
            return estimate.json
        }

        // ── 4. Multi-frame depth fusion ─────────────────────────────────
        print("[ROI] view=side path=lidar shape=roundedRect (side silhouette carves the fused voxels; side frame also colours side-facing vertices) top=circle")
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
        // Measured ARKit table plane: the support plane only when no labelled
        // depth voxel exists to measure the plate from.
        fusion.setTablePlaneY(recorder.tableDistanceCm.map {
            topFrame.cameraTransform.columns.3.y - Float($0 / 100)
        })

        // ── 6. Voxel clusters + 3-D export (hard contract) ─────────────
        // A successful scan exists ONLY if these voxels produce a real file
        // on disk. No 2-D volume substitute, no thumbnail success path.
        // Sparse depth is not a failure by itself: every food without enough
        // fused depth is rebuilt from its exact top ∩ side silhouettes, or the
        // scan fails below (never a prior/default height).
        print("[PIPELINE] depth clusters: occupied_voxels=\(fusion.totalOccupiedVoxels), " +
              "top_frames=\(recorder.topViewFrames.count), side_frames=\(recorder.lightFrames.count)" +
              (fusion.totalOccupiedVoxels > 10 ? "" : " sparse_depth=true"))

        // ── 5b. Side-silhouette carving (top ∩ side hull, AGENTS.md §9) ──
        if let sideFrame = recorder.sideFrame {
            // Borrowed (occluded/nearest) side pieces belong to another food;
            // LiDAR keeps carving only with each food's own silhouette.
            fusion.setSideSilhouette(lidarSideSilhouette(
                sideFrame: sideFrame, topFrame: topFrame,
                profiles: capturedSideProfiles.filter { !$0.sideShared }))
        } else {
            print("[DUALHULL] path=lidar sideApplied=false reason=missing_side_capture geometry=observed_top_depth")
        }

        let voxelClusters = fusion.voxelClusters()
        print("[PIPELINE] voxel clusters: \(voxelClusters.count) " +
              voxelClusters.map { "\($0.id)=\($0.voxelKeys.count)(\($0.heightSource.rawValue))" }.joined(separator: ", "))
        if let unresolved = fusion.lastUnresolvedFoods.first {
            let error = Self.lidarUnresolvedFailure(
                unresolved,
                sideFrameCaptured: recorder.sideFrame != nil,
                sideProfileCount: capturedSideProfiles.filter { !$0.sideShared }.count)
            let summary = fusion.lastUnresolvedFoods
                .map { "food#\($0.topIndex)(\($0.label)):\($0.reason)" }.joined(separator: ",")
            if case .sideViewRequired(let reason) = error {
                print("[PIPELINE] SIDE_VIEW_REQUIRED path=lidar reason=\(reason) unresolved=\(summary)")
            } else {
                print("[PIPELINE] lidar measurement failed: \(error.localizedDescription) unresolved=\(summary)")
            }
            print("[PIPELINE] export success: false")
            throw error
        }
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
            sideImageHeight: recorder.sideFrame.map { CVPixelBufferGetHeight($0.pixelBuffer) } ?? 0,
            sideDepthBuffer: recorder.sideFrame?.depthBuffer,
            clusters: voxelClusters
        )
        print("[SCAN] exportFoodObjects: \(foodObjects.count) meshes — \(foodObjects.map { "\($0.id)(v=\($0.vertices.count),f=\($0.faces.count/3))" }.joined(separator: ", "))")
        guard !foodObjects.isEmpty else {
            print("[PIPELINE] export success: false")
            print("[PIPELINE] model3dPath: nil")
            print("[PIPELINE] file exists: false")
            throw PipelineError.model3DExportFailed("mesh_reconstruction_empty")
        }
        // No silent drops: every measured food must reach the displayed mesh.
        let exportedIDs = Set(foodObjects.map(\.id))
        let droppedIDs = voxelClusters.map(\.id).filter { !exportedIDs.contains($0) }
        guard droppedIDs.isEmpty else {
            print("[PIPELINE] export success: false dropped=\(droppedIDs.joined(separator: ","))")
            throw PipelineError.model3DExportFailed("mesh_reconstruction_empty_\(droppedIDs.joined(separator: ","))")
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
        // Match the prerequisites used by DepthFusion's carving branch, using
        // the source cluster's top instance rather than its possibly shared label.
        let payloadSideSilhouette = recorder.sideFrame.flatMap {
            lidarSideSilhouette(sideFrame: $0, topFrame: topFrame,
                                profiles: capturedSideProfiles.filter { !$0.sideShared })
        }
        func sideMissingReason(for obj: DepthFusion.Food3DObject) -> String {
            guard recorder.sideFrame != nil else { return "missing_capture" }
            guard let side = payloadSideSilhouette else { return "unmatched_occluded_or_invalid_mask" }
            guard let cluster = voxelClusters.first(where: { $0.id == obj.id }),
                  let topIndex = cluster.topSegmentIndex,
                  let mask = side.instanceMasks[topIndex] else {
                return "unmatched_occluded_or_invalid_mask"
            }
            guard !mask.isEmpty, let maskW = mask.first?.count, maskW > 0,
                  side.imageWidth > 0, side.imageHeight > 0,
                  side.cropRect.width > 0.001, side.cropRect.height > 0.001 else {
                return "invalid_side_silhouette"
            }
            let fx = side.cameraIntrinsics.columns.0.x
            let fy = side.cameraIntrinsics.columns.1.y
            guard abs(fx) > 0.0001, abs(fy) > 0.0001 else {
                return "invalid_side_intrinsics"
            }
            let horizontal = side.cameraTransform.columns.0
            let up = side.cameraTransform.columns.1
            let rawAxis = abs(horizontal.y) < abs(up.y)
                ? SIMD3<Float>(horizontal.x, 0, horizontal.z)
                : SIMD3<Float>(-up.x, 0, -up.z)
            guard simd_length(rawAxis) > 0.0001 else { return "invalid_side_axis" }
            guard cluster.sideCarved else { return "side_carve_empty_kept_measured_depth" }
            return "none"
        }
        func measurementMetadata(for obj: DepthFusion.Food3DObject) -> [String: Any] {
            let sideReason = sideMissingReason(for: obj)
            let sideApplied = sideReason == "none"
            let meshVolume = round(obj.volumeCm3 * 10) / 10
            let validMeshVolume = meshVolume.isFinite && meshVolume > 0 &&
                !obj.vertices.isEmpty && !obj.faces.isEmpty
            let measured = sideApplied && validMeshVolume
            let heightSource = voxelClusters.first(where: { $0.id == obj.id })?.heightSource ?? .depth
            return [
                "height_source": heightSource.rawValue,
                "volume_measured": measured,
                "side_view_applied": sideApplied,
                "side_missing_reason": sideReason,
                "volume_measurement_reason": measured ? "none"
                    : (sideApplied ? "invalid_display_mesh_volume" : sideReason),
                // No fallback geometry exists on the LiDAR path.
                "fallback_used": false,
                "low_confidence": !measured,
            ]
        }
        lastModel3DObjects = foodObjects.map { obj -> [String: Any] in
            let seg = segByLabel[obj.label]
            let confidence = Double(seg?.confidence ?? 1.0)
            let dims = Self.meshDimensionsCm(obj.vertices)
            var metadata: [String: Any] = [
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
                "needs_user_label": seg?.needsUserLabel ?? false,
                "candidate_labels": seg?.candidateLabels ?? [],
                "embedding": (seg?.embedding ?? []).map { Double($0) },
                "label_source": seg?.labelSource ?? "recognizer",
            ]
            metadata.merge(measurementMetadata(for: obj)) { _, current in current }
            return metadata
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
            d["needs_user_label"] = seg?.needsUserLabel ?? false
            d["candidate_labels"] = seg?.candidateLabels ?? []
            d["embedding"] = (seg?.embedding ?? []).map { Double($0) }
            d["label_source"] = seg?.labelSource ?? "recognizer"
            d.merge(measurementMetadata(for: obj)) { _, current in current }
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
    ///
    /// The side view ONLY provides profiles — it never adds or splits food
    /// instances. Its segments are de-duplicated (mask-overlap NMS) and every
    /// TOP instance is assigned its own side segment, or its own horizontal
    /// slice of a shared one, by position / prominence / centredness
    /// (`ScanMaskGeometry.matchSideSegments`). The returned profiles carry the
    /// matched `topSegmentIndex`, so the estimator never guesses by label.
    private func extractSideProfiles(
        preprocessedRGB: CVPixelBuffer,
        topSegments: [SegmentationService.SegmentedObject],
        axes: SideProfileAxes,
        roiShape: ScanMaskGeometry.ROIShape,
        cropSidePx: Int,
        calibration: MonocularVolumeEstimator.PhotoCalibration?
    ) -> [MonocularVolumeEstimator.SideProfile] {
        var sideSegments: [SegmentationService.SegmentedObject]
        do {
            sideSegments = yoloSegmentationService.isAvailable
                ? try yoloSegmentationService.segment(pixelBuffer: preprocessedRGB)
                : try segmentationService.segment(pixelBuffer: preprocessedRGB)
        } catch {
            print("[PIPELINE] side-profile: segmentation failed: \(error)")
            return []
        }
        let rawSideCount = sideSegments.count
        sideSegments = constrainToCaptureROI(sideSegments, shape: roiShape)
        let inROISideCount = sideSegments.count
        sideSegments = mergeOverlappingInstances(sideSegments, view: "side")
        sideSegments = splitDisconnectedInstances(
            sideSegments, maskWidth: preprocessor.modelInputWidth,
            maskHeight: preprocessor.modelInputHeight)
        print("[INSTANCES] view=side raw=\(rawSideCount) inROI=\(inROISideCount) afterMerge=\(sideSegments.count) (profiles only — the side view never adds instances)")
        guard !sideSegments.isEmpty else {
            print("[PIPELINE] side-profile: no side segments")
            return []
        }
        guard !topSegments.isEmpty else { return [] }

        // TOP footprints along the matched top axis, oriented into the side
        // view's horizontal direction (flipped when `reversed`).
        let tops: [ScanMaskGeometry.SideMatchTop] = topSegments.map { segment in
            let mask = segment.mask
            let h = mask.count
            let w = mask.first?.count ?? 0
            let dim = max(1, axes.topAxis == .columns ? w : h)
            var minIdx = Int.max
            var maxIdx = -1
            for r in 0..<h {
                let row = mask[r]
                for c in 0..<min(w, row.count) where row[c] != 0 {
                    let idx = axes.topAxis == .columns ? c : r
                    if idx < minIdx { minIdx = idx }
                    if idx > maxIdx { maxIdx = idx }
                }
            }
            var lo = maxIdx >= minIdx ? Double(minIdx) / Double(dim) : 0
            var hi = maxIdx >= minIdx ? Double(maxIdx + 1) / Double(dim) : 0
            if axes.reversed { (lo, hi) = (1.0 - hi, 1.0 - lo) }
            var descriptor = ScanMaskGeometry.SideMatchTop(
                lo: lo, hi: hi, area: segment.pixelCount,
                label: segment.label, classIndex: segment.classIndex)
            if let calibration {
                var projected: [Double] = []
                var depths: [Double] = []
                for r in 0..<h {
                    for c in 0..<min(w, mask[r].count) where mask[r][c] != 0 {
                        guard let world = calibration.topWorld(
                            row: (Double(r) + 0.5) / Double(h),
                            column: (Double(c) + 0.5) / Double(w)),
                            let uv = calibration.sideUV(world: world) else { continue }
                        projected.append(Double(axes.verticalUsesColumns ? uv.y : uv.x))
                        let cameraPoint = calibration.sideTransform.inverse * SIMD4(world.x, world.y, world.z, 1)
                        depths.append(Double(-cameraPoint.z))
                    }
                }
                descriptor.projectedLo = projected.min()
                descriptor.projectedHi = projected.max()
                descriptor.cameraDepth = depths.isEmpty ? nil : depths.reduce(0, +) / Double(depths.count)
            }
            return descriptor
        }

        // SIDE segments along the side horizontal axis (rows when the side
        // vertical runs along columns, as in a portrait hold).
        let sideMaskH = sideSegments[0].mask.count
        let sideMaskW = sideSegments[0].mask.first?.count ?? 0
        let horizontalDim = axes.verticalUsesColumns ? sideMaskH : sideMaskW
        let sideROI = ScanMaskGeometry.ROI(width: sideMaskW, height: sideMaskH, shape: roiShape)
        let sides: [ScanMaskGeometry.SideMatchSide] = sideSegments.map { segment in
            var minV = [Int](repeating: Int.max, count: max(1, horizontalDim))
            var maxV = [Int](repeating: -1, count: max(1, horizontalDim))
            var lo = Int.max
            var hi = -1
            let mask = segment.mask
            for r in 0..<mask.count {
                let row = mask[r]
                for c in 0..<row.count where row[c] != 0 {
                    let horizontal = axes.verticalUsesColumns ? r : c
                    let vertical = axes.verticalUsesColumns ? c : r
                    guard horizontal < minV.count else { continue }
                    lo = min(lo, horizontal)
                    hi = max(hi, horizontal)
                    minV[horizontal] = min(minV[horizontal], vertical)
                    maxV[horizontal] = max(maxV[horizontal], vertical)
                }
            }
            let extent = zip(minV, maxV).map { $1 >= $0 ? $1 - $0 + 1 : 0 }
            return ScanMaskGeometry.SideMatchSide(
                lo: hi >= lo ? lo : 0,
                hi: hi >= lo ? hi : -1,
                area: segment.pixelCount,
                label: segment.label,
                classIndex: segment.classIndex,
                centredness: sideROI.centredness(
                    row: Double(segment.centroid.row), column: Double(segment.centroid.col)),
                verticalExtent: extent)
        }

        let assignments = ScanMaskGeometry.matchSideSegments(
            tops: tops, sides: sides, horizontalDim: horizontalDim)
        var profiles: [MonocularVolumeEstimator.SideProfile] = []
        let sideMasks = sideSegments.map(\.mask)
        for (topIndex, top) in topSegments.enumerated() {
            let mine = assignments.filter { $0.topIndex == topIndex }
            guard !mine.isEmpty else {
                print("[SIDEMATCH] top#\(topIndex)(\(top.label)) ← none (no side segment available; no prior fallback — scan will require a side view)")
                continue
            }
            // The food's side silhouette is the UNION of every piece assigned
            // to it (split stem/highlight/shadow pieces are rejoined).
            let union = ScanMaskGeometry.sidePieceUnion(
                sideMasks: sideMasks, assignments: mine,
                horizontalAlongRows: axes.verticalUsesColumns)
            let pieceMask = union.mask
            let count = union.pixelCount
            let sideList = mine.map { "\($0.sideIndex)(\(sideSegments[$0.sideIndex].label))[\($0.from),\($0.to)]\($0.reason)\($0.isShared ? "*" : "")" }
                .joined(separator: ",")
            guard count > 0 else {
                print("[SIDEMATCH] top#\(topIndex)(\(top.label)) ← sides [\(sideList)] empty union")
                continue
            }
            var rowTotal = 0
            var columnTotal = 0
            for r in 0..<pieceMask.count {
                for c in 0..<pieceMask[r].count where pieceMask[r][c] != 0 {
                    rowTotal += r
                    columnTotal += c
                }
            }
            let largestPiece = zip(mine, union.piecePixels).max { $0.1 < $1.1 }!.0
            let side = sideSegments[largestPiece.sideIndex]
            let isSplit = mine.contains(where: \.isSplit)
            let shared = mine.allSatisfy(\.isShared)
            let reasons = mine.map(\.reason).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                .joined(separator: "+")
            let score = mine.map(\.score).max() ?? 0
            var piece = SegmentationService.SegmentedObject(
                label: side.label,
                classIndex: side.classIndex,
                mask: pieceMask,
                pixelCount: count,
                centroid: (rowTotal / count, columnTotal / count),
                confidence: mine.map { sideSegments[$0.sideIndex].confidence }.max() ?? side.confidence
            )
            piece.candidateLabels = side.candidateLabels
            guard var profile = makeSideProfile(
                segment: piece,
                axes: axes,
                imageWidth: cropSidePx,
                imageHeight: cropSidePx
            ) else {
                print("[SIDEMATCH] top#\(topIndex)(\(top.label)) ← sides [\(sideList)] rejected by profile bounds px=\(count)")
                continue
            }
            profile.matchReason = reasons
            profile.sideShared = shared
            profile.topSegmentIndex = topIndex
            profile.matchScore = score
            profile.sourceMask = pieceMask
            profile.verticalIndexIncreasesUp = axes.verticalIndexIncreasesUp
            profile.calibration = calibration
            if let calibration,
               let centre = calibration.topWorld(
                    row: (Double(top.centroid.row) + 0.5) / Double(top.mask.count),
                    column: (Double(top.centroid.col) + 0.5) / Double(top.mask.first?.count ?? 1)),
               let bottom = calibration.sideWorld(
                    uv: profile.sourceUV(axisU: 0.5, heightFraction: 0), through: centre),
               let upper = calibration.sideWorld(
                    uv: profile.sourceUV(axisU: 0.5, heightFraction: 1), through: centre) {
                profile.measuredHeightCm = Double(abs(upper.y - bottom.y)) * 100
                profile.sourceBaseHeightM = min(upper.y, bottom.y) - calibration.tableY
            }
            print("[SIDEMATCH] top#\(topIndex)(\(top.label)) ← sides [\(sideList)] reason=\(reasons) shared=\(shared)\(isSplit ? " split" : "") score=\(String(format: "%.2f", score)) sidePx=\(count) ar=\(String(format: "%.2f", profile.aspectRatio)) measuredH=\(profile.measuredHeightCm.map { String(format: "%.2fcm", $0) } ?? "uncalibrated") topSpan=\(String(format: "%.2f-%.2f", tops[topIndex].lo, tops[topIndex].hi))")
            profiles.append(profile)
        }
        print("[PIPELINE] side-profile: profiles=\(profiles.count), " +
              profiles.map { "\($0.label)→top#\($0.topSegmentIndex ?? -1)(axis=\($0.topAxis.rawValue)\($0.reversed ? "R" : ""), ar=\(String(format: "%.2f", $0.aspectRatio)), fill=\(String(format: "%.2f", $0.meanNormalizedHeight)))" }.joined(separator: ", "))
        return profiles
    }

    /// LiDAR side silhouette for `DepthFusion` carving. Segments the side
    /// photo exactly like the monocular path (centred square crop, side
    /// rounded-rect ROI, ROI clip + mask NMS) and returns the UNION of the side
    /// food masks with the real side camera pose. Returns nil — and logs why —
    /// when the side mask is unusable, so the scan never fails on it.
    private func lidarSideSilhouette(
        sideFrame: FrameCaptureService.CapturedFrame,
        topFrame: FrameCaptureService.CapturedFrame,
        profiles: [MonocularVolumeEstimator.SideProfile]
    ) -> DepthFusion.SideSilhouette? {
        let sideAxes = sideProfileAxes(sideFrame: sideFrame, topFrame: topFrame)
        let bufferW = CVPixelBufferGetWidth(sideFrame.pixelBuffer)
        let bufferH = CVPixelBufferGetHeight(sideFrame.pixelBuffer)
        let crop = ScanMaskGeometry.centredSquareCrop(width: bufferW, height: bufferH)
        let shape = ScanMaskGeometry.ROIShape.roundedRect(
            longAxisAlongColumns: !sideAxes.verticalUsesColumns)
        guard let first = profiles.first?.sourceMask, !first.isEmpty,
              let maskW = first.first?.count, maskW > 0 else {
            print("[DUALHULL] path=lidar side carving skipped (no_side_food_mask)")
            return nil
        }
        let maskH = first.count
        var union = [[UInt8]](repeating: [UInt8](repeating: 0, count: maskW), count: maskH)
        var onPixels = 0
        for profile in profiles where profile.sourceMask.count == maskH {
            for r in 0..<maskH {
                let row = profile.sourceMask[r]
                for c in 0..<min(maskW, row.count) where row[c] != 0 && union[r][c] == 0 {
                    union[r][c] = 1
                    onPixels += 1
                }
            }
        }
        let coverage = Double(onPixels) / Double(maskW * maskH)
        guard onPixels > 0 else {
            print("[DUALHULL] path=lidar side carving skipped (empty_matched_side_masks)")
            return nil
        }
        print("[ROI] view=side path=lidar \(ScanMaskGeometry.ROI(width: maskW, height: maskH, shape: shape).logDescription) crop=centred_square buffer=\(bufferW)x\(bufferH) sideMaskCoverage=\(String(format: "%.3f", coverage))")
        return DepthFusion.SideSilhouette(
            mask: union,
            instanceMasks: Dictionary(uniqueKeysWithValues: profiles.compactMap {
                guard let index = $0.topSegmentIndex else { return nil }
                return (index, $0.sourceMask)
            }),
            cropRect: crop,
            roiShape: shape,
            cameraTransform: sideFrame.cameraTransform,
            cameraIntrinsics: sideFrame.cameraIntrinsics,
            imageWidth: bufferW,
            imageHeight: bufferH)
    }

    /// The visual guide is also an inference boundary. Blackening everything
    /// outside the capture ROI (TOP: centred circle; SIDE: centred rounded
    /// rectangle, see `ScanMaskGeometry.ROI`) prevents global classifiers from
    /// naming food outside the guide; clipping masks afterwards is a second
    /// guard against a model prediction crossing that boundary.
    private func captureROIFrame(
        from input: CVPixelBuffer,
        shape: ScanMaskGeometry.ROIShape
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        guard width > 0, height > 0 else { return nil }

        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &output
        ) == kCVReturnSuccess, let output else { return nil }

        CVPixelBufferLockBaseAddress(input, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(input, .readOnly)
        }
        guard let source = CVPixelBufferGetBaseAddress(input),
              let destination = CVPixelBufferGetBaseAddress(output) else { return nil }
        let sourceStride = CVPixelBufferGetBytesPerRow(input)
        let destinationStride = CVPixelBufferGetBytesPerRow(output)
        let copyBytes = min(sourceStride, destinationStride)
        for row in 0..<height {
            memcpy(destination.advanced(by: row * destinationStride),
                   source.advanced(by: row * sourceStride), copyBytes)
        }

        let pixels = destination.assumingMemoryBound(to: UInt8.self)
        let roi = ScanMaskGeometry.ROI(width: width, height: height, shape: shape)
        for row in 0..<height {
            for column in 0..<width where !roi.contains(row: row, column: column) {
                let offset = row * destinationStride + column * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        return output
    }

    /// Copy of `segment` with a new mask (pixel count / centroid recomputed),
    /// keeping every label/refinement field.
    private func rebuiltSegment(
        _ segment: SegmentationService.SegmentedObject,
        withMask mask: [[UInt8]],
        confidence: Float? = nil
    ) -> SegmentationService.SegmentedObject? {
        var count = 0
        var rowTotal = 0
        var columnTotal = 0
        for r in 0..<mask.count {
            for c in 0..<mask[r].count where mask[r][c] != 0 {
                count += 1
                rowTotal += r
                columnTotal += c
            }
        }
        guard count > 0 else { return nil }
        var out = SegmentationService.SegmentedObject(
            label: segment.label,
            classIndex: segment.classIndex,
            mask: mask,
            pixelCount: count,
            centroid: (rowTotal / count, columnTotal / count),
            confidence: confidence ?? segment.confidence
        )
        out.needsUserLabel = segment.needsUserLabel
        out.candidateLabels = segment.candidateLabels
        out.embedding = segment.embedding
        out.labelSource = segment.labelSource
        return out
    }

    private func constrainToCaptureROI(
        _ segments: [SegmentationService.SegmentedObject],
        shape: ScanMaskGeometry.ROIShape
    ) -> [SegmentationService.SegmentedObject] {
        segments.compactMap { segment in
            let height = segment.mask.count
            let width = segment.mask.first?.count ?? 0
            guard height > 0, width > 0 else { return nil }
            let roi = ScanMaskGeometry.ROI(width: width, height: height, shape: shape)
            var mask = segment.mask
            for row in 0..<height {
                for column in 0..<mask[row].count where mask[row][column] == 1 {
                    if !roi.contains(row: row, column: column) {
                        mask[row][column] = 0
                    }
                }
            }
            guard let constrained = rebuiltSegment(segment, withMask: mask) else {
                print("[ROI] rejected segment outside capture \(shape == .circle ? "circle" : "roundedRect"): \(segment.label)")
                return nil
            }
            return constrained
        }
    }

    /// Mask-overlap NMS (instance de-duplication). YOLO-seg can emit several
    /// instances for ONE food (duplicate boxes, a partial box on half of it,
    /// a second class guess for the same region). Same-food instances merge on
    /// IoU ≥ 0.5 or containment IoMin ≥ 0.7; different classes merge only on
    /// IoU ≥ 0.7 (the same region), so a garnish on a different food stays.
    /// The merged instance is the mask UNION with the largest member's label.
    private func mergeOverlappingInstances(
        _ segments: [SegmentationService.SegmentedObject],
        view: String
    ) -> [SegmentationService.SegmentedObject] {
        guard segments.count > 1 else { return segments }
        let masks = segments.map { ScanMaskGeometry.BinaryMask(rows: $0.mask) }
        let groups = ScanMaskGeometry.mergeGroups(masks: masks) { i, j in
            ScanMaskGeometry.sameFood(
                segments[i].label, segments[i].classIndex,
                segments[j].label, segments[j].classIndex)
        }
        guard groups.contains(where: { $0.count > 1 }) else { return segments }
        var merged: [(order: Int, segment: SegmentationService.SegmentedObject)] = []
        for group in groups {
            let representative = segments[group[0]]
            guard group.count > 1 else {
                merged.append((group[0], representative))
                continue
            }
            var union = masks[group[0]]
            for j in group.dropFirst() { union = union.union(masks[j]) }
            let confidence = group.map { segments[$0].confidence }.max() ?? representative.confidence
            print("[INSTANCES] view=\(view) merged \(group.map { "\(segments[$0].label)#\($0)(\(segments[$0].pixelCount)px)" }.joined(separator: " + ")) → \(representative.label)(\(union.count)px)")
            if let combined = rebuiltSegment(representative, withMask: union.rows, confidence: confidence) {
                merged.append((group.min() ?? group[0], combined))
            }
        }
        return merged.sorted { $0.order < $1.order }.map(\.segment)
    }

    private typealias SideProfileAxes = (
        verticalUsesColumns: Bool,
        topAxis: MonocularVolumeEstimator.SideProfile.TopAxis,
        reversed: Bool,
        verticalIndexIncreasesUp: Bool
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
        // Direction of increasing vertical index in WORLD terms. A normal
        // portrait hold (sensor is landscape-right: columns follow camera-right
        // which points DOWN) and a normal landscape hold (rows grow downward)
        // both give `false` — larger index = closer to the table. An upside-down
        // hold flips it; profiles and side UVs honour this sign.
        let verticalIndexIncreasesUp = verticalUsesColumns
            ? simd_dot(sideRight, worldUp) > 0
            : simd_dot(sideUp, worldUp) < 0

        let topT = topFrame.cameraTransform
        let topCols = tableProjected(simd_float3(topT.columns.0.x, topT.columns.0.y, topT.columns.0.z)) ?? simd_float3(1, 0, 0)
        let topRows = tableProjected(-simd_float3(topT.columns.1.x, topT.columns.1.y, topT.columns.1.z)) ?? simd_float3(0, 0, 1)
        let sideHorizontalProjected = tableProjected(sideHorizontal) ?? topCols

        let dotCols = simd_dot(sideHorizontalProjected, topCols)
        let dotRows = simd_dot(sideHorizontalProjected, topRows)
        if abs(dotCols) >= abs(dotRows) {
            return (verticalUsesColumns, .columns, dotCols < 0, verticalIndexIncreasesUp)
        }
        return (verticalUsesColumns, .rows, dotRows < 0, verticalIndexIncreasesUp)
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
        let sampleCount = horizontalExtent
        var heights = [Double](repeating: 0, count: sampleCount)
        var bottoms = [Double](repeating: 0, count: sampleCount)
        var tops = [Double](repeating: 0, count: sampleCount)

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
                // the phone is held. Normalize from bottom-up: 0 = visible
                // side-mask bottom, 1 = visible side-mask top. The bottom is the
                // LARGER vertical index unless the hold flips it.
                let bottomOffset: Double
                let topOffset: Double
                if axes.verticalIndexIncreasesUp {
                    bottomOffset = Double(localMinV - minVertical) / Double(max(1, verticalExtent))
                    topOffset = Double(localMaxV - minVertical + 1) / Double(max(1, verticalExtent))
                } else {
                    bottomOffset = Double(maxVertical - localMaxV) / Double(max(1, verticalExtent))
                    topOffset = Double(maxVertical - localMinV + 1) / Double(max(1, verticalExtent))
                }
                bottoms[sampleIndex] = min(1.0, max(0.0, bottomOffset))
                tops[sampleIndex] = min(1.0, max(0.0, topOffset))
            }
        }

        // One sample per measured mask column/row. Empty samples stay empty.
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
        guard aspectRatio.isFinite, aspectRatio > 0, segment.pixelCount > 0 else { return nil }

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
                    recordRejectedCandidate(label, for: segment)
                    print("[Classifier] kept \(segment.label) (seg \(String(format: "%.2f", segment.confidence))) over \(label) (\(String(format: "%.2f", confidence)); strong=\(classifierStrong); same=\(sameFood))")
                    continue
                }
                confirmedLabelKeys.insert(Self.segmentKey(segment))
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

    /// Split a segment whose mask is several genuinely SEPARATE blobs into one
    /// segment per blob. Components are grouped after a morphological close +
    /// hole fill (a stem, specular highlight or shadow fringe across a thin gap
    /// stays with its food) and a split needs ≥2 substantial pieces (each
    /// ≥150 px and ≥20% of the largest) — see `ScanMaskGeometry.planSplit`.
    /// Pieces keep their original pixels: a real food is never rounded or
    /// dropped, and a single food (one apple) is returned unchanged.
    private func splitDisconnectedInstances(
        _ segments: [SegmentationService.SegmentedObject],
        maskWidth: Int,
        maskHeight: Int
    ) -> [SegmentationService.SegmentedObject] {
        var out: [SegmentationService.SegmentedObject] = []
        out.reserveCapacity(segments.count)
        for seg in segments {
            let h = seg.mask.count
            let w = seg.mask.first?.count ?? 0
            guard h > 0, w > 0 else { out.append(seg); continue }
            let plan = ScanMaskGeometry.planSplit(ScanMaskGeometry.BinaryMask(rows: seg.mask))
            if plan.rawComponents >= 2 {
                print("[SPLIT] \(seg.label): rawComponents=\(plan.rawComponents) grouped=\(plan.groupedComponents) closeRadius=\(plan.closingRadius) areas=\(Array(plan.componentAreas.prefix(8))) → \(plan.shouldSplit ? "\(plan.pieces.count) instances" : "kept as 1") (\(plan.reason))")
            }
            guard plan.shouldSplit else { out.append(seg); continue }
            for piece in plan.pieces {
                if let pieceSegment = rebuiltSegment(seg, withMask: piece.rows) {
                    out.append(pieceSegment)
                }
            }
        }
        return out
    }

    /// Demote (never rename) the confidence of a segment whose label is a produce
    /// that must be a saturated colour (red tomato, green cucumber, orange
    /// carrot…) but whose sampled mean colour is beige/brown/dark/neutral. The
    /// lowered confidence lets MobileCLIP re-name it from the real crop rather
    /// than a colour heuristic guessing the food.
    private func demoteColorContradictingProduce(
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
        var out = segments
        for i in segments.indices {
            let seg = segments[i]
            guard Self.needsSaturatedColor(seg.label) else { continue }
            let mh = seg.mask.count
            let mw = seg.mask.first?.count ?? 0
            guard mh > 0, mw > 0 else { continue }
            let stride = max(1, max(mw, mh) / 48)
            var rSum = 0.0, gSum = 0.0, bSum = 0.0, n = 0.0
            var r = 0
            while r < mh {
                var c = 0
                while c < mw {
                    if seg.mask[r][c] == 1 {
                        let x = min(w - 1, c * w / max(mw, 1))
                        let y = min(h - 1, r * h / max(mh, 1))
                        let off = y * rowBytes + x * 4
                        rSum += Double(ptr[off + 2]); gSum += Double(ptr[off + 1]); bSum += Double(ptr[off]); n += 1
                    }
                    c += stride
                }
                r += stride
            }
            guard n > 0 else { continue }
            let family = Self.colorFamily(r: rSum / n, g: gSum / n, b: bSum / n)
            if family == "other" || family == "dark" || family == "grey" || family == "white" {
                out[i] = SegmentationService.SegmentedObject(
                    label: seg.label,
                    classIndex: seg.classIndex,
                    mask: seg.mask,
                    pixelCount: seg.pixelCount,
                    centroid: seg.centroid,
                    confidence: min(seg.confidence, 0.22)
                )
                print("[COLOR-DEMOTE] \(seg.label) family=\(family) -> conf 0.22 (lets CLIP re-name)")
            }
        }
        return out
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
        // Decision is driven by COSINE similarity + a synonym-aware margin, not
        // softmax-over-N: with ~380 labels the softmax mass splits across near-
        // synonyms (salmon / grilled salmon / smoked salmon), so a correct top-1
        // scores a tiny confidence and the old 0.64/0.78 gate kept the wrong base
        // label ("fish"). Cosine stays stable as the vocabulary grows.
        let cosineFloor = MobileCLIPService.minimumCosineSimilarity
        let unsureSegmentation: Float = 0.32
        let strongConfidence: Float = 0.64
        let strongCosine: Float = 0.24
        let strongMargin: Float = 0.02
        let veryStrongConfidence: Float = 0.78
        let veryStrongCosine: Float = 0.30
        let veryStrongMargin: Float = 0.035
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
                guard let embedding = try mobileClip.embedding(
                    pixelBuffer: frame,
                    regionOfInterest: roi
                ) else { continue }
                // Cache the crop's embedding (keyed by stable centroid) so it can
                // be serialised for on-device exemplar learning and reused by the
                // exemplar-match pass without re-running the encoder.
                segmentEmbeddingsByKey[Self.segmentKey(segment)] = embedding
                let candidates = try mobileClip.nearestLabels(
                    for: embedding,
                    limit: 8
                )
                guard let best = candidates.first,
                      best.cosine >= cosineFloor
                else { continue }
                // Margin against the best candidate that is a genuinely DIFFERENT
                // food — synonyms of the winner (grilled salmon vs salmon) must
                // not sink the margin.
                let runnerUpCosine = candidates.dropFirst()
                    .first { !Self.labelsCompatible($0.label, best.label) }?.cosine ?? 0
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
                let clipStrong = (best.cosine >= strongCosine || best.confidence >= strongConfidence) && margin >= strongMargin
                let clipVeryStrong = (best.cosine >= veryStrongCosine || best.confidence >= veryStrongConfidence) && margin >= veryStrongMargin
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
                // A whole-produce base label can ALSO be wrong: the segmenter
                // often blobs a pile of nuts/other food into a round "tomato".
                // Allow a STRONG CLIP match for a DIFFERENT specific, non-produce,
                // non-composite food (e.g. "almond") to correct it. The
                // composite-dish block above still stops a red blob becoming
                // "caprese salad", and whole-produce→whole-produce still needs a
                // very-strong match (a tomato can't flip to "apple" cheaply).
                let correctsProduceMislabel = Self.isWholeProduce(segment.label)
                    && !Self.isWholeProduce(best.label)
                    && !Self.isCompositeDish(best.label)
                    && !sameFood && clipStrong
                // A generic base label ("fish", "seafood", "meat", "others", …)
                // carries little nutrition specificity: a strong CLIP match for a
                // specific, non-composite food should replace it. This is what
                // fixes salmon (base "fish" → "salmon") and nut piles the
                // segmenter dumps into a generic "others" bucket.
                let correctsGeneric = Self.isGenericBase(segment.label)
                    && !Self.isCompositeDish(best.label)
                    && !sameFood && clipStrong
                let usableCorrection = sameFood || clipVeryStrong || correctsNonProduce || correctsProduceMislabel || correctsGeneric || (segmentationUnsure && clipStrong)
                guard usableCorrection else {
                    for candidate in candidates.prefix(3) where candidate.cosine >= cosineFloor {
                        recordRejectedCandidate(candidate.label, for: segment)
                    }
                    print("[MobileCLIP] kept \(segment.label) (seg \(String(format: "%.2f", segment.confidence))) over \(best.label) margin=\(String(format: "%.3f", margin)) top=[\(topSummary)]")
                    continue
                }
                confirmedLabelKeys.insert(Self.segmentKey(segment))
                let chosenLabel = sameFood && !clipVeryStrong && !segmentationUnsure && !correctsNonProduce && !correctsProduceMislabel && !correctsGeneric
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

        var kept: [SegmentationService.SegmentedObject] = []
        for i in segments.indices {
            let seg = segments[i]
            let mh = seg.mask.count
            let mw = seg.mask.first?.count ?? 0
            guard mh > 0, mw > 0 else { kept.append(seg); continue }
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
            guard n > 0 else { kept.append(seg); continue }
            let rr = rSum / n, gg = gSum / n, bb = bSum / n
            let family = Self.colorFamily(r: rr, g: gg, b: bb)
            let fraction = Double(seg.pixelCount) / Double(max(1, mw * mh))
            print("[COLOR] seg#\(i) \(seg.label): rgb=(\(Int(rr)),\(Int(gg)),\(Int(bb))) family=\(family) fraction=\(String(format: "%.2f", fraction))")

            // Plate / background rejection (chroma-key idea): a white or grey
            // region is the plate or table, not food — real food is saturated.
            // Drop a pale segment when it is a composite-dish mislabel (a bare
            // white plate called "caprese salad") OR it fills most of the frame
            // (the plate), UNLESS its label is a genuinely pale food.
            let plateLike = (family == "white" || family == "grey")
            if plateLike && !Self.isPaleFood(seg.label) &&
                (Self.isCompositeDish(seg.label) || fraction > 0.42) {
                print("[COLOR] rejected plate/background seg#\(i) \(seg.label) family=\(family) fraction=\(String(format: "%.2f", fraction))")
                continue
            }

            var outSeg = seg
            // Only correct a label the pipeline is NOT already sure about. The
            // colour guard exists to catch a genuine miscue (a green cucumber
            // called "ice cream"), NOT to overrule an already-specific,
            // reasonably-confident classification. A seared entrecote reads
            // reddish-brown, so without this gate every confident "beef"/
            // "steak"/"entrecote" segment was force-relabelled "tomato". Fire
            // the override only when the current label is a vague generic base
            // (fish/meat/vegetable/…) OR its confidence is below the classifier
            // rejection floor — i.e. exactly the labels worth second-guessing.
            let labelIsGeneric = Self.isGenericBase(seg.label)
            let labelIsLowConfidence = seg.confidence < Self.colorOverrideConfidenceFloor
            // `seg.confidence` after MobileCLIP refinement is
            // max(segmentationConfidence, best.confidence), and
            // `refineLabelsWithOpenVocab`'s own comment documents that its
            // softmax `confidence` is near-tiny even for a CORRECT top-1 once
            // the vocabulary has ~380 near-synonym labels (mass splits across
            // them) — that pass deliberately decides on cosine similarity +
            // margin instead, never on that softmax number. So a stamped
            // confidence under 0.55 does NOT mean MobileCLIP was unsure; it is
            // an artefact of a metric this pass doesn't otherwise trust. Any
            // segment MobileCLIP already confirmed/refined via a usable
            // cosine match (see `confirmedLabelKeys`) must therefore be exempt
            // from the low-confidence branch, or a correctly-identified warm-
            // toned food (e.g. a lentil dahl, a beef ragù, roasted chickpeas)
            // gets silently overwritten back to "tomato"/"carrot"/"cucumber"
            // right after MobileCLIP got it right.
            let mobileClipConfirmed = confirmedLabelKeys.contains(Self.segmentKey(seg))
            let eligibleForColorOverride = !mobileClipConfirmed && (labelIsGeneric || labelIsLowConfidence)
            if eligibleForColorOverride,
               let corrected = Self.colorCorrectedLabel(currentLabel: seg.label, family: family),
               corrected != seg.label.lowercased() {
                print("[COLOR] corrected \(seg.label) -> \(corrected) (colour=\(family))")
                outSeg = SegmentationService.SegmentedObject(
                    label: corrected,
                    classIndex: seg.classIndex,
                    mask: seg.mask,
                    pixelCount: seg.pixelCount,
                    centroid: seg.centroid,
                    confidence: seg.confidence
                )
            } else if !eligibleForColorOverride,
                      Self.colorCorrectedLabel(currentLabel: seg.label, family: family) != nil {
                print("[COLOR] kept confident specific label \(seg.label) despite colour=\(family) (conf=\(String(format: "%.2f", seg.confidence)))")
            }
            kept.append(outSeg)
        }
        // Never brick the scan: if every segment looked plate-like, keep the
        // original set so downstream still has something to reconstruct.
        return kept.isEmpty ? segments : kept
    }

    /// A specific label at or above this confidence is trusted over the colour
    /// guard. Mirrors FoodClassifierService's 0.55 max-softmax rejection floor
    /// (Hendrycks & Gimpel, ICLR 2017): below it a fine-grained food prediction
    /// is an unreliable guess worth colour-correcting; at or above it the label
    /// is trusted even when its sampled colour doesn't fit a produce whitelist.
    private static let colorOverrideConfidenceFloor: Float = 0.55

    private static func colorFamily(r: Double, g: Double, b: Double) -> String {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        // Near-grey (plate/background, cream/white foods): no hue to judge.
        if maxC - minC < 26 { return maxC > 165 ? "white" : (maxC < 70 ? "dark" : "grey") }
        if g > r * 1.12 && g >= b * 1.02 && g > 55 { return "green" }
        // Orange MUST be tested before red. Roasted/browned orange foods (a
        // seared sweet potato reads ~ r180 g110 b60) carry enough red to satisfy
        // the greedy `r > g*1.25` red test, so with red first they were
        // mis-bucketed "red" — and since "sweet potato" is only in the orange
        // whitelist it then got force-relabelled "tomato". Requiring a
        // meaningful green channel (g > 85) here keeps true reds (a tomato is
        // r200 g60 b50, g < 85) falling through to the red test below.
        if r > 150 && g > 85 && g < 195 && b < 95 { return "orange" }
        if r > g * 1.25 && r > b * 1.2 && r > 70 { return "red" }
        return "other"
    }

    /// Whether a label is a genuinely pale food (rice, egg, cheese…), so a
    /// white/grey mean colour is NOT proof it is the plate/background.
    private static func isPaleFood(_ label: String) -> Bool {
        let l = label.lowercased()
        let pale = ["rice", "egg", "bread", "pasta", "noodle", "potato", "cheese",
                    "mozzarella", "feta", "yogurt", "yoghurt", "cauliflower", "milk",
                    "tofu", "dough", "cream", "garlic", "onion", "coconut", "sugar",
                    "flour", "mushroom", "dumpling", "bun", "tortilla", "mayonnaise",
                    "mayo", "ricotta", "quark", "oat"]
        return pale.contains { l.contains($0) }
    }

    private static func colorCorrectedLabel(currentLabel: String, family: String) -> String? {
        let l = currentLabel.lowercased()
        // Cooked proteins read as warm reds/oranges/browns: a seared steak is
        // reddish, roasted chicken/sausage/bacon is orange-brown, salmon/tuna
        // are pink-red. They are NOT produce, so the colour guard must never
        // rewrite them into a vegetable — a low-confidence "meat"/"beef" on a
        // red-brown entrecote used to become "tomato". Whitelisted in every warm
        // family so even the low-confidence fallback keeps the protein rather
        // than inventing produce.
        let proteins = ["steak", "beef", "entrecote", "pork", "chicken",
                        "sausage", "bacon", "salmon", "tuna", "ham", "meat",
                        "lamb", "turkey", "fish", "shrimp"]
        switch family {
        case "green":
            let ok = ["cucumber", "lettuce", "broccoli", "salad", "spinach",
                      "pea", "bean", "zucchini", "avocado", "kale", "celery",
                      "lime", "kiwi", "asparagus", "cabbage", "herb", "pepper",
                      "pickle", "edamame", "sprout", "green"] + proteins
            return ok.contains(where: { l.contains($0) }) ? nil : "cucumber"
        case "red":
            let ok = ["tomato", "strawberr", "apple", "pepper", "cherry",
                      "radish", "beet", "raspberr", "watermelon", "pomegranate",
                      "chili", "red"] + proteins
            return ok.contains(where: { l.contains($0) }) ? nil : "tomato"
        case "orange":
            let ok = ["carrot", "orange", "pumpkin", "sweet potato", "mango",
                      "apricot", "peach", "squash", "cantaloupe", "papaya"] + proteins
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

    /// Low-specificity base labels the segmenter falls back to when it cannot
    /// name a food precisely. A confident open-vocabulary match should be
    /// allowed to replace these (e.g. "fish" → "salmon", "others" → "almond").
    /// Tokens are singularised by `recognitionTokens`, so plural forms match too.
    private static let genericBaseLabels: Set<String> = [
        "fish", "seafood", "meat", "poultry", "food", "other",
        "vegetable", "fruit", "nut", "seed", "dish", "snack", "produce",
    ]

    /// Produce that must read as a saturated colour (red tomato, green cucumber,
    /// orange carrot…). A beige/brown/dark sample under one of these labels is a
    /// contradiction handled by `demoteColorContradictingProduce`.
    private static let saturatedProduceLabels: Set<String> = [
        "tomato", "strawberry", "cherry", "raspberry", "watermelon",
        "pomegranate", "chili", "radish", "beet", "carrot", "pumpkin",
        "apricot", "mango", "tangerine", "clementine", "cucumber",
        "lettuce", "broccoli", "spinach", "kale", "zucchini", "lime",
        "kiwi", "celery", "edamame",
    ]

    private static func needsSaturatedColor(_ label: String) -> Bool {
        !recognitionTokens(label).isDisjoint(with: saturatedProduceLabels)
    }

    private static func isCompositeDish(_ label: String) -> Bool {
        !recognitionTokens(label).isDisjoint(with: compositeDishLabels)
    }

    private static func isWholeProduce(_ label: String) -> Bool {
        !recognitionTokens(label).isDisjoint(with: wholeProduceLabels)
    }

    private static func isGenericBase(_ label: String) -> Bool {
        !recognitionTokens(label).isDisjoint(with: genericBaseLabels)
    }

    /// Stable per-segment key used to correlate the classifier / open-vocab
    /// candidate bookkeeping with the final segment list. The mask centroid is
    /// preserved verbatim by every refinement pass, so it survives relabelling.
    private static func segmentKey(_ segment: SegmentationService.SegmentedObject) -> String {
        "\(segment.centroid.row),\(segment.centroid.col)"
    }

    /// Record a plausible-but-rejected refinement guess for a segment so the UI
    /// can offer it as a candidate when it later asks the user for the real name.
    private func recordRejectedCandidate(_ label: String, for segment: SegmentationService.SegmentedObject) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = Self.segmentKey(segment)
        var existing = refinementCandidatesByKey[key] ?? []
        guard !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        existing.append(trimmed)
        refinementCandidatesByKey[key] = existing
    }

    /// On-device exemplar matching (few-shot, prototype/centroid style — the
    /// Prototypical Networks pattern). For every segment the recogniser has NOT
    /// already confidently confirmed, compare its cached MobileCLIP image
    /// embedding against the per-label centroids of the user's locally-stored
    /// corrections. If the best centroid clears the conservative
    /// `userExemplarCosineFloor`, adopt that learned label and mark the segment
    /// confirmed (`label_source = "user_exemplar"`) so it is NOT surfaced as
    /// unknown. Purely local: operates only on `userExemplars` passed in from
    /// on-device storage. No-op when MobileCLIP is unavailable, no exemplars
    /// exist, or no embedding was captured for the segment.
    private func applyUserExemplarLabels(
        _ segments: [SegmentationService.SegmentedObject]
    ) -> [SegmentationService.SegmentedObject] {
        guard !userExemplars.isEmpty, !segments.isEmpty else { return segments }

        // Build per-label centroids (prototypes): mean of the L2-normalised
        // exemplar vectors for each label, renormalised so cosine == dot.
        var sums: [String: [Float]] = [:]
        var counts: [String: Int] = [:]
        for ex in userExemplars {
            if var acc = sums[ex.label] {
                guard acc.count == ex.vector.count else { continue }
                for i in 0..<acc.count { acc[i] += ex.vector[i] }
                sums[ex.label] = acc
            } else {
                sums[ex.label] = ex.vector
            }
            counts[ex.label, default: 0] += 1
        }
        var centroids: [(label: String, vector: [Float])] = []
        for (label, sum) in sums {
            var v = sum
            var norm: Float = 0
            for x in v { norm += x * x }
            norm = norm.squareRoot()
            guard norm > 0 else { continue }
            for i in 0..<v.count { v[i] /= norm }
            centroids.append((label, v))
        }
        guard !centroids.isEmpty else { return segments }

        var out = segments
        for i in out.indices {
            let seg = out[i]
            let key = Self.segmentKey(seg)
            // Do not fight a recogniser-confirmed label; only fill/rescue
            // segments the normal passes left unconfirmed.
            if confirmedLabelKeys.contains(key) { continue }
            guard let vec = segmentEmbeddingsByKey[key], !vec.isEmpty else { continue }

            var best: (label: String, cosine: Float)?
            for centroid in centroids where centroid.vector.count == vec.count {
                var dot: Float = 0
                for c in 0..<vec.count { dot += vec[c] * centroid.vector[c] }
                if best == nil || dot > best!.cosine {
                    best = (centroid.label, dot)
                }
            }
            guard let match = best else { continue }
            if match.cosine >= Self.userExemplarCosineFloor {
                out[i] = SegmentationService.SegmentedObject(
                    label: match.label,
                    classIndex: seg.classIndex,
                    mask: seg.mask,
                    pixelCount: seg.pixelCount,
                    centroid: seg.centroid,
                    confidence: max(seg.confidence, match.cosine)
                )
                confirmedLabelKeys.insert(key)
                labelSourceByKey[key] = "user_exemplar"
                print("[EXEMPLAR] matched seg \(seg.label) → \(match.label) " +
                      "cos=\(String(format: "%.3f", match.cosine)) " +
                      "(floor \(String(format: "%.2f", Self.userExemplarCosineFloor)))")
            } else {
                print("[EXEMPLAR] no confident match for seg \(seg.label) " +
                      "best=\(match.label) cos=\(String(format: "%.3f", match.cosine)) " +
                      "< floor \(String(format: "%.2f", Self.userExemplarCosineFloor)) — will ask user")
            }
        }
        return out
    }

    /// Copy the per-scan cached embedding + label provenance onto each segment
    /// struct so both serialisers (LiDAR in this file, monocular in
    /// `MonocularVolumeEstimator`) emit `embedding` / `label_source`
    /// identically. Additive: touches no label, mask or volume.
    private func stampLabelMetadata(
        _ segments: [SegmentationService.SegmentedObject]
    ) -> [SegmentationService.SegmentedObject] {
        var out = segments
        for i in out.indices {
            let key = Self.segmentKey(out[i])
            out[i].embedding = segmentEmbeddingsByKey[key] ?? []
            out[i].labelSource = labelSourceByKey[key]
        }
        return out
    }

    /// Flag every segment that reached the end of both refinement passes still
    /// carrying only a generic / low-confidence segmentation guess that no pass
    /// confidently confirmed, and attach the best-effort candidate labels those
    /// passes rejected. Purely additive: it never changes a label, mask or
    /// volume — it only sets `needsUserLabel` / `candidateLabels` so the JSON can
    /// tell Dart to ask the user instead of silently showing a guess.
    private func annotateSegmentsNeedingUserLabel(
        _ segments: [SegmentationService.SegmentedObject]
    ) -> [SegmentationService.SegmentedObject] {
        var out = segments
        for i in out.indices {
            let seg = out[i]
            let key = Self.segmentKey(seg)
            let confirmed = confirmedLabelKeys.contains(key)
            let uncertain = Self.isGenericBase(seg.label)
                || seg.confidence < Self.needsUserLabelConfidenceFloor
            let needs = !confirmed && uncertain
            out[i].needsUserLabel = needs
            // Only surface candidates for the segments we will actually ask
            // about — a confident food does not need a picker.
            out[i].candidateLabels = needs
                ? (refinementCandidatesByKey[key] ?? [])
                : []
            if needs {
                print("[NEEDS-LABEL] seg \(seg.label) conf=\(String(format: "%.2f", seg.confidence)) generic=\(Self.isGenericBase(seg.label)) candidates=[\(out[i].candidateLabels.joined(separator: ", "))]")
            }
        }
        return out
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
        // Raw central depth spread for the food-presence gate/log only. It is
        // never a food height, shape or volume source, so no clamp/floor.
        return heightCm
    }

}

// MARK: - ScanMaskGeometry (pure, unit-testable)

/// Pure mask geometry for the scan pipeline. It has no CoreVideo/ARKit state,
/// so every rule can be tested on its own:
///  • the capture ROI: TOP keeps the centred circle, SIDE uses a centred
///    rounded rectangle with the same normalisation (fraction of the square
///    crop side);
///  • instance de-duplication by mask overlap (mask-IoU / IoMin NMS);
///  • connected-component splitting AFTER a morphological close and hole fill,
///    so a stem / highlight / shadow fragment never becomes a second food;
///  • nearest in-mask pixel lookup (exact side-photo colour sampling);
///  • side-silhouette ↔ top-instance matching.
enum ScanMaskGeometry {

    // MARK: Capture ROI

    /// Capture-guide radius as a fraction of the square crop side (the crop is
    /// resized to the square model input). The TOP circle radius and the SIDE
    /// rounded rectangle's half-width share this value.
    static let roiRadiusFraction = 0.485
    /// SIDE rounded rectangle: half-height = this × half-width.
    static let sideRectHeightRatio = 0.55
    /// SIDE rounded rectangle corner radius as a fraction of the FULL rect height.
    static let sideRectCornerFraction = 0.18

    enum ROIShape: Equatable {
        case circle
        /// The rectangle's long side runs along image columns (x) when
        /// `longAxisAlongColumns` is true, along image rows otherwise.
        case roundedRect(longAxisAlongColumns: Bool)
    }

    struct ROI {
        let width: Int
        let height: Int
        let shape: ROIShape
        let centreX: Double
        let centreY: Double
        let halfX: Double
        let halfY: Double
        let cornerRadius: Double

        init(width: Int, height: Int, shape: ROIShape) {
            self.width = width
            self.height = height
            self.shape = shape
            centreX = Double(width - 1) * 0.5
            centreY = Double(height - 1) * 0.5
            let radius = Double(min(width, height)) * ScanMaskGeometry.roiRadiusFraction
            switch shape {
            case .circle:
                halfX = radius
                halfY = radius
                cornerRadius = radius
            case .roundedRect(let longAxisAlongColumns):
                let halfShort = radius * ScanMaskGeometry.sideRectHeightRatio
                halfX = longAxisAlongColumns ? radius : halfShort
                halfY = longAxisAlongColumns ? halfShort : radius
                cornerRadius = ScanMaskGeometry.sideRectCornerFraction * 2.0 * halfShort
            }
        }

        func contains(row: Int, column: Int) -> Bool {
            let dx = abs(Double(column) - centreX)
            let dy = abs(Double(row) - centreY)
            switch shape {
            case .circle:
                return dx * dx + dy * dy <= halfX * halfX
            case .roundedRect:
                guard dx <= halfX, dy <= halfY else { return false }
                let qx = dx - (halfX - cornerRadius)
                let qy = dy - (halfY - cornerRadius)
                guard qx > 0, qy > 0 else { return true }
                return qx * qx + qy * qy <= cornerRadius * cornerRadius
            }
        }

        /// 0…1 score of how close a point is to the ROI centre (1 = centre,
        /// 0 = on/after the ROI boundary along that direction).
        func centredness(row: Double, column: Double) -> Double {
            let nx = (column - centreX) / max(halfX, 1e-6)
            let ny = (row - centreY) / max(halfY, 1e-6)
            return max(0.0, 1.0 - (nx * nx + ny * ny).squareRoot())
        }

        /// Geometry normalised to the square crop side, for the `[ROI]` log.
        var logDescription: String {
            let side = Double(max(1, min(width, height)))
            switch shape {
            case .circle:
                return String(format: "shape=circle centre=0.50,0.50 radius=%.3f", halfX / side)
            case .roundedRect(let longAxisAlongColumns):
                let halfLong = max(halfX, halfY) / side
                let halfShort = min(halfX, halfY) / side
                let geometry = String(
                    format: "shape=roundedRect centre=0.50,0.50 halfW=%.3f halfH=%.3f corner=%.3f",
                    halfLong, halfShort, cornerRadius / side)
                return geometry + " longAxis=\(longAxisAlongColumns ? "columns" : "rows")"
            }
        }
    }

    /// Normalised (top-left origin) centred square of the buffer's short side —
    /// the same crop `PlateDetector` falls back to when no plate is found, so
    /// the SIDE ROI shares the TOP circle's normalisation (no aspect squash).
    static func centredSquareCrop(width: Int, height: Int) -> CGRect {
        guard width > 0, height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let side = Double(min(width, height))
        let w = side / Double(width)
        let h = side / Double(height)
        return CGRect(x: (1.0 - w) / 2.0, y: (1.0 - h) / 2.0, width: w, height: h)
    }

    // MARK: Binary masks

    struct BinaryMask: Equatable {
        let width: Int
        let height: Int
        var bits: [Bool]

        init(width: Int, height: Int, bits: [Bool]? = nil) {
            let w = max(0, width)
            let h = max(0, height)
            self.width = w
            self.height = h
            if let bits, bits.count == w * h {
                self.bits = bits
            } else {
                self.bits = [Bool](repeating: false, count: w * h)
            }
        }

        init(rows: [[UInt8]]) {
            let h = rows.count
            let w = rows.first?.count ?? 0
            var bits = [Bool](repeating: false, count: w * h)
            for r in 0..<h {
                let row = rows[r]
                for c in 0..<min(w, row.count) where row[c] != 0 {
                    bits[r * w + c] = true
                }
            }
            self.init(width: w, height: h, bits: bits)
        }

        subscript(row: Int, column: Int) -> Bool {
            get { bits[row * width + column] }
            set { bits[row * width + column] = newValue }
        }

        var count: Int { bits.reduce(0) { $1 ? $0 + 1 : $0 } }

        var rows: [[UInt8]] {
            var out = [[UInt8]](
                repeating: [UInt8](repeating: 0, count: width), count: height)
            for r in 0..<height {
                for c in 0..<width where bits[r * width + c] { out[r][c] = 1 }
            }
            return out
        }

        /// Integer centroid (row, col), matching `SegmentedObject.centroid`.
        var centroid: (row: Int, col: Int)? {
            var n = 0, sumR = 0, sumC = 0
            for i in 0..<bits.count where bits[i] {
                n += 1
                sumR += i / max(1, width)
                sumC += i % max(1, width)
            }
            guard n > 0 else { return nil }
            return (sumR / n, sumC / n)
        }

        func intersectionCount(_ other: BinaryMask) -> Int {
            guard width == other.width, height == other.height else { return 0 }
            var n = 0
            for i in 0..<bits.count where bits[i] && other.bits[i] { n += 1 }
            return n
        }

        func union(_ other: BinaryMask) -> BinaryMask {
            guard width == other.width, height == other.height else { return self }
            var out = self
            for i in 0..<bits.count where other.bits[i] { out.bits[i] = true }
            return out
        }

        func inverted() -> BinaryMask {
            BinaryMask(width: width, height: height, bits: bits.map { !$0 })
        }
    }

    /// Square (box) dilation by `radius` using separable prefix sums. Pixels
    /// outside the image count as unset.
    static func dilated(_ m: BinaryMask, radius: Int) -> BinaryMask {
        guard radius > 0, m.width > 0, m.height > 0 else { return m }
        let w = m.width, h = m.height
        var horizontal = [Bool](repeating: false, count: w * h)
        var rowPrefix = [Int](repeating: 0, count: w + 1)
        for r in 0..<h {
            let base = r * w
            for c in 0..<w { rowPrefix[c + 1] = rowPrefix[c] + (m.bits[base + c] ? 1 : 0) }
            for c in 0..<w {
                let lo = max(0, c - radius), hi = min(w - 1, c + radius)
                horizontal[base + c] = rowPrefix[hi + 1] - rowPrefix[lo] > 0
            }
        }
        var out = [Bool](repeating: false, count: w * h)
        var columnPrefix = [Int](repeating: 0, count: h + 1)
        for c in 0..<w {
            for r in 0..<h { columnPrefix[r + 1] = columnPrefix[r] + (horizontal[r * w + c] ? 1 : 0) }
            for r in 0..<h {
                let lo = max(0, r - radius), hi = min(h - 1, r + radius)
                out[r * w + c] = columnPrefix[hi + 1] - columnPrefix[lo] > 0
            }
        }
        return BinaryMask(width: w, height: h, bits: out)
    }

    /// Square (box) erosion. Pixels outside the image count as SET, so a
    /// closing never eats a food that touches the frame edge.
    static func eroded(_ m: BinaryMask, radius: Int) -> BinaryMask {
        guard radius > 0 else { return m }
        return dilated(m.inverted(), radius: radius).inverted()
    }

    /// Morphological closing (dilate then erode), always a superset of `m`.
    static func closed(_ m: BinaryMask, radius: Int) -> BinaryMask {
        guard radius > 0 else { return m }
        return eroded(dilated(m, radius: radius), radius: radius).union(m)
    }

    /// Fill every background region not 4-connected to the image border.
    static func filledHoles(_ m: BinaryMask) -> BinaryMask {
        let w = m.width, h = m.height
        guard w > 0, h > 0 else { return m }
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func seed(_ i: Int) {
            if !m.bits[i] && !outside[i] {
                outside[i] = true
                stack.append(i)
            }
        }
        for c in 0..<w {
            seed(c)
            seed((h - 1) * w + c)
        }
        for r in 0..<h {
            seed(r * w)
            seed(r * w + w - 1)
        }
        while let i = stack.popLast() {
            let r = i / w, c = i % w
            if r > 0 { seed(i - w) }
            if r < h - 1 { seed(i + w) }
            if c > 0 { seed(i - 1) }
            if c < w - 1 { seed(i + 1) }
        }
        var out = m
        for i in 0..<out.bits.count where !outside[i] { out.bits[i] = true }
        return out
    }

    /// 8-connected component labelling: `labels[i]` is the component id of
    /// pixel `i` (-1 for background) and `areas[id]` its pixel count.
    static func labelComponents(_ m: BinaryMask) -> (labels: [Int], areas: [Int]) {
        let w = m.width, h = m.height
        var labels = [Int](repeating: -1, count: w * h)
        var areas: [Int] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where m.bits[start] && labels[start] < 0 {
            let id = areas.count
            labels[start] = id
            stack.append(start)
            var area = 0
            while let i = stack.popLast() {
                area += 1
                let r = i / w, c = i % w
                for dr in -1...1 {
                    let nr = r + dr
                    guard nr >= 0, nr < h else { continue }
                    for dc in -1...1 where dr != 0 || dc != 0 {
                        let nc = c + dc
                        guard nc >= 0, nc < w else { continue }
                        let j = nr * w + nc
                        if m.bits[j] && labels[j] < 0 {
                            labels[j] = id
                            stack.append(j)
                        }
                    }
                }
            }
            areas.append(area)
        }
        return (labels, areas)
    }

    // MARK: Instance split

    struct SplitPlan {
        let rawComponents: Int
        let groupedComponents: Int
        let closingRadius: Int
        /// Original-pixel area of each grouped component, largest first.
        let componentAreas: [Int]
        /// One mask per real piece (original pixels; sub-threshold fragments are
        /// attached to the nearest piece), largest first. Empty = keep as one.
        let pieces: [BinaryMask]
        let reason: String
        var shouldSplit: Bool { pieces.count >= 2 }
    }

    /// Decide whether one instance mask really holds several separate foods.
    /// Components are grouped on a closed + hole-filled copy of the mask (so a
    /// stem, a specular highlight or a shadow fringe separated by a thin gap
    /// stays with its food), and a split only happens when ≥2 grouped pieces are
    /// each substantial (≥ `minPieceFractionOfLargest` of the largest and
    /// ≥ `minPiecePixels`). Pieces keep their ORIGINAL pixels, so the exact
    /// silhouette is never altered.
    static func planSplit(
        _ mask: BinaryMask,
        minPiecePixels: Int = 150,
        minPieceFractionOfLargest: Double = 0.2,
        maxPieces: Int = 16
    ) -> SplitPlan {
        let raw = labelComponents(mask)
        guard raw.areas.count >= 2 else {
            return SplitPlan(rawComponents: raw.areas.count, groupedComponents: raw.areas.count,
                             closingRadius: 0, componentAreas: raw.areas, pieces: [],
                             reason: "single_component")
        }
        let w = mask.width
        let largestRaw = raw.areas.max() ?? 0
        let radius = min(8, max(2, Int((0.05 * Double(largestRaw).squareRoot()).rounded())))
        let grouped = labelComponents(filledHoles(closed(mask, radius: radius)))
        var areas = [Int](repeating: 0, count: grouped.areas.count)
        var sumR = [Double](repeating: 0, count: grouped.areas.count)
        var sumC = [Double](repeating: 0, count: grouped.areas.count)
        for i in 0..<mask.bits.count where mask.bits[i] {
            let g = grouped.labels[i]
            guard g >= 0 else { continue }
            areas[g] += 1
            sumR[g] += Double(i / w)
            sumC[g] += Double(i % w)
        }
        let order = areas.indices.filter { areas[$0] > 0 }.sorted { areas[$0] > areas[$1] }
        let sortedAreas = order.map { areas[$0] }
        guard order.count >= 2, let largest = sortedAreas.first else {
            return SplitPlan(rawComponents: raw.areas.count, groupedComponents: order.count,
                             closingRadius: radius, componentAreas: sortedAreas, pieces: [],
                             reason: "fragments_bridged")
        }
        let threshold = max(minPiecePixels,
                            Int((Double(largest) * minPieceFractionOfLargest).rounded(.up)))
        let real = order.filter { areas[$0] >= threshold }
        guard real.count >= 2 else {
            return SplitPlan(rawComponents: raw.areas.count, groupedComponents: order.count,
                             closingRadius: radius, componentAreas: sortedAreas, pieces: [],
                             reason: "fragments_below_threshold(\(threshold)px)")
        }
        guard real.count <= maxPieces else {
            return SplitPlan(rawComponents: raw.areas.count, groupedComponents: order.count,
                             closingRadius: radius, componentAreas: sortedAreas, pieces: [],
                             reason: "too_many_pieces")
        }
        var owner = [Int](repeating: -1, count: grouped.areas.count)
        for (k, g) in real.enumerated() { owner[g] = k }
        for g in order where owner[g] < 0 {
            let cr = sumR[g] / Double(areas[g]), cc = sumC[g] / Double(areas[g])
            var best = 0
            var bestD = Double.greatestFiniteMagnitude
            for (k, rg) in real.enumerated() {
                let dr = cr - sumR[rg] / Double(areas[rg])
                let dc = cc - sumC[rg] / Double(areas[rg])
                let d = dr * dr + dc * dc
                if d < bestD { bestD = d; best = k }
            }
            owner[g] = best
        }
        var pieces = real.map { _ in BinaryMask(width: mask.width, height: mask.height) }
        for i in 0..<mask.bits.count where mask.bits[i] {
            let g = grouped.labels[i]
            guard g >= 0, owner[g] >= 0 else { continue }
            pieces[owner[g]].bits[i] = true
        }
        return SplitPlan(rawComponents: raw.areas.count, groupedComponents: order.count,
                         closingRadius: radius, componentAreas: sortedAreas, pieces: pieces,
                         reason: "separated")
    }

    // MARK: Instance merge (mask NMS)

    static func normalisedFoodLabel(_ label: String) -> String {
        label.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sameFood(_ aLabel: String, _ aClass: Int, _ bLabel: String, _ bClass: Int) -> Bool {
        aClass == bClass || normalisedFoodLabel(aLabel) == normalisedFoodLabel(bLabel)
    }

    /// Merge rule: the same food merges on IoU ≥ 0.5 or containment
    /// (IoMin ≥ 0.7, a partial duplicate / highlight / stem detection);
    /// different foods merge only when they are the same region (IoU ≥ 0.7),
    /// so a garnish sitting on another food is never swallowed.
    static func shouldMerge(iou: Double, ioMin: Double, sameFood: Bool) -> Bool {
        if sameFood { return iou >= 0.5 || ioMin >= 0.7 }
        return iou >= 0.7
    }

    /// Overlap-based instance de-duplication. Masks are visited largest first;
    /// each later mask joins the current group when it overlaps the group's
    /// accumulated union per `shouldMerge`. Returns groups of input indices,
    /// the representative (largest) first.
    static func mergeGroups(
        masks: [BinaryMask],
        sameFood: (Int, Int) -> Bool
    ) -> [[Int]] {
        let areas = masks.map { $0.count }
        let order = masks.indices.sorted {
            areas[$0] != areas[$1] ? areas[$0] > areas[$1] : $0 < $1
        }
        var assigned = [Bool](repeating: false, count: masks.count)
        var groups: [[Int]] = []
        for (pos, i) in order.enumerated() where !assigned[i] {
            assigned[i] = true
            var group = [i]
            var union = masks[i]
            var unionArea = areas[i]
            for j in order[(pos + 1)...] where !assigned[j] {
                let inter = union.intersectionCount(masks[j])
                guard inter > 0 else { continue }
                let unionCount = unionArea + areas[j] - inter
                let iou = Double(inter) / Double(max(1, unionCount))
                let ioMin = Double(inter) / Double(max(1, min(unionArea, areas[j])))
                if shouldMerge(iou: iou, ioMin: ioMin, sameFood: sameFood(i, j)) {
                    assigned[j] = true
                    group.append(j)
                    union = union.union(masks[j])
                    unionArea = unionCount
                }
            }
            groups.append(group)
        }
        return groups
    }

    // MARK: Nearest in-mask pixel

    /// Euclidean-nearest set pixel to (row, column) in a row-major 0/1 grid,
    /// searching square rings out to `maxRadius`.
    static func nearestSetPixel(
        in grid: [[UInt8]],
        row: Int,
        column: Int,
        maxRadius: Int
    ) -> (row: Int, column: Int)? {
        let h = grid.count
        let w = grid.first?.count ?? 0
        guard h > 0, w > 0 else { return nil }
        func isSet(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < h && c >= 0 && c < grid[r].count && grid[r][c] != 0
        }
        if isSet(row, column) { return (row, column) }
        var best: (row: Int, column: Int)?
        var bestD = Int.max
        func consider(_ r: Int, _ c: Int) {
            guard isSet(r, c) else { return }
            let d = (r - row) * (r - row) + (c - column) * (c - column)
            if d < bestD {
                bestD = d
                best = (r, c)
            }
        }
        var limit = max(0, maxRadius)
        var tightened = false
        var radius = 1
        while radius <= limit {
            for dr in -radius...radius {
                let r = row + dr
                guard r >= 0, r < h else { continue }
                if abs(dr) == radius {
                    for dc in -radius...radius { consider(r, column + dc) }
                } else {
                    consider(r, column - radius)
                    consider(r, column + radius)
                }
            }
            if best != nil, !tightened {
                // A hit at ring r is ≤ r·√2 away; nothing beyond that ring can win.
                limit = min(limit, Int((Double(radius) * 2.0.squareRoot()).rounded(.up)))
                tightened = true
            }
            radius += 1
        }
        return best
    }

    // MARK: Side silhouette ↔ top instance matching

    struct SideMatchTop {
        /// Footprint interval along the side camera's horizontal image axis,
        /// normalised 0…1 in TOP-mask space and already oriented (flipped when
        /// the side horizontal runs opposite to the matched top axis).
        let lo: Double
        let hi: Double
        let area: Int
        let label: String
        let classIndex: Int
        var projectedLo: Double?
        var projectedHi: Double?
        var cameraDepth: Double?
        var centre: Double { (lo + hi) * 0.5 }
    }

    struct SideMatchSide {
        /// Inclusive horizontal pixel span along the side horizontal axis.
        let lo: Int
        let hi: Int
        let area: Int
        let label: String
        let classIndex: Int
        /// 0…1, 1 = segment centroid at the side ROI centre.
        let centredness: Double
        /// Vertical mask extent (pixels) per horizontal pixel index.
        let verticalExtent: [Int]
    }

    struct SideMatchAssignment: Equatable {
        let topIndex: Int
        let sideIndex: Int
        /// Inclusive horizontal pixel range of the side mask used for this top.
        let from: Int
        let to: Int
        let score: Double
        let isSplit: Bool
        /// True when this top borrows a side slice that belongs to another top
        /// (occluded behind it, or left unmatched and given the nearest one).
        var isShared: Bool = false
        /// Why this side piece was given to this top (logged as [SIDEMATCH]).
        var reason: String = "overlap"
    }

    /// Assign every top instance one or more side-silhouette pieces. The side
    /// view only ever provides PROFILES — it never adds instances — and a real
    /// side silhouette is never dropped (AGENTS.md §9: there is no prior,
    /// default height to fall back to). A top may receive
    /// several pieces (their union is its silhouette).
    ///
    /// - One top food: it gets the union of ALL side food segments (stem /
    ///   highlight / shadow splits are rejoined).
    /// - Several foods: each top's footprint is mapped onto the side
    ///   horizontal axis (calibrated photo-pose projection, else a linear map
    ///   of the top span onto the side span). A side segment goes to the
    ///   top(s) it overlaps; one shared by separated foods is cut at the
    ///   narrowest point (waist) between their predicted positions, and
    ///   co-located foods use only the calibrated front food's piece.
    /// - Side pieces overlapping no top are paired with still-unmatched tops by
    ///   horizontal ORDER, or else unioned into the nearest top.
    /// - A top still unmatched remains explicitly unmeasured.
    static func matchSideSegments(
        tops: [SideMatchTop],
        sides: [SideMatchSide],
        horizontalDim: Int
    ) -> [SideMatchAssignment] {
        guard !tops.isEmpty, !sides.isEmpty, horizontalDim > 0 else { return [] }
        let candidates = sides.indices.filter {
            sides[$0].area > 0 && sides[$0].hi >= sides[$0].lo
        }
        guard !candidates.isEmpty else { return [] }
        func sorted(_ list: [SideMatchAssignment]) -> [SideMatchAssignment] {
            list.sorted {
                ($0.topIndex, $0.sideIndex, $0.from) < ($1.topIndex, $1.sideIndex, $1.from)
            }
        }

        if tops.count == 1 {
            let reason = candidates.count == 1 ? "single_food" : "single_food_union"
            return sorted(candidates.map {
                SideMatchAssignment(topIndex: 0, sideIndex: $0, from: sides[$0].lo, to: sides[$0].hi,
                                    score: 1, isSplit: false, isShared: false, reason: reason)
            })
        }

        let maxTopArea = tops.map(\.area).max() ?? 0
        let substantial = Set(tops.indices.filter {
            Double(tops[$0].area) >= 0.15 * Double(maxTopArea)
        })
        let anchor = substantial.count >= 2 ? Array(substantial) : Array(tops.indices)
        let a = anchor.map { tops[$0].lo }.min() ?? 0
        let b = anchor.map { tops[$0].hi }.max() ?? 1
        let h0 = Double(candidates.map { sides[$0].lo }.min() ?? 0)
        let h1 = Double((candidates.map { sides[$0].hi }.max() ?? 0) + 1)
        let topSpan = max(1e-6, b - a)
        func predict(_ x: Double) -> Double { h0 + (x - a) / topSpan * (h1 - h0) }
        func predicted(_ t: Int) -> (lo: Double, hi: Double) {
            if let lo = tops[t].projectedLo, let hi = tops[t].projectedHi {
                return (lo * Double(horizontalDim), hi * Double(horizontalDim))
            }
            return (predict(tops[t].lo), predict(tops[t].hi))
        }
        func predictedCentre(_ t: Int) -> Double {
            let p = predicted(t)
            return (p.lo + p.hi) * 0.5
        }
        func sideCentre(_ s: Int) -> Double { (Double(sides[s].lo) + Double(sides[s].hi + 1)) * 0.5 }
        /// Fraction of the narrower of the two intervals covered by their
        /// intersection: 1 when one contains the other.
        func overlap(_ t: Int, _ s: Int) -> Double {
            let p = predicted(t)
            let sLo = Double(sides[s].lo), sHi = Double(sides[s].hi + 1)
            let inter = max(0, min(p.hi, sHi) - max(p.lo, sLo))
            return inter / max(1e-6, min(p.hi - p.lo, sHi - sLo))
        }
        /// A small, uncalibrated top never slices a main food's silhouette.
        func mayOwn(_ t: Int, among owners: [Int]) -> Bool {
            substantial.contains(t) || tops[t].projectedLo != nil
                || !owners.contains(where: { substantial.contains($0) })
        }

        var result: [SideMatchAssignment] = []
        var unowned: [Int] = []

        // Phase 1: overlap ownership and waist splitting.
        for s in candidates {
            let side = sides[s]
            let scored = tops.indices.map { ($0, overlap($0, s)) }.filter { $0.1 >= 0.25 }
            guard let best = scored.map(\.1).max() else {
                unowned.append(s)
                continue
            }
            var owners = scored.filter { $0.1 >= 0.5 * best }.map(\.0)
            owners = owners.filter { mayOwn($0, among: owners) }
            let scoreOf = Dictionary(uniqueKeysWithValues: scored)
            let members = owners.sorted { predictedCentre($0) < predictedCentre($1) }
            guard !members.isEmpty else {
                unowned.append(s)
                continue
            }
            var clusters: [[Int]] = [[members[0]]]
            for k in 1..<max(1, members.count) {
                let prev = predicted(members[k - 1])
                let cur = predicted(members[k])
                let inter = max(0, min(prev.hi, cur.hi) - max(prev.lo, cur.lo))
                let minWidth = min(prev.hi - prev.lo, cur.hi - cur.lo)
                if inter >= 0.5 * minWidth {
                    clusters[clusters.count - 1].append(members[k])
                } else {
                    clusters.append([members[k]])
                }
            }
            var bounds = [(lo: Int, hi: Int)](repeating: (side.lo, side.hi), count: clusters.count)
            if clusters.count > 1 {
                for k in 0..<(clusters.count - 1) {
                    let c0 = clusters[k].map { predictedCentre($0) }.reduce(0, +) / Double(clusters[k].count)
                    let c1 = clusters[k + 1].map { predictedCentre($0) }.reduce(0, +) / Double(clusters[k + 1].count)
                    let delta = c1 - c0
                    let mid = (c0 + c1) * 0.5
                    let lo = max(side.lo, Int((c0 + 0.25 * delta).rounded(.up)))
                    let hi = min(side.hi - 1, Int((c1 - 0.25 * delta).rounded(.down)))
                    var cut = min(max(Int(mid.rounded()), side.lo), max(side.lo, side.hi - 1))
                    if lo <= hi {
                        var bestExtent = Int.max
                        var bestDistance = Double.greatestFiniteMagnitude
                        for x in lo...hi {
                            let extent = x >= 0 && x < side.verticalExtent.count ? side.verticalExtent[x] : 0
                            let distance = abs(Double(x) - mid)
                            if extent < bestExtent || (extent == bestExtent && distance < bestDistance) {
                                bestExtent = extent
                                bestDistance = distance
                                cut = x
                            }
                        }
                    }
                    bounds[k].hi = min(bounds[k].hi, cut)
                    bounds[k + 1].lo = max(bounds[k + 1].lo, cut + 1)
                }
            }
            for (k, cluster) in clusters.enumerated() where bounds[k].lo <= bounds[k].hi {
                let primary: Int
                if cluster.count == 1 {
                    primary = cluster[0]
                } else if cluster.allSatisfy({ tops[$0].cameraDepth != nil }) {
                    primary = cluster.min { tops[$0].cameraDepth! < tops[$1].cameraDepth! }!
                } else {
                    print("[SIDEMATCH] tops=\(cluster) reason=ambiguous_side_overlap_without_calibration (no borrowed silhouette)")
                    continue
                }
                for t in cluster where t != primary {
                    print("[SIDEMATCH] top#\(t) reason=side_occluded_by_top#\(primary) (no borrowed silhouette)")
                }
                result.append(SideMatchAssignment(
                    topIndex: primary, sideIndex: s, from: bounds[k].lo, to: bounds[k].hi,
                    score: scoreOf[primary] ?? 0, isSplit: clusters.count > 1,
                    isShared: false, reason: "overlap"))
            }
        }

        // Phase 2: side pieces that overlap no top. Pair them with still
        // unmatched tops by horizontal ORDER; otherwise they are split-off
        // parts (stem/highlight/shadow) of the nearest top and are unioned.
        if !unowned.isEmpty {
            let assignedTops = Set(result.map(\.topIndex))
            let freeTops = tops.indices.filter { !assignedTops.contains($0) }
                .sorted { predictedCentre($0) < predictedCentre($1) }
            let freeSides = unowned.sorted { sideCentre($0) < sideCentre($1) }
            for (rank, s) in freeSides.enumerated() {
                let t: Int
                let reason: String
                if !freeTops.isEmpty {
                    let sideRank = (Double(rank) + 0.5) / Double(freeSides.count)
                    t = freeTops.indices.min {
                        abs((Double($0) + 0.5) / Double(freeTops.count) - sideRank)
                            < abs((Double($1) + 0.5) / Double(freeTops.count) - sideRank)
                    }.map { freeTops[$0] }!
                    reason = "order"
                } else {
                    t = tops.indices.min {
                        abs(predictedCentre($0) - sideCentre(s)) < abs(predictedCentre($1) - sideCentre(s))
                    }!
                    reason = "nearest_piece"
                }
                result.append(SideMatchAssignment(
                    topIndex: t, sideIndex: s, from: sides[s].lo, to: sides[s].hi,
                    score: overlap(t, s), isSplit: false, isShared: false, reason: reason))
            }
        }

        return sorted(result)
    }

    /// Union of the assigned side-mask pieces for ONE top: each assignment
    /// contributes its side mask restricted to `from…to` along the side
    /// horizontal axis (rows when `horizontalAlongRows`). Returns the union
    /// mask, its pixel count and each assignment's own pixel count. Pure.
    static func sidePieceUnion(
        sideMasks: [[[UInt8]]],
        assignments: [SideMatchAssignment],
        horizontalAlongRows: Bool
    ) -> (mask: [[UInt8]], pixelCount: Int, piecePixels: [Int]) {
        let height = sideMasks.map(\.count).max() ?? 0
        let width = sideMasks.flatMap { $0.map(\.count) }.max() ?? 0
        var union = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: height)
        var total = 0
        var piecePixels: [Int] = []
        for a in assignments {
            var pixels = 0
            if a.sideIndex >= 0, a.sideIndex < sideMasks.count {
                let mask = sideMasks[a.sideIndex]
                for r in 0..<mask.count {
                    for c in 0..<mask[r].count where mask[r][c] != 0 {
                        let horizontal = horizontalAlongRows ? r : c
                        guard horizontal >= a.from, horizontal <= a.to else { continue }
                        pixels += 1
                        if union[r][c] == 0 {
                            union[r][c] = 1
                            total += 1
                        }
                    }
                }
            }
            piecePixels.append(pixels)
        }
        return (union, total, piecePixels)
    }
}
