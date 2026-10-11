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
///   • Scale priority: plate diameter → ARKit table distance → 22 cm fallback.
///   • Geometry: top-mask footprint × matched side-view silhouette profile.
///     Height ALWAYS comes from the side silhouette; there is no class prior,
///     default height or thickness floor. Missing side evidence requires retake.
///   • Mesh: source-pixel visual hull from real masks, suitable for
///     the viewer and for keeping volume/calorie math wired identically.
final class MonocularVolumeEstimator {

    struct PhotoCalibration {
        let topTransform: simd_float4x4
        let topIntrinsics: simd_float3x3
        let topWidth: Int
        let topHeight: Int
        let topCrop: CGRect
        let sideTransform: simd_float4x4
        let sideIntrinsics: simd_float3x3
        let sideWidth: Int
        let sideHeight: Int
        let sideCrop: CGRect
        let tableY: Float

        static func validPose(_ pose: simd_float4x4) -> Bool {
            let x = SIMD3(pose.columns.0.x, pose.columns.0.y, pose.columns.0.z)
            let y = SIMD3(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z)
            let z = SIMD3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
            return pose.columns.3.x.isFinite && pose.columns.3.y.isFinite && pose.columns.3.z.isFinite &&
                abs(simd_length(x) - 1) < 0.01 && abs(simd_length(y) - 1) < 0.01 &&
                abs(simd_length(z) - 1) < 0.01 && abs(simd_dot(x, y)) < 0.01 &&
                abs(simd_dot(y, z)) < 0.01 && simd_dot(simd_cross(x, y), z) > 0.99 &&
                abs(pose.columns.3.w - 1) < 0.01 &&
                abs(pose.columns.0.w) < 0.01 && abs(pose.columns.1.w) < 0.01 && abs(pose.columns.2.w) < 0.01
        }

        static func validImage(width: Int, height: Int, crop: CGRect, intrinsics: simd_float3x3) -> Bool {
            width > 0 && height > 0 && !crop.isNull && !crop.isInfinite &&
                crop.minX.isFinite && crop.minY.isFinite && crop.width.isFinite && crop.height.isFinite &&
                crop.minX >= 0 && crop.minY >= 0 && crop.maxX <= 1 && crop.maxY <= 1 &&
                crop.width > 0 && crop.height > 0 &&
                intrinsics.columns.0.x.isFinite && intrinsics.columns.1.y.isFinite &&
                intrinsics.columns.2.x.isFinite && intrinsics.columns.2.y.isFinite &&
                intrinsics.columns.0.x > 1 && intrinsics.columns.1.y > 1
        }

        func topWorld(row: Double, column: Double) -> SIMD3<Float>? {
            guard Self.validPose(topTransform),
                  Self.validImage(width: topWidth, height: topHeight, crop: topCrop, intrinsics: topIntrinsics),
                  row.isFinite, column.isFinite, row >= 0, row <= 1, column >= 0, column <= 1,
                  tableY.isFinite else { return nil }
            let u = Float(topCrop.minX + CGFloat(column) * topCrop.width) * Float(topWidth)
            let v = Float(topCrop.minY + CGFloat(row) * topCrop.height) * Float(topHeight)
            let fx = topIntrinsics.columns.0.x, fy = topIntrinsics.columns.1.y
            guard fx > 0, fy > 0 else { return nil }
            let ray = topTransform * SIMD4<Float>(
                (u - topIntrinsics.columns.2.x) / fx,
                -(v - topIntrinsics.columns.2.y) / fy, -1, 0)
            let origin = topTransform.columns.3
            guard ray.y.isFinite, ray.y < -0.05 else { return nil }
            let t = (tableY - origin.y) / ray.y
            guard t > 0, t.isFinite, t * simd_length(SIMD3(ray.x, ray.y, ray.z)) < 2 else { return nil }
            let world = SIMD3(origin.x + t * ray.x, tableY, origin.z + t * ray.z)
            return world.x.isFinite && world.z.isFinite ? world : nil
        }

        func sideUV(world: SIMD3<Float>) -> SIMD2<Float>? {
            guard Self.validPose(sideTransform),
                  Self.validImage(width: sideWidth, height: sideHeight, crop: sideCrop, intrinsics: sideIntrinsics) else { return nil }
            let k = sideIntrinsics
            guard let p = DepthFusion.projectToImage(
                world, worldToCamera: sideTransform.inverse,
                fx: k.columns.0.x, fy: k.columns.1.y,
                cx: k.columns.2.x, cy: k.columns.2.y),
                sideCrop.width > 0, sideCrop.height > 0 else { return nil }
            let u = (p.u / Float(sideWidth) - Float(sideCrop.minX)) / Float(sideCrop.width)
            let v = (p.v / Float(sideHeight) - Float(sideCrop.minY)) / Float(sideCrop.height)
            guard u.isFinite, v.isFinite else { return nil }
            return SIMD2(u, v)
        }

        func sideWorld(uv: SIMD2<Float>, through point: SIMD3<Float>) -> SIMD3<Float>? {
            guard Self.validPose(sideTransform),
                  Self.validImage(width: sideWidth, height: sideHeight, crop: sideCrop, intrinsics: sideIntrinsics),
                  uv.x.isFinite, uv.y.isFinite, uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1,
                  point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
            let k = sideIntrinsics
            guard k.columns.0.x > 0, k.columns.1.y > 0 else { return nil }
            let u = (Float(sideCrop.minX) + uv.x * Float(sideCrop.width)) * Float(sideWidth)
            let v = (Float(sideCrop.minY) + uv.y * Float(sideCrop.height)) * Float(sideHeight)
            let r = sideTransform * SIMD4<Float>(
                (u - k.columns.2.x) / k.columns.0.x,
                -(v - k.columns.2.y) / k.columns.1.y, -1, 0)
            let origin = SIMD3<Float>(sideTransform.columns.3.x, sideTransform.columns.3.y, sideTransform.columns.3.z)
            let normal = SIMD3<Float>(sideTransform.columns.2.x, 0, sideTransform.columns.2.z)
            let ray = SIMD3<Float>(r.x, r.y, r.z)
            let denominator = simd_dot(ray, normal)
            guard denominator.isFinite, abs(denominator) > 0.05 else { return nil }
            let t = simd_dot(point - origin, normal) / denominator
            guard t > 0, t.isFinite, t * simd_length(ray) < 2 else { return nil }
            let world = origin + ray * t
            return world.x.isFinite && world.y.isFinite && world.z.isFinite ? world : nil
        }

        func silhouetteHeight(mask: [[UInt8]], through point: SIMD3<Float>,
                              verticalUsesColumns: Bool) -> (heightCm: Double?, baseM: Float, reason: String) {
            let h = mask.count, w = mask.first?.count ?? 0
            guard h > 0, w > 0, mask.allSatisfy({ $0.count == w }) else {
                return (nil, 0, "invalid_side_mask")
            }
            var lower = Float.infinity, upper = -Float.infinity
            var samples = 0
            let horizontalCount = verticalUsesColumns ? h : w
            let verticalCount = verticalUsesColumns ? w : h
            for horizontal in 0..<horizontalCount {
                var lo: Int?, hi: Int?
                for vertical in 0..<verticalCount {
                    let value = verticalUsesColumns ? mask[horizontal][vertical] : mask[vertical][horizontal]
                    if value != 0 { if lo == nil { lo = vertical }; hi = vertical }
                }
                guard let lo, let hi else { continue }
                // Occupied column endpoints, not the bounding box's empty centre.
                for edge in [lo, hi + 1] {
                    let uv = verticalUsesColumns
                        ? SIMD2(Float(edge) / Float(w), (Float(horizontal) + 0.5) / Float(h))
                        : SIMD2((Float(horizontal) + 0.5) / Float(w), Float(edge) / Float(h))
                    guard let world = sideWorld(uv: uv, through: point) else {
                        return (nil, 0, "side_endpoint_ray_invalid")
                    }
                    lower = min(lower, world.y); upper = max(upper, world.y)
                    samples += 1
                }
            }
            let height = Double(upper - lower) * 100
            guard samples > 0, height.isFinite, height > 0 else {
                return (nil, 0, "nonpositive_or_nonfinite_ray_height")
            }
            return (height, lower - tableY, "side_pose_ray")
        }
    }

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
        /// True when a LARGER vertical mask index is HIGHER above the table
        /// (upside-down hold). Default false: portrait/landscape holds put the
        /// table at the larger vertical index.
        var verticalIndexIncreasesUp = false
        /// The exact side-mask piece (mask grid = side preprocessed frame) this
        /// profile was extracted from. Side colour is sampled ONLY inside it.
        var sourceMask: [[UInt8]] = []
        /// Index of the TOP segment this side silhouette was matched to
        /// (`ScanMaskGeometry.matchSideSegments`); nil = legacy label matching.
        var topSegmentIndex: Int? = nil
        var matchScore = 0.0
        /// How the side↔top pairing was decided (`SideMatchAssignment.reason`).
        var matchReason = "label"
        /// True when this top re-uses a side silhouette primarily matched to
        /// another top (occluded / position-nearest), never a prior.
        var sideShared = false
        var calibration: PhotoCalibration?
        var measuredHeightCm: Double?
        var sourceBaseHeightM: Float = 0
        var measurementProvenance = ""
        var calibrationFailure: String?

        func projectedUV(row: Double, column: Double, heightM: Float) -> SIMD2<Float>? {
            guard let calibration,
                  var world = calibration.topWorld(row: row, column: column) else { return nil }
            world.y += heightM + sourceBaseHeightM
            return calibration.sideUV(world: world)
        }

        var meanNormalizedHeight: Double {
            guard !normalizedHeights.isEmpty else { return 0 }
            return normalizedHeights.reduce(0, +) / Double(normalizedHeights.count)
        }

        func sample(_ u: Double) -> Double {
            guard !normalizedHeights.isEmpty else { return 0 }
            let clamped = reversed ? 1.0 - min(1.0, max(0.0, u)) : min(1.0, max(0.0, u))
            let index = min(normalizedHeights.count - 1, Int(clamped * Double(normalizedHeights.count)))
            return normalizedHeights[index]
        }

        func sampleBounds(_ u: Double) -> (bottom: Double, top: Double) {
            guard !normalizedBottoms.isEmpty,
                  normalizedBottoms.count == normalizedTops.count else {
                let h = sample(u)
                return (0.0, h)
            }
            let clamped = reversed ? 1.0 - min(1.0, max(0.0, u)) : min(1.0, max(0.0, u))
            let index = min(normalizedBottoms.count - 1, Int(clamped * Double(normalizedBottoms.count)))
            let bottom = normalizedBottoms[index]
            let top = normalizedTops[index]
            return (min(bottom, top), max(bottom, top))
        }

        func sourceUV(axisU: Double, heightFraction: Double) -> SIMD2<Float> {
            let horizontalT = reversed
                ? 1.0 - min(1.0, max(0.0, axisU))
                : min(1.0, max(0.0, axisU))
            let verticalT = min(1.0, max(0.0, heightFraction))
            let horizontal = textureHorizontalMin +
                (textureHorizontalMax - textureHorizontalMin) * horizontalT
            // In image/mask coordinates the visible bottom of the side
            // silhouette is the LARGER vertical index unless the hold flips it.
            let vertical = verticalIndexIncreasesUp
                ? textureVerticalMin + (textureVerticalMax - textureVerticalMin) * verticalT
                : textureVerticalMax - (textureVerticalMax - textureVerticalMin) * verticalT
            if textureHorizontalUsesRows {
                return SIMD2(Float(vertical), Float(horizontal))
            }
            return SIMD2(Float(horizontal), Float(vertical))
        }

        /// `sourceUV` snapped to the EXACT side-mask pixel it lands on, or to
        /// the nearest in-mask pixel when it falls just outside (thin tips,
        /// one-pixel boundary rounding). `uv` is (x = column, y = row)
        /// normalised to the side mask/frame. Returns the pixel-centre UV.
        func maskSnappedUV(
            _ uv: SIMD2<Float>,
            maxRadius: Int = 40
        ) -> (uv: SIMD2<Float>, inMask: Bool, found: Bool) {
            let h = sourceMask.count
            let w = sourceMask.first?.count ?? 0
            guard h > 0, w > 0 else { return (uv, false, false) }
            guard uv.x.isFinite, uv.y.isFinite, uv.x >= 0, uv.x < 1, uv.y >= 0, uv.y < 1 else {
                return (uv, false, false)
            }
            let column = Int(floor(Double(uv.x) * Double(w)))
            let row = Int(floor(Double(uv.y) * Double(h)))
            guard let hit = ScanMaskGeometry.nearestSetPixel(
                in: sourceMask, row: row, column: column, maxRadius: maxRadius
            ) else { return (uv, false, false) }
            let snapped = SIMD2<Float>(
                Float((Double(hit.column) + 0.5) / Double(w)),
                Float((Double(hit.row) + 0.5) / Double(h)))
            return (snapped, hit.row == row && hit.column == column, true)
        }
    }

    enum EstimateError: LocalizedError {
        case noObjects
        case exportFailed
        case jsonFailed
        /// No side silhouette for a food: its height cannot be measured and is
        /// never guessed. Surfaced to Dart as `SIDE_VIEW_REQUIRED`.
        case sideViewRequired(String)

        var errorDescription: String? {
            switch self {
            case .sideViewRequired:
                return InferencePipeline.PipelineError.sideViewRequiredMessage
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

    private struct EstimatedObject {
        let object: DepthFusion.Food3DObject
        let meshVolumeCm3: Double
        let hullVoxelVolumeCm3: Double
        let surfaceExtractionMode: String
        let topSilhouetteSnapVertices: Int
        let topSilhouetteEdgeSnapVertices: Int
    }

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
        tableDistanceCm: Double? = nil,
        preprocessingPlate: PlateDetector.PlateResult? = nil,
        captureProvenance: String? = nil
    ) throws -> Result {
        guard sideFrame != nil else {
            throw EstimateError.sideViewRequired("missing_side_capture")
        }
        if let failed = sideProfiles.first(where: { $0.calibrationFailure != nil }) {
            print("[HEIGHTMEASUREMENT] rejected reason=\(failed.calibrationFailure ?? "invalid_side_calibration") action=retake")
            throw EstimateError.sideViewRequired(failed.calibrationFailure ?? "invalid_side_calibration")
        }
        let scale = estimateScale(
            topFrame: topFrame,
            maskWidth: maskWidth,
            maskHeight: maskHeight,
            tableDistanceCm: tableDistanceCm,
            preprocessingPlate: preprocessingPlate
        )
        guard scale.pixelsPerCm.isFinite, scale.pixelsPerCm > 0 else {
            throw EstimateError.sideViewRequired(scale.fallbackReason ?? "invalid_calibration")
        }

        // Depth Anything V2 (gated, AGENTS.md §9) is only ever a RELATIVE top
        // surface relief. It is never a height or volume source.
        let depthGrid: MonoDepthService.DepthGrid? = {
            guard MonocularVolumeEstimator.useMetricDepthVolume
                    || MonocularVolumeEstimator.useDepthRelief,
                  let rgb = preprocessedRGB, monoDepth.isAvailable else { return nil }
            return autoreleasepool {
                monoDepth.depthGrid(pixelBuffer: rgb, targetW: maskWidth, targetH: maskHeight)
            }
        }()
        if depthGrid != nil { print("[MonocularEstimator] depth relief grid available (shape only, never height)") }

        var objects: [DepthFusion.Food3DObject] = []
        var payload: [[String: Any]] = []
        var metadata: [[String: Any]] = []
        var usedSideProfileIndices = Set<Int>()
        let totalSegmentPixels = segments.reduce(0) { $0 + $1.pixelCount }

        for (idx, seg) in segments.enumerated() {
            guard let footprint = footprintStats(seg.mask, maskWidth: maskWidth, maskHeight: maskHeight) else {
                print("[MonocularEstimator] top-footprint missing food#\(idx) \(seg.label): pixels=\(seg.pixelCount)")
                continue
            }
            let centroidCol = String(format: "%.1f", footprint.centroid.col)
            let centroidRow = String(format: "%.1f", footprint.centroid.row)
            print("[MonocularEstimator] top-footprint food#\(idx) \(seg.label): pixels=\(seg.pixelCount), bbox=\(footprint.maxCol - footprint.minCol + 1)x\(footprint.maxRow - footprint.minRow + 1), centroid=(\(centroidCol),\(centroidRow))")

            let rawAreaCm2 = Double(seg.pixelCount) / (scale.columnPixelsPerCm * scale.rowPixelsPerCm)
            let rawWidthCm = Double(max(1, footprint.maxCol - footprint.minCol + 1)) / scale.columnPixelsPerCm
            let rawDepthCm = Double(max(1, footprint.maxRow - footprint.minRow + 1)) / scale.rowPixelsPerCm
            let areaCm2 = rawAreaCm2
            let widthCm = rawWidthCm
            let depthCm = rawDepthCm

            // The matched side silhouette is the ONLY height source.
            let profileMatch = sideProfileMatch(
                for: seg,
                index: idx,
                in: sideProfiles,
                excluding: usedSideProfileIndices
            )
            let profile = sideFrame == nil ? nil : usableSideProfile(profileMatch?.profile, for: seg.label, mode: .monocular)
            let sideApplied = profile != nil
            guard sideApplied, profile?.topSegmentIndex == idx else {
                throw EstimateError.sideViewRequired("food#\(idx)_missing_independent_side_silhouette")
            }
            if sideApplied, let profileMatch { usedSideProfileIndices.insert(profileMatch.index) }

            let topAxisCm = profile?.topAxis == .columns ? widthCm : depthCm
            // Thickness comes straight from the measured side silhouette —
            // metric via the captured side pose when calibrated, else the side
            // aspect ratio × the matching top axis. No floor, cap or prior.
            let calibratedHeightCm = profile?.measuredHeightCm.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let heightSource = sideApplied
                ? (calibratedHeightCm != nil ? "side_pose_ray" : "side_aspect_x_top_axis")
                : "unmeasured"
            let heightCm = calibratedHeightCm ?? (profile?.aspectRatio ?? 0) * topAxisCm
            // Prism telemetry only (the display mesh is the volume source): the
            // measured side-silhouette fill, no shape-factor prior or guardrail.
            let rawVolumeCm3 = areaCm2 * heightCm * (profile?.meanNormalizedHeight ?? 0)
            let volumeCm3 = rawVolumeCm3
            let scanMode = sideApplied ? "monocular_visual_hull" : "monocular_top_only"
            let meshMode = "exact_silhouette"
            let debugInfo = String(
                format: "%@: side=%@ mesh=%@ scale=%@ %.1fpx/cm axis=%@%@ h=%.1fcm(%@) fill=%.2f ar=%.2f match=%@ vol=%.0fcm³",
                scanMode,
                sideApplied ? "exact" : "missing_volume_unmeasured",
                meshMode,
                scale.source,
                scale.pixelsPerCm,
                profile?.topAxis.rawValue ?? "none",
                profile?.reversed == true ? "R" : "",
                heightCm,
                heightSource,
                profile?.meanNormalizedHeight ?? 0,
                profile?.aspectRatio ?? 0,
                profile?.matchReason ?? "unmatched",
                volumeCm3
            )
            if let profile {
                print("[MonocularEstimator] visual-hull food#\(idx) \(seg.label): sideLabel=\(profile.label), sideMatch=top#\(profile.topSegmentIndex.map(String.init) ?? "label") reason=\(profile.matchReason) score=\(String(format: "%.2f", profile.matchScore)), heightSource=\(heightSource), measuredH=\(calibratedHeightCm.map { String(format: "%.2f", $0) } ?? "nil")cm, axisCm=\(String(format: "%.2f", topAxisCm)), axis=\(profile.topAxis.rawValue), reversed=\(profile.reversed), mesh=\(meshMode), ar=\(String(format: "%.2f", profile.aspectRatio)), height=\(String(format: "%.2f", heightCm))cm, fill=\(String(format: "%.2f", profile.meanNormalizedHeight)), vol=\(String(format: "%.1f", volumeCm3))cm3")
            }
            let id = "\(sanitised(seg.label))_\(idx)"
            // Depth-relief shaping (gated + fail-safe): a normalized per-pixel
            // top-surface relief from the metric depth, used ONLY to shape the
            // mesh top surface — the absolute height/scale stays from the
            // plate/side path. Skipped for low coverage or flat foods.
            var reliefValues: [[Float]]? = nil
            var reliefWeight: Float = 0
            if sideApplied, MonocularVolumeEstimator.useDepthRelief, let grid = depthGrid,
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
            let estimatedObject = try makeEstimatedObject(
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
                reliefGrid: reliefValues,
                reliefWeight: reliefWeight
            )
            let object = estimatedObject.object
            objects.append(object)

            // Hard contract: the user-visible mesh is the volume source. The
            // prism value is retained only as diagnostic telemetry so
            // calibration logs can explain differences.
            let finalVolumeCm3 = estimatedObject.meshVolumeCm3
            let densityEstimate = estimatedDensityGPerCm3(for: seg.label)
            let weightEstimateG = finalVolumeCm3 * densityEstimate
            let heightSamples = [0.0, 0.25, 0.5, 0.75, 1.0]
                .map { String(format: "%.2f", profile?.sample($0) ?? 0) }
                .joined(separator: ",")
            let sideProfileSummary = String(
                format: " sideProfile=%@ axis=%@%@ samples=%d heights=[%@] fill=%.2f ar=%.2f",
                sideApplied ? "applied" : "missing",
                profile?.topAxis.rawValue ?? "none",
                profile?.reversed == true ? "R" : "",
                profile?.normalizedHeights.count ?? 0,
                heightSamples,
                profile?.meanNormalizedHeight ?? 0,
                profile?.aspectRatio ?? 0
            )
            let diagnosticInfo = String(
                format: "%@ | footprint raw=%.1fcm² %.1fx%.1fcm height=%.2fcm rawVol=%.1fcm³ meshVol=%.1fcm³ hullCellVol=%.1fcm³ finalVol=%.1fcm³ density=%.2fg/cm³ weight=%.0fg sideApplied=%@%@",
                debugInfo,
                rawAreaCm2,
                rawWidthCm,
                rawDepthCm,
                heightCm,
                rawVolumeCm3,
                estimatedObject.meshVolumeCm3,
                estimatedObject.hullVoxelVolumeCm3,
                finalVolumeCm3,
                densityEstimate,
                weightEstimateG,
                sideApplied ? "true" : "false",
                sideProfileSummary
            )
            let confidence = confidenceForScale(scale, segmentConfidence: seg.confidence, sideFrame: sideFrame)

            let roundedVolume = finalVolumeCm3
            let roundedConfidence = round(confidence * 1000) / 1000
            // Component confidences so the diagnostics screen can explain WHY a
            // scan scored the way it did (scale vs segmentation vs silhouette).
            let scaleConfidence = scale.confidence
            let silhouetteConfidence = Double(profile?.confidence ?? 0)
            let lowConfidence = !sideApplied || roundedConfidence < 0.62 || scale.source == "intrinsic_default"
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
                "height_source": heightSource,
                "side_match_reason": profile?.matchReason ?? "unmatched",
                "side_match_shared": false,
                "raw_volume_cm3": round(rawVolumeCm3 * 10) / 10,
                "density_g_cm3": round(densityEstimate * 100) / 100,
                "weight_g": round(weightEstimateG),
                "volume_guardrail_applied": false,
                "side_view_applied": sideApplied,
                "volume_measured": sideApplied,
                "side_missing_reason": sideApplied ? "none" : (sideFrame == nil ? "missing_capture" : "unmatched_occluded_or_invalid_mask"),
                "fallback_used": !sideApplied,
                "temporal_smoothing_applied": false,
                "temporal_samples": 1,
                "pre_smoothing_volume_cm3": round(volumeCm3 * 10) / 10,
                "mesh_volume_cm3": estimatedObject.meshVolumeCm3,
                "hull_cell_volume_cm3": round(estimatedObject.hullVoxelVolumeCm3 * 10) / 10,
                "surface_extraction_mode": estimatedObject.surfaceExtractionMode,
                "top_silhouette_snap_vertices": estimatedObject.topSilhouetteSnapVertices,
                "top_silhouette_edge_snap_vertices": estimatedObject.topSilhouetteEdgeSnapVertices,
                "side_profile_samples": profile?.normalizedHeights.count ?? 0,
                "volume_source": "display_mesh",
                "needs_user_label": seg.needsUserLabel,
                "candidate_labels": seg.candidateLabels,
                "embedding": seg.embedding.map { Double($0) },
                "label_source": seg.labelSource ?? "recognizer",
            ]
            row["debug"] = diagnosticInfo
            let provenance = "\(captureProvenance ?? "capture_metadata_unavailable") \(scale.provenance) " +
                "topMask={\(ScanMaskGeometry.maskProvenance(seg.mask))} " +
                "side={\(profile?.measurementProvenance ?? "unmatched_or_missing")} " +
                "heightSource=\(heightSource) axisCm=\(topAxisCm) heightCm=\(heightCm) " +
                "aspectHeightCm=\((profile?.aspectRatio ?? 0) * topAxisCm) " +
                "meshVolumeCm3=\(finalVolumeCm3) hullCellVolumeCm3=\(estimatedObject.hullVoxelVolumeCm3) volumeSource=display_mesh"
            row["measurement_provenance"] = provenance
            print("[MEASUREMENT] food#\(idx) \(provenance)")
            // [EVAL] one line per food for known-weight calibration (#3).
            print("[EVAL] label=\(seg.label) conf=\(String(format: "%.2f", roundedConfidence)) footprint_cm2=\(String(format: "%.1f", areaCm2)) silhouette_px=\(String(format: "%.1f", heightCm * scale.pixelsPerCm)) height_cm=\(String(format: "%.2f", heightCm)) height_source=\(heightSource) raw_volume_cm3=\(String(format: "%.1f", rawVolumeCm3)) final_volume_cm3=\(String(format: "%.1f", roundedVolume)) density_g_cm3=\(String(format: "%.2f", densityEstimate)) density_source=label_prior weight_g=\(String(format: "%.0f", weightEstimateG)) mode=\(scanMode) scale=\(scale.source) px/cm=\(String(format: "%.2f", scale.pixelsPerCm)) side_applied=\(sideApplied) side_match=\(profile?.matchReason ?? "unmatched") fallback=\(!sideApplied)")
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
        //
        // Silhouette coverage for the atlas: the exporter masks each tile to the
        // food outline over a dominant-colour underlay so UVs that graze the
        // plate/table paste food colour, not grey/white background (the reported
        // bug). The top tile uses the union of the top segmentation masks; the
        // side tile uses a coverage grid reconstructed from the side profiles.
        let topCoverage = unionTopCoverage(
            segments: segments, maskWidth: maskWidth, maskHeight: maskHeight)
        let sideCoverage = sidePreprocessedRGB != nil
            ? sideCoverageGrid(profiles: sideProfiles)
            : nil
        guard let url = exporter.export(
            objects: objects,
            baseName: baseName,
            textureSource: preprocessedRGB,
            sideTextureSource: sidePreprocessedRGB,
            topCoverage: topCoverage,
            sideCoverage: sideCoverage
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

    // MARK: - Atlas silhouette coverage

    /// Union of every top segmentation mask, in mask (row-major, top-down)
    /// coordinates. The atlas top tile is masked to this so the baked top photo
    /// only shows through where the camera actually saw food; anywhere else the
    /// exporter's dominant-colour underlay shows instead of the plate/table.
    private func unionTopCoverage(
        segments: [SegmentationService.SegmentedObject],
        maskWidth: Int,
        maskHeight: Int
    ) -> [[UInt8]]? {
        guard maskWidth > 0, maskHeight > 0, !segments.isEmpty else { return nil }
        var union = [[UInt8]](
            repeating: [UInt8](repeating: 0, count: maskWidth), count: maskHeight)
        var any = false
        for seg in segments {
            let m = seg.mask
            for r in 0..<min(maskHeight, m.count) {
                let row = m[r]
                let cols = min(maskWidth, row.count)
                for c in 0..<cols where row[c] != 0 {
                    union[r][c] = 1
                    any = true
                }
            }
        }
        return any ? union : nil
    }

    /// Food-vs-background coverage grid for the atlas SIDE tile, in side-image
    /// (row-major, top-down) normalized space.
    ///
    /// Profiles from the pipeline carry the exact matched side-mask piece
    /// (`sourceMask`), which is used directly. Legacy profiles without it fall
    /// back to rebuilding the silhouette as the exact INVERSE of
    /// `InferencePipeline.makeSideProfile`:
    /// for each grid pixel we map its normalized (col,row) into the profile's
    /// horizontal/vertical axes, and mark it food when it lies inside that
    /// column's [bottom,top] band. Gaps between per-sample columns are the only
    /// approximation; the food outline itself is the captured one. Multiple
    /// profiles (multi-food side view) are unioned since they share one photo.
    private func sideCoverageGrid(
        profiles: [SideProfile],
        gridW: Int = 384,
        gridH: Int = 384
    ) -> [[UInt8]]? {
        let usable = profiles.filter {
            $0.normalizedBottoms.count >= 2 &&
            $0.normalizedBottoms.count == $0.normalizedTops.count &&
            $0.textureHorizontalMax > $0.textureHorizontalMin &&
            $0.textureVerticalMax > $0.textureVerticalMin
        }
        guard !usable.isEmpty, gridW > 0, gridH > 0 else { return nil }

        var grid = [[UInt8]](
            repeating: [UInt8](repeating: 0, count: gridW), count: gridH)
        var any = false

        // Preferred: the EXACT matched side-mask pieces (same side-frame grid as
        // the atlas side tile), resampled nearest-neighbour. No reconstruction.
        let exactMasks = usable.map(\.sourceMask).filter { !$0.isEmpty && !($0.first?.isEmpty ?? true) }
        if !exactMasks.isEmpty {
            for mask in exactMasks {
                let mh = mask.count
                let mw = mask.first?.count ?? 0
                for r in 0..<gridH {
                    let mr = min(mh - 1, r * mh / gridH)
                    let row = mask[mr]
                    for c in 0..<gridW {
                        let mc = min(mw - 1, c * mw / gridW)
                        if mc < row.count, row[mc] != 0 {
                            grid[r][c] = 1
                            any = true
                        }
                    }
                }
            }
            return any ? grid : nil
        }

        for r in 0..<gridH {
            // Row 0 = top of the side image, matching `CIImage(cvPixelBuffer:)`.
            let vImg = (Double(r) + 0.5) / Double(gridH)
            for c in 0..<gridW {
                let uImg = (Double(c) + 0.5) / Double(gridW)
                for p in usable {
                    // Map the image (col,row) to this profile's horizontal /
                    // vertical axes. `textureHorizontalUsesRows` mirrors
                    // makeSideProfile's `verticalUsesColumns`: when the height
                    // axis is image columns, the profile's horizontal axis is
                    // image rows (and vice versa).
                    let horizontalNorm = p.textureHorizontalUsesRows ? vImg : uImg
                    let verticalNorm = p.textureHorizontalUsesRows ? uImg : vImg
                    let hSpan = p.textureHorizontalMax - p.textureHorizontalMin
                    guard horizontalNorm >= p.textureHorizontalMin,
                          horizontalNorm <= p.textureHorizontalMax else { continue }
                    let hFrac = min(1.0, max(0.0, (horizontalNorm - p.textureHorizontalMin) / hSpan))
                    // Index the silhouette bounds directly in image order (NOT
                    // via `sampleBounds`, which applies `reversed` to align with
                    // the TOP axis — here we want raw image orientation).
                    let bounds = p.normalizedBottoms
                    let x = hFrac * Double(bounds.count - 1)
                    let i0 = Int(x.rounded(.down))
                    let i1 = min(bounds.count - 1, i0 + 1)
                    let t = x - Double(i0)
                    let bottom = p.normalizedBottoms[i0] * (1.0 - t) + p.normalizedBottoms[i1] * t
                    let top = p.normalizedTops[i0] * (1.0 - t) + p.normalizedTops[i1] * t
                    guard top > bottom else { continue }
                    // Bounds are fractions of the food's vertical extent measured
                    // from its bottom (0) to top (1). The extent spans
                    // [textureVerticalMin, textureVerticalMax] with the larger
                    // normalized coordinate at the silhouette bottom, so map both
                    // edges back into image vertical space.
                    let vSpan = p.textureVerticalMax - p.textureVerticalMin
                    let bottomEdge = p.verticalIndexIncreasesUp
                        ? p.textureVerticalMin + bottom * vSpan
                        : p.textureVerticalMax - bottom * vSpan
                    let topEdge = p.verticalIndexIncreasesUp
                        ? p.textureVerticalMin + top * vSpan
                        : p.textureVerticalMax - top * vSpan
                    if verticalNorm >= min(topEdge, bottomEdge), verticalNorm <= max(topEdge, bottomEdge) {
                        grid[r][c] = 1
                        any = true
                        break
                    }
                }
            }
        }
        return any ? grid : nil
    }

    // MARK: - Scale

    struct ScaleEstimate {
        let pixelsPerCm: Double
        let columnPixelsPerCm: Double
        let rowPixelsPerCm: Double
        let source: String
        let confidence: Double
        let fallbackReason: String?
        var provenance = ""
    }

    func estimateScale(
        topFrame: FrameCaptureService.CapturedFrame,
        maskWidth: Int,
        maskHeight: Int,
        tableDistanceCm: Double? = nil,
        preprocessingPlate: PlateDetector.PlateResult? = nil
    ) -> ScaleEstimate {
        let imageWidth = CVPixelBufferGetWidth(topFrame.pixelBuffer)
        // The segmentation mask is a square resize of this crop. A credible
        // detected plate provides an in-frame metric reference, whereas the
        // guided camera-distance fallback is only an estimate.
        let plate = preprocessingPlate ?? plateDetector.detect(in: topFrame.pixelBuffer)
        let cropWidthPx = Double(plate.rect.width) * Double(imageWidth)
        let cropHeightPx = Double(plate.rect.height) * Double(CVPixelBufferGetHeight(topFrame.pixelBuffer))
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
        //   MISSING  : explicit calibration failure requiring a retake
        //
        // Guided distance is an assumption, never a veto of a valid reference.
        let intrinsicGuidedPxPerCm: Double? = {
            guard PhotoCalibration.validImage(width: imageWidth,
                height: CVPixelBufferGetHeight(topFrame.pixelBuffer), crop: plate.rect,
                intrinsics: topFrame.cameraIntrinsics) else { return nil }
            let cmPerImagePx = guidedDistanceCm / fx
            let cmPerMaskPx = cmPerImagePx * cropWidthPx / Double(maskWidth)
            let value = 1.0 / cmPerMaskPx
            return value.isFinite && value > 0 ? value : nil
        }()

        func selected(pixelsPerCm: Double, source: String, confidence: Double, fallbackReason: String?,
                      rowPixelsPerCm: Double? = nil) -> ScaleEstimate {
            let planePxPerCm = tableDistanceCm.flatMap { distance -> Double? in
                guard fx.isFinite, fx > 1, distance.isFinite, distance > 5, distance < 100 else { return nil }
                let value = source == "arkit_plane" ? pixelsPerCm :
                    fx * Double(maskWidth) / (distance * cropWidthPx)
                return value.isFinite && value > 0 ? value : nil
            }
            func candidate(_ value: Double?, available: Bool) -> String {
                guard let value else { return available ? "invalid_or_out_of_range" : "unavailable" }
                return "pxPerCm=\(value),gate=accepted"
            }
            let rowScale = rowPixelsPerCm ?? pixelsPerCm * cropWidthPx / cropHeightPx *
                Double(maskHeight) / Double(maskWidth)
            var result = ScaleEstimate(pixelsPerCm: sqrt(pixelsPerCm * rowScale),
                                       columnPixelsPerCm: pixelsPerCm, rowPixelsPerCm: rowScale, source: source,
                                       confidence: confidence, fallbackReason: fallbackReason)
            result.provenance = "scaleSource=\(source) scaleFallback=\(fallbackReason ?? "none") pxPerCm=\(result.pixelsPerCm) " +
                "scaleActualCropTL=\(plate.rect.minX),\(plate.rect.minY),\(plate.rect.width),\(plate.rect.height) " +
                "scaleCropWidthPx=\(cropWidthPx) mask=\(maskWidth)x\(maskHeight) fx=\(fx) " +
                "columnPixelsPerCm=\(pixelsPerCm) rowPixelsPerCm=\(rowScale) " +
                "assumedPlateDiameterCm=\(PlateDetector.defaultDiameterCm) detectedPlateDiameterPx=\(plate.diameterPx) " +
                "assumedGuidedDistanceCm=\(guidedDistanceCm) " +
                "plateCandidate={\(candidate(plateDiameterPxPerCm, available: plate.detected))} " +
                "planeCandidate={\(candidate(planePxPerCm, available: tableDistanceCm != nil))} " +
                "planeCandidateGeometry=\(source == "arkit_plane" ? "captured_ray_projection" : "distance_only_not_selected") " +
                "intrinsicGuidedPxPerCm=\(intrinsicGuidedPxPerCm.map(String.init(describing:)) ?? "nil") guidedDistanceIsAssumption=true cropSource=\(preprocessingPlate == nil ? "standalone_detection" : "preprocessing")"
            print("[ScaleValidation] \(result.provenance)")
            return result
        }

        let crop = plate.rect
        guard maskWidth > 0, maskHeight > 0,
              crop.minX.isFinite, crop.minY.isFinite, crop.width.isFinite, crop.height.isFinite,
              crop.minX >= 0, crop.minY >= 0, crop.maxX <= 1, crop.maxY <= 1,
              crop.width > 0, crop.height > 0 else {
            return selected(pixelsPerCm: .nan, source: "calibration_invalid", confidence: 0,
                            fallbackReason: "invalid_preprocessing_crop")
        }

        if let platePxPerCm = plateDiameterPxPerCm {
            logScaleValidation(chosenPxPerCm: platePxPerCm, plateDetected: true,
                               maskWidth: maskWidth, maskHeight: maskHeight, source: "plate_diameter")
            return selected(pixelsPerCm: platePxPerCm, source: "plate_diameter",
                            confidence: fx > 1 ? 0.86 : 0.80, fallbackReason: nil)
        }

        if let tableDistanceCm, tableDistanceCm.isFinite, fx.isFinite, fx > 1,
           tableDistanceCm > 5, tableDistanceCm < 100 {
            let calibration = PhotoCalibration(
                topTransform: topFrame.cameraTransform, topIntrinsics: topFrame.cameraIntrinsics,
                topWidth: imageWidth, topHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer), topCrop: crop,
                sideTransform: topFrame.cameraTransform, sideIntrinsics: topFrame.cameraIntrinsics,
                sideWidth: imageWidth, sideHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer), sideCrop: crop,
                tableY: topFrame.cameraTransform.columns.3.y - Float(tableDistanceCm / 100))
            guard let left = calibration.topWorld(row: 0.5, column: 0.5 - 0.5 / Double(maskWidth)),
                  let right = calibration.topWorld(row: 0.5, column: 0.5 + 0.5 / Double(maskWidth)),
                  let near = calibration.topWorld(row: 0.5 - 0.5 / Double(maskHeight), column: 0.5),
                  let far = calibration.topWorld(row: 0.5 + 0.5 / Double(maskHeight), column: 0.5) else {
                return selected(pixelsPerCm: .nan, source: "calibration_invalid", confidence: 0,
                                fallbackReason: "invalid_captured_plane_projection")
            }
            let pxPerCm = 1 / (Double(simd_distance(left, right)) * 100)
            let rowPxPerCm = 1 / (Double(simd_distance(near, far)) * 100)
            guard pxPerCm.isFinite, pxPerCm > 0, rowPxPerCm.isFinite, rowPxPerCm > 0 else {
                return selected(pixelsPerCm: .nan, source: "calibration_invalid", confidence: 0,
                                fallbackReason: "degenerate_plane_pixel_scale")
            }

            logScaleValidation(chosenPxPerCm: pxPerCm, plateDetected: plate.detected,
                               maskWidth: maskWidth, maskHeight: maskHeight, source: "arkit_plane")
            return selected(
                pixelsPerCm: pxPerCm,
                source: "arkit_plane",
                confidence: 0.82,
                fallbackReason: nil, rowPixelsPerCm: rowPxPerCm)
        }

        if let pxPerCm = intrinsicGuidedPxPerCm {
            logScaleValidation(chosenPxPerCm: pxPerCm, plateDetected: plate.detected,
                               maskWidth: maskWidth, maskHeight: maskHeight, source: "intrinsic_guided")
            return selected(
                pixelsPerCm: pxPerCm,
                source: "intrinsic_guided",
                confidence: 0.60,
                fallbackReason: tableDistanceCm == nil ? "no_arkit_plane" : "invalid_arkit_plane_distance",
                rowPixelsPerCm: Double(topFrame.cameraIntrinsics.columns.1.y) *
                    Double(maskHeight) / (guidedDistanceCm * cropHeightPx))
        }

        // No metric reference: retake, rather than silently inventing scale.
        return selected(
            pixelsPerCm: .nan,
            source: "calibration_invalid",
            confidence: 0,
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

    private func sideProfileMatch(
        for segment: SegmentationService.SegmentedObject,
        index: Int,
        in profiles: [SideProfile],
        excluding used: Set<Int>
    ) -> (index: Int, profile: SideProfile)? {
        guard !profiles.isEmpty else { return nil }
        // Geometric matching from the pipeline (`ScanMaskGeometry
        // .matchSideSegments`): each profile already names the TOP instance it
        // belongs to, so labels — which differ between views and after
        // refinement — are never needed.
        if profiles.contains(where: { $0.topSegmentIndex != nil }) {
            guard let matched = profiles.enumerated().first(where: {
                !used.contains($0.offset) && $0.element.topSegmentIndex == index
            }) else { return nil }
            return (matched.offset, matched.element)
        }
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

    enum SideProfileMode {
        case monocular
        case lidar
    }

    func usableSideProfile(_ profile: SideProfile?, for label: String, mode: SideProfileMode) -> SideProfile? {
        guard let profile, !profile.sideShared else { return nil }
        // Reject only geometrically unusable masks. A low segmentation
        // confidence never drops a real side silhouette (there is no prior to
        // fall back to — AGENTS.md §9).
        var rejectionReasons: [String] = []
        // LiDAR projects measured depth into the observed mask without using
        // the monocular section-height calibration.
        if mode == .monocular, let failure = profile.calibrationFailure { rejectionReasons.append(failure) }
        if profile.pixelCount <= 0 { rejectionReasons.append("empty_mask") }
        if mode == .monocular {
            let width = profile.sourceMask.first?.count ?? 0
            if width == 0 || !profile.sourceMask.allSatisfy({ $0.count == width }) ||
               !profile.sourceMask.contains(where: { $0.contains(where: { $0 != 0 }) }) {
                rejectionReasons.append("invalid_side_mask")
            }
            if !profile.aspectRatio.isFinite || profile.aspectRatio <= 0 { rejectionReasons.append("invalid_aspect") }
            if !profile.normalizedHeights.contains(where: { $0 > 0 }) { rejectionReasons.append("empty_profile") }
        } else {
            let width = profile.sourceMask.first?.count ?? 0
            if width == 0 || !profile.sourceMask.allSatisfy({ $0.count == width }) ||
               !profile.sourceMask.contains(where: { $0.contains(where: { $0 != 0 }) }) {
                rejectionReasons.append("invalid_side_mask")
            }
        }
        guard rejectionReasons.isEmpty else {
            print("[MonocularEstimator] side-profile rejected label=\(profile.label) reasons=\(rejectionReasons.joined(separator: ",")) px=\(profile.pixelCount) conf=\(String(format: "%.2f", profile.confidence)) cov=\(String(format: "%.3f", profile.coverage)) ar=\(String(format: "%.2f", profile.aspectRatio)) fill=\(String(format: "%.2f", profile.meanNormalizedHeight))")
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

    /// Primary-object telemetry. Strict estimation validates each assignment
    /// independently and requires retake for missing side evidence.
    func validateDualSilhouette(
        segments: [SegmentationService.SegmentedObject],
        sideProfiles: [SideProfile],
        mode: SideProfileMode
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
        guard let profile = usableSideProfile(match?.profile, for: primary.label, mode: mode) else {
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

    /// Legacy whole-mask reference, not the detected diameter used for selection.
    private func logScaleValidation(chosenPxPerCm: Double, plateDetected: Bool, maskWidth: Int, maskHeight: Int, source: String) {
        guard plateDetected else { return }
        let platePxPerCm = Double(min(maskWidth, maskHeight)) / Double(PlateDetector.defaultDiameterCm)
        let ratio = platePxPerCm / max(chosenPxPerCm, 0.0001)
        print("[ScaleValidation] source=\(source) chosen=\(String(format: "%.2f", chosenPxPerCm))px/cm wholeMaskDefaultPlateReference=\(String(format: "%.2f", platePxPerCm))px/cm ratio=\(String(format: "%.2f", ratio)) referenceOnly=true")
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

    private func normalisedLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Mask geometry

    struct SilhouetteHull {
        let vertices: [SIMD3<Float>]
        let faces: [Int]
        let cellCount: Int
        let cellVolumeCm3: Double
    }

    /// Orthographic, axis-aligned raster hull. The transverse view reuses the
    /// measured side profile with the same reversal (symmetry assumption).
    /// Partitioning at BOTH masks' pixel edges avoids touched-cell expansion
    /// and preserves every side interval, including holes. This is exact for
    /// the registered raster masks, not an exact reconstruction of hidden food.
    /// Grid overhang is zero; metric Float vertices are rounded at storage
    /// precision. Capture/segmentation/orthographic registration error is not
    /// bounded by this grid and still requires device validation.
    func silhouetteHull(
        mask: [[UInt8]], profile: SideProfile,
        widthCm: Double, depthCm: Double, heightCm: Double,
        offsetX: Float = 0, offsetZ: Float = 0,
        measuredCeilingCm: ((Int, Int) -> Double?)? = nil
    ) throws -> SilhouetteHull {
        let mw = mask.first?.count ?? 0
        let sw = profile.sourceMask.first?.count ?? 0
        func bounds(_ m: [[UInt8]]) -> (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)? {
            var r0 = m.count, r1 = -1, c0 = m.first?.count ?? 0, c1 = -1
            for r in m.indices {
                for c in m[r].indices where m[r][c] != 0 {
                    r0 = min(r0, r); r1 = max(r1, r); c0 = min(c0, c); c1 = max(c1, c)
                }
            }
            return r1 >= r0 && c1 >= c0 ? (r0, r1, c0, c1) : nil
        }
        guard mw > 0, mask.allSatisfy({ $0.count == mw }),
              sw > 0, profile.sourceMask.allSatisfy({ $0.count == sw }),
              !profile.sideShared, profile.calibrationFailure == nil,
              widthCm.isFinite, depthCm.isFinite, heightCm.isFinite,
              widthCm > 0, depthCm > 0, heightCm > 0,
              let topBounds = bounds(mask),
              let sideBounds = bounds(profile.sourceMask) else {
            throw EstimateError.sideViewRequired("empty_or_invalid_silhouette_support")
        }
        let tw = topBounds.maxCol - topBounds.minCol + 1
        let th = topBounds.maxRow - topBounds.minRow + 1
        let horizontalLo = profile.textureHorizontalUsesRows ? sideBounds.minRow : sideBounds.minCol
        let verticalLo = profile.textureHorizontalUsesRows ? sideBounds.minCol : sideBounds.minRow
        let horizontalCount = profile.textureHorizontalUsesRows
            ? sideBounds.maxRow - horizontalLo + 1 : sideBounds.maxCol - horizontalLo + 1
        let verticalCount = profile.textureHorizontalUsesRows
            ? sideBounds.maxCol - verticalLo + 1 : sideBounds.maxRow - verticalLo + 1

        func edges(_ topCount: Int) -> [Double] {
            // Each mapped side column must have its own cell even when it is
            // narrower than a top pixel. Endpoints are never snapped inward.
            let all = (0...topCount).map { Double($0) / Double(topCount) } +
                (0...horizontalCount).map { Double($0) / Double(horizontalCount) }
            var unique: [Double] = []
            for value in all.sorted() {
                if unique.last.map({ abs($0 - value) > 1e-12 }) ?? true { unique.append(value) }
            }
            return unique
        }
        let xs = edges(tw), zs = edges(th)
        let nx = xs.count - 1, nz = zs.count - 1
        var sideRuns = [[Range<Int>]](repeating: [], count: horizontalCount)
        for horizontal in 0..<horizontalCount {
            var start: Int?
            for y in 0...verticalCount {
                let vertical = profile.verticalIndexIncreasesUp
                    ? verticalLo + y : verticalLo + verticalCount - 1 - y
                let occupied: Bool
                if y == verticalCount { occupied = false }
                else if profile.textureHorizontalUsesRows {
                    occupied = profile.sourceMask[horizontalLo + horizontal][vertical] != 0
                } else {
                    occupied = profile.sourceMask[vertical][horizontalLo + horizontal] != 0
                }
                if occupied, start == nil { start = y }
                if !occupied, let lo = start {
                    sideRuns[horizontal].append(lo..<y)
                    start = nil
                }
            }
        }
        func sideColumn(_ u: Double) -> Int {
            let t = profile.reversed ? 1 - u : u
            return min(horizontalCount - 1, Int(t * Double(horizontalCount)))
        }
        func intersection(_ a: [Range<Int>], _ b: [Range<Int>]) -> [Range<Int>] {
            var result: [Range<Int>] = []
            var i = 0, j = 0
            while i < a.count, j < b.count {
                let lo = max(a[i].lowerBound, b[j].lowerBound)
                let hi = min(a[i].upperBound, b[j].upperBound)
                if lo < hi { result.append(lo..<hi) }
                if a[i].upperBound < b[j].upperBound { i += 1 } else { j += 1 }
            }
            return result
        }
        var columns = [[Range<Int>]](repeating: [], count: nx * nz)
        var cellCount = 0, cellVolume = 0.0
        for z in 0..<nz {
            let v = (zs[z] + zs[z + 1]) / 2
            let r = topBounds.minRow + min(th - 1, Int(v * Double(th)))
            for x in 0..<nx {
                let u = (xs[x] + xs[x + 1]) / 2
                let c = topBounds.minCol + min(tw - 1, Int(u * Double(tw)))
                guard mask[r][c] != 0 else { continue }
                let matched = profile.topAxis == .columns ? u : v
                let transverse = profile.topAxis == .columns ? v : u
                var runs = intersection(sideRuns[sideColumn(matched)], sideRuns[sideColumn(transverse)])
                if let ceiling = measuredCeilingCm?(r, c) {
                    guard ceiling.isFinite else {
                        throw EstimateError.sideViewRequired("invalid_measured_depth_ceiling")
                    }
                    let limit = max(0, min(verticalCount, Int(floor(ceiling / heightCm * Double(verticalCount)))))
                    runs = intersection(runs, [0..<limit])
                }
                columns[z * nx + x] = runs
                let layers = runs.reduce(0) { $0 + $1.count }
                cellCount += layers
                cellVolume += (xs[x + 1] - xs[x]) * widthCm *
                    (zs[z + 1] - zs[z]) * depthCm * heightCm *
                    Double(layers) / Double(verticalCount)
            }
        }
        guard cellCount > 0 else {
            throw EstimateError.sideViewRequired("empty_top_side_mirrored_intersection")
        }
        func occupied(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard x >= 0, x < nx, z >= 0, z < nz, y >= 0, y < verticalCount else { return false }
            return columns[z * nx + x].contains { $0.contains(y) }
        }

        struct GridPoint: Hashable { let x: Int; let y: Int; let z: Int }
        struct Edge: Hashable { let a: GridPoint; let b: GridPoint }
        struct HalfEdge { let a: Int; let b: Int; let owner: GridPoint }
        var points: [GridPoint] = []
        var quads: [[Int]] = []
        var boundaryEdges: [Edge: [HalfEdge]] = [:]
        func less(_ a: GridPoint, _ b: GridPoint) -> Bool {
            if a.x != b.x { return a.x < b.x }
            if a.y != b.y { return a.y < b.y }
            return a.z < b.z
        }
        func quad(_ corners: [GridPoint], owner: GridPoint) {
            let base = points.count
            points.append(contentsOf: corners)
            quads.append(Array(base..<base + 4))
            for i in 0..<4 {
                let j = (i + 1) % 4
                let a = corners[i], b = corners[j]
                let key = less(a, b) ? Edge(a: a, b: b) : Edge(a: b, b: a)
                boundaryEdges[key, default: []].append(HalfEdge(a: base + i, b: base + j, owner: owner))
            }
        }
        for z in 0..<nz {
            for x in 0..<nx {
                for run in columns[z * nx + x] {
                    let lo = run.lowerBound, hi = run.upperBound
                    quad([GridPoint(x: x, y: hi, z: z), GridPoint(x: x, y: hi, z: z + 1),
                          GridPoint(x: x + 1, y: hi, z: z + 1), GridPoint(x: x + 1, y: hi, z: z)],
                         owner: GridPoint(x: x, y: hi - 1, z: z))
                    quad([GridPoint(x: x, y: lo, z: z), GridPoint(x: x + 1, y: lo, z: z),
                          GridPoint(x: x + 1, y: lo, z: z + 1), GridPoint(x: x, y: lo, z: z + 1)],
                         owner: GridPoint(x: x, y: lo, z: z))
                    for y in run {
                        let p000 = GridPoint(x: x, y: y, z: z), p100 = GridPoint(x: x + 1, y: y, z: z)
                        let p010 = GridPoint(x: x, y: y + 1, z: z), p110 = GridPoint(x: x + 1, y: y + 1, z: z)
                        let p001 = GridPoint(x: x, y: y, z: z + 1), p101 = GridPoint(x: x + 1, y: y, z: z + 1)
                        let p011 = GridPoint(x: x, y: y + 1, z: z + 1), p111 = GridPoint(x: x + 1, y: y + 1, z: z + 1)
                        if !occupied(x - 1, y, z) { quad([p000, p001, p011, p010], owner: p000) }
                        if !occupied(x + 1, y, z) { quad([p100, p110, p111, p101], owner: p000) }
                        if !occupied(x, y, z - 1) { quad([p000, p010, p110, p100], owner: p000) }
                        if !occupied(x, y, z + 1) { quad([p001, p101, p111, p011], owner: p000) }
                    }
                }
            }
        }
        // Weld surface fans, not just equal positions: diagonal components
        // may touch at an edge/point without sharing a manifold surface.
        var parents = Array(points.indices)
        func root(_ i: Int) -> Int {
            var p = i
            while parents[p] != p { parents[p] = parents[parents[p]]; p = parents[p] }
            return p
        }
        func join(_ a: Int, _ b: Int) { parents[root(a)] = root(b) }
        func pair(_ a: HalfEdge, _ b: HalfEdge) throws {
            guard points[a.a] == points[b.b], points[a.b] == points[b.a] else {
                throw EstimateError.sideViewRequired("nonorientable_silhouette_boundary")
            }
            join(a.a, b.b); join(a.b, b.a)
        }
        for edges in boundaryEdges.values {
            if edges.count == 2 { try pair(edges[0], edges[1]) }
            else if edges.count == 4 {
                let groups = Dictionary(grouping: edges, by: { $0.owner })
                guard groups.count == 2, groups.values.allSatisfy({ $0.count == 2 }) else {
                    throw EstimateError.sideViewRequired("nonmanifold_silhouette_boundary")
                }
                for group in groups.values { try pair(group[0], group[1]) }
            } else {
                throw EstimateError.sideViewRequired("open_silhouette_boundary")
            }
        }
        var vertices: [SIMD3<Float>] = [], faces: [Int] = []
        var indices: [Int: Int] = [:]
        func vertex(_ i: Int) -> Int {
            let key = root(i)
            if let v = indices[key] { return v }
            let p = points[i], index = vertices.count
            indices[key] = index
            vertices.append(SIMD3(
                offsetX + Float((xs[p.x] - 0.5) * widthCm / 100),
                Float(Double(p.y) / Double(verticalCount) * heightCm / 100),
                offsetZ + Float((zs[p.z] - 0.5) * depthCm / 100)))
            return index
        }
        for q in quads {
            let a = vertex(q[0]), b = vertex(q[1]), c = vertex(q[2]), d = vertex(q[3])
            faces.append(contentsOf: [a, b, c, a, c, d])
        }
        let finiteFaces = stride(from: 0, to: faces.count, by: 3).allSatisfy { i in
            let a = vertices[faces[i]], b = vertices[faces[i + 1]], c = vertices[faces[i + 2]]
            return simd_length(simd_cross(b - a, c - a)) > 0
        }
        let volume = meshVolumeCm3(vertices: vertices, faces: faces)
        guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              finiteFaces, volume.isFinite, volume > 0 else {
            throw EstimateError.sideViewRequired("nonpositive_silhouette_mesh")
        }
        return SilhouetteHull(vertices: vertices, faces: faces, cellCount: cellCount, cellVolumeCm3: cellVolume)
    }

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
        guard maskWidth > 0, maskHeight > 0, mask.count == maskHeight,
              mask.allSatisfy({ $0.count == maskWidth }) else { return nil }
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

    /// Build the estimated 3-D mesh for one food from its captured silhouettes.
    /// The returned mesh is also the volume source, so the user sees the exact
    /// geometry that drives weight, calories and diagnostics.

    func sourceSilhouetteObject(
        id: String, label: String, instanceIndex: Int, mask: [[UInt8]],
        widthCm: Double, depthCm: Double, heightCm: Double,
        topFrame: FrameCaptureService.CapturedFrame,
        colorFrame: CVPixelBuffer?, sideColorFrame: CVPixelBuffer?,
        profile: SideProfile, measuredCeilingCm: ((Int, Int) -> Double?)? = nil
    ) throws -> DepthFusion.Food3DObject {
        let mw = mask.first?.count ?? 0
        guard let footprint = footprintStats(mask, maskWidth: mw, maskHeight: mask.count) else {
            throw EstimateError.sideViewRequired("empty_top_silhouette")
        }
        return try makeEstimatedObject(
            id: id, label: label, instanceIndex: instanceIndex, mask: mask, footprint: footprint,
            widthCm: widthCm, depthCm: depthCm, heightCm: heightCm,
            topFrame: topFrame, colorFrame: colorFrame, sideColorFrame: sideColorFrame,
            maskWidth: mw, maskHeight: mask.count, sideProfile: profile,
            measuredCeilingCm: measuredCeilingCm).object
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
        topFrame: FrameCaptureService.CapturedFrame,
        colorFrame: CVPixelBuffer?,
        sideColorFrame: CVPixelBuffer?,
        maskWidth: Int,
        maskHeight: Int,
        sideProfile: SideProfile? = nil,
        reliefGrid: [[Float]]? = nil,
        reliefWeight: Float = 0,
        measuredCeilingCm: ((Int, Int) -> Double?)? = nil
    ) throws -> EstimatedObject {
        let centroid = footprint.centroid
        let rx = Float(widthCm / 200.0)
        let rz = Float(depthCm / 200.0)
        let h = Float(heightCm / 100.0)
        let offsetX = Float((centroid.col / Double(maskWidth)) - 0.5) * 0.28
        let offsetZ = Float((centroid.row / Double(maskHeight)) - 0.5) * 0.28

        let bboxW = footprint.maxCol - footprint.minCol + 1
        let bboxH = footprint.maxRow - footprint.minRow + 1
        guard let geometryProfile = sideProfile else { throw EstimateError.sideViewRequired("missing_side_silhouette") }
        let hull = try silhouetteHull(mask: mask, profile: geometryProfile,
            widthCm: widthCm, depthCm: depthCm, heightCm: heightCm,
            offsetX: offsetX, offsetZ: offsetZ, measuredCeilingCm: measuredCeilingCm)
        let vertices = hull.vertices, faces = hull.faces
        let surfaceExtractionMode = "source_pixel_silhouette_boundary"
        let occupiedCellCount = hull.cellCount
        let hullVoxelVolumeCm3 = hull.cellVolumeCm3
        let topSilhouetteSnapVertices = 0, topSilhouetteEdgeSnapVertices = 0
        print("[DUALHULL] path=monocular food=\(label) mode=\(surfaceExtractionMode) cells=\(occupiedCellCount) vertices=\(vertices.count) faces=\(faces.count / 3) cellVolumeCm3=\(hullVoxelVolumeCm3) shapeAdded=false")

        @inline(__always) func maskPosition(for p: SIMD3<Float>) -> (row: Double, col: Double) {
            let colNorm = Double(((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5)
            let rowNorm = Double(((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5)
            return (
                Double(footprint.minRow) + rowNorm * Double(bboxH),
                Double(footprint.minCol) + colNorm * Double(bboxW)
            )
        }
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
        let resolvedVolumeCm3 = surfaceVolumeCm3.isFinite ? surfaceVolumeCm3 : 0
        // Seamless top-down photo projection: every vertex samples the real
        // captured TOP photo at the pixel directly above its footprint (x,z).
        // Because the vertices follow source-pixel boundaries the
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
        // Never stretch a full frame across crop-space mask coordinates.
        guard let sharedBGRA = colorFrame.flatMap({ Food3DTextureBaker.bgraCopy(of: $0) }) else {
            throw EstimateError.exportFailed
        }
        let sharedSideBGRA = sideColorFrame.flatMap { Food3DTextureBaker.bgraCopy(of: $0) }
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
            solidMask: mask,
            positions: vertexMaskPositions,
            heightFractions: vertices.map { Double(max(0, min(1, $0.y / max(h, 0.0001)))) },
            heightsM: vertices.map { $0.y },
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
            var atlasSideVerts = 0
            var atlasSideInMask = 0
            @inline(__always) func sideUV(_ p: SIMD3<Float>) -> SIMD2<Float> {
                guard let sp = sideProfile else { return topUV(p) }
                let colNorm = clamp01(((p.x - offsetX) / max(0.0001, 2.0 * rx)) + 0.5)
                let rowNorm = clamp01(((p.z - offsetZ) / max(0.0001, 2.0 * rz)) + 0.5)
                let axisU = sp.topAxis == .columns ? Double(colNorm) : Double(rowNorm)
                let hf = Double(clamp01(p.y / Float(max(h, 0.0001))))
                // `sourceUV` is (x = side-frame column, y = side-frame row); the
                // side tile is the side frame scaled WITHOUT rotation, exactly
                // like the top tile, so u follows x and v = 1 − row (same as
                // `topUV`). Snapped to the exact side-mask pixel when available.
                let pos = maskPosition(for: p)
                let raw = sp.calibration != nil
                    ? sp.projectedUV(row: pos.row / Double(maskHeight), column: pos.col / Double(maskWidth), heightM: p.y)
                    : sp.sourceUV(axisU: axisU, heightFraction: hf)
                guard let raw else { return topUV(p) }
                let snap = sp.sourceMask.isEmpty ? (uv: raw, inMask: false, found: false) : sp.maskSnappedUV(raw, maxRadius: 2)
                atlasSideVerts += 1
                if snap.inMask { atlasSideInMask += 1 }
                let uv = snap.found ? snap.uv : raw
                return SIMD2<Float>(clamp01(sideU0 + clamp01(uv.x) * (sideU1 - sideU0)),
                                    1.0 - clamp01(uv.y))
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
                        // Fall back to the segment's own dominant food colour
                        // (never a fixed grey `200`) when a per-vertex colour
                        // index runs past the sampled array, so an out-of-bounds
                        // vertex still reads as food, not institutional grey.
                        nc.append(cBase + k < colors.count
                            ? colors[cBase + k]
                            : (k < color.count ? color[k] : 200))
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
                if sideProfile != nil {
                    print("[SIDECOLOR] atlas food=\(label) sideVerts=\(atlasSideVerts) uvInMask=\(String(format: "%.0f", 100.0 * Double(atlasSideInMask) / Double(max(1, atlasSideVerts))))% sideTile=u[\(sideU0),\(sideU1)] uv=(col,1-row) unrotated")
                }
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
            // Shading normals may be shared; geometry is never smoothed.
            preserveCreases: true
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
        let p = vertices[0]
        let origin = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))

        var volumeM3 = 0.0
        var i = 0
        while i + 2 < faces.count {
            let ia = faces[i], ib = faces[i + 1], ic = faces[i + 2]
            if ia >= 0, ia < vertices.count,
               ib >= 0, ib < vertices.count,
               ic >= 0, ic < vertices.count {
                func relative(_ i: Int) -> SIMD3<Double> {
                    let v = vertices[i]
                    return SIMD3(Double(v.x), Double(v.y), Double(v.z)) - origin
                }
                let a = relative(ia), b = relative(ib), c = relative(ic)
                volumeM3 += simd_dot(a, simd_cross(b, c)) / 6.0
            }
            i += 3
        }
        return volumeM3 * 1_000_000.0
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
        heightsM: [Float],
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

        // Mask membership, not brightness, distinguishes food from background.
        @inline(__always) func topPixel(_ mr: Int, _ mc: Int) -> (Double, Double, Double)? {
            guard let (r, c) = nearestInMask(mr, mc) else { return nil }
            var rSum = 0.0, gSum = 0.0, bSum = 0.0, n = 0.0
            for dr in -1...1 {
                for dc in -1...1 {
                    let mrr = min(max(r + dr, 0), maskHeight - 1)
                    let mcc = min(max(c + dc, 0), maskWidth - 1)
                    guard solidMask[mrr][mcc] == 1 else { continue }
                    let x = min(max(Int(((Double(mcc) + 0.5) / Double(maskWidth)) * Double(w)), 0), w - 1)
                    let y = min(max(Int(((Double(mrr) + 0.5) / Double(maskHeight)) * Double(h)), 0), h - 1)
                    let off = y * rowBytes + x * 4
                    rSum += Double(ptr[off + 2]); gSum += Double(ptr[off + 1]); bSum += Double(ptr[off + 0]); n += 1
                }
            }
            guard n > 0 else { return nil }
            return (rSum / n, gSum / n, bSum / n)
        }

        // Exact side-photo colour at a side-frame UV (x = column, y = row,
        // normalised). 3×3 denoise restricted to the side mask when present.
        let sideMaskAvailable = !(sideProfile?.sourceMask.isEmpty ?? true)
        @inline(__always) func sideSample(_ uv: SIMD2<Float>, mask: [[UInt8]]?) -> (Double, Double, Double)? {
            guard let sidePtr, sideWidth > 0, sideHeight > 0 else { return nil }
            let cx = min(max(Int(floor(Double(uv.x) * Double(sideWidth))), 0), sideWidth - 1)
            let cy = min(max(Int(floor(Double(uv.y) * Double(sideHeight))), 0), sideHeight - 1)
            let mh = mask?.count ?? 0
            let mw = mask?.first?.count ?? 0
            var rSum = 0.0, gSum = 0.0, bSum = 0.0, n = 0.0
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(cx + dx, 0), sideWidth - 1)
                    let y = min(max(cy + dy, 0), sideHeight - 1)
                    if let mask, mh > 0, mw > 0 {
                        let mr = min(mh - 1, y * mh / sideHeight)
                        let mc = min(mw - 1, x * mw / sideWidth)
                        guard mc < mask[mr].count, mask[mr][mc] != 0 else { continue }
                    }
                    let off = y * sideRowBytes + x * 4
                    rSum += Double(sidePtr[off + 2]); gSum += Double(sidePtr[off + 1]); bSum += Double(sidePtr[off]); n += 1
                }
            }
            guard n > 0 else { return nil }
            return (rSum / n, gSum / n, bSum / n)
        }
        let baseMax = max(baseR, max(baseG, baseB)), baseMin = min(baseR, min(baseG, baseB))
        let baseIsNearWhite = baseMin > 175 && baseMax - baseMin < 40
        var sideVertexCount = 0
        var sideInMaskCount = 0
        var sideFallbackTopCount = 0
        var sideColoredCount = 0
        var sideSumR = 0.0, sideSumG = 0.0, sideSumB = 0.0

        for i in 0..<positions.count {
            let pos = positions[i]
            let mr = Int(pos.row.rounded())
            let mc = Int(pos.col.rounded())
            var sr = baseR, sg = baseG, sb = baseB
            let ny = i < normals.count ? normals[i].y : 1.0
            if ny < 0.45,
               ny > -0.35,
               let sideProfile,
               sidePtr != nil,
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
                let projected = sideProfile.projectedUV(
                    row: pos.row / Double(maskHeight), column: pos.col / Double(maskWidth),
                    heightM: i < heightsM.count ? heightsM[i] : 0)
                let uv = sideProfile.calibration != nil ? projected : sideProfile.sourceUV(
                    axisU: axisU, heightFraction: i < heightFractions.count ? heightFractions[i] : 0.5)
                sideVertexCount += 1
                // `uv` is (x = column, y = row) in the side frame. Snap it to
                // the exact side-mask pixel (or the nearest in-mask pixel) so a
                // side face only ever takes the food's own side-photo colour.
                let snap = uv.map {
                    sideMaskAvailable ? sideProfile.maskSnappedUV($0, maxRadius: 2)
                        : (uv: $0, inMask: false, found: true)
                } ?? (uv: SIMD2<Float>(0, 0), inMask: false, found: false)
                if snap.inMask { sideInMaskCount += 1 }
                var sidePixel: (Double, Double, Double)?
                if snap.found {
                    sidePixel = sideSample(snap.uv, mask: sideMaskAvailable ? sideProfile.sourceMask : nil)
                }
                if let px = sidePixel {
                    sr = px.0; sg = px.1; sb = px.2
                    sideSumR += sr; sideSumG += sg; sideSumB += sb
                    sideColoredCount += 1
                } else {
                    sideFallbackTopCount += 1
                    if let t = topPixel(mr, mc) { sr = t.0; sg = t.1; sb = t.2 }
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
        if sideProfile != nil {
            let pct = { (n: Int) -> String in
                String(format: "%.0f", 100.0 * Double(n) / Double(max(1, sideVertexCount)))
            }
            let avg = sideColoredCount > 0
                ? "rgb(\(Int(sideSumR / Double(sideColoredCount))),\(Int(sideSumG / Double(sideColoredCount))),\(Int(sideSumB / Double(sideColoredCount))))"
                : "none"
            print("[SIDECOLOR] path=monocular food=\(label) projection=\(sideProfile?.calibration == nil ? "uncalibrated_mask_bounds" : "captured_pose_intrinsics") sideVerts=\(sideVertexCount)/\(positions.count) inMask=\(pct(sideInMaskCount))% fallbackTop=\(pct(sideFallbackTopCount))% avgSide=\(avg) base=rgb(\(Int(baseR)),\(Int(baseG)),\(Int(baseB))) sideMask=\(sideMaskAvailable) sideFrame=\(sideWidth)x\(sideHeight) whiteFood=\(baseIsNearWhite)")
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
        if let pixel = samples.first {
            return [UInt8(pixel.r), UInt8(pixel.g), UInt8(pixel.b)]
        }
        return [210, 170, 120]
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
