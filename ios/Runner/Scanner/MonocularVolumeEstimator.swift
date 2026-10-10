import ARKit
import CoreVideo
import Foundation
import simd

/// Camera-only fallback for iPhones/iPads that do not expose LiDAR-backed
/// scene depth. It produces the same output contract as the LiDAR pipeline:
/// per-food `volume_cm3`, confidence, and an exportable 3-D model file.
///
/// Accuracy contract:
///   • This is an estimate, not a measured LiDAR reconstruction.
///   • Scale priority: plate diameter → ARKit table distance → 30 cm fallback.
///   • Geometry: top-mask footprint × side-view silhouette profile when
///     available, falling back to bounded class priors.
///   • Mesh: generated height-field visual hull from real masks, suitable for
///     the viewer and for keeping volume/calorie math wired identically.
final class MonocularVolumeEstimator {

    struct Result {
        let json: String
        let modelPath: String
        let objects: [[String: Any]]
    }

    struct SideProfile {
        enum TopAxis: String {
            case columns
            case rows
        }

        let label: String
        let classIndex: Int
        let topAxis: TopAxis
        let reversed: Bool
        /// Normalized side silhouette height samples across the side-view
        /// horizontal extent. Values are 0...1 and are extracted from the real
        /// side-view mask, not from a food prior.
        let normalizedHeights: [Double]
        /// Lower/upper side silhouette boundaries for each sample, normalized
        /// so 0 is the visible bottom of the side mask and 1 is its visible top.
        /// These let the mesh match the side contour's bottom and top arcs
        /// instead of assuming every object has a perfectly flat base.
        let normalizedBottoms: [Double]
        let normalizedTops: [Double]
        /// Full-frame vertical-pixel extent / horizontal-pixel extent of the
        /// side mask. Multiplying by the matching top-axis length gives metric
        /// object height without assuming a fixed camera distance.
        let aspectRatio: Double
        let coverage: Double
        let confidence: Float
        let pixelCount: Int
        /// Side-image texture bounds in the same horizontal/vertical axes used
        /// to extract the profile. Values are normalized to the side frame so
        /// mesh side walls can sample the actual side photo locally.
        let textureHorizontalUsesRows: Bool
        let textureHorizontalMin: Double
        let textureHorizontalMax: Double
        let textureVerticalMin: Double
        let textureVerticalMax: Double

        var meanNormalizedHeight: Double {
            guard !normalizedHeights.isEmpty else { return 0 }
            return normalizedHeights.reduce(0, +) / Double(normalizedHeights.count)
        }

        func sample(_ u: Double) -> Double {
            guard !normalizedHeights.isEmpty else { return 0 }
            let clamped = reversed ? 1.0 - min(1.0, max(0.0, u)) : min(1.0, max(0.0, u))
            let x = clamped * Double(normalizedHeights.count - 1)
            let i0 = Int(floor(x))
            let i1 = min(normalizedHeights.count - 1, i0 + 1)
            let t = x - Double(i0)
            return normalizedHeights[i0] * (1.0 - t) + normalizedHeights[i1] * t
        }

        func sampleBounds(_ u: Double) -> (bottom: Double, top: Double) {
            guard !normalizedBottoms.isEmpty,
                  normalizedBottoms.count == normalizedTops.count else {
                let h = sample(u)
                return (0.0, h)
            }
            let clamped = reversed ? 1.0 - min(1.0, max(0.0, u)) : min(1.0, max(0.0, u))
            let x = clamped * Double(normalizedBottoms.count - 1)
            let i0 = Int(floor(x))
            let i1 = min(normalizedBottoms.count - 1, i0 + 1)
            let t = x - Double(i0)
            let bottom = normalizedBottoms[i0] * (1.0 - t) + normalizedBottoms[i1] * t
            let top = normalizedTops[i0] * (1.0 - t) + normalizedTops[i1] * t
            return (min(bottom, top), max(bottom, top))
        }

        func sourceUV(axisU: Double, heightFraction: Double) -> SIMD2<Float> {
            let horizontalT = reversed
                ? 1.0 - min(1.0, max(0.0, axisU))
                : min(1.0, max(0.0, axisU))
            let verticalT = min(1.0, max(0.0, heightFraction))
            let horizontal = textureHorizontalMin +
                (textureHorizontalMax - textureHorizontalMin) * horizontalT
            // In image/mask coordinates, increasing vertical index points
            // toward the visible bottom of the side silhouette.
            let vertical = textureVerticalMax -
                (textureVerticalMax - textureVerticalMin) * verticalT
            if textureHorizontalUsesRows {
                return SIMD2(Float(vertical), Float(horizontal))
            }
            return SIMD2(Float(horizontal), Float(vertical))
        }
    }

    enum EstimateError: LocalizedError {
        case noObjects
        case exportFailed
        case jsonFailed

        var errorDescription: String? {
            switch self {
            case .noObjects:
                return "Camera estimate failed: no exportable food objects"
            case .exportFailed:
                return "Camera estimate failed: 3D model export failed"
            case .jsonFailed:
                return "Camera estimate failed: result serialisation failed"
            }
        }
    }

    private let plateDetector = PlateDetector()
    private let exporter = Food3DExporter()
    private let framePreprocessor = FramePreprocessor()
    private let monoDepth = MonoDepthService()
    /// Conservative fallback capture distance when ARKit has not yet locked a
    /// table plane. Earlier code used 30 cm for every plateless scan; at the
    /// actual 10-25 cm food-scanning distance, monocular volume error grows
    /// roughly with distance cubed, producing tomato-sized objects in the
    /// kilogram range. 22 cm matches the guided capture distance while keeping
    /// ARKit plane distance as the preferred metric source whenever available.
    private let guidedDistanceCm: Double = 22.0

    private struct PhysicalEnvelope {
        let maxLateralCm: Double
        let maxHeightCm: Double
        let maxVolumeCm3: Double
    }

    private struct EstimatedObject {
        let object: DepthFusion.Food3DObject
        let meshVolumeCm3: Double
        let hullVoxelVolumeCm3: Double
        let surfaceExtractionMode: String
        let topSilhouetteSnapVertices: Int
        let topSilhouetteEdgeSnapVertices: Int
    }

    /// A detected bowl/deep container the food sits inside. The side view is
    /// occluded by the bowl walls, so the hidden lower portion of the food is
    /// reconstructed as a rounded cavity (deepest at the centre, rising to the
    /// rim) from the exact top-view footprint, with a common wall thickness
    /// removed so the bowl material is never counted as food.
    private struct BowlModel {
        /// Food fill depth below the visible surface (cm), wall already removed.
        let innerDepthCm: Double
        /// Common bowl wall thickness removed from the food (cm).
        let wallCm: Double
    }

    /// Foods commonly served in a bowl. Bowl reconstruction is gated on one of
    /// these being the dominant food inside a detected circular rim, so a flat
    /// plated food (steak, pizza, sandwich) never triggers the cavity model.
    private static let bowlFoodKeywords: [String] = [
        "salad", "rice", "noodle", "pasta", "soup", "cereal", "oatmeal",
        "porridge", "yogurt", "yoghurt", "granola", "muesli", "bean", "curry",
        "stew", "grain", "poke", "ramen", "pho", "chili", "chilli", "quinoa",
        "couscous", "congee", "chowder", "pudding", "risotto", "cornflakes",
        "fruit salad", "berries", "lentil", "miso",
    ]

    /// Metric-depth (Depth Anything V2 metric-indoor) is OUT-OF-DOMAIN at the
    /// 10–30 cm hold distance used for plated food: device testing showed 4–9×
    /// absolute scale error and ~3× height overestimation (the "everything looks
    /// like a cucumber" tall-dome bug). It is therefore disabled as a volume
    /// source. The reliable metric signal on non-LiDAR devices is the ARKit
    /// tracked camera-to-table distance (see `tableDistanceCm`).
    static var useMetricDepthVolume = false

    /// Depth Anything V2 is unreliable for ABSOLUTE scale (above), but its
    /// RELATIVE per-pixel relief (which parts of the food are higher) is
    /// informative. When enabled we use that relief only to SHAPE the top
    /// surface of the reconstructed mesh; the absolute height/scale still comes
    /// from the reliable plate-diameter + side-silhouette path, so a bad depth
    /// scale can no longer inflate the volume. Fail-safe: with no depth, low
    /// coverage, or a near-flat food (peak < 3 mm → nil relief) the mesh is
    /// built exactly as before, so a flat food stays flat.
    /// Sequenced OFF for now: the texture-projection fix is being validated
    /// first so a shape change can't confound it. Flip to `true` (AGENTS.md §9
    /// sanctioned lever #1) once the texture pass is confirmed on-device; the
    /// relief only refines the top surface within the measured envelope
    /// (weight ≤ 0.5) and never moves the footprint outline.
    static var useDepthRelief = false

    func estimate(
        segments: [SegmentationService.SegmentedObject],
        topFrame: FrameCaptureService.CapturedFrame,
        sideFrame: FrameCaptureService.CapturedFrame?,
        sideProfiles: [SideProfile] = [],
        maskWidth: Int,
        maskHeight: Int,
        measuredHeightCm: Double? = nil,
        preprocessedRGB: CVPixelBuffer? = nil,
        sidePreprocessedRGB: CVPixelBuffer? = nil,
        tableDistanceCm: Double? = nil
    ) throws -> Result {
        let scale = estimateScale(
            topFrame: topFrame,
            maskWidth: maskWidth,
            maskHeight: maskHeight,
            tableDistanceCm: tableDistanceCm
        )

        // Effective focal lengths in MASK-pixel units, used to back-project each
        // food pixel's metric area from depth (self-consistent scale, no plate /
        // distance assumption). The mask is a scaleFill resize of the plate crop,
        // so a full-image focal length maps through the crop fraction.
        let imageW = CVPixelBufferGetWidth(topFrame.pixelBuffer)
        let imageH = CVPixelBufferGetHeight(topFrame.pixelBuffer)
        let plateForFocal = plateDetector.detect(in: topFrame.pixelBuffer)
        let fxImg = Double(topFrame.cameraIntrinsics.columns.0.x)
        let fyImg = Double(topFrame.cameraIntrinsics.columns.1.y)
        let cropWFrac = max(0.05, Double(plateForFocal.rect.width))
        let cropHFrac = max(0.05, Double(plateForFocal.rect.height))
        let fxMask = fxImg > 1 ? fxImg * Double(maskWidth) / (cropWFrac * Double(imageW)) : 0
        let fyMask = fyImg > 1 ? fyImg * Double(maskHeight) / (cropHFrac * Double(imageH)) : 0

        // Metric monocular depth (gated): when `MonoDepth.mlmodelc` is bundled
        // and we have the preprocessed RGB the segmenter used, predict a depth
        // grid aligned to the mask so each food's height above the table can be
        // MEASURED instead of taken from a fixed class prior.
        let depthGrid: MonoDepthService.DepthGrid? = {
            guard MonocularVolumeEstimator.useMetricDepthVolume
                    || MonocularVolumeEstimator.useDepthRelief,
                  let rgb = preprocessedRGB, monoDepth.isAvailable else { return nil }
            return autoreleasepool {
                monoDepth.depthGrid(pixelBuffer: rgb, targetW: maskWidth, targetH: maskHeight)
            }
        }()
        if depthGrid != nil { print("[MonocularEstimator] metric depth available — measuring heights") }

        var objects: [DepthFusion.Food3DObject] = []
        var payload: [[String: Any]] = []
        var metadata: [[String: Any]] = []
        var usedSideProfileIndices = Set<Int>()
        let totalSegmentPixels = segments.reduce(0) { $0 + $1.pixelCount }
        let primarySegmentIndex = segments.indices.max(by: {
            segments[$0].pixelCount < segments[$1].pixelCount
        })
        let primaryPixelCount = primarySegmentIndex.map { segments[$0].pixelCount } ?? 0
        let hasDominantPrimary = primaryPixelCount > 0 &&
            Double(primaryPixelCount) / Double(max(totalSegmentPixels, 1)) >= 0.55

        // Bowl detection (occluded side view). When the dominant food sits in a
        // detected rim and fills it, its hidden lower part is reconstructed as a
        // rounded bowl cavity instead of the (occluded) side silhouette.
        let bowlModel = detectBowl(
            segments: segments,
            primaryIndex: primarySegmentIndex,
            plate: plateForFocal,
            scale: scale,
            sideProfiles: sideProfiles,
            maskWidth: maskWidth,
            maskHeight: maskHeight
        )
        if let bowlModel {
            let name = primarySegmentIndex.map { segments[$0].label } ?? "?"
            print("[BOWL] detected primary=\(name) innerDepth=\(String(format: "%.1f", bowlModel.innerDepthCm))cm wall=\(String(format: "%.1f", bowlModel.wallCm))cm")
        }

        for (idx, seg) in segments.enumerated() {
            guard let footprint = footprintStats(seg.mask, maskWidth: maskWidth, maskHeight: maskHeight) else {
                print("[MonocularEstimator] top-footprint missing food#\(idx) \(seg.label): pixels=\(seg.pixelCount)")
                continue
            }
            let centroidCol = String(format: "%.1f", footprint.centroid.col)
            let centroidRow = String(format: "%.1f", footprint.centroid.row)
            print("[MonocularEstimator] top-footprint food#\(idx) \(seg.label): pixels=\(seg.pixelCount), bbox=\(footprint.maxCol - footprint.minCol + 1)x\(footprint.maxRow - footprint.minRow + 1), centroid=(\(centroidCol),\(centroidRow))")

            let prior = priors(for: seg.label)
            let rawAreaCm2 = Double(seg.pixelCount) / max(scale.pixelsPerCm * scale.pixelsPerCm, 0.0001)
            let rawWidthCm = Double(max(1, footprint.maxCol - footprint.minCol + 1)) / scale.pixelsPerCm
            let rawDepthCm = Double(max(1, footprint.maxRow - footprint.minRow + 1)) / scale.pixelsPerCm
            let stabilized = stabilizeFootprint(
                label: seg.label,
                scaleSource: scale.source,
                widthCm: rawWidthCm,
                depthCm: rawDepthCm,
                areaCm2: rawAreaCm2
            )
            let areaCm2 = stabilized.areaCm2
            let widthCm = stabilized.widthCm
            let depthCm = stabilized.depthCm
            let lateralBoundCm = max(0.8, max(widthCm, depthCm))
            let priorBoundCm = min(prior.heightCm, lateralBoundCm)

            // Bowl mode applies only to the dominant food inside a detected rim.
            let bowl = (idx == primarySegmentIndex) ? bowlModel : nil

            // 1) Metric depth integral (currently disabled). 2) Real side-view
            // contour visual hull. 3) Legacy side height. 4) Bounded prior.
            let depthResult = depthGrid.flatMap { grid in
                monoDepth.foodVolume(
                    depth: grid, mask: seg.mask,
                    maskWidth: maskWidth, maskHeight: maskHeight,
                    fxMask: fxMask, fyMask: fyMask
                )
            }

            let heightCm: Double
            let volumeCm3: Double
            let rawVolumeCm3: Double
            let guardrailUpperCm3: Double?
            let guardrailApplied: Bool
            let scanMode: String
            var debugInfo: String? = nil
            let profileMatch = sideProfileMatch(
                for: seg,
                index: idx,
                in: sideProfiles,
                excluding: usedSideProfileIndices
            )
            // A bowl's side view is the container, so no side profile is used or
            // consumed for the bowl food.
            let profile = bowl == nil
                ? usableSideProfile(profileMatch?.profile, for: seg.label)
                : nil
            if profile == nil, bowl == nil {
                print("[MonocularEstimator] top-mask fallback food#\(idx) \(seg.label): sideProfile=none, pixels=\(seg.pixelCount), dominantPrimary=\(hasDominantPrimary)")
            }
            if profile != nil, let profileMatch { usedSideProfileIndices.insert(profileMatch.index) }
            if let bowl {
                // Food fills the rounded bowl cavity up to the visible surface.
                // The display mesh (makeEstimatedObject) is the volume source, so
                // this hemispherical-cap value is telemetry only.
                heightCm = bowl.innerDepthCm
                let rCm = 0.25 * (widthCm + depthCm)
                rawVolumeCm3 = (2.0 / 3.0) * Double.pi * rCm * rCm * heightCm
                volumeCm3 = rawVolumeCm3
                guardrailUpperCm3 = nil
                guardrailApplied = false
                scanMode = "monocular_bowl"
                debugInfo = String(
                    format: "bowl: depth=%.1fcm wall=%.1fcm r=%.1fcm vol=%.0fcm³",
                    heightCm, bowl.wallCm, rCm, volumeCm3)
                print("[MonocularEstimator] bowl food#\(idx) \(seg.label): foodW=\(String(format: "%.1f", widthCm))cm foodD=\(String(format: "%.1f", depthCm))cm innerDepth=\(String(format: "%.2f", heightCm))cm r=\(String(format: "%.2f", rCm))cm vol=\(String(format: "%.1f", volumeCm3))cm3")
            } else if let dr = depthResult {
                heightCm = dr.meanHeightCm
                volumeCm3 = max(6.0, dr.volumeCm3)
                rawVolumeCm3 = dr.volumeCm3
                guardrailUpperCm3 = nil
                guardrailApplied = false
                scanMode = "monocular_depth"
                debugInfo = String(
                    format: "depth: table=%.0fcm food=%.0fcm h=%.1fcm cov=%.0f%% vol=%.0fcm³",
                    dr.tableDepthM * 100, dr.foodDepthM * 100,
                    dr.meanHeightCm, dr.coverage * 100, dr.volumeCm3
                )
                print("[MonocularEstimator] depth food#\(idx) \(seg.label): meanH=\(String(format: "%.2f", dr.meanHeightCm))cm peakH=\(String(format: "%.2f", dr.peakHeightCm))cm cov=\(String(format: "%.2f", dr.coverage)) vol=\(String(format: "%.1f", dr.volumeCm3))cm3")
            } else if let profile {
                let topAxisCm = profile.topAxis == .columns ? widthCm : depthCm
                // Thickness comes straight from the measured side silhouette
                // (aspect ratio × top axis); only a 0.2 cm physical floor so a
                // flat food is never padded thicker than it truly is.
                let rawHeightCm = max(0.2, profile.aspectRatio * topAxisCm)
                heightCm = boundedHeightCm(
                    rawHeightCm: rawHeightCm,
                    label: seg.label,
                    priorBoundCm: priorBoundCm,
                    lateralBoundCm: lateralBoundCm
                )
                let shapeFactor = sideProfileShapeFactor(
                    profile,
                    fallback: prior.shapeFactor,
                    roundness: Double(transverseRoundnessStrength(for: seg.label))
                )
                rawVolumeCm3 = areaCm2 * heightCm * shapeFactor
                let bounded = boundedVolumeCm3(
                    rawVolumeCm3: rawVolumeCm3,
                    label: seg.label,
                    widthCm: widthCm,
                    depthCm: depthCm,
                    heightCm: heightCm,
                    shapeFactor: shapeFactor
                )
                volumeCm3 = bounded.volumeCm3
                guardrailUpperCm3 = bounded.upperCm3
                guardrailApplied = bounded.softened
                scanMode = "monocular_visual_hull"
                let meshMode = "exact_silhouette"
                debugInfo = String(
                    format: "visual_hull: side=exact mesh=%@ scale=%@ %.1fpx/cm axis=%@%@ h=%.1fcm fill=%.2f ar=%.2f vol=%.0fcm³",
                    meshMode,
                    scale.source,
                    scale.pixelsPerCm,
                    profile.topAxis.rawValue,
                    profile.reversed ? "R" : "",
                    heightCm,
                    profile.meanNormalizedHeight,
                    profile.aspectRatio,
                    volumeCm3
                )
                print("[MonocularEstimator] visual-hull food#\(idx) \(seg.label): sideLabel=\(profile.label), axis=\(profile.topAxis.rawValue), reversed=\(profile.reversed), mesh=\(meshMode), ar=\(String(format: "%.2f", profile.aspectRatio)), height=\(String(format: "%.2f", heightCm))cm, fill=\(String(format: "%.2f", profile.meanNormalizedHeight)), vol=\(String(format: "%.1f", volumeCm3))cm3")
            } else {
                // No side silhouette was captured, so the height was NOT
                // measured. Do NOT inflate it with a tall class prior — a flat
                // pile of nuts must never become a 5 cm tomato. Reconstruct from
                // the exact TOP silhouette as a thin, flat body: a small fraction
                // of the smaller footprint dimension, capped low, so an
                // unmeasured food stays flat instead of being puffed up.
                let flatUnknownHeightCm = min(2.2, max(0.4, min(widthCm, depthCm) * 0.32))
                let rawHeightCm = (idx == 0 ? measuredHeightCm : nil) ?? flatUnknownHeightCm
                heightCm = boundedHeightCm(
                    rawHeightCm: rawHeightCm,
                    label: seg.label,
                    priorBoundCm: priorBoundCm,
                    lateralBoundCm: lateralBoundCm
                )
                rawVolumeCm3 = areaCm2 * heightCm * prior.shapeFactor
                let bounded = boundedVolumeCm3(
                    rawVolumeCm3: rawVolumeCm3,
                    label: seg.label,
                    widthCm: widthCm,
                    depthCm: depthCm,
                    heightCm: heightCm,
                    shapeFactor: prior.shapeFactor
                )
                volumeCm3 = bounded.volumeCm3
                guardrailUpperCm3 = bounded.upperCm3
                guardrailApplied = bounded.softened
                scanMode = "monocular_scale"
                debugInfo = String(
                    format: "prism: scale=%@ %.1fpx/cm h=%.1fcm vol=%.0fcm³",
                    scale.source, scale.pixelsPerCm, heightCm, volumeCm3
                )
            }
            let id = "\(sanitised(seg.label))_\(idx)"
            // Depth-relief shaping (gated + fail-safe): a normalized per-pixel
            // top-surface relief from the metric depth, used ONLY to shape the
            // mesh top surface — the absolute height/scale stays from the
            // plate/side path. Skipped for bowls, low coverage, or flat foods.
            var reliefValues: [[Float]]? = nil
            var reliefWeight: Float = 0
            if MonocularVolumeEstimator.useDepthRelief, bowl == nil, let grid = depthGrid,
               let relief = monoDepth.reliefGrid(
                   depth: grid, mask: seg.mask,
                   maskWidth: maskWidth, maskHeight: maskHeight),
               relief.coverage >= 0.35 {
                reliefValues = relief.values
                // Weight rises with coverage, capped at 0.5 so the smooth base
                // shape is preserved and depth noise cannot dominate the surface.
                reliefWeight = Float(min(0.5, max(0.0, relief.coverage - 0.35)))
                print("[MonocularEstimator] depth-relief food#\(idx) \(seg.label): cov=\(String(format: "%.2f", relief.coverage)) peakH=\(String(format: "%.2f", relief.peakHeightCm))cm weight=\(String(format: "%.2f", reliefWeight))")
            }
            let estimatedObject = makeEstimatedObject(
                id: id,
                label: seg.label,
                instanceIndex: idx,
                mask: seg.mask,
                footprint: footprint,
                widthCm: widthCm,
                depthCm: depthCm,
                heightCm: heightCm,
                topFrame: topFrame,
                colorFrame: preprocessedRGB,
                sideColorFrame: sidePreprocessedRGB,
                maskWidth: maskWidth,
                maskHeight: maskHeight,
                sideProfile: profile,
                bowl: bowl,
                reliefGrid: reliefValues,
                reliefWeight: reliefWeight
            )
            let object = estimatedObject.object
            objects.append(object)

            // Hard contract: the user-visible mesh is the volume source. The
            // earlier prism/shape-factor value is retained only as diagnostic
            // telemetry so calibration logs can explain differences.
            let finalVolumeCm3 = estimatedObject.meshVolumeCm3
            let densityEstimate = estimatedDensityGPerCm3(for: seg.label)
            let weightEstimateG = finalVolumeCm3 * densityEstimate
            let guardrailText = guardrailUpperCm3.map {
                return String(
                    format: " guard=%@%.0fcm³",
                    guardrailApplied ? "soft>" : "≤",
                    $0
                )
            } ?? ""
            let sideApplied = profile != nil
            let fallbackUsed = bowl == nil && depthResult == nil && profile == nil
            let sideProfileSummary = profile.map { sideProfile in
                let heightSamples = [0.0, 0.25, 0.5, 0.75, 1.0]
                    .map { position in
                        String(format: "%.2f", sideProfile.sample(position))
                    }
                    .joined(separator: ",")
                return String(
                    format: " sideProfile=applied axis=%@%@ samples=%d heights=[%@] fill=%.2f ar=%.2f",
                    sideProfile.topAxis.rawValue,
                    sideProfile.reversed ? "R" : "",
                    sideProfile.normalizedHeights.count,
                    heightSamples,
                    sideProfile.meanNormalizedHeight,
                    sideProfile.aspectRatio
                )
            } ?? " sideProfile=none"
            let diagnosticInfo = String(
                format: "%@ | footprint raw=%.1fcm² %.1fx%.1fcm stable=%.1fcm² %.1fx%.1fcm height=%.2fcm rawVol=%.1fcm³ meshVol=%.1fcm³ hullCellVol=%.1fcm³ finalVol=%.1fcm³ density=%.2fg/cm³ weight=%.0fg fallback=%@ sideApplied=%@%@%@",
                debugInfo ?? scanMode,
                rawAreaCm2,
                rawWidthCm,
                rawDepthCm,
                areaCm2,
                widthCm,
                depthCm,
                heightCm,
                rawVolumeCm3,
                estimatedObject.meshVolumeCm3,
                estimatedObject.hullVoxelVolumeCm3,
                finalVolumeCm3,
                densityEstimate,
                weightEstimateG,
                fallbackUsed ? "true" : "false",
                sideApplied ? "true" : "false",
                sideProfileSummary,
                guardrailText
            )
            let confidence = confidenceForScale(scale, segmentConfidence: seg.confidence, sideFrame: sideFrame)

            let roundedVolume = round(finalVolumeCm3 * 10) / 10
            let roundedConfidence = round(confidence * 1000) / 1000
            // Component confidences so the diagnostics screen can explain WHY a
            // scan scored the way it did (scale vs segmentation vs silhouette).
            let scaleConfidence = scale.confidence
            let silhouetteConfidence = sideApplied ? Double(profile?.confidence ?? 0.0) : 0.0
            let lowConfidence = roundedConfidence < 0.62 || scale.source == "intrinsic_default"
            var row: [String: Any] = [
                "id": id,
                "label": seg.label,
                "detected_category": seg.label,
                "volume_cm3": roundedVolume,
                "voxel_count": object.voxelCount,
                "pixel_count": seg.pixelCount,
                "confidence": roundedConfidence,
                "confidence_score": roundedConfidence,
                "scale_confidence": round(scaleConfidence * 1000) / 1000,
                "segmentation_confidence": round(Double(seg.confidence) * 1000) / 1000,
                "silhouette_confidence": round(silhouetteConfidence * 1000) / 1000,
                "low_confidence": lowConfidence,
                "silhouette_height_px": round(heightCm * scale.pixelsPerCm * 10) / 10,
                "pixels_per_cm": round(scale.pixelsPerCm * 100) / 100,
                "density_source": "label_prior",
                "frames_used": sideFrame == nil ? 1 : 2,
                "scan_mode": scanMode,
                "scale_source": scale.source,
                "scale_fallback_reason": scale.fallbackReason ?? "none",
                "overall_scan_confidence": roundedConfidence,
                "estimated": true,
                "footprint_area_cm2": round(areaCm2 * 10) / 10,
                "width_cm": round(widthCm * 10) / 10,
                "depth_cm": round(depthCm * 10) / 10,
                "height_cm": round(heightCm * 10) / 10,
                "raw_volume_cm3": round(rawVolumeCm3 * 10) / 10,
                "density_g_cm3": round(densityEstimate * 100) / 100,
                "weight_g": round(weightEstimateG),
                "volume_guardrail_applied": guardrailApplied,
                "side_view_applied": sideApplied,
                "fallback_used": fallbackUsed,
                "temporal_smoothing_applied": false,
                "temporal_samples": 1,
                "pre_smoothing_volume_cm3": round(volumeCm3 * 10) / 10,
                "mesh_volume_cm3": round(estimatedObject.meshVolumeCm3 * 10) / 10,
                "hull_cell_volume_cm3": round(estimatedObject.hullVoxelVolumeCm3 * 10) / 10,
                "surface_extraction_mode": estimatedObject.surfaceExtractionMode,
                "top_silhouette_snap_vertices": estimatedObject.topSilhouetteSnapVertices,
                "top_silhouette_edge_snap_vertices": estimatedObject.topSilhouetteEdgeSnapVertices,
                "side_profile_samples": profile?.normalizedHeights.count ?? 0,
                "volume_source": "display_mesh",
            ]
            if let guardrailUpperCm3 {
                row["guardrail_upper_cm3"] = round(guardrailUpperCm3 * 10) / 10
            }
            row["mesh_roundness_applied"] = sideApplied && transverseRoundnessStrength(for: seg.label) > 0
            row["debug"] = diagnosticInfo
            // [EVAL] one line per food for known-weight calibration (#3).
            print("[EVAL] label=\(seg.label) conf=\(String(format: "%.2f", roundedConfidence)) footprint_cm2=\(String(format: "%.1f", areaCm2)) silhouette_px=\(String(format: "%.1f", heightCm * scale.pixelsPerCm)) height_cm=\(String(format: "%.2f", heightCm)) raw_volume_cm3=\(String(format: "%.1f", rawVolumeCm3)) final_volume_cm3=\(String(format: "%.1f", roundedVolume)) density_g_cm3=\(String(format: "%.2f", densityEstimate)) density_source=label_prior weight_g=\(String(format: "%.0f", weightEstimateG)) mode=\(scanMode) scale=\(scale.source) px/cm=\(String(format: "%.2f", scale.pixelsPerCm)) side_applied=\(sideApplied) fallback=\(fallbackUsed) guardrail=\(guardrailApplied ? "soft" : "none")")
            payload.append(row)
            metadata.append(row)
        }

        guard !objects.isEmpty, !payload.isEmpty else {
            print("[MonocularEstimator] no exportable objects: segments=\(segments.count), payload=\(payload.count), sideProfiles=\(sideProfiles.count), totalTopPixels=\(totalSegmentPixels)")
            throw EstimateError.noObjects
        }

        let baseName = "scan3d_camera_\(Int(Date().timeIntervalSince1970 * 1000))"
        // Paste the real photos onto the mesh. With a side capture the exporter
        // bakes a TOP+SIDE atlas; the per-object mesh is seam-split (unwelded per
        // triangle, each triangle assigned wholly to the top or side tile — see
        // makeEstimatedObject) so no triangle straddles the two photos and there
        // is no doubled/flickering texture. Without a side capture the top photo
        // is baked alone and every vertex maps into it.
        guard let url = exporter.export(
            objects: objects,
            baseName: baseName,
            textureSource: preprocessedRGB,
            sideTextureSource: sidePreprocessedRGB
        ),
              FileManager.default.fileExists(atPath: url.path) else {
            print("[MonocularEstimator] export failed: objects=\(objects.count), baseName=\(baseName)")
            throw EstimateError.exportFailed
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            throw EstimateError.jsonFailed
        }

        print("[MonocularEstimator] scale=\(scale.source), px/cm=\(String(format: "%.2f", scale.pixelsPerCm)), objects=\(objects.count), path=\(url.path)")
        return Result(json: json, modelPath: url.path, objects: metadata)
    }

    // MARK: - Scale

    private struct ScaleEstimate {
        let pixelsPerCm: Double
        let source: String
        let confidence: Double
        let fallbackReason: String?
    }

    private func estimateScale(
        topFrame: FrameCaptureService.CapturedFrame,
        maskWidth: Int,
        maskHeight: Int,
        tableDistanceCm: Double? = nil
    ) -> ScaleEstimate {
        let imageWidth = CVPixelBufferGetWidth(topFrame.pixelBuffer)
        // The segmentation mask is a square resize of this crop. A credible
        // detected plate provides an in-frame metric reference, whereas the
        // guided camera-distance fallback is only an estimate.
        let plate = plateDetector.detect(in: topFrame.pixelBuffer)
        let cropWidthPx = max(1.0, Double(plate.rect.width) * Double(imageWidth))
        let fx = Double(topFrame.cameraIntrinsics.columns.0.x)

        let plateDiameterPxPerCm: Double? = {
            guard plate.detected, plate.diameterPx > 0 else { return nil }
            let diameterInMask = Double(plate.diameterPx) * Double(maskWidth) / cropWidthPx
            let pxPerCm = diameterInMask / Double(PlateDetector.defaultDiameterCm)
            guard pxPerCm.isFinite, pxPerCm >= 4.0, pxPerCm <= 80.0 else { return nil }
            return pxPerCm
        }()

        // Deterministic single-source hierarchy — no blending, no weighted
        // fusion. Exactly one source is selected per scan:
        //   PRIMARY  : detected plate diameter in the captured image
        //   SECONDARY: ARKit tracked plane distance
        //   FALLBACK : camera-intrinsic estimate at the guided hold distance
        //   LAST     : default-plate geometry only when intrinsics are missing
        //
        // The intrinsic-guided px/cm is computed up front and doubles as a
        // plausibility yardstick for the ARKit plane below.
        let intrinsicGuidedPxPerCm: Double? = {
            guard fx > 1 else { return nil }
            let cmPerImagePx = guidedDistanceCm / fx
            let cmPerMaskPx = cmPerImagePx * cropWidthPx / Double(maskWidth)
            return max(1.0 / max(cmPerMaskPx, 0.0001), 1.0)
        }()

        if let platePxPerCm = plateDiameterPxPerCm {
            if let reference = intrinsicGuidedPxPerCm {
                let ratio = platePxPerCm / reference
                if ratio >= 0.55, ratio <= 1.9 {
                    logScaleValidation(chosenPxPerCm: platePxPerCm, plateDetected: true,
                                       maskWidth: maskWidth, maskHeight: maskHeight,
                                       source: "plate_diameter")
                    return ScaleEstimate(
                        pixelsPerCm: platePxPerCm,
                        source: "plate_diameter",
                        confidence: 0.86,
                        fallbackReason: nil)
                }
                print("[MonocularEstimator] rejected plate_diameter scale \(String(format: "%.1f", platePxPerCm))px/cm vs intrinsic \(String(format: "%.1f", reference))px/cm (ratio \(String(format: "%.2f", ratio)))")
            } else {
                logScaleValidation(chosenPxPerCm: platePxPerCm, plateDetected: true,
                                   maskWidth: maskWidth, maskHeight: maskHeight,
                                   source: "plate_diameter")
                return ScaleEstimate(
                    pixelsPerCm: platePxPerCm,
                    source: "plate_diameter",
                    confidence: 0.80,
                    fallbackReason: nil)
            }
        }

        if let tableDistanceCm, fx > 1, tableDistanceCm > 1.0 {
            let cmPerImagePx = tableDistanceCm / fx
            let cmPerMaskPx = cmPerImagePx * cropWidthPx / Double(maskWidth)
            let pxPerCm = max(1.0 / max(cmPerMaskPx, 0.0001), 1.0)

            // Plausibility cross-check. At close macro hold range a tracked
            // plane can lock onto the floor (or a far surface) and report a
            // distance several times too large. Because px/cm scales linearly
            // with distance and volume with its cube, a 4x distance error cubes
            // into an ~80x volume error (the "3 kg tomato" bug). If the ARKit
            // px/cm disagrees with the intrinsic-guided reference by more than
            // ~1.8x in either direction, reject it and use the bounded
            // intrinsic scale instead.
            if let reference = intrinsicGuidedPxPerCm {
                let ratio = pxPerCm / reference
                if ratio < 0.55 || ratio > 1.9 {
                    let pxStr = String(format: "%.1f", pxPerCm)
                    let refStr = String(format: "%.1f", reference)
                    let ratioStr = String(format: "%.2f", ratio)
                    print("[MonocularEstimator] rejected arkit_plane scale \(pxStr)px/cm vs intrinsic \(refStr)px/cm (ratio \(ratioStr)) — using intrinsic_guided")
                    logScaleValidation(chosenPxPerCm: reference, plateDetected: plate.detected,
                                       maskWidth: maskWidth, maskHeight: maskHeight, source: "intrinsic_guided")
                    return ScaleEstimate(
                        pixelsPerCm: reference,
                        source: "intrinsic_guided",
                        confidence: 0.58,
                        fallbackReason: "arkit_plane_implausible")
                }
            }

            logScaleValidation(chosenPxPerCm: pxPerCm, plateDetected: plate.detected,
                               maskWidth: maskWidth, maskHeight: maskHeight, source: "arkit_plane")
            return ScaleEstimate(
                pixelsPerCm: pxPerCm,
                source: "arkit_plane",
                confidence: 0.82,
                fallbackReason: nil)
        }

        if let pxPerCm = intrinsicGuidedPxPerCm {
            logScaleValidation(chosenPxPerCm: pxPerCm, plateDetected: plate.detected,
                               maskWidth: maskWidth, maskHeight: maskHeight, source: "intrinsic_guided")
            return ScaleEstimate(
                pixelsPerCm: pxPerCm,
                source: "intrinsic_guided",
                confidence: 0.60,
                fallbackReason: tableDistanceCm == nil ? "no_arkit_plane" : "arkit_plane_below_threshold")
        }

        // Degenerate last resort (camera intrinsics unavailable — effectively
        // never on a real ARFrame). Uses default-plate geometry purely so the
        // mesh can still be exported; flagged as the lowest confidence source.
        return ScaleEstimate(
            pixelsPerCm: max(Double(min(maskWidth, maskHeight)) / Double(PlateDetector.defaultDiameterCm), 1.0),
            source: "intrinsic_default",
            confidence: 0.50,
            fallbackReason: "no_camera_intrinsics")
    }

    private func confidenceForScale(
        _ scale: ScaleEstimate,
        segmentConfidence: Float,
        sideFrame: FrameCaptureService.CapturedFrame?
    ) -> Double {
        // Deterministic blend of the per-source scale confidence with the
        // segmentation confidence. The floor is low enough that genuinely poor
        // captures surface as low confidence (the consistency engine flags
        // them) instead of being clamped into the "acceptable" band.
        let sideBonus = sideFrame == nil ? 0.0 : 0.04
        return min(0.90, max(0.40, scale.confidence * 0.6 + Double(segmentConfidence) * 0.4 + sideBonus))
    }

    // MARK: - Food priors

    private func priors(for label: String) -> (heightCm: Double, shapeFactor: Double) {
        let l = label.lowercased()
        if l.contains("rice") || l.contains("pasta") || l.contains("noodle") { return (3.2, 0.68) }
        if l.contains("salad") || l.contains("vegetable") { return (3.5, 0.48) }
        // Bananas are almost always scanned as a piled bunch, which stacks far
        // taller than a single plated fruit. A flat lateral-bound clamp in
        // `estimate(...)` still trims a single banana lying flat, but the bunch
        // keeps a realistic height instead of collapsing to the 3 cm default.
        if l.contains("banana") { return (6.5, 0.88) }
        // Nuts / seeds are scanned as a low, loose pile — a thin flat layer, not
        // a whole-fruit height. Keep them flat so a handful of almonds is never
        // reconstructed with a tall round-produce prior.
        if l.contains("almond") || l.contains("cashew") || l.contains("walnut") ||
           l.contains("peanut") || l.contains("pecan") || l.contains("pistachio") ||
           l.contains("hazelnut") || l.contains("nuts") { return (1.5, 0.62) }
        if l.contains("apple") || l.contains("orange") || l.contains("egg") ||
           l.contains("tomato") || l.contains("onion") || l.contains("potato") ||
           l.contains("peach") || l.contains("plum") { return (5.0, 0.58) }
        if l.contains("bread") || l.contains("toast") || l.contains("pizza") { return (2.2, 0.82) }
        if l.contains("chicken") || l.contains("beef") || l.contains("steak") || l.contains("fish") { return (2.8, 0.78) }
        if l.contains("soup") || l.contains("sauce") || l.contains("yogurt") { return (1.8, 0.90) }
        return (3.0, 0.70)
    }

    private func sideProfileMatch(
        for segment: SegmentationService.SegmentedObject,
        index: Int,
        in profiles: [SideProfile],
        excluding used: Set<Int>
    ) -> (index: Int, profile: SideProfile)? {
        guard !profiles.isEmpty else { return nil }
        let label = normalisedLabel(segment.label)
        if let exactLabel = profiles.enumerated().first(where: {
            !used.contains($0.offset) && normalisedLabel($0.element.label) == label
        }) {
            return (exactLabel.offset, exactLabel.element)
        }
        if let exactClass = profiles.enumerated().first(where: {
            !used.contains($0.offset) && $0.element.classIndex == segment.classIndex
        }) {
            // Class ids are helpful, but on dense mixed plates a broad class or
            // view-dependent label can assign one fruit's side contour to a
            // neighbouring fruit. Only trust class-only matching when there is
            // a single side candidate, or when the text label agrees too.
            if profiles.count == 1 || normalisedLabel(exactClass.element.label) == label {
                return (exactClass.offset, exactClass.element)
            }
        }
        // Single-food scans are the common calibration/testing case. If the top
        // object is dominant, a side label mismatch should not discard useful
        // silhouette geometry; labels are less stable than masks across view.
          if index == 0,
              profiles.count == 1,
           let firstUnused = profiles.enumerated().first(where: { !used.contains($0.offset) }) {
            return (firstUnused.offset, firstUnused.element)
        }
        return nil
    }

    private func boundedHeightCm(
        rawHeightCm: Double,
        label: String,
        priorBoundCm: Double,
        lateralBoundCm: Double
    ) -> Double {
        // Hard-force the measured silhouette: only a 0.2 cm physical floor, never
        // a prior-based one, so a genuinely thin/flat food keeps its true
        // thickness instead of being inflated up toward a class prior. The upper
        // cap still guards against a foreshortened side view reading too tall.
        let lower = 0.2
        let upper = maxVisualHeightCm(
            label: label,
            priorBoundCm: priorBoundCm,
            lateralBoundCm: lateralBoundCm
        )
        return min(upper, max(lower, rawHeightCm))
    }

    private func maxVisualHeightCm(
        label: String,
        priorBoundCm: Double,
        lateralBoundCm: Double
    ) -> Double {
        let l = label.lowercased()
        if l.contains("soup") || l.contains("sauce") || l.contains("yogurt") {
            return min(6.0, max(1.0, min(lateralBoundCm * 0.45, priorBoundCm * 1.4)))
        }
        // Flat baked goods are physically short no matter how wide the footprint
        // reads. A slice of bread, a tortilla or a pizza can never be tall, so a
        // foreshortened side view (the #1 cause of a 4x-too-tall slice) is capped
        // hard here. This is a physical ceiling, not the primary height driver:
        // a clean side capture still measures the true 1-3 cm within this bound.
        if l.contains("bread") || l.contains("toast") || l.contains("pizza") ||
            l.contains("cracker") || l.contains("tortilla") || l.contains("pancake") ||
            l.contains("waffle") || l.contains("flatbread") || l.contains("cookie") ||
            l.contains("biscuit") || l.contains("pita") || l.contains("naan") {
            return 3.5
        }
        if l.contains("rice") || l.contains("pasta") || l.contains("noodle") || l.contains("salad") {
            return min(11.0, max(priorBoundCm * 1.3, lateralBoundCm * 0.7))
        }
        if l.contains("banana") {
            return min(14.0, max(priorBoundCm * 1.2, lateralBoundCm * 0.85))
        }
        if l.contains("tomato") {
            return min(7.0, max(3.8, lateralBoundCm * 0.78))
        }
        // Generic: a plated food is almost never taller than it is wide. Capping
        // the height near the lateral footprint (not 1.05x of it) blocks absurd
        // monocular spikes while leaving real domes and round produce intact.
        let base = min(14.0, max(1.0, lateralBoundCm * 0.9))
        if let envelope = physicalEnvelope(for: label) {
            return min(base, envelope.maxHeightCm)
        }
        return base
    }

    private func sideProfileShapeFactor(
        _ profile: SideProfile,
        fallback: Double,
        roundness: Double = 0
    ) -> Double {
        // Treat the side silhouette as the primary geometric evidence. The
        // prior only provides a light stabiliser after `usableSideProfile(...)`
        // has accepted the mask, so the side view visibly changes both volume
        // and mesh shape instead of being blended into a generic dome.
        //
        // Round produce (tomato/apple/orange/…) is volumetrically FULLER than a
        // flat mound of the same silhouette: with a square-on side view the
        // measured height is true, so a sphere-ish fill gain (0.88) would now
        // under-read the volume. Scale the gain up toward ~0.97 for round foods
        // so a true 7.5cm / 5.5cm tomato lands near its real ~190cm³ instead of
        // ~160cm³. Flat foods keep the conservative 0.88 gain.
        let gain = 0.88 + 0.09 * max(0.0, min(1.0, roundness))
        let silhouetteFactor = min(0.95, max(0.38, profile.meanNormalizedHeight * gain))
        return min(0.95, max(0.38, fallback * 0.15 + silhouetteFactor * 0.85))
    }

    private func usableSideProfile(_ profile: SideProfile?, for label: String) -> SideProfile? {
        guard let profile else { return nil }
        // The side view is powerful, but a bad side mask is also the fastest
        // way to explode volume. Keep only profiles that look like a real,
        // reasonably filled object silhouette.
        var rejectionReasons: [String] = []
        if profile.pixelCount < 600 { rejectionReasons.append("px<600") }
        if profile.confidence < 0.20 { rejectionReasons.append("conf<0.20") }
        if profile.coverage < 0.0015 { rejectionReasons.append("cov<0.0015") }
        if profile.aspectRatio < 0.10 { rejectionReasons.append("ar<0.10") }
        if profile.aspectRatio > 2.5 { rejectionReasons.append("ar>2.5") }
        if profile.meanNormalizedHeight < 0.14 { rejectionReasons.append("fill<0.14") }
        if profile.meanNormalizedHeight > 0.98 { rejectionReasons.append("fill>0.98") }
        guard rejectionReasons.isEmpty else {
            print("[MonocularEstimator] side-profile rejected label=\(profile.label) reasons=\(rejectionReasons.joined(separator: ",")) px=\(profile.pixelCount) conf=\(String(format: "%.2f", profile.confidence)) cov=\(String(format: "%.3f", profile.coverage)) ar=\(String(format: "%.2f", profile.aspectRatio)) fill=\(String(format: "%.2f", profile.meanNormalizedHeight))")
            return nil
        }

        if let envelope = physicalEnvelope(for: label),
           profile.aspectRatio * envelope.maxLateralCm > envelope.maxHeightCm * 1.35 {
            print("[MonocularEstimator] side-profile rejected as too-tall for \(label): ar=\(String(format: "%.2f", profile.aspectRatio))")
            return nil
        }
        return profile
    }

    struct DualSilhouetteCheck {
        let valid: Bool
        let topValid: Bool
        let sideValid: Bool
        let alignmentScore: Double
        let segConfTop: Float
        let segConfSide: Float
        let reason: String
    }

    /// Dual-silhouette gate. A monocular reconstruction is only accepted when a
    /// valid TOP silhouette AND a valid SIDE silhouette both exist for the
    /// primary (largest) food and their alignment/consistency clears threshold.
    /// There is NO single-silhouette fallback: when this returns valid == false
    /// the caller retries the pipeline or surfaces a failure to the user instead
    /// of exporting a degraded single-view shape.
    func validateDualSilhouette(
        segments: [SegmentationService.SegmentedObject],
        sideProfiles: [SideProfile]
    ) -> DualSilhouetteCheck {
        let minTopPixels = 650
        let alignmentThreshold = 0.35
        let confidenceThreshold: Float = 0.30

        // Primary = the largest segment (what the user frames and evaluates).
        guard let primaryIdx = segments.indices.max(by: {
            segments[$0].pixelCount < segments[$1].pixelCount
        }) else {
            return DualSilhouetteCheck(valid: false, topValid: false, sideValid: false,
                alignmentScore: 0, segConfTop: 0, segConfSide: 0, reason: "no_top_silhouette")
        }
        let primary = segments[primaryIdx]
        let segConfTop = primary.confidence
        let topValid = primary.pixelCount >= minTopPixels && segConfTop >= confidenceThreshold
        if !topValid {
            return DualSilhouetteCheck(valid: false, topValid: false, sideValid: false,
                alignmentScore: 0, segConfTop: segConfTop, segConfSide: 0,
                reason: "top_silhouette_invalid")
        }

        // Match + usability-filter the side profile for the primary using the
        // SAME gates the mesh uses, so validation and reconstruction agree.
        let match = sideProfileMatch(for: primary, index: primaryIdx, in: sideProfiles, excluding: [])
        guard let profile = usableSideProfile(match?.profile, for: primary.label) else {
            return DualSilhouetteCheck(valid: false, topValid: true, sideValid: false,
                alignmentScore: 0, segConfTop: segConfTop,
                segConfSide: match?.profile.confidence ?? 0,
                reason: sideProfiles.isEmpty ? "missing_side_silhouette" : "side_silhouette_invalid")
        }
        let segConfSide = profile.confidence
        // Alignment/consistency score blends side confidence with how much real
        // side-mask substance backs it (a thin/sparse side mask is unreliable).
        let alignmentScore = min(1.0,
            Double(profile.confidence) * 0.7 +
            0.3 * min(1.0, Double(profile.pixelCount) / 4000.0))
        if alignmentScore < alignmentThreshold {
            return DualSilhouetteCheck(valid: false, topValid: true, sideValid: true,
                alignmentScore: alignmentScore, segConfTop: segConfTop, segConfSide: segConfSide,
                reason: "alignment_below_threshold")
        }
        return DualSilhouetteCheck(valid: true, topValid: true, sideValid: true,
            alignmentScore: alignmentScore, segConfTop: segConfTop, segConfSide: segConfSide,
            reason: "ok")
    }

    /// Plate-vs-chosen scale agreement, logged for debugging only. Plate scale
    /// NEVER influences the returned `ScaleEstimate`; this just records how far
    /// a (noisy) plate-diameter assumption would have diverged from the
    /// deterministic source actually used.
    private func logScaleValidation(chosenPxPerCm: Double, plateDetected: Bool, maskWidth: Int, maskHeight: Int, source: String) {
        guard plateDetected else { return }
        let platePxPerCm = Double(min(maskWidth, maskHeight)) / Double(PlateDetector.defaultDiameterCm)
        let ratio = platePxPerCm / max(chosenPxPerCm, 0.0001)
        print("[ScaleValidation] source=\(source) chosen=\(String(format: "%.2f", chosenPxPerCm))px/cm plate=\(String(format: "%.2f", platePxPerCm))px/cm ratio=\(String(format: "%.2f", ratio)) (plate used for validation only, never scaling)")
    }

    private func stabilizeFootprint(
        label: String,
        scaleSource: String,
        widthCm: Double,
        depthCm: Double,
        areaCm2: Double
    ) -> (widthCm: Double, depthCm: Double, areaCm2: Double) {
        guard let envelope = physicalEnvelope(for: label) else {
            return (widthCm, depthCm, areaCm2)
        }

        let lateral = max(widthCm, depthCm)
        guard lateral > envelope.maxLateralCm else {
            return (widthCm, depthCm, areaCm2)
        }

        let factor = envelope.maxLateralCm / max(lateral, 0.0001)
        // How far past the physical envelope is this footprint? A tomato that
        // measures 34 cm across (envelope 10 cm) is physically impossible — no
        // legitimately huge specimen exists — so a gross overshoot always gets
        // the full clamp regardless of scale source. Only a mild overshoot (a
        // genuinely large-but-plausible specimen) keeps the gentle ARKit
        // softening so we don't shrink real produce.
        let overshoot = lateral / envelope.maxLateralCm
        let softenedFactor: Double
        if overshoot > 1.6 {
            softenedFactor = factor
        } else {
            switch scaleSource {
            case "arkit_plane":
                // ARKit plane distance is metrically stable; trim only truly
                // implausible masks while preserving unusually large foods.
                softenedFactor = max(factor, 0.78)
            default:
                // AR plane/fallback scale at macro distances is noisier. Apply
                // the full physical clamp so a bad distance estimate cannot
                // cube into a kilogram tomato.
                softenedFactor = factor
            }
        }
        let clampedWidth = max(0.8, widthCm * softenedFactor)
        let clampedDepth = max(0.8, depthCm * softenedFactor)
        let clampedArea = max(0.5, areaCm2 * softenedFactor * softenedFactor)
        print("[MonocularEstimator] footprint stabilized \(label): \(String(format: "%.1f", widthCm))x\(String(format: "%.1f", depthCm))cm -> \(String(format: "%.1f", clampedWidth))x\(String(format: "%.1f", clampedDepth))cm source=\(scaleSource)")
        return (clampedWidth, clampedDepth, clampedArea)
    }

    private func boundedVolumeCm3(
        rawVolumeCm3: Double,
        label: String,
        widthCm: Double,
        depthCm: Double,
        heightCm: Double,
        shapeFactor: Double
    ) -> (volumeCm3: Double, upperCm3: Double, softened: Bool) {
        var upper = widthCm * depthCm * max(heightCm, 0.8) * min(0.92, max(0.35, shapeFactor * 1.18))
        if let envelope = physicalEnvelope(for: label) {
            upper = min(upper, envelope.maxVolumeCm3)
        }
        let safeUpper = max(6.0, upper)
        let floorVolume = max(6.0, rawVolumeCm3)
        guard floorVolume > safeUpper else {
            return (floorVolume, safeUpper, false)
        }

        // Do not snap to the same cap for every oversized scan. Compress the
        // excess logarithmically so impossible monocular outliers are still
        // damped, while different top/side masks produce different final
        // volumes for diagnostics and calibration.
        let ratio = floorVolume / safeUpper
        let softened = safeUpper * (1.0 + 0.10 * log(ratio))
        print("[MonocularEstimator] volume softened \(label): raw=\(String(format: "%.0f", rawVolumeCm3))cm3 upper=\(String(format: "%.0f", safeUpper))cm3 -> \(String(format: "%.0f", softened))cm3")
        return (max(6.0, softened), safeUpper, true)
    }

    private func estimatedDensityGPerCm3(for label: String) -> Double {
        let l = label.lowercased()
        if l.contains("banana") { return 0.875 }
        if l.contains("tomato") { return 1.125 }
        if l.contains("apple") || l.contains("orange") || l.contains("peach") || l.contains("plum") { return 0.90 }
        if l.contains("onion") || l.contains("potato") { return 0.975 }
        if l.contains("egg") { return 1.03 }
        if l.contains("rice") || l.contains("pasta") || l.contains("noodle") { return 0.95 }
        if l.contains("bread") || l.contains("toast") { return 0.30 }
        if l.contains("chicken") || l.contains("beef") || l.contains("steak") || l.contains("fish") { return 1.02 }
        if l.contains("salad") || l.contains("vegetable") { return 0.55 }
        return 0.90
    }

    private func transverseRoundnessStrength(for label: String) -> Float {
        let l = label.lowercased()
        if l.contains("tomato") { return 0.96 }
        if l.contains("apple") || l.contains("orange") ||
            l.contains("peach") || l.contains("plum") { return 0.92 }
        if l.contains("egg") { return 0.88 }
        if l.contains("onion") || l.contains("potato") { return 0.72 }
        return 0
    }

    private func transverseSideTaperStrength(for label: String) -> Float {
        let l = label.lowercased()
        if l.contains("tomato") { return 0.42 }
        if l.contains("apple") || l.contains("orange") ||
            l.contains("peach") || l.contains("plum") { return 0.50 }
        if l.contains("egg") { return 0.60 }
        if l.contains("onion") || l.contains("potato") { return 0.45 }
        return 0
    }

    private func roundSideFillTarget(for label: String) -> Float {
        let l = label.lowercased()
        if l.contains("tomato") { return 0.80 }
        if l.contains("apple") || l.contains("orange") ||
            l.contains("peach") || l.contains("plum") { return 0.78 }
        if l.contains("egg") { return 0.74 }
        if l.contains("onion") || l.contains("potato") { return 0.72 }
        return 0
    }

    private func physicalEnvelope(for label: String) -> PhysicalEnvelope? {
        let l = label.lowercased()
        // Flat baked goods: bounded hard in height so a foreshortened or
        // plate-bleeding side mask can never inflate the object vertically.
        if l.contains("bread") || l.contains("toast") || l.contains("pizza") ||
            l.contains("tortilla") || l.contains("pancake") || l.contains("waffle") ||
            l.contains("cracker") || l.contains("flatbread") || l.contains("pita") ||
            l.contains("naan") || l.contains("cookie") || l.contains("biscuit") {
            return PhysicalEnvelope(maxLateralCm: 30.0, maxHeightCm: 3.5, maxVolumeCm3: 2000.0)
        }
        if l.contains("tomato") { return PhysicalEnvelope(maxLateralCm: 10.0, maxHeightCm: 7.0, maxVolumeCm3: 360.0) }
        if l.contains("apple") || l.contains("orange") || l.contains("peach") || l.contains("plum") {
            return PhysicalEnvelope(maxLateralCm: 11.0, maxHeightCm: 10.0, maxVolumeCm3: 620.0)
        }
        if l.contains("onion") || l.contains("potato") {
            return PhysicalEnvelope(maxLateralCm: 13.0, maxHeightCm: 10.0, maxVolumeCm3: 900.0)
        }
        if l.contains("egg") { return PhysicalEnvelope(maxLateralCm: 7.5, maxHeightCm: 6.0, maxVolumeCm3: 110.0) }
        if l.contains("banana") { return PhysicalEnvelope(maxLateralCm: 26.0, maxHeightCm: 14.0, maxVolumeCm3: 950.0) }
        return nil
    }

    private func normalisedLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Mask geometry

    private typealias Footprint = (
        minRow: Int,
        maxRow: Int,
        minCol: Int,
        maxCol: Int,
        centroid: (row: Double, col: Double)
    )

    private func footprintStats(
        _ mask: [[UInt8]],
        maskWidth: Int,
        maskHeight: Int
    ) -> Footprint? {
        var minRow = maskHeight
        var maxRow = 0
        var minCol = maskWidth
        var maxCol = 0
        var sumRow = 0.0
        var sumCol = 0.0
        var count = 0.0

        for r in 0..<maskHeight {
            for c in 0..<maskWidth where mask[r][c] == 1 {
                minRow = min(minRow, r)
                maxRow = max(maxRow, r)
                minCol = min(minCol, c)
                maxCol = max(maxCol, c)
                sumRow += Double(r)
                sumCol += Double(c)
                count += 1
            }
        }

        guard count > 0 else { return nil }
        return (minRow, maxRow, minCol, maxCol, (sumRow / count, sumCol / count))
    }

    // MARK: – Bowl detection (occluded container)

    /// True when the scene is a food in a bowl (see `detectBowl`). Used by the
    /// LiDAR path so a bowl scan routes through the SAME rounded-cavity
    /// reconstruction as the non-LiDAR path and both look identical.
    func isBowlScene(
        segments: [SegmentationService.SegmentedObject],
        topFrame: FrameCaptureService.CapturedFrame,
        maskWidth: Int,
        maskHeight: Int
    ) -> Bool {
        let plate = plateDetector.detect(in: topFrame.pixelBuffer)
        let scale = estimateScale(
            topFrame: topFrame, maskWidth: maskWidth, maskHeight: maskHeight)
        let primaryIndex = segments.indices.max(by: {
            segments[$0].pixelCount < segments[$1].pixelCount
        })
        return detectBowl(
            segments: segments, primaryIndex: primaryIndex, plate: plate,
            scale: scale, sideProfiles: [], maskWidth: maskWidth, maskHeight: maskHeight) != nil
    }

    /// Detect a food served in a bowl OR a deep plate. There is no container
    /// segmentation class, so this is a conservative heuristic: a bowl-typical
    /// DOMINANT food, inside a detected circular rim, that is a substantial
    /// central portion (it need NOT fill the whole container). The side view of
    /// such a scene is the opaque container, so no side profile is used; the
    /// hidden lower food is reconstructed as a rounded cavity sized to the FOOD's
    /// own top-view width/depth — never the container rim — with a common wall
    /// thickness removed.
    private func detectBowl(
        segments: [SegmentationService.SegmentedObject],
        primaryIndex: Int?,
        plate: PlateDetector.PlateResult,
        scale: ScaleEstimate,
        sideProfiles: [SideProfile],
        maskWidth: Int,
        maskHeight: Int
    ) -> BowlModel? {
        guard plate.detected, let pIdx = primaryIndex, pIdx < segments.count else { return nil }
        let primary = segments[pIdx]
        let label = primary.label.lowercased()
        guard Self.bowlFoodKeywords.contains(where: { label.contains($0) }) else { return nil }
        // Bowls hold one dominant dish.
        let total = segments.reduce(0) { $0 + $1.pixelCount }
        guard total > 0, Double(primary.pixelCount) / Double(total) >= 0.6 else { return nil }
        // If the side view shows a clearly LOW, flat silhouette, the food is on a
        // flat plate, not in a bowl — never fabricate a deep cavity for it.
        for sp in sideProfiles {
            if let usable = usableSideProfile(sp, for: primary.label), usable.aspectRatio < 0.40 {
                return nil
            }
        }
        guard let fp = footprintStats(primary.mask, maskWidth: maskWidth, maskHeight: maskHeight) else { return nil }
        let bboxW = Double(fp.maxCol - fp.minCol + 1)
        let bboxH = Double(fp.maxRow - fp.minRow + 1)
        // The food need NOT fill the whole container (so a partly-filled bowl or
        // a deep plate still qualifies); it just has to be a substantial central
        // portion, not a small garnish.
        guard bboxW / Double(maskWidth) >= 0.30, bboxH / Double(maskHeight) >= 0.30 else { return nil }
        guard scale.pixelsPerCm > 0.01 else { return nil }
        // WIDTH & DEPTH are the FOOD's own top-view footprint, never the bowl /
        // plate rim, so a food smaller than its container is reconstructed at its
        // true size.
        let widthCm = bboxW / scale.pixelsPerCm
        let depthCm = bboxH / scale.pixelsPerCm
        let radiusCm = 0.25 * (widthCm + depthCm)
        // Reject implausible sizes so a bad scale can't fabricate a huge cavity.
        guard radiusCm >= 3.0, radiusCm <= 16.0 else { return nil }
        let wallCm = 0.4
        // The side is occluded, so fill depth is inferred, not measured. A
        // rounded cavity cannot be deeper than its narrower half-extent, and a
        // deep plate is wide but shallow, so tie the depth to the SMALLER
        // dimension and cap it. Remove the base wall thickness.
        let geomMaxDepthCm = 0.5 * min(widthCm, depthCm)
        let innerDepthCm = min(6.5, max(1.5, min(radiusCm, geomMaxDepthCm) * 0.65 - wallCm))
        return BowlModel(innerDepthCm: innerDepthCm, wallCm: wallCm)
    }

    /// Build the estimated 3-D mesh for one food from its captured silhouettes.
    /// The returned mesh is also the volume source, so the user sees the exact
    /// geometry that drives weight, calories and diagnostics.

    private func makeEstimatedObject(
        id: String,
        label: String,
        instanceIndex: Int,
        mask: [[UInt8]],
        footprint: Footprint,
        widthCm: Double,
        depthCm: Double,
        heightCm: Double,
        topFrame: FrameCaptureService.CapturedFrame,
        colorFrame: CVPixelBuffer?,
        sideColorFrame: CVPixelBuffer?,
        maskWidth: Int,
        maskHeight: Int,
        sideProfile: SideProfile? = nil,
        bowl: BowlModel? = nil,
        reliefGrid: [[Float]]? = nil,
        reliefWeight: Float = 0
    ) -> EstimatedObject {
        let centroid = footprint.centroid
        let rx = Float(max(widthCm, 2.0) / 200.0)   // half-width in metres
        let rz = Float(max(depthCm, 2.0) / 200.0)   // half-depth in metres
        // Honour the measured thickness exactly; only a 1.5 mm physical floor so
        // a flat food (chocolate, cracker, slice) renders as thin as it truly is
        // instead of being forced up to a 0.8 cm minimum.
        let h  = Float(max(heightCm, 0.15) / 100.0)  // height in metres
        let offsetX = Float((centroid.col / Double(maskWidth)) - 0.5) * 0.28
        let offsetZ = Float((centroid.row / Double(maskHeight)) - 0.5) * 0.28

        // Every food — round or irregular — is reconstructed from its ACTUAL
        // captured silhouettes, never from a fitted primitive: the top mask
        // gives the on-plate footprint (vertical extrusion) and the side
        // profile gives the per-column vertical bounds (horizontal extrusion);
        // their overlap is the two-view visual hull. Round foods additionally
        // round the single unobserved transverse axis, bounded by the top mask.
        // The shared Loop+Taubin post-process then removes the facets, so the
        // shape always follows the real food the user photographed.

        // Fill only fully enclosed source-mask holes at the original mask
        // resolution. This fixes segmentation voids inside foods (for example
        // a tomato stem/leaf hole) without changing the outer silhouette the
        // user photographed.
        var solidMask = mask
        @inline(__always) func sourceIdx(_ r: Int, _ c: Int) -> Int { r * maskWidth + c }
        @inline(__always) func sourceSolid(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < maskHeight && c >= 0 && c < maskWidth && solidMask[r][c] == 1
        }
        func fillSourceMaskHoles(_ grid: inout [[UInt8]]) -> Int {
            guard maskWidth > 2, maskHeight > 2 else { return 0 }
            var outside = [Bool](repeating: false, count: maskWidth * maskHeight)
            var queue: [(Int, Int)] = []
            func enqueue(_ r: Int, _ c: Int) {
                guard r >= 0, r < maskHeight, c >= 0, c < maskWidth else { return }
                let idx = sourceIdx(r, c)
                guard grid[r][c] == 0, !outside[idx] else { return }
                outside[idx] = true
                queue.append((r, c))
            }
            for c in 0..<maskWidth {
                enqueue(0, c)
                enqueue(maskHeight - 1, c)
            }
            for r in 0..<maskHeight {
                enqueue(r, 0)
                enqueue(r, maskWidth - 1)
            }
            var head = 0
            while head < queue.count {
                let (r, c) = queue[head]
                head += 1
                enqueue(r - 1, c)
                enqueue(r + 1, c)
                enqueue(r, c - 1)
                enqueue(r, c + 1)
            }
            var filled = 0
            for r in 0..<maskHeight {
                for c in 0..<maskWidth {
                    let idx = sourceIdx(r, c)
                    if grid[r][c] == 0, !outside[idx] {
                        grid[r][c] = 1
                        filled += 1
                    }
                }
            }
            return filled
        }
        let filledHolePixels = fillSourceMaskHoles(&solidMask)
        if filledHolePixels > 0 {
            print("[MonocularEstimator] filled enclosed top-mask holes label=\(label) pixels=\(filledHolePixels)")
        }

        // Downsample the exact source silhouette only as an acceleration grid;
        // the final smoothed vertices are snapped back against `solidMask`.
        let bboxW = max(1, footprint.maxCol - footprint.minCol + 1)
        let bboxH = max(1, footprint.maxRow - footprint.minRow + 1)
        // High-resolution silhouette sampling for the cage. Keep this bounded:
        // the mesh is exported on-device during the scan flow, and Loop
        // subdivision scales with face count. 104 cells preserves the captured
        // outline for produce without turning a tomato into a timeout-sized
        // 300k+ triangle export.
        let maxCells = 100
        let step = max(1, Int((Double(max(bboxW, bboxH)) / Double(maxCells)).rounded(.up)))
        let gc = max(1, Int((Double(bboxW) / Double(step)).rounded(.up)))
        let gr = max(1, Int((Double(bboxH) / Double(step)).rounded(.up)))

        @inline(__always) func cell(_ r: Int, _ c: Int) -> Int { r * gc + c }

        // Exact-source occupancy of the underlying mask block per grid cell.
        var on = [Bool](repeating: false, count: gr * gc)
        for r in 0..<gr {
            for c in 0..<gc {
                var onCount = 0
                var total = 0
                let r0 = footprint.minRow + r * step
                let c0 = footprint.minCol + c * step
                for mr in r0..<min(r0 + step, maskHeight) {
                    for mc in c0..<min(c0 + step, maskWidth) {
                        total += 1
                        if solidMask[mr][mc] == 1 { onCount += 1 }
                    }
                }
                // Any touched source-mask pixel keeps the cell alive. Possible
                // sub-cell overhang is corrected later by snapping vertices to
                // the exact filled source mask, while this rule avoids shaving
                // thin real silhouette features before meshing.
                if total > 0 && onCount > 0 { on[cell(r, c)] = true }
            }
        }
        // Guarantee at least one cell so the viewer always has geometry.
        if !on.contains(true) { on[cell(gr / 2, gc / 2)] = true }

        @inline(__always) func isOn(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < gr && c >= 0 && c < gc && on[cell(r, c)]
        }

        let filledHoleCells = filledHolePixels

        // Shared-corner height field. With a side profile, this becomes a
        // two-silhouette visual hull: the top mask defines where the object
        // exists on the plate, while the side contour defines the vertical
        // profile across the aligned footprint axis. Without side evidence, it
        // falls back to a conservative spherical cap prior.
        let cornerCols = gc + 1
        @inline(__always) func corner(_ rr: Int, _ cc: Int) -> Int { rr * cornerCols + cc }
        @inline(__always) func cornerCells(_ rr: Int, _ cc: Int) -> Int {
            var n = 0
            if isOn(rr - 1, cc - 1) { n += 1 }
            if isOn(rr - 1, cc) { n += 1 }
            if isOn(rr, cc - 1) { n += 1 }
            if isOn(rr, cc) { n += 1 }
            return n
        }
        // Centroid in corner coordinates (cell centre r sits at corner r + 0.5).
        let cgR = Float((centroid.row - Double(footprint.minRow)) / Double(step)) + 0.5
        let cgC = Float((centroid.col - Double(footprint.minCol)) / Double(step)) + 0.5
        // Distance transform of the top silhouette over the corner lattice: 0 on
        // the outline, growing inward (two-pass chamfer). The no-side-profile
        // fallback shapes its vertical profile from THIS instead of a centroid
        // sphere, so the cap follows the real outline rather than a generic dome.
        var edgeDist = [Float](repeating: 0, count: (gr + 1) * cornerCols)
        let bigDist = Float((gr + 1) + (gc + 1))
        for rr in 0...gr {
            for cc in 0...gc {
                edgeDist[corner(rr, cc)] = cornerCells(rr, cc) >= 4 ? bigDist : 0
            }
        }
        for rr in 0...gr {
            for cc in 0...gc {
                let idx = corner(rr, cc)
                if edgeDist[idx] == 0 { continue }
                var d = edgeDist[idx]
                if rr > 0 { d = min(d, edgeDist[corner(rr - 1, cc)] + 1) }
                if cc > 0 { d = min(d, edgeDist[corner(rr, cc - 1)] + 1) }
                if rr > 0 && cc > 0 { d = min(d, edgeDist[corner(rr - 1, cc - 1)] + 1.41421) }
                if rr > 0 && cc < gc { d = min(d, edgeDist[corner(rr - 1, cc + 1)] + 1.41421) }
                edgeDist[idx] = d
            }
        }
        for rr in stride(from: gr, through: 0, by: -1) {
            for cc in stride(from: gc, through: 0, by: -1) {
                let idx = corner(rr, cc)
                if edgeDist[idx] == 0 { continue }
                var d = edgeDist[idx]
                if rr < gr { d = min(d, edgeDist[corner(rr + 1, cc)] + 1) }
                if cc < gc { d = min(d, edgeDist[corner(rr, cc + 1)] + 1) }
                if rr < gr && cc < gc { d = min(d, edgeDist[corner(rr + 1, cc + 1)] + 1.41421) }
                if rr < gr && cc > 0 { d = min(d, edgeDist[corner(rr + 1, cc - 1)] + 1.41421) }
                edgeDist[idx] = d
            }
        }
        var maxEdgeDist: Float = 0.0001
        for v in edgeDist where v > maxEdgeDist { maxEdgeDist = v }

        // Side-profile low-pass smoothing, fill inflation, taper and analytic
        // dome were REMOVED per the user requirement to use the REAL captured
        // silhouette. `cornerBounds` below reads the raw measured side bounds
        // directly, so the displayed mesh is the exact two-silhouette hull.

        // ── Exact-silhouette continuous bounds ────────────────────────────
        // `cornerBounds` evaluates bottom/top height fractions from the SIDE
        // silhouette (side-profile bounds along the matched axis, with
        // transverse rounding for round foods) or, without one, from the TOP
        // silhouette's distance transform. The occupied hull below is still a
        // sampled acceleration structure, but it is built from these exact
        // captured silhouettes and the final vertices are snapped back to the
        // source top mask after smoothing.
        @inline(__always) func cornerBounds(_ rr: Int, _ cc: Int) -> (bottom: Float, top: Float) {
            if bowl != nil {
                // Rounded bowl interior: a flat food surface on top (fraction 1)
                // with the hidden underside curving DOWN into the bowl — deepest
                // at the footprint centre (distance-transform maximum) and rising
                // to meet the surface at the rim. Horizontally this is the exact
                // top silhouette; vertically it is the bowl's rounded cavity.
                let nd = min(1.0, edgeDist[corner(rr, cc)] / maxEdgeDist)
                let bottom = 1.0 - sqrt(nd)
                return (max(0.0, bottom), 1.0)
            }
            // Blend the measured depth relief into the TOP-surface fraction only
            // (bottom rests on the plate). Weighted, clamped, and skipped where
            // depth has no data, so it refines the reliable base shape without
            // ever breaking it. `rr`/`cc` are captured from `cornerBounds`.
            func finish(_ bottom: Float, _ top: Float) -> (bottom: Float, top: Float) {
                var t = top
                if let relief = reliefGrid, reliefWeight > 0 {
                    let mc = min(maskWidth - 1, max(0,
                        footprint.minCol + Int((Double(cc) / Double(max(1, gc))) * Double(bboxW - 1))))
                    let mr = min(maskHeight - 1, max(0,
                        footprint.minRow + Int((Double(rr) / Double(max(1, gr))) * Double(bboxH - 1))))
                    let rf = relief[mr][mc]
                    if rf >= 0 {
                        t = t * (1 - reliefWeight) + max(bottom + 0.02, rf) * reliefWeight
                    }
                }
                let lo = max(0, bottom)
                return (lo, min(1, max(lo + 0.001, t)))
            }
            if let sideProfile, !sideProfile.normalizedHeights.isEmpty {
                // TWO-SILHOUETTE VISUAL HULL (space carving from the top + side
                // views). The side view gives the EXACT height profile along its
                // matched top axis; the perpendicular (unobserved) axis is that
                // SAME measured profile MIRRORED onto it — the camera never sees
                // that side, so it is taken to be symmetric. The surface is the
                // INTERSECTION of the two extruded silhouettes: the top fraction
                // is the MIN of the two profile tops, the base the MAX of the two
                // bottoms. Nothing is invented — only the measured side silhouette
                // (mirrored) + the measured top footprint bound it, so it rounds
                // to the true body instead of extruding a box/wall.
                let uMatched = sideProfile.topAxis == .columns
                    ? Double(cc) / Double(max(gc, 1))
                    : Double(rr) / Double(max(gr, 1))
                let uTransverse = sideProfile.topAxis == .columns
                    ? Double(rr) / Double(max(gr, 1))
                    : Double(cc) / Double(max(gc, 1))
                let a = sideProfile.sampleBounds(uMatched)
                let b = sideProfile.sampleBounds(uTransverse)
                let bottom = Float(max(a.bottom, b.bottom))
                let top = Float(min(a.top, b.top))
                if top <= bottom { return (0, max(0.02, top)) }
                return finish(bottom, top)
            }
            // No side silhouette: the height PROFILE was never observed, so per
            // AGENTS.md §9 we invent no dome/analytic shape. Extrude the EXACT
            // top silhouette at constant full height (flat top, vertical walls on
            // the true outline); the scalar height still comes from heightCm.
            return finish(0, 1.0)
        }

        @inline(__always) func cornerX(_ cc: Int) -> Float {
            offsetX + (Float(cc) / Float(gc) - 0.5) * 2.0 * rx
        }
        @inline(__always) func cornerZ(_ rr: Int) -> Float {
            offsetZ + (Float(rr) / Float(gr) - 0.5) * 2.0 * rz
        }

        var exactEdge = [Bool](repeating: false, count: maskWidth * maskHeight)
        @inline(__always) func sourceEdge(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < maskHeight && c >= 0 && c < maskWidth && exactEdge[sourceIdx(r, c)]
        }
        if footprint.minRow <= footprint.maxRow, footprint.minCol <= footprint.maxCol {
            for r in footprint.minRow...footprint.maxRow {
                for c in footprint.minCol...footprint.maxCol where sourceSolid(r, c) {
                    if !sourceSolid(r - 1, c) || !sourceSolid(r + 1, c) ||
                        !sourceSolid(r, c - 1) || !sourceSolid(r, c + 1) {
                        exactEdge[sourceIdx(r, c)] = true
                    }
                }
            }
        }
        @inline(__always) func maskPosition(for p: SIMD3<Float>) -> (row: Double, col: Double) {
            let colNorm = Double(((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5)
            let rowNorm = Double(((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5)
            return (
                Double(footprint.minRow) + rowNorm * Double(max(1, bboxH - 1)),
                Double(footprint.minCol) + colNorm * Double(max(1, bboxW - 1))
            )
        }
        @inline(__always) func moveHorizontal(_ p: inout SIMD3<Float>, to row: Int, _ col: Int) {
            let colNorm = (Double(col - footprint.minCol) + 0.5) / Double(max(1, bboxW))
            let rowNorm = (Double(row - footprint.minRow) + 0.5) / Double(max(1, bboxH))
            p.x = offsetX + (Float(colNorm) - 0.5) * 2.0 * rx
            p.z = offsetZ + (Float(rowNorm) - 0.5) * 2.0 * rz
        }
        func nearestExactPixel(row: Double, col: Double, edgeOnly: Bool, maxRadius: Int) -> (Int, Int)? {
            let centerR = Int(row.rounded())
            let centerC = Int(col.rounded())
            var best: (Int, Int)?
            var bestD = Double.greatestFiniteMagnitude
            for radius in 0...maxRadius {
                let r0 = max(footprint.minRow, centerR - radius)
                let r1 = min(footprint.maxRow, centerR + radius)
                let c0 = max(footprint.minCol, centerC - radius)
                let c1 = min(footprint.maxCol, centerC + radius)
                if r0 > r1 || c0 > c1 { continue }
                for r in r0...r1 {
                    for c in c0...c1 {
                        if radius > 0,
                           abs(r - centerR) < radius,
                           abs(c - centerC) < radius { continue }
                        let ok = edgeOnly ? sourceEdge(r, c) : sourceSolid(r, c)
                        guard ok else { continue }
                        let d = pow(Double(r) - row, 2) + pow(Double(c) - col, 2)
                        if d < bestD {
                            bestD = d
                            best = (r, c)
                        }
                    }
                }
                if best != nil { return best }
            }
            return best
        }

        // ── Continuous contour loft ──────────────────────────────────────
        // Emit one smooth shell from the exact top occupancy and side contour
        // bounds. There is no vertical voxel stack here, so the tomato cannot
        // show horizontal hull layers; y is continuous at every top-mask corner.
        var vertices: [SIMD3<Float>] = []
        var faces: [Int] = []
        var weldedVertex: [String: Int] = [:]
        let surfaceExtractionMode = "exact_silhouette_loft"
        let occupiedCellCount = on.reduce(0) { $0 + ($1 ? 1 : 0) }
        let cellAreaCm2 = max(widthCm, 2.0) * max(depthCm, 2.0) /
            Double(max(1, gc * gr))
        var hullVoxelVolumeCm3 = 0.0

        @inline(__always) func shellPoint(row: Int, col: Int, heightFraction: Float) -> SIMD3<Float> {
            SIMD3<Float>(cornerX(col), max(0, min(1, heightFraction)) * h, cornerZ(row))
        }
        @inline(__always) func vertexKey(_ position: SIMD3<Float>) -> String {
            let scale: Float = 1_000_000
            let qx = Int((position.x * scale).rounded())
            let qy = Int((position.y * scale).rounded())
            let qz = Int((position.z * scale).rounded())
            return "\(qx):\(qy):\(qz)"
        }
        func addVertex(_ position: SIMD3<Float>) -> Int {
            let key = vertexKey(position)
            if let existing = weldedVertex[key] { return existing }
            let index = vertices.count
            weldedVertex[key] = index
            vertices.append(position)
            return index
        }
        func addQuad(_ first: Int, _ second: Int, _ third: Int, _ fourth: Int) {
            faces.append(first); faces.append(second); faces.append(third)
            faces.append(first); faces.append(third); faces.append(fourth)
        }

        for row in 0..<gr {
            for col in 0..<gc where on[cell(row, col)] {
                let bounds00 = cornerBounds(row, col)
                let bounds01 = cornerBounds(row, col + 1)
                let bounds11 = cornerBounds(row + 1, col + 1)
                let bounds10 = cornerBounds(row + 1, col)
                let averageBottom = max(0.0, min(0.98,
                    (bounds00.bottom + bounds01.bottom + bounds11.bottom + bounds10.bottom) * 0.25))
                let averageTop = max(averageBottom + 0.001, min(1.0,
                    (bounds00.top + bounds01.top + bounds11.top + bounds10.top) * 0.25))
                hullVoxelVolumeCm3 += Double(averageTop - averageBottom) * heightCm * cellAreaCm2

                let top00 = addVertex(shellPoint(row: row, col: col, heightFraction: bounds00.top))
                let top01 = addVertex(shellPoint(row: row, col: col + 1, heightFraction: bounds01.top))
                let top11 = addVertex(shellPoint(row: row + 1, col: col + 1, heightFraction: bounds11.top))
                let top10 = addVertex(shellPoint(row: row + 1, col: col, heightFraction: bounds10.top))
                let bottom00 = addVertex(shellPoint(row: row, col: col, heightFraction: bounds00.bottom))
                let bottom01 = addVertex(shellPoint(row: row, col: col + 1, heightFraction: bounds01.bottom))
                let bottom11 = addVertex(shellPoint(row: row + 1, col: col + 1, heightFraction: bounds11.bottom))
                let bottom10 = addVertex(shellPoint(row: row + 1, col: col, heightFraction: bounds10.bottom))

                addQuad(top00, top10, top11, top01)
                addQuad(bottom00, bottom01, bottom11, bottom10)
                if !isOn(row - 1, col) { addQuad(bottom00, top00, top01, bottom01) }
                if !isOn(row + 1, col) { addQuad(bottom10, bottom11, top11, top10) }
                if !isOn(row, col - 1) { addQuad(bottom00, bottom10, top10, top00) }
                if !isOn(row, col + 1) { addQuad(bottom01, top01, top11, bottom11) }
            }
        }

        if vertices.isEmpty || faces.count < 3 {
            let x0 = cornerX(max(0, gc / 2 - 1))
            let x1 = cornerX(min(gc, gc / 2 + 1))
            let z0 = cornerZ(max(0, gr / 2 - 1))
            let z1 = cornerZ(min(gr, gr / 2 + 1))
            let y1 = max(0.005, h * 0.4)
            vertices = [
                SIMD3<Float>(x0, 0, z0), SIMD3<Float>(x1, 0, z0),
                SIMD3<Float>(x1, 0, z1), SIMD3<Float>(x0, 0, z1),
                SIMD3<Float>(x0, y1, z0), SIMD3<Float>(x1, y1, z0),
                SIMD3<Float>(x1, y1, z1), SIMD3<Float>(x0, y1, z1)
            ]
            faces = [0, 1, 2, 0, 2, 3, 4, 7, 6, 4, 6, 5,
                     0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
                     2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0]
            hullVoxelVolumeCm3 = max(0.5, Double(y1 * 1_000_000))
        }
        print("[MonocularEstimator] visual-hull mesh label=\(label) mode=\(surfaceExtractionMode) grid=\(gc)x\(gr) cells=\(occupiedCellCount) rawV=\(vertices.count) rawF=\(faces.count / 3) filledHolePixels=\(filledHoleCells)")

        // Smooth the silhouette cage into an organic surface: one Loop
        // subdivision level removes the triangle facets / straight lines, then a
        // short Taubin pass polishes it (base pinned + re-grounded inside). This
        // is the SAME post-process the LiDAR path uses, so both look identical.
        //
        // HARD-FORCED EXACT SILHOUETTE (every scan, no fallback): by default a
        // food keeps its exact captured outline with ZERO subdivision and ZERO
        // Taubin smoothing, so a flat/angular food (chocolate bar, toast, slice)
        // can never be rounded into a thicker pillow. ONLY genuinely round
        // produce — the labels with a transverse-roundness value (tomato, apple,
        // orange, egg, onion, potato…) — is allowed the organic smoothing that
        // makes a dome look round.
        // Bowls always get the organic smoothing so the rounded cavity reads
        // smooth; otherwise only genuinely round produce is smoothed and a
        // flat/angular food keeps its exact hard silhouette.
        // Smooth EVERY food (subdivide + Taubin) so a coarse silhouette cage can
        // never render as a faceted spike/point — a repeated user complaint. The
        // outline is re-snapped to the exact mask below, so smoothing keeps the
        // captured silhouette exact while removing facets. Round produce gets an
        // extra Taubin pass for a fuller organic surface.
        // HARD-FORCED EXACT SILHOUETTE (user requirement): NO geometry
        // smoothing. Loop subdivision + Taubin were rounding the captured
        // outline into a softer pillow; the user wants the displayed mesh to be
        // EXACTLY the top + side silhouette. We keep the raw silhouette-cage
        // vertices and only re-snap them to the exact source mask below. Soft
        // per-vertex NORMALS (the exporter's addNormals) still shade it
        // pleasantly without ever altering the geometry.

        @inline(__always) func hullBoundsAt(rowGrid: Float, colGrid: Float) -> (bottom: Float, top: Float) {
            let rr = min(gr - 1, max(0, Int(floor(rowGrid))))
            let cc = min(gc - 1, max(0, Int(floor(colGrid))))
            let tr = max(0, min(1, rowGrid - Float(rr)))
            let tc = max(0, min(1, colGrid - Float(cc)))
            let b00 = cornerBounds(rr, cc)
            let b10 = cornerBounds(rr + 1, cc)
            let b11 = cornerBounds(rr + 1, cc + 1)
            let b01 = cornerBounds(rr, cc + 1)
            let bottom0 = b00.bottom * (1 - tr) + b10.bottom * tr
            let bottom1 = b01.bottom * (1 - tr) + b11.bottom * tr
            let top0 = b00.top * (1 - tr) + b10.top * tr
            let top1 = b01.top * (1 - tr) + b11.top * tr
            let bottom = bottom0 * (1 - tc) + bottom1 * tc
            let top = top0 * (1 - tc) + top1 * tc
            return (max(0, bottom), max(bottom + 0.001, top))
        }
        var topSilhouetteSnapVertices = 0
        var topSilhouetteEdgeSnapVertices = 0
        for i in 0..<vertices.count {
            var p = vertices[i]
            var colGrid = (((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5) * Float(gc)
            var rowGrid = (((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5) * Float(gr)
            colGrid = max(0, min(Float(gc) - 0.0001, colGrid))
            rowGrid = max(0, min(Float(gr) - 0.0001, rowGrid))
            let sourcePos = maskPosition(for: p)
            let roundedR = Int(sourcePos.row.rounded())
            let roundedC = Int(sourcePos.col.rounded())
            let exactRadius = max(6, step * 3)
            if !sourceSolid(roundedR, roundedC),
               let nearest = nearestExactPixel(
                    row: sourcePos.row, col: sourcePos.col,
                    edgeOnly: false, maxRadius: exactRadius) {
                topSilhouetteSnapVertices += 1
                moveHorizontal(&p, to: nearest.0, nearest.1)
            } else if let edge = nearestExactPixel(
                row: sourcePos.row, col: sourcePos.col,
                edgeOnly: true, maxRadius: max(2, step)) {
                topSilhouetteEdgeSnapVertices += 1
                moveHorizontal(&p, to: edge.0, edge.1)
            }
            colGrid = (((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5) * Float(gc)
            rowGrid = (((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5) * Float(gr)
            colGrid = max(0, min(Float(gc) - 0.0001, colGrid))
            rowGrid = max(0, min(Float(gr) - 0.0001, rowGrid))
            let bnds = hullBoundsAt(rowGrid: rowGrid, colGrid: colGrid)
            p.y = min(max(p.y, bnds.bottom * h), bnds.top * h)
            vertices[i] = p
        }

        // Per-side realism self-check + repair. Runs after the vertices are
        // snapped back to the exact silhouette, so it operates on the final
        // shape the user will see. It (1) removes "shark fin" spikes — vertices
        // that poke far above their 1-ring neighbours, the signature of a noisy
        // side-mask column — by clamping them down to the neighbourhood, and
        // (2) inspects the body from every canonical side (top/bottom/front/
        // back/left/right) and reports whether each reads as a plausible food
        // surface, so the log shows the realism decision for each face.
        func repairMeshRealism(
            vertices: inout [SIMD3<Float>],
            faces: [Int],
            label: String,
            heightM: Float
        ) -> String {
            let n = vertices.count
            guard n > 4, faces.count >= 3 else { return "label=\(label) sides=n/a (degenerate)" }

            // 1-ring adjacency from the triangle list.
            var adjacency = [Set<Int>](repeating: [], count: n)
            var f = 0
            while f + 2 < faces.count {
                let a = faces[f], b = faces[f + 1], c = faces[f + 2]
                if a >= 0, a < n, b >= 0, b < n, c >= 0, c < n {
                    adjacency[a].insert(b); adjacency[a].insert(c)
                    adjacency[b].insert(a); adjacency[b].insert(c)
                    adjacency[c].insert(a); adjacency[c].insert(b)
                }
                f += 3
            }

            // Spike removal: a vertex whose height exceeds its neighbourhood
            // median by more than a fraction of the object height is a fin.
            let spikeThreshold = max(0.0015, heightM * 0.16)
            var repairedSpikes = 0
            for _ in 0..<3 {
                var newY = vertices.map { $0.y }
                var pass = 0
                for v in 0..<n {
                    let neigh = adjacency[v]
                    guard neigh.count >= 3 else { continue }
                    var ys = neigh.map { vertices[$0].y }
                    ys.sort()
                    let median = ys[ys.count / 2]
                    if vertices[v].y - median > spikeThreshold {
                        newY[v] = median + spikeThreshold * 0.5
                        pass += 1
                    }
                }
                if pass == 0 { break }
                for v in 0..<n { vertices[v].y = newY[v] }
                repairedSpikes += pass
            }

            // Per-side plausibility from the repaired extents.
            var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
            var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
            var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
            for p in vertices {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
                minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
            }
            let extentX = max(0.0001, maxX - minX)
            let extentY = max(0.0001, maxY - minY)
            let extentZ = max(0.0001, maxZ - minZ)
            // A believable plated food is not much taller than it is wide/deep.
            func sideStatus(lateral: Float) -> String {
                let ratio = extentY / lateral
                if ratio > 1.6 { return "tall" }
                if ratio < 0.06 { return "flat" }
                return "ok"
            }
            let front = sideStatus(lateral: extentX)
            let left = sideStatus(lateral: extentZ)
            let footprint = (extentX > 0.0001 && extentZ > 0.0001) ? "ok" : "degenerate"
            return String(
                format: "label=%@ spikes_repaired=%d top=%@ bottom=%@ front=%@ back=%@ left=%@ right=%@ h/w=%.2f",
                label, repairedSpikes, footprint, footprint, front, front, left, left,
                Double(extentY / max(extentX, extentZ)))
        }

        let realismReport = repairMeshRealism(
            vertices: &vertices, faces: faces, label: label, heightM: h)
        print("[REALISM] \(realismReport)")

        func vertexNormals(vertices: [SIMD3<Float>], faces: [Int]) -> [SIMD3<Float>] {
            var normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: vertices.count)
            var accum = [SIMD3<Float>](repeating: SIMD3<Float>(repeating: 0), count: vertices.count)
            var i = 0
            while i + 2 < faces.count {
                let a = faces[i], b = faces[i + 1], c = faces[i + 2]
                if a >= 0, a < vertices.count,
                   b >= 0, b < vertices.count,
                   c >= 0, c < vertices.count {
                    let n = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
                    if simd_length(n) > 0.000001 {
                        accum[a] += n
                        accum[b] += n
                        accum[c] += n
                    }
                }
                i += 3
            }
            for idx in 0..<accum.count {
                let len = simd_length(accum[idx])
                if len > 0.000001 { normals[idx] = accum[idx] / len }
            }
            return normals
        }

        @inline(__always) func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }
        let normals = vertexNormals(vertices: vertices, faces: faces)
        let surfaceVolumeCm3 = meshVolumeCm3(vertices: vertices, faces: faces)
        let resolvedVolumeCm3 = surfaceVolumeCm3.isFinite && surfaceVolumeCm3 > 1.0
            ? surfaceVolumeCm3
            : max(0.5, hullVoxelVolumeCm3)
        // Seamless top-down photo projection: every vertex samples the real
        // captured TOP photo at the pixel directly above its footprint (x,z).
        // Because the vertices are snapped to the exact top-mask silhouette the
        // photo lines up with the outline and wraps continuously down the sides
        // as ONE image — no atlas split, so no straddling triangles and no
        // doubled/flickering texture. The matching texture is the mask-aligned
        // preprocessed top RGB baked by Food3DExporter, so these UVs index it.
        let uvs: [SIMD2<Float>] = vertices.map { p in
            let colNorm = clamp01(((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5)
            let rowNorm = clamp01(((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5)
            let sourceU = (Float(footprint.minCol) + colNorm * Float(bboxW)) / Float(max(maskWidth, 1))
            let sourceV = (Float(footprint.minRow) + rowNorm * Float(bboxH)) / Float(max(maskHeight, 1))
            return SIMD2<Float>(clamp01(sourceU), 1.0 - clamp01(sourceV))
        }

        // Sample colour from the MASK-ALIGNED preprocessed plate crop (BGRA,
        // 512², the exact image the segmenter saw and the SAME space the masks
        // live in), decoded to BGRA ONCE per food and reused for the dominant
        // tint AND every per-vertex sample below.
        //
        // ROOT CAUSE of "food stays white": the masks span ONLY the plate crop,
        // but the colour sampler used the FULL camera frame (topFrame) and mapped
        // each mask coordinate across the whole frame (mc/maskWidth × frameW). A
        // food-mask pixel near the crop edge therefore read the plate rim / table
        // (near-white) instead of the food, washing every sampled colour toward
        // white. The preprocessed crop is the same dimensions as the mask, so
        // sampling it maps 1:1 to the real food pixel. It is also far smaller
        // than the full frame, so the shared decode is cheaper too. Falls back to
        // the full frame only if the preprocessed crop is somehow unavailable.
        // ALWAYS colour the food from the captured photos — never a synthetic
        // per-label colour. Decode the mask-aligned preprocessed crop first; if
        // that allocation fails under 3-D-phase memory pressure, retry the full
        // top frame (still a real photo) so the tint is always sampled from
        // pixels the camera actually saw. dominantColor prefers the eroded mask
        // interior, so a loose outline that grazes the plate rim no longer
        // bleeds white into the food colour.
        let sharedBGRA = Food3DTextureBaker.bgraCopy(of: colorFrame ?? topFrame.pixelBuffer)
            ?? Food3DTextureBaker.bgraCopy(of: topFrame.pixelBuffer)
        let sharedSideBGRA = sideColorFrame.flatMap { Food3DTextureBaker.bgraCopy(of: $0) }
        if sharedBGRA == nil {
            print("[MonocularEstimator] ⚠️ colour-frame BGRA decode failed for \(label) — both crop and full-frame decode returned nil")
        }
        let color = dominantColor(bgra: sharedBGRA, mask: mask, footprint: footprint, maskWidth: maskWidth, maskHeight: maskHeight)
        print("[MonocularEstimator] colour \(label) = (\(color[0]),\(color[1]),\(color[2])) src=photo")
        // Per-vertex colour sampled directly from the captured photos. Instead
        // of a single flat tint, every vertex takes the real colour at its own
        // position on the food, so natural variation (ripening blush,
        // highlights, blemishes, char) is preserved. Point-sampling per vertex —
        // not a stretched texture atlas — means there are no projection stripes.
        // Downward-facing (underside) vertices are reasoned about by food type:
        // round whole produce mirrors the top colour (a tomato looks the same
        // underneath), while layered/baked foods get a distinct browned contact
        // shade.
        var vertexMaskPositions: [(row: Double, col: Double)] = []
        vertexMaskPositions.reserveCapacity(vertices.count)
        for p in vertices { vertexMaskPositions.append(maskPosition(for: p)) }
        let colors = sampledVertexColors(
            bgra: sharedBGRA,
            sideBGRA: sharedSideBGRA,
            solidMask: solidMask,
            positions: vertexMaskPositions,
            heightFractions: vertices.map { Double(max(0, min(1, $0.y / max(h, 0.0001)))) },
            normals: normals,
            baseColor: color,
            label: label,
            footprint: footprint,
            sideProfile: sideProfile,
            maskWidth: maskWidth,
            maskHeight: maskHeight
        )

        // Seam-split for the TOP+SIDE photo atlas. A shared-vertex mesh cannot
        // be atlased directly: triangles on the top/side boundary would straddle
        // the two photo tiles and the GPU would smear both pictures together
        // (doubled image + flicker on rotation). So when a side capture exists we
        // UNWELD per triangle and assign each whole triangle to ONE tile by its
        // average normal — top-facing and underside → top photo, the vertical
        // side band → side photo — cutting the picture cleanly at the seam with
        // no straddle. The viewer welds normals by position, so shading stays
        // smooth despite the duplicated seam vertices. Volume is unchanged (the
        // positions are identical; only vertices shared at the seam are copied).
        var outVertices = vertices
        var outFaces = faces
        var outColors = colors
        var outUVs = uvs
        if sideColorFrame != nil {
            let topU0 = Food3DTextureBaker.atlasTopU0, topU1 = Food3DTextureBaker.atlasTopU1
            let sideU0 = Food3DTextureBaker.atlasSideU0, sideU1 = Food3DTextureBaker.atlasSideU1
            let colorStride = vertices.isEmpty ? 3 : max(1, colors.count / vertices.count)
            @inline(__always) func topUV(_ p: SIMD3<Float>) -> SIMD2<Float> {
                let colNorm = clamp01(((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5)
                let rowNorm = clamp01(((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5)
                let su = (Float(footprint.minCol) + colNorm * Float(bboxW)) / Float(max(maskWidth, 1))
                let sv = (Float(footprint.minRow) + rowNorm * Float(bboxH)) / Float(max(maskHeight, 1))
                return SIMD2<Float>(clamp01(topU0 + su * (topU1 - topU0)), 1.0 - clamp01(sv))
            }
            @inline(__always) func sideUV(_ p: SIMD3<Float>) -> SIMD2<Float> {
                guard let sp = sideProfile else { return topUV(p) }
                let colNorm = clamp01(((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5)
                let rowNorm = clamp01(((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5)
                let axisU = sp.topAxis == .columns ? Double(colNorm) : Double(rowNorm)
                let hf = Double(clamp01(p.y / Float(max(h, 0.0001))))
                let uv = sp.sourceUV(axisU: axisU, heightFraction: hf)
                return SIMD2<Float>(clamp01(sideU0 + Float(uv.y) * (sideU1 - sideU0)),
                                    1.0 - clamp01(Float(uv.x)))
            }
            var nv = [SIMD3<Float>](); nv.reserveCapacity(faces.count)
            var nc = [UInt8](); nc.reserveCapacity(faces.count * colorStride)
            var nu = [SIMD2<Float>](); nu.reserveCapacity(faces.count)
            var nf = [Int](); nf.reserveCapacity(faces.count)
            var t = 0
            while t + 2 < faces.count {
                let i0 = faces[t], i1 = faces[t + 1], i2 = faces[t + 2]
                t += 3
                guard i0 >= 0, i0 < vertices.count, i1 >= 0, i1 < vertices.count,
                      i2 >= 0, i2 < vertices.count else { continue }
                let avgNy = (normals[i0].y + normals[i1].y + normals[i2].y) / 3.0
                let isSide = sideProfile != nil && avgNy < 0.45 && avgNy > -0.35
                for v in [i0, i1, i2] {
                    nf.append(nv.count)
                    nv.append(vertices[v])
                    let cBase = v * colorStride
                    for k in 0..<colorStride {
                        nc.append(cBase + k < colors.count ? colors[cBase + k] : 200)
                    }
                    nu.append(isSide ? sideUV(vertices[v]) : topUV(vertices[v]))
                }
            }
            if nf.count >= 3 {
                outVertices = nv
                outFaces = nf
                outColors = nc
                outUVs = nu
                print("[MonocularEstimator] atlas seam-split \(label): welded=\(vertices.count)v/\(faces.count / 3)f -> unwelded=\(nv.count)v")
            }
        }

        let object = DepthFusion.Food3DObject(
            id: id,
            label: label,
            instanceIndex: instanceIndex,
            vertices: outVertices,
            faces: outFaces,
            colors: outColors,
            uvs: outUVs,
            voxelCount: occupiedCellCount,
            volumeCm3: resolvedVolumeCm3,
            // The hull is now Taubin-smoothed into a curved organic surface, so
            // average normals across shared vertices for soft shading instead of
            // preserving the old voxel creases that made it read as low-poly.
            preserveCreases: false
        )
        return EstimatedObject(
            object: object,
            meshVolumeCm3: resolvedVolumeCm3,
            hullVoxelVolumeCm3: hullVoxelVolumeCm3,
            surfaceExtractionMode: surfaceExtractionMode,
            topSilhouetteSnapVertices: topSilhouetteSnapVertices,
            topSilhouetteEdgeSnapVertices: topSilhouetteEdgeSnapVertices
        )
    }

    private func meshVolumeCm3(vertices: [SIMD3<Float>], faces: [Int]) -> Double {
        guard vertices.count >= 4, faces.count >= 3 else { return 0 }
        var origin = SIMD3<Float>(repeating: 0)
        for p in vertices { origin += p }
        origin /= Float(vertices.count)

        var volumeM3 = 0.0
        var i = 0
        while i + 2 < faces.count {
            let ia = faces[i], ib = faces[i + 1], ic = faces[i + 2]
            if ia >= 0, ia < vertices.count,
               ib >= 0, ib < vertices.count,
               ic >= 0, ic < vertices.count {
                let a = vertices[ia] - origin
                let b = vertices[ib] - origin
                let c = vertices[ic] - origin
                volumeM3 += Double(simd_dot(a, simd_cross(b, c))) / 6.0
            }
            i += 3
        }
        return abs(volumeM3) * 1_000_000.0
    }

    /// Whether a food's underside looks essentially the same as its top. Whole
    /// round produce (a tomato, apple, orange, egg, onion, plum…) is uniform all
    /// around, so the unobserved bottom mirrors the captured top colour. Layered
    /// or baked/plated foods (bread, pizza, pancakes, a plated portion) have a
    /// visibly different underside — a browned crust or plate-contact face — so
    /// they get a distinct shade instead of the top colour.
    private func undersideResemblesTop(for label: String) -> Bool {
        let l = label.lowercased()
        let roundWholeProduce = [
            "tomato", "apple", "orange", "peach", "plum", "onion", "potato",
            "egg", "grape", "berry", "cherry", "lemon", "lime", "meatball",
            "melon", "kiwi", "mango", "avocado", "radish", "beet", "sprout",
        ]
        return roundWholeProduce.contains { l.contains($0) }
    }

    /// Sample a real per-vertex colour for the reconstructed mesh directly from
    /// the captured top photo. Each vertex is coloured from the food's actual
    /// appearance at its own footprint position (natural inconsistency), then
    /// shaded by its surface normal and reasoned underside behaviour. This gives
    /// the "the whole food is that colour, with variation" look the flat
    /// dominant tint could not, without reintroducing stretched-texture stripes.
    private func sampledVertexColors(
        bgra: CVPixelBuffer?,
        sideBGRA: CVPixelBuffer?,
        solidMask: [[UInt8]],
        positions: [(row: Double, col: Double)],
        heightFractions: [Double],
        normals: [SIMD3<Float>],
        baseColor: [UInt8],
        label: String,
        footprint: Footprint,
        sideProfile: SideProfile?,
        maskWidth: Int,
        maskHeight: Int
    ) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(positions.count * 3)
        let base = baseColor.count >= 3 ? baseColor : [210, 170, 120]
        let baseR = Double(base[0]), baseG = Double(base[1]), baseB = Double(base[2])

        guard let buffer = bgra else {
            for _ in positions { out += base }
            return out
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddr = CVPixelBufferGetBaseAddress(buffer) else {
            for _ in positions { out += base }
            return out
        }
        let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)

        var sidePtr: UnsafeMutablePointer<UInt8>?
        var sideWidth = 0
        var sideHeight = 0
        var sideRowBytes = 0
        if let sideBGRA {
            CVPixelBufferLockBaseAddress(sideBGRA, .readOnly)
            sidePtr = CVPixelBufferGetBaseAddress(sideBGRA)?
                .assumingMemoryBound(to: UInt8.self)
            sideWidth = CVPixelBufferGetWidth(sideBGRA)
            sideHeight = CVPixelBufferGetHeight(sideBGRA)
            sideRowBytes = CVPixelBufferGetBytesPerRow(sideBGRA)
        }
        defer {
            if let sideBGRA { CVPixelBufferUnlockBaseAddress(sideBGRA, .readOnly) }
        }

        @inline(__always) func nearestInMask(_ r0: Int, _ c0: Int) -> (Int, Int)? {
            if r0 >= 0, r0 < maskHeight, c0 >= 0, c0 < maskWidth, solidMask[r0][c0] == 1 {
                return (r0, c0)
            }
            for radius in 1...6 {
                let rlo = max(0, r0 - radius), rhi = min(maskHeight - 1, r0 + radius)
                let clo = max(0, c0 - radius), chi = min(maskWidth - 1, c0 + radius)
                if rlo > rhi || clo > chi { continue }
                for r in rlo...rhi {
                    for c in clo...chi where solidMask[r][c] == 1 {
                        return (r, c)
                    }
                }
            }
            return nil
        }

        // Exact per-vertex colour from the TOP photo (3×3 denoise). Returns nil
        // when the sample is the white plate showing through a loose mask, so the
        // caller can fall back to another source instead of bleeding white.
        @inline(__always) func topPixel(_ mr: Int, _ mc: Int) -> (Double, Double, Double)? {
            guard let (r, c) = nearestInMask(mr, mc) else { return nil }
            var rSum = 0.0, gSum = 0.0, bSum = 0.0, n = 0.0
            for dr in -1...1 {
                for dc in -1...1 {
                    let mrr = min(max(r + dr, 0), maskHeight - 1)
                    let mcc = min(max(c + dc, 0), maskWidth - 1)
                    guard solidMask[mrr][mcc] == 1 else { continue }
                    let x = min(max(Int((Double(mcc) / Double(maskWidth)) * Double(w)), 0), w - 1)
                    let y = min(max(Int((Double(mrr) / Double(maskHeight)) * Double(h)), 0), h - 1)
                    let off = y * rowBytes + x * 4
                    rSum += Double(ptr[off + 2]); gSum += Double(ptr[off + 1]); bSum += Double(ptr[off + 0]); n += 1
                }
            }
            guard n > 0 else { return nil }
            let rr = rSum / n, gg = gSum / n, bb = bSum / n
            let mx = max(rr, max(gg, bb)), mn = min(rr, min(gg, bb))
            if mn > 175, mx - mn < 40 { return nil }
            return (rr, gg, bb)
        }

        for i in 0..<positions.count {
            let pos = positions[i]
            let mr = Int(pos.row.rounded())
            let mc = Int(pos.col.rounded())
            var sr = baseR, sg = baseG, sb = baseB
            let ny = i < normals.count ? normals[i].y : 1.0
            if ny < 0.45,
               ny > -0.35,
               let sideProfile,
               let sidePtr,
               sideWidth > 0,
               sideHeight > 0 {
                let axisU: Double
                if sideProfile.topAxis == .columns {
                    axisU = (pos.col - Double(footprint.minCol)) /
                        Double(max(1, footprint.maxCol - footprint.minCol))
                } else {
                    axisU = (pos.row - Double(footprint.minRow)) /
                        Double(max(1, footprint.maxRow - footprint.minRow))
                }
                let uv = sideProfile.sourceUV(
                    axisU: axisU,
                    heightFraction: i < heightFractions.count ? heightFractions[i] : 0.5
                )
                let x = min(max(Int((Double(uv.y) * Double(sideWidth)).rounded()), 0), sideWidth - 1)
                let y = min(max(Int((Double(uv.x) * Double(sideHeight)).rounded()), 0), sideHeight - 1)
                let offset = y * sideRowBytes + x * 4
                sr = Double(sidePtr[offset + 2])
                sg = Double(sidePtr[offset + 1])
                sb = Double(sidePtr[offset])
                // If the side photo pixel is the white plate / background behind
                // the food, fall back to the exact top-photo colour so a side
                // face never picks up the table instead of the food.
                let mxS = max(sr, max(sg, sb)), mnS = min(sr, min(sg, sb))
                if mnS > 175, mxS - mnS < 40, let t = topPixel(mr, mc) {
                    sr = t.0; sg = t.1; sb = t.2
                }
            } else if let t = topPixel(mr, mc) {
                sr = t.0; sg = t.1; sb = t.2
            }
            if ny < -0.35 {
                // Underside is unobserved by both photos; colour it from the TOP
                // photo pixel directly above its footprint — the exact captured
                // colour, not a synthetic tint — so the whole object is coloured
                // straight from the pictures.
                if let t = topPixel(mr, mc) { sr = t.0; sg = t.1; sb = t.2 }
            }
            out.append(UInt8(min(255.0, max(0.0, sr.rounded()))))
            out.append(UInt8(min(255.0, max(0.0, sg.rounded()))))
            out.append(UInt8(min(255.0, max(0.0, sb.rounded()))))
        }
        return out
    }

    /// Robust dominant colour of the food. Averages many in-mask pixels from
    /// the decoded top frame, rejecting specular highlights and deep shadows so
    /// a single glare/shadow pixel can't skew the whole mesh. This is what makes
    /// a tomato render red, a banana yellow and bread brown instead of a generic
    /// tint. Falls back to the centroid pixel, then a neutral beige.
    private func dominantColor(
        bgra: CVPixelBuffer?,
        mask: [[UInt8]],
        footprint: Footprint,
        maskWidth: Int,
        maskHeight: Int
    ) -> [UInt8] {
        guard let buffer = bgra else {
            return [210, 170, 120]
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [210, 170, 120] }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let minR = max(0, footprint.minRow), maxRow = min(maskHeight - 1, footprint.maxRow)
        let minC = max(0, footprint.minCol), maxCol = min(maskWidth - 1, footprint.maxCol)
        let rows = max(1, maxRow - minR + 1), cols = max(1, maxCol - minC + 1)
        // Bound the work to roughly 50x50 mask samples regardless of food size.
        let stride = max(1, Int((Double(max(rows, cols)) / 50.0).rounded(.up)))

        var samples: [(r: Double, g: Double, b: Double, lum: Double)] = []
        var interiorSamples: [(r: Double, g: Double, b: Double, lum: Double)] = []
        // Erode the mask by ~2 sampling steps: a pixel only counts as "interior"
        // if the mask is solid this far up/down/left/right of it. Sampling the
        // interior first keeps the tint on the real food and off the plate rim
        // that a loose outline can graze.
        let erode = 2 * stride
        var mr = minR
        while mr <= maxRow {
            var mc = minC
            while mc <= maxCol {
                if mask[mr][mc] == 1 {
                    let x = min(max(Int((Double(mc) / Double(maskWidth)) * Double(w)), 0), w - 1)
                    let y = min(max(Int((Double(mr) / Double(maskHeight)) * Double(h)), 0), h - 1)
                    let off = y * rowBytes + x * 4
                    let r = Double(ptr[off + 2]), g = Double(ptr[off + 1]), b = Double(ptr[off + 0])
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b
                    samples.append((r, g, b, lum))
                    if mr - erode >= 0, mr + erode < maskHeight, mc - erode >= 0, mc + erode < maskWidth,
                       mask[mr - erode][mc] == 1, mask[mr + erode][mc] == 1,
                       mask[mr][mc - erode] == 1, mask[mr][mc + erode] == 1 {
                        interiorSamples.append((r, g, b, lum))
                    }
                }
                mc += stride
            }
            mr += stride
        }
        // Prefer the eroded interior when it has enough pixels; otherwise use the
        // full in-mask set (tiny foods may have no interior after erosion).
        var chosen = interiorSamples.count >= 8 ? interiorSamples : samples
        // Keep only the central 5-95% luminance band so specular highlights and
        // cast shadows cannot wash out or darken the dominant hue, then take the
        // trimmed mean of that band as the representative food colour.
        if chosen.count >= 8 {
            chosen.sort { $0.lum < $1.lum }
            let lo = Int(Double(chosen.count) * 0.05)
            let hi = max(lo + 1, Int(Double(chosen.count) * 0.95))
            let band = chosen[lo..<min(hi, chosen.count)]
            var rSum = 0.0, gSum = 0.0, bSum = 0.0
            for s in band { rSum += s.r; gSum += s.g; bSum += s.b }
            let n = Double(band.count)
            return [
                UInt8(min(255.0, max(0.0, (rSum / n).rounded()))),
                UInt8(min(255.0, max(0.0, (gSum / n).rounded()))),
                UInt8(min(255.0, max(0.0, (bSum / n).rounded())))
            ]
        }
        return sampleColor(bgra: buffer, centroid: footprint.centroid, maskWidth: maskWidth, maskHeight: maskHeight)
    }

    private func sampleColor(
        bgra: CVPixelBuffer?,
        centroid: (row: Double, col: Double),
        maskWidth: Int,
        maskHeight: Int
    ) -> [UInt8] {
        // Sample the shared BGRA decode of the captured top photo so we read the
        // real food colour instead of hitting the grey/beige fallback.
        guard let buffer = bgra else {
            return [210, 170, 120]
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [210, 170, 120] }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let x = min(max(Int((centroid.col / Double(maskWidth)) * Double(w)), 0), w - 1)
        let y = min(max(Int((centroid.row / Double(maskHeight)) * Double(h)), 0), h - 1)
        let off = y * rowBytes + x * 4
        return [ptr[off + 2], ptr[off + 1], ptr[off + 0]]
    }

    private func sanitised(_ label: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        let chars = label.replacingOccurrences(of: " ", with: "_").unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        }
        let cleaned = String(chars)
        return cleaned.isEmpty ? "food" : cleaned
    }
}
