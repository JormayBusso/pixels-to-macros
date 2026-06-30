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

    /// Metric-depth (Depth Anything V2 metric-indoor) is OUT-OF-DOMAIN at the
    /// 10–30 cm hold distance used for plated food: device testing showed 4–9×
    /// absolute scale error and ~3× height overestimation (the "everything looks
    /// like a cucumber" tall-dome bug). It is therefore disabled as a volume
    /// source. The reliable metric signal on non-LiDAR devices is the ARKit
    /// tracked camera-to-table distance (see `tableDistanceCm`).
    static var useMetricDepthVolume = false

    /// P2 temporal stabilization state. Keyed by lowercased food label and kept
    /// for the app session so repeated captures of the same food converge to a
    /// stable volume instead of jittering 20-30% per capture.
    private struct VolumeSmoother {
        var volumeCm3: Double
        var samples: Int
    }
    private static var volumeHistory: [String: VolumeSmoother] = [:]
    private static let volumeSmoothingAlpha = 0.5
    private static let volumeResetBandFraction = 0.35

    func estimate(
        segments: [SegmentationService.SegmentedObject],
        topFrame: FrameCaptureService.CapturedFrame,
        sideFrame: FrameCaptureService.CapturedFrame?,
        sideProfiles: [SideProfile] = [],
        maskWidth: Int,
        maskHeight: Int,
        measuredHeightCm: Double? = nil,
        preprocessedRGB: CVPixelBuffer? = nil,
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
            guard MonocularVolumeEstimator.useMetricDepthVolume,
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

        for (idx, seg) in segments.enumerated() {
            guard let footprint = footprintStats(seg.mask, maskWidth: maskWidth, maskHeight: maskHeight) else {
                continue
            }

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
            let profile = usableSideProfile(profileMatch?.profile, for: seg.label)
            if profile != nil, let profileMatch { usedSideProfileIndices.insert(profileMatch.index) }
            if let dr = depthResult {
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
                let rawHeightCm = max(0.5, profile.aspectRatio * topAxisCm)
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
                let roundMesh = transverseRoundnessStrength(for: seg.label) > 0
                debugInfo = String(
                    format: "visual_hull: side=hard mesh=%@ scale=%@ %.1fpx/cm axis=%@%@ h=%.1fcm fill=%.2f ar=%.2f vol=%.0fcm³",
                    roundMesh ? "round" : "profile",
                    scale.source,
                    scale.pixelsPerCm,
                    profile.topAxis.rawValue,
                    profile.reversed ? "R" : "",
                    heightCm,
                    profile.meanNormalizedHeight,
                    profile.aspectRatio,
                    volumeCm3
                )
                print("[MonocularEstimator] visual-hull food#\(idx) \(seg.label): sideLabel=\(profile.label), axis=\(profile.topAxis.rawValue), reversed=\(profile.reversed), mesh=\(roundMesh ? "round" : "profile"), ar=\(String(format: "%.2f", profile.aspectRatio)), height=\(String(format: "%.2f", heightCm))cm, fill=\(String(format: "%.2f", profile.meanNormalizedHeight)), vol=\(String(format: "%.1f", volumeCm3))cm3")
            } else {
                let rawHeightCm = (idx == 0 ? measuredHeightCm : nil) ?? priorBoundCm
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
            // P2 temporal stabilization: converge repeated captures of the same
            // food to a stable volume (EMA + out-of-band reset).
            let smoothing = smoothedVolume(label: seg.label, volumeCm3: volumeCm3)
            let finalVolumeCm3 = smoothing.volumeCm3
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
            let fallbackUsed = depthResult == nil && profile == nil
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
                format: "%@ | footprint raw=%.1fcm² %.1fx%.1fcm stable=%.1fcm² %.1fx%.1fcm height=%.2fcm rawVol=%.1fcm³ finalVol=%.1fcm³ density=%.2fg/cm³ weight=%.0fg fallback=%@ sideApplied=%@%@%@",
                debugInfo ?? scanMode,
                rawAreaCm2,
                rawWidthCm,
                rawDepthCm,
                areaCm2,
                widthCm,
                depthCm,
                heightCm,
                rawVolumeCm3,
                finalVolumeCm3,
                densityEstimate,
                weightEstimateG,
                fallbackUsed ? "true" : "false",
                sideApplied ? "true" : "false",
                sideProfileSummary,
                guardrailText
            )
            let confidence = confidenceForScale(scale, segmentConfidence: seg.confidence, sideFrame: sideFrame)
            let id = "\(sanitised(seg.label))_\(idx)"

            let object = makeEstimatedObject(
                id: id,
                label: seg.label,
                instanceIndex: idx,
                mask: seg.mask,
                footprint: footprint,
                widthCm: widthCm,
                depthCm: depthCm,
                heightCm: heightCm,
                volumeCm3: finalVolumeCm3,
                voxelCount: max(seg.pixelCount, Int(finalVolumeCm3.rounded())),
                topFrame: topFrame,
                maskWidth: maskWidth,
                maskHeight: maskHeight,
                sideProfile: profile
            )
            objects.append(object)

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
                "height_cm": round(heightCm * 10) / 10,
                "raw_volume_cm3": round(rawVolumeCm3 * 10) / 10,
                "density_g_cm3": round(densityEstimate * 100) / 100,
                "weight_g": round(weightEstimateG),
                "volume_guardrail_applied": guardrailApplied,
                "side_view_applied": sideApplied,
                "fallback_used": fallbackUsed,
                "temporal_smoothing_applied": smoothing.applied,
                "temporal_samples": smoothing.samples,
                "pre_smoothing_volume_cm3": round(volumeCm3 * 10) / 10,
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
            throw EstimateError.noObjects
        }

        let baseName = "scan3d_camera_\(Int(Date().timeIntervalSince1970 * 1000))"
        guard let url = exporter.export(objects: objects, baseName: baseName),
              FileManager.default.fileExists(atPath: url.path) else {
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
        // Plate detection is used ONLY to recover the preprocessing crop
        // fraction (the mask is a scaleFill crop of the frame) and, below, for
        // a debug-only validation log. Plate diameter is NEVER a scale source:
        // its ±20% circle-fit swing cubed into the ~2x volume variance, so it
        // was removed from scaling entirely.
        let plate = plateDetector.detect(in: topFrame.pixelBuffer)
        let cropWidthPx = max(1.0, Double(plate.rect.width) * Double(imageWidth))
        let fx = Double(topFrame.cameraIntrinsics.columns.0.x)

        // Deterministic single-source hierarchy — no blending, no weighted
        // fusion. Exactly one source is selected per scan:
        //   PRIMARY  : ARKit tracked plane distance (metrically stable)
        //   FALLBACK : camera-intrinsic estimate at the guided hold distance
        //   LAST     : default-plate geometry only when intrinsics are missing
        if let tableDistanceCm, fx > 1, tableDistanceCm > 1.0 {
            let cmPerImagePx = tableDistanceCm / fx
            let cmPerMaskPx = cmPerImagePx * cropWidthPx / Double(maskWidth)
            let pxPerCm = max(1.0 / max(cmPerMaskPx, 0.0001), 1.0)
            logScaleValidation(chosenPxPerCm: pxPerCm, plateDetected: plate.detected,
                               maskWidth: maskWidth, maskHeight: maskHeight, source: "arkit_plane")
            return ScaleEstimate(
                pixelsPerCm: pxPerCm,
                source: "arkit_plane",
                confidence: 0.82,
                fallbackReason: nil)
        }

        if fx > 1 {
            let cmPerImagePx = guidedDistanceCm / fx
            let cmPerMaskPx = cmPerImagePx * cropWidthPx / Double(maskWidth)
            let pxPerCm = max(1.0 / max(cmPerMaskPx, 0.0001), 1.0)
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
        if let exactClass = profiles.enumerated().first(where: {
            !used.contains($0.offset) && $0.element.classIndex == segment.classIndex
        }) {
            return (exactClass.offset, exactClass.element)
        }
        let label = normalisedLabel(segment.label)
        if let exactLabel = profiles.enumerated().first(where: {
            !used.contains($0.offset) && normalisedLabel($0.element.label) == label
        }) {
            return (exactLabel.offset, exactLabel.element)
        }
        // Single-food scans are the common calibration/testing case. If the top
        // object is dominant, a side label mismatch should not discard useful
        // silhouette geometry; labels are less stable than masks across view.
        if index == 0,
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
        let lower = max(0.8, min(priorBoundCm * 0.45, lateralBoundCm))
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

    /// Exponential moving average on the final per-food volume, keyed by label
    /// and persisted for the app session. Repeated scans of the same food
    /// converge to a stable value (removing the 20-30% capture-to-capture
    /// jitter from independently-segmented frames). A capture differing from the
    /// running estimate by more than `volumeResetBandFraction` is treated as a
    /// genuinely different food and resets the smoother, so distinct foods are
    /// never blended together. Masks cannot be pixel-aligned across separate
    /// guided captures, so smoothing is applied to the derived volume — the
    /// quantity that drives the reported weight.
    private func smoothedVolume(label: String, volumeCm3: Double) -> (volumeCm3: Double, samples: Int, applied: Bool) {
        let key = label.lowercased()
        let alpha = MonocularVolumeEstimator.volumeSmoothingAlpha
        if let prev = MonocularVolumeEstimator.volumeHistory[key], prev.samples > 0, prev.volumeCm3 > 0 {
            let jump = abs(volumeCm3 - prev.volumeCm3) / max(prev.volumeCm3, 0.0001)
            if jump > MonocularVolumeEstimator.volumeResetBandFraction {
                MonocularVolumeEstimator.volumeHistory[key] = VolumeSmoother(volumeCm3: volumeCm3, samples: 1)
                return (volumeCm3, 1, false)
            }
            let smoothed = prev.volumeCm3 * (1 - alpha) + volumeCm3 * alpha
            MonocularVolumeEstimator.volumeHistory[key] = VolumeSmoother(volumeCm3: smoothed, samples: prev.samples + 1)
            return (smoothed, prev.samples + 1, true)
        }
        MonocularVolumeEstimator.volumeHistory[key] = VolumeSmoother(volumeCm3: volumeCm3, samples: 1)
        return (volumeCm3, 1, false)
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
        let softenedFactor: Double
        switch scaleSource {
        case "arkit_plane":
            // ARKit plane distance is metrically stable; trim only truly
            // implausible masks while preserving unusually large foods.
            softenedFactor = max(factor, 0.78)
        default:
            // AR plane/fallback scale at macro distances is noisier. Apply the
            // full physical clamp so a bad distance estimate cannot cube into a
            // kilogram tomato.
            softenedFactor = factor
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
        if l.contains("tomato") { return 0.915 }
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
        if l.contains("tomato") { return PhysicalEnvelope(maxLateralCm: 10.0, maxHeightCm: 8.0, maxVolumeCm3: 420.0) }
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

    /// Build the estimated 3-D mesh for one food by extruding its actual
    /// segmentation silhouette into a domed height field, rather than a
    /// generic circle. The outline therefore matches the food the user sees.
    ///
    /// This is purely the *visual* geometry of a camera estimate — the volume
    /// and calorie numbers come from the prism formula in `estimate(...)` and
    /// are NOT derived from this mesh.
    /// Shrink-free Taubin smoothing. Turns the blocky exposed-voxel surface into
    /// a smoothly curved one so round food gets round edges, while the alternating
    /// positive (lambda) and negative (mu) passes cancel the volume shrink that a
    /// plain Laplacian smooth would cause. Vertices flagged `pinned` (the contact
    /// base on the table) never move, keeping the food grounded with a crisp
    /// footprint while the body and rim are rounded to follow the true silhouette.
    private func taubinSmooth(
        _ verts: inout [SIMD3<Float>],
        faces: [Int],
        iterations: Int,
        pinned: [Bool]
    ) {
        let n = verts.count
        guard n > 4, faces.count >= 3 else { return }
        var adjacency = [[Int]](repeating: [], count: n)
        var seen = [Set<Int>](repeating: [], count: n)
        @inline(__always) func link(_ a: Int, _ b: Int) {
            guard a != b, a >= 0, a < n, b >= 0, b < n else { return }
            if !seen[a].contains(b) {
                seen[a].insert(b)
                adjacency[a].append(b)
            }
        }
        var i = 0
        while i + 2 < faces.count {
            let a = faces[i], b = faces[i + 1], c = faces[i + 2]
            link(a, b); link(a, c)
            link(b, a); link(b, c)
            link(c, a); link(c, b)
            i += 3
        }
        let lambda: Float = 0.5
        let mu: Float = -0.53
        var scratch = verts
        @inline(__always) func pass(_ factor: Float) {
            for v in 0..<n {
                if v < pinned.count && pinned[v] {
                    scratch[v] = verts[v]
                    continue
                }
                let nb = adjacency[v]
                if nb.isEmpty {
                    scratch[v] = verts[v]
                    continue
                }
                var sum = SIMD3<Float>(repeating: 0)
                for j in nb { sum += verts[j] }
                let avg = sum / Float(nb.count)
                scratch[v] = verts[v] + (avg - verts[v]) * factor
            }
            swap(&verts, &scratch)
        }
        for _ in 0..<max(0, iterations) {
            pass(lambda)
            pass(mu)
        }
    }

    private func makeEstimatedObject(
        id: String,
        label: String,
        instanceIndex: Int,
        mask: [[UInt8]],
        footprint: Footprint,
        widthCm: Double,
        depthCm: Double,
        heightCm: Double,
        volumeCm3: Double,
        voxelCount: Int,
        topFrame: FrameCaptureService.CapturedFrame,
        maskWidth: Int,
        maskHeight: Int,
        sideProfile: SideProfile? = nil
    ) -> DepthFusion.Food3DObject {
        let centroid = footprint.centroid
        let rx = Float(max(widthCm, 2.0) / 200.0)   // half-width in metres
        let rz = Float(max(depthCm, 2.0) / 200.0)   // half-depth in metres
        let h  = Float(max(heightCm, 0.8) / 100.0)  // height in metres
        let offsetX = Float((centroid.col / Double(maskWidth)) - 0.5) * 0.28
        let offsetZ = Float((centroid.row / Double(maskHeight)) - 0.5) * 0.28

        // Downsample the silhouette to a bounded occupancy grid so the mesh
        // follows the food outline while keeping vertex counts small.
        let bboxW = max(1, footprint.maxCol - footprint.minCol + 1)
        let bboxH = max(1, footprint.maxRow - footprint.minRow + 1)
        // Higher silhouette sampling resolution = the reconstructed mesh tracks
        // the real top/side contour more tightly (finer rim, crisper outline)
        // for a more accurate 3D object. 100 cells gives a smooth, mask-faithful
        // outline (a round tomato reads round) while staying within a safe
        // vertex budget for the viewer/exporter. Volume math is unaffected.
        let maxCells = 100
        let step = max(1, Int((Double(max(bboxW, bboxH)) / Double(maxCells)).rounded(.up)))
        let gc = max(1, Int((Double(bboxW) / Double(step)).rounded(.up)))
        let gr = max(1, Int((Double(bboxH) / Double(step)).rounded(.up)))

        @inline(__always) func cell(_ r: Int, _ c: Int) -> Int { r * gc + c }

        // Majority occupancy of the underlying mask block per grid cell.
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
                        if mask[mr][mc] == 1 { onCount += 1 }
                    }
                }
                // Preserve the real top-view outline. Majority voting was too
                // aggressive on small/round foods and could shave off the mask
                // into a generic blob; 25% keeps legitimate silhouette edges
                // while the later close step handles tiny internal gaps.
                if total > 0 && onCount * 4 >= total { on[cell(r, c)] = true }
            }
        }
        // Guarantee at least one cell so the viewer always has geometry.
        if !on.contains(true) { on[cell(gr / 2, gc / 2)] = true }

        @inline(__always) func isOn(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < gr && c >= 0 && c < gc && on[cell(r, c)]
        }

        // Morphological close: fill single-cell pockets so a clustered item
        // (e.g. a banana bunch the segmenter split) reads as one continuous
        // surface instead of showing a hole or a gap straight down the middle.
        if gr > 2 && gc > 2 {
            var filled = on
            for r in 0..<gr {
                for c in 0..<gc where !on[cell(r, c)] {
                    let up = isOn(r - 1, c)
                    let down = isOn(r + 1, c)
                    let left = isOn(r, c - 1)
                    let right = isOn(r, c + 1)
                    let diagonal = isOn(r - 1, c - 1) ||
                        isOn(r - 1, c + 1) ||
                        isOn(r + 1, c - 1) ||
                        isOn(r + 1, c + 1)
                    if (up && down && (left || right || diagonal)) ||
                        (left && right && (up || down || diagonal)) {
                        filled[cell(r, c)] = true
                    }
                }
            }
            on = filled
        }

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
        @inline(__always) func smoothstep01(_ x: Float) -> Float {
            let t = max(0.0, min(1.0, x))
            return t * t * (3.0 - 2.0 * t)
        }
        let transverseStrength = transverseRoundnessStrength(for: label)

        // ── Exact-silhouette smooth surface (no voxels, no layers) ────────
        // We do NOT voxelize the body anymore. `cornerBounds` evaluates a
        // CONTINUOUS bottom/top height (fraction of full height) at any
        // silhouette corner, from the SIDE silhouette (side-profile bounds
        // along the matched axis, with transverse rounding for round foods) or,
        // without one, from the TOP silhouette's distance transform (a smooth
        // dome). Because the height is continuous — not snapped to 30 layers —
        // and the outline comes straight from the mask, the reconstructed mesh
        // matches the two captured silhouettes exactly: a round tomato comes
        // out round, never as stacked cubes or horizontal layers.
        @inline(__always) func cornerBounds(_ rr: Int, _ cc: Int) -> (bottom: Float, top: Float) {
            if let sideProfile, !sideProfile.normalizedHeights.isEmpty {
                let axisU = sideProfile.topAxis == .columns
                    ? Double(cc) / Double(max(gc, 1))
                    : Double(rr) / Double(max(gr, 1))
                let b = sideProfile.sampleBounds(axisU)
                var bottom = Float(b.bottom)
                var top = Float(b.top)
                if top <= bottom { return (0, max(0.02, Float(b.top))) }
                if transverseStrength > 0 {
                    let tCoord = sideProfile.topAxis == .columns ? Float(rr) : Float(cc)
                    let tCenter = sideProfile.topAxis == .columns ? cgR : cgC
                    let tExtent = sideProfile.topAxis == .columns ? Float(gr) : Float(gc)
                    let radius = tCoord >= tCenter ? max(0.5, tExtent - tCenter) : max(0.5, tCenter)
                    let tRho = min(1.0, abs(tCoord - tCenter) / radius)
                    let falloff = sqrt(max(0.0, 1.0 - tRho * tRho))
                    let mid = (bottom + top) * 0.5
                    let halfH = (top - bottom) * 0.5 * (1.0 - transverseStrength * (1.0 - falloff))
                    bottom = mid - halfH
                    top = mid + halfH
                }
                let lo = max(0, bottom)
                return (lo, max(lo + 0.001, top))
            }
            // No side silhouette: dome the top silhouette via its distance
            // transform (round) or a near-flat cap (box); base rests on plate.
            let nd = min(1.0, edgeDist[corner(rr, cc)] / maxEdgeDist)
            let topShape: Float = transverseStrength > 0 ? sqrt(nd) : smoothstep01(nd * 3.0)
            return (0, max(0.02, topShape))
        }

        @inline(__always) func cornerX(_ cc: Int) -> Float {
            offsetX + (Float(cc) / Float(gc) - 0.5) * 2.0 * rx
        }
        @inline(__always) func cornerZ(_ rr: Int) -> Float {
            offsetZ + (Float(rr) / Float(gr) - 0.5) * 2.0 * rz
        }

        var vertices: [SIMD3<Float>] = []
        var faces: [Int] = []
        // Weld vertices by position so shared corners collapse to one vertex.
        // The exporter then averages normals across them (creaseThreshold 0) for
        // smooth Gouraud shading instead of a faceted low-poly look. Safe here:
        // every vertex of a monocular object carries the same sampled colour.
        var vmap: [Int64: Int] = [:]
        @inline(__always) func vid(_ p: SIMD3<Float>) -> Int {
            // Exact 21-bit-per-axis packing (0.1 mm grid) — collision-free for
            // any food-scale coordinate, so distinct positions never merge.
            @inline(__always) func q(_ v: Float) -> Int64 {
                let scaled = Int64((v * 10000).rounded()) + 1_048_576
                return min(2_097_151, max(0, scaled))
            }
            let key = (q(p.x) << 42) | (q(p.y) << 21) | q(p.z)
            if let existing = vmap[key] { return existing }
            let idx = vertices.count
            vertices.append(p)
            vmap[key] = idx
            return idx
        }
        @inline(__always) func addQuad(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>,
            _ c: SIMD3<Float>, _ d: SIMD3<Float>
        ) {
            let ia = vid(a), ib = vid(b), ic = vid(c), id2 = vid(d)
            faces += [ia, ib, ic, ia, ic, id2]
        }

        // ── Emit the smooth solid directly from the silhouette ────────────
        // Cache a smooth top/bottom height (metres) at every silhouette corner,
        // then for each "on" cell add a smooth top cap, a smooth underside, and
        // a vertical wall ONLY where the cell borders empty space. The result
        // is a watertight body whose top-down outline is the exact mask and
        // whose surfaces vary smoothly — no stacked voxel layers, no cubes.
        let cornerCount = (gr + 1) * cornerCols
        var topYAt = [Float](repeating: 0, count: cornerCount)
        var botYAt = [Float](repeating: 0, count: cornerCount)
        for rr in 0...gr {
            for cc in 0...gc {
                let bnds = cornerBounds(rr, cc)
                let bottomM = bnds.bottom * h
                botYAt[corner(rr, cc)] = bottomM
                topYAt[corner(rr, cc)] = max(bottomM + 0.0005, bnds.top * h)
            }
        }
        @inline(__always) func topP(_ rr: Int, _ cc: Int) -> SIMD3<Float> {
            SIMD3<Float>(cornerX(cc), topYAt[corner(rr, cc)], cornerZ(rr))
        }
        @inline(__always) func botP(_ rr: Int, _ cc: Int) -> SIMD3<Float> {
            SIMD3<Float>(cornerX(cc), botYAt[corner(rr, cc)], cornerZ(rr))
        }
        for ri in 0..<gr {
            for ci in 0..<gc where on[cell(ri, ci)] {
                // Smooth top cap (outward normal up).
                addQuad(topP(ri, ci), topP(ri + 1, ci),
                        topP(ri + 1, ci + 1), topP(ri, ci + 1))
                // Smooth underside (outward normal down).
                addQuad(botP(ri, ci), botP(ri, ci + 1),
                        botP(ri + 1, ci + 1), botP(ri + 1, ci))
                // Silhouette walls — only on cells bordering empty space, so the
                // rim hugs the exact outline from underside to top cap.
                if !isOn(ri, ci + 1) {
                    addQuad(botP(ri + 1, ci + 1), botP(ri, ci + 1),
                            topP(ri, ci + 1), topP(ri + 1, ci + 1))
                }
                if !isOn(ri, ci - 1) {
                    addQuad(botP(ri, ci), botP(ri + 1, ci),
                            topP(ri + 1, ci), topP(ri, ci))
                }
                if !isOn(ri + 1, ci) {
                    addQuad(botP(ri + 1, ci), botP(ri + 1, ci + 1),
                            topP(ri + 1, ci + 1), topP(ri + 1, ci))
                }
                if !isOn(ri - 1, ci) {
                    addQuad(botP(ri, ci + 1), botP(ri, ci),
                            topP(ri, ci), topP(ri, ci + 1))
                }
            }
        }

        // Guarantee non-empty geometry so the viewer always has something.
        if faces.isEmpty {
            let x0 = cornerX(gc / 2), x1 = cornerX(gc / 2 + 1)
            let z0 = cornerZ(gr / 2), z1 = cornerZ(gr / 2 + 1)
            let y1 = max(0.005, h * 0.4)
            addQuad(SIMD3<Float>(x0, 0, z0), SIMD3<Float>(x1, 0, z0),
                    SIMD3<Float>(x1, y1, z0), SIMD3<Float>(x0, y1, z0))
            addQuad(SIMD3<Float>(x0, 0, z1), SIMD3<Float>(x0, y1, z1),
                    SIMD3<Float>(x1, y1, z1), SIMD3<Float>(x1, 0, z1))
            addQuad(SIMD3<Float>(x0, y1, z0), SIMD3<Float>(x0, y1, z1),
                    SIMD3<Float>(x1, y1, z1), SIMD3<Float>(x1, y1, z0))
        }

        // Round the surface so rounded food gets round edges. The silhouette
        // height field is already continuous, so a moderate Taubin pass turns
        // the dome + rim into a smooth organic body without shrinking it. The
        // contact base (vertices on the table plane) is pinned so the food
        // stays grounded with a crisp footprint.
        let basePin = max(Float(0.0006), h * 0.03)
        var pinnedBase = [Bool](repeating: false, count: vertices.count)
        for vi in 0..<vertices.count where vertices[vi].y <= basePin {
            pinnedBase[vi] = true
        }
        taubinSmooth(
            &vertices,
            faces: faces,
            iterations: 8,
            pinned: pinnedBase
        )

        let color = dominantColor(topFrame: topFrame, mask: mask, footprint: footprint, maskWidth: maskWidth, maskHeight: maskHeight)
        var colors: [UInt8] = []
        colors.reserveCapacity(vertices.count * 3)
        for _ in vertices {
            colors += color
        }

        return DepthFusion.Food3DObject(
            id: id,
            label: label,
            instanceIndex: instanceIndex,
            vertices: vertices,
            faces: faces,
            colors: colors,
            // No projected UVs: this is a synthetic local-space prism and the
            // monocular path exports without a texture source, so texturing is
            // a later step. Empty UVs make the exporter skip the texture path.
            uvs: [],
            voxelCount: voxelCount,
            volumeCm3: volumeCm3,
            // The hull is now Taubin-smoothed into a curved organic surface, so
            // average normals across shared vertices for soft shading instead of
            // preserving the old voxel creases that made it read as low-poly.
            preserveCreases: false
        )
    }

    /// Robust dominant colour of the food. Averages many in-mask pixels from
    /// the decoded top frame, rejecting specular highlights and deep shadows so
    /// a single glare/shadow pixel can't skew the whole mesh. This is what makes
    /// a tomato render red, a banana yellow and bread brown instead of a generic
    /// tint. Falls back to the centroid pixel, then a neutral beige.
    private func dominantColor(
        topFrame: FrameCaptureService.CapturedFrame,
        mask: [[UInt8]],
        footprint: Footprint,
        maskWidth: Int,
        maskHeight: Int
    ) -> [UInt8] {
        guard let buffer = Food3DTextureBaker.bgraCopy(of: topFrame.pixelBuffer) else {
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
                }
                mc += stride
            }
            mr += stride
        }
        // Keep only the central 5-95% luminance band so specular highlights and
        // cast shadows cannot wash out or darken the dominant hue, then take the
        // trimmed mean of that band as the representative food colour.
        if samples.count >= 8 {
            samples.sort { $0.lum < $1.lum }
            let lo = Int(Double(samples.count) * 0.05)
            let hi = max(lo + 1, Int(Double(samples.count) * 0.95))
            let band = samples[lo..<min(hi, samples.count)]
            var rSum = 0.0, gSum = 0.0, bSum = 0.0
            for s in band { rSum += s.r; gSum += s.g; bSum += s.b }
            let n = Double(band.count)
            return [
                UInt8(min(255.0, max(0.0, (rSum / n).rounded()))),
                UInt8(min(255.0, max(0.0, (gSum / n).rounded()))),
                UInt8(min(255.0, max(0.0, (bSum / n).rounded())))
            ]
        }
        return sampleColor(topFrame: topFrame, centroid: footprint.centroid, maskWidth: maskWidth, maskHeight: maskHeight)
    }

    private func sampleColor(
        topFrame: FrameCaptureService.CapturedFrame,
        centroid: (row: Double, col: Double),
        maskWidth: Int,
        maskHeight: Int
    ) -> [UInt8] {
        // ARKit capturedImage is planar YCbCr; decode to BGRA so we sample the
        // real food colour instead of hitting the grey/beige fallback.
        guard let buffer = Food3DTextureBaker.bgraCopy(of: topFrame.pixelBuffer) else {
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
