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
///   • Scale priority: plate diameter → camera intrinsics at 30 cm.
///   • Geometry: top-mask footprint × class-specific height/shape prior.
///   • Mesh: generated dome/extrusion from the mask bounding box, suitable
///     for the viewer and for keeping volume/calorie math wired identically.
final class MonocularVolumeEstimator {

    struct Result {
        let json: String
        let modelPath: String
        let objects: [[String: Any]]
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
    private let guidedDistanceCm: Double = 30.0

    func estimate(
        segments: [SegmentationService.SegmentedObject],
        topFrame: FrameCaptureService.CapturedFrame,
        sideFrame: FrameCaptureService.CapturedFrame?,
        maskWidth: Int,
        maskHeight: Int
    ) throws -> Result {
        let scale = estimateScale(
            topFrame: topFrame,
            maskWidth: maskWidth,
            maskHeight: maskHeight
        )

        var objects: [DepthFusion.Food3DObject] = []
        var payload: [[String: Any]] = []
        var metadata: [[String: Any]] = []

        for (idx, seg) in segments.enumerated() {
            guard let footprint = footprintStats(seg.mask, maskWidth: maskWidth, maskHeight: maskHeight) else {
                continue
            }

            let prior = priors(for: seg.label)
            let areaCm2 = Double(seg.pixelCount) / max(scale.pixelsPerCm * scale.pixelsPerCm, 0.0001)
            let widthCm = Double(max(1, footprint.maxCol - footprint.minCol + 1)) / scale.pixelsPerCm
            let depthCm = Double(max(1, footprint.maxRow - footprint.minRow + 1)) / scale.pixelsPerCm
            // Conservative height bound: non-stacked plated food is rarely taller
            // than its narrower measured footprint, so clamp the class height prior
            // to that lateral extent. This only trims implausible over-estimates of
            // small items (e.g. a single grape carrying a 5 cm fruit prior) and never
            // inflates flat foods, keeping calorie estimates on the safe side.
            let lateralBoundCm = max(0.8, min(widthCm, depthCm))
            let heightCm = min(prior.heightCm, lateralBoundCm)
            let volumeCm3 = max(6.0, areaCm2 * heightCm * prior.shapeFactor)
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
                volumeCm3: volumeCm3,
                voxelCount: max(seg.pixelCount, Int(volumeCm3.rounded())),
                topFrame: topFrame,
                maskWidth: maskWidth,
                maskHeight: maskHeight
            )
            objects.append(object)

            let roundedVolume = round(volumeCm3 * 10) / 10
            let roundedConfidence = round(confidence * 1000) / 1000
            let row: [String: Any] = [
                "id": id,
                "label": seg.label,
                "volume_cm3": roundedVolume,
                "voxel_count": object.voxelCount,
                "pixel_count": seg.pixelCount,
                "confidence": roundedConfidence,
                "frames_used": sideFrame == nil ? 1 : 2,
                "scan_mode": "monocular_scale",
                "scale_source": scale.source,
                "estimated": true,
            ]
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
    }

    private func estimateScale(
        topFrame: FrameCaptureService.CapturedFrame,
        maskWidth: Int,
        maskHeight: Int
    ) -> ScaleEstimate {
        let plate = plateDetector.detect(in: topFrame.pixelBuffer)
        if plate.detected {
            // The preprocessor crops the plate to the model input. In mask
            // space, the plate spans most of the shorter dimension.
            let pxPerCm = Double(min(maskWidth, maskHeight)) / Double(PlateDetector.defaultDiameterCm)
            return ScaleEstimate(pixelsPerCm: max(pxPerCm, 1.0), source: "plate")
        }

        let imageWidth = CVPixelBufferGetWidth(topFrame.pixelBuffer)
        let cropWidthPx = max(1.0, Double(plate.rect.width) * Double(imageWidth))
        let fx = Double(topFrame.cameraIntrinsics.columns.0.x)
        if fx > 1 {
            // cm per full-image pixel at 30 cm = D / fx. Scale to mask pixels
            // through the crop width represented by the segmentation mask.
            let cmPerImagePx = guidedDistanceCm / fx
            let cmPerMaskPx = cmPerImagePx * cropWidthPx / Double(maskWidth)
            return ScaleEstimate(pixelsPerCm: max(1.0 / max(cmPerMaskPx, 0.0001), 1.0), source: "30cm_intrinsics")
        }

        // Last resort: assume the crop covers a default dinner plate.
        return ScaleEstimate(
            pixelsPerCm: max(Double(min(maskWidth, maskHeight)) / Double(PlateDetector.defaultDiameterCm), 1.0),
            source: "default_plate"
        )
    }

    private func confidenceForScale(
        _ scale: ScaleEstimate,
        segmentConfidence: Float,
        sideFrame: FrameCaptureService.CapturedFrame?
    ) -> Double {
        let scaleConfidence: Double
        switch scale.source {
        case "plate": scaleConfidence = 0.78
        case "30cm_intrinsics": scaleConfidence = 0.66
        default: scaleConfidence = 0.58
        }
        let sideBonus = sideFrame == nil ? 0.0 : 0.04
        return min(0.86, max(0.62, scaleConfidence * 0.65 + Double(segmentConfidence) * 0.35 + sideBonus))
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
        if l.contains("apple") || l.contains("orange") || l.contains("egg") { return (5.0, 0.58) }
        if l.contains("bread") || l.contains("toast") || l.contains("pizza") { return (2.2, 0.82) }
        if l.contains("chicken") || l.contains("beef") || l.contains("steak") || l.contains("fish") { return (2.8, 0.78) }
        if l.contains("soup") || l.contains("sauce") || l.contains("yogurt") { return (1.8, 0.90) }
        return (3.0, 0.70)
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
        maskHeight: Int
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
        let maxCells = 36
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
                if total > 0 && onCount * 2 >= total { on[cell(r, c)] = true }
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
                    var n = 0
                    if isOn(r - 1, c) { n += 1 }
                    if isOn(r + 1, c) { n += 1 }
                    if isOn(r, c - 1) { n += 1 }
                    if isOn(r, c + 1) { n += 1 }
                    if n >= 3 { filled[cell(r, c)] = true }
                }
            }
            on = filled
        }

        // Smooth dome as a shared-corner height field. Heights live on the
        // (gr+1)×(gc+1) lattice so neighbouring cells reuse identical corner
        // heights — the top surface is therefore continuous, with no stair-step
        // "cubes" between cells.
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
        var maxR2: Float = 0.5
        for rr in 0...gr {
            for cc in 0...gc where cornerCells(rr, cc) > 0 {
                let dr = Float(rr) - cgR, dc = Float(cc) - cgC
                let d2 = dr * dr + dc * dc
                if d2 > maxR2 { maxR2 = d2 }
            }
        }
        let maxR = sqrt(maxR2)
        var cornerH = [Float](repeating: 0, count: (gr + 1) * cornerCols)
        for rr in 0...gr {
            for cc in 0...gc {
                let n = cornerCells(rr, cc)
                if n == 0 { continue }
                let dr = Float(rr) - cgR, dc = Float(cc) - cgC
                let rho = min(1.0, sqrt(dr * dr + dc * dc) / maxR)
                // Spherical-cap profile → a rounded top instead of a cone tip.
                let dome = sqrt(max(0.0, 1.0 - rho * rho))
                // Corners on the silhouette edge taper toward the plate so the
                // rim rounds off rather than dropping as a vertical cliff.
                let edge: Float = n >= 4 ? 1.0 : Float(n) / 4.0
                cornerH[corner(rr, cc)] = max(0.0, h * dome * edge)
            }
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

        for r in 0..<gr {
            for c in 0..<gc where on[cell(r, c)] {
                let x0 = cornerX(c), x1 = cornerX(c + 1)
                let z0 = cornerZ(r), z1 = cornerZ(r + 1)
                let yTL = cornerH[corner(r, c)]
                let yTR = cornerH[corner(r, c + 1)]
                let yBL = cornerH[corner(r + 1, c)]
                let yBR = cornerH[corner(r + 1, c + 1)]

                // Top surface (shared corner heights → smooth & watertight).
                addQuad(
                    SIMD3<Float>(x0, yTL, z0), SIMD3<Float>(x0, yBL, z1),
                    SIMD3<Float>(x1, yBR, z1), SIMD3<Float>(x1, yTR, z0)
                )
                // Bottom face (normal -Y).
                addQuad(
                    SIMD3<Float>(x0, 0, z0), SIMD3<Float>(x1, 0, z0),
                    SIMD3<Float>(x1, 0, z1), SIMD3<Float>(x0, 0, z1)
                )
                // Skirt walls only on silhouette edges, meeting the rounded top.
                if !isOn(r - 1, c) {
                    addQuad(
                        SIMD3<Float>(x0, 0, z0), SIMD3<Float>(x0, yTL, z0),
                        SIMD3<Float>(x1, yTR, z0), SIMD3<Float>(x1, 0, z0)
                    )
                }
                if !isOn(r + 1, c) {
                    addQuad(
                        SIMD3<Float>(x1, 0, z1), SIMD3<Float>(x1, yBR, z1),
                        SIMD3<Float>(x0, yBL, z1), SIMD3<Float>(x0, 0, z1)
                    )
                }
                if !isOn(r, c - 1) {
                    addQuad(
                        SIMD3<Float>(x0, 0, z1), SIMD3<Float>(x0, yBL, z1),
                        SIMD3<Float>(x0, yTL, z0), SIMD3<Float>(x0, 0, z0)
                    )
                }
                if !isOn(r, c + 1) {
                    addQuad(
                        SIMD3<Float>(x1, 0, z0), SIMD3<Float>(x1, yTR, z0),
                        SIMD3<Float>(x1, yBR, z1), SIMD3<Float>(x1, 0, z1)
                    )
                }
            }
        }

        let color = sampleColor(topFrame: topFrame, centroid: centroid, maskWidth: maskWidth, maskHeight: maskHeight)
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
            volumeCm3: volumeCm3
        )
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
