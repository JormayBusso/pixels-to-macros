import CoreML
import CoreVideo
import Foundation
import Vision

/// On-device YOLO11-seg (Ultralytics) instance-segmentation handler.
///
/// Why this exists
/// ----------------
/// The `upgraded` branch trains a YOLO*-seg model instead of dense SegFormer.
/// The Ultralytics Core ML export has **two raw outputs and no baked-in NMS**
/// (`nms=True` is not supported for segment export), so this class performs the
/// post-processing the model graph omits:
///   1. decode the `[1, 4+nc+32, 8400]` prediction tensor,
///   2. class-aware Non-Maximum Suppression,
///   3. assemble each instance mask from the `[1, 32, 160, 160]` prototypes,
///   4. rasterise every instance into a per-pixel mask at the **same grid the
///      rest of the pipeline already uses** (`FramePreprocessor` input size).
///
/// It deliberately produces the identical `SegmentationService.SegmentedObject`
/// contract, so `DepthFusion.assignLabels`, `MonocularVolumeEstimator`, the
/// food-presence gate and the 3-D exporter consume it **unchanged**. The "2-D
/// mask → 3-D volume" step Gemini asked about is therefore already solved by the
/// existing `DepthFusion` back-projection — no new 3-D maths required.
///
/// The class is model-agnostic: the class count and labels are read from the
/// model itself, so a COCO export and a FoodSeg export both work without code
/// changes.
final class YOLOSegmentationService {

    typealias SegmentedObject = SegmentationService.SegmentedObject

    enum YOLOSegmentationError: Error {
        case modelNotFound
        case unexpectedOutput
    }

    // MARK: – Tunables

    /// Minimum class confidence to keep a raw detection.
    private let confThreshold: Float = 0.15
    /// IoU above which a lower-scoring same-class box is suppressed.
    private let iouThreshold: Float = 0.45
    /// Sigmoid threshold that turns a mask logit into a solid pixel.
    private let maskThreshold: Float = 0.5
    /// Hard caps that bound CPU + RAM regardless of model output.
    private let maxPreNMS = 300
    private let maxObjects = 20
    private let protoCount = 32

    /// Compiled `.mlmodelc` resource names searched in the app bundle, in order.
    /// Add the FoodSeg-trained export as `FoodSegYolo.mlmodelc` to activate it.
    private static let resourceCandidates = [
        "FoodSegYolo", "yolo11s-seg", "yolo11n-seg", "yolo11m-seg", "yolov8s-seg",
    ]

    // MARK: – Model state

    private let modelLock = NSLock()
    private var model: VNCoreMLModel?
    private var labels: [Int: String] = [:]
    private var loadAttempted = false
    private(set) var loadedResource: String?

    /// `true` when a YOLO-seg model is bundled and successfully loaded. The
    /// pipeline uses this to pick the YOLO path and otherwise fall back to the
    /// dense SegFormer service, so the app keeps working until the food-trained
    /// model is added.
    var isAvailable: Bool {
        do {
            try ensureLoaded()
            return model != nil
        } catch {
            return false
        }
    }

    // MARK: – Loading

    private func ensureLoaded() throws {
        modelLock.lock()
        defer { modelLock.unlock() }
        if model != nil { return }
        if loadAttempted { throw YOLOSegmentationError.modelNotFound }
        loadAttempted = true

        var found: (url: URL, name: String)?
        for name in Self.resourceCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                found = (url, name)
                break
            }
        }
        guard let resource = found else { throw YOLOSegmentationError.modelNotFound }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Neural Engine + GPU + CPU
        let mlModel = try MLModel(contentsOf: resource.url, configuration: config)
        labels = Self.loadLabels(from: mlModel)
        model = try VNCoreMLModel(for: mlModel)
        loadedResource = resource.name
        print("[YOLOSeg] Loaded \(resource.name).mlmodelc with \(labels.count) labels")
    }

    private static func loadLabels(from model: MLModel) -> [Int: String] {
        // 1. Ultralytics embeds the class map in the model metadata.
        if let creator = model.modelDescription
            .metadata[.creatorDefinedKey] as? [String: String],
            let raw = creator["names"] {
            let parsed = parseNames(raw)
            if !parsed.isEmpty { return parsed }
        }
        // 2. Fall back to the bundled labels JSON (export convention).
        if let url = Bundle.main.url(
            forResource: "FoodSegmentationLabels", withExtension: "json"
        ),
            let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var map: [Int: String] = [:]
            for (key, value) in obj where Int(key) != nil {
                map[Int(key)!] = String(describing: value)
            }
            if !map.isEmpty { return map }
        }
        return [:]
    }

    /// Parse the Ultralytics `names` metadata, a Python-dict string such as
    /// `{0: 'person', 1: 'bicycle', ...}` (single or double quoted).
    private static func parseNames(_ raw: String) -> [Int: String] {
        var result: [Int: String] = [:]
        let pattern = #"(\d+)\s*:\s*['"]([^'"]*)['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = raw as NSString
        regex.enumerateMatches(
            in: raw, range: NSRange(location: 0, length: ns.length)
        ) { match, _, _ in
            guard let match = match, match.numberOfRanges == 3,
                let idx = Int(ns.substring(with: match.range(at: 1)))
            else { return }
            result[idx] = ns.substring(with: match.range(at: 2))
        }
        return result
    }

    // MARK: – Public inference

    /// Modern-concurrency entry point. The underlying Vision request is
    /// synchronous, so this simply runs it with cancellation support.
    func predict(_ pixelBuffer: CVPixelBuffer) async throws -> [SegmentedObject] {
        try Task.checkCancellation()
        return try segment(pixelBuffer: pixelBuffer)
    }

    /// Drop-in replacement for `SegmentationService.segment(pixelBuffer:)`.
    /// Returns instance masks rasterised at the input buffer's resolution
    /// (the pipeline feeds a square `modelInputWidth × modelInputHeight` frame).
    func segment(pixelBuffer: CVPixelBuffer) throws -> [SegmentedObject] {
        try ensureLoaded()
        guard let visionModel = model else { throw YOLOSegmentationError.modelNotFound }

        let targetW = CVPixelBufferGetWidth(pixelBuffer)
        let targetH = CVPixelBufferGetHeight(pixelBuffer)

        var detArray: MLMultiArray?
        var protoArray: MLMultiArray?
        var requestError: Error?

        autoreleasepool {
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error { requestError = error; return }
                guard let observations = request.results
                    as? [VNCoreMLFeatureValueObservation] else {
                    requestError = YOLOSegmentationError.unexpectedOutput
                    return
                }
                // Identify outputs by rank (names like `var_1328` change on every
                // re-export, so never hardcode them): rank-3 = predictions,
                // rank-4 = prototype masks.
                for observation in observations {
                    guard let array = observation.featureValue.multiArrayValue
                    else { continue }
                    switch array.shape.count {
                    case 3: detArray = array
                    case 4: protoArray = array
                    default: break
                    }
                }
            }
            // Input frame is square, so scaleFill is a uniform resize to the
            // model's 640² input — no aspect distortion.
            request.imageCropAndScaleOption = .scaleFill
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                try handler.perform([request])
            } catch {
                requestError = error
            }
        }

        if let requestError { throw requestError }
        guard let det = detArray, let proto = protoArray else {
            throw YOLOSegmentationError.unexpectedOutput
        }

        let detections = decode(det: det)
        let kept = nonMaxSuppression(detections)
        return rasterise(kept, proto: proto, targetW: targetW, targetH: targetH)
    }

    // MARK: – Decode

    private struct Detection {
        var x0: Float
        var y0: Float
        var x1: Float
        var y1: Float
        var score: Float
        var classIndex: Int
        var coeffs: [Float]
    }

    private func decode(det: MLMultiArray) -> [Detection] {
        let shape = det.shape.map { $0.intValue } // [1, C, A]
        guard shape.count == 3 else { return [] }
        let strides = det.strides.map { $0.intValue }
        let channels = shape[1]
        let anchors = shape[2]
        let numClasses = channels - 4 - protoCount
        guard numClasses > 0 else { return [] }

        let strideChannel = strides[1]
        let strideAnchor = strides[2]
        let read = Self.makeReader(det)
        let coeffBase = 4 + numClasses

        var detections: [Detection] = []
        detections.reserveCapacity(min(anchors, maxPreNMS))

        for a in 0..<anchors {
            let anchorOffset = a * strideAnchor
            // Class argmax (Ultralytics already applies sigmoid in-graph).
            var bestScore: Float = -.infinity
            var bestClass = 0
            for k in 0..<numClasses {
                let value = read((4 + k) * strideChannel + anchorOffset)
                if value > bestScore {
                    bestScore = value
                    bestClass = k
                }
            }
            if bestScore < confThreshold { continue }

            let cx = read(0 * strideChannel + anchorOffset)
            let cy = read(1 * strideChannel + anchorOffset)
            let w = read(2 * strideChannel + anchorOffset)
            let h = read(3 * strideChannel + anchorOffset)

            var coeffs = [Float](repeating: 0, count: protoCount)
            for k in 0..<protoCount {
                coeffs[k] = read((coeffBase + k) * strideChannel + anchorOffset)
            }

            detections.append(Detection(
                x0: cx - w / 2, y0: cy - h / 2,
                x1: cx + w / 2, y1: cy + h / 2,
                score: bestScore, classIndex: bestClass, coeffs: coeffs
            ))
        }

        if detections.count > maxPreNMS {
            detections.sort { $0.score > $1.score }
            detections.removeLast(detections.count - maxPreNMS)
        }
        return detections
    }

    // MARK: – NMS

    private func nonMaxSuppression(_ detections: [Detection]) -> [Detection] {
        let sorted = detections.sorted { $0.score > $1.score }
        var removed = [Bool](repeating: false, count: sorted.count)
        var kept: [Detection] = []
        for i in 0..<sorted.count {
            if removed[i] { continue }
            kept.append(sorted[i])
            if kept.count >= maxObjects { break }
            for j in (i + 1)..<sorted.count where !removed[j] {
                if sorted[j].classIndex == sorted[i].classIndex,
                    iou(sorted[i], sorted[j]) > iouThreshold {
                    removed[j] = true
                }
            }
        }
        return kept
    }

    private func iou(_ a: Detection, _ b: Detection) -> Float {
        let interW = max(0, min(a.x1, b.x1) - max(a.x0, b.x0))
        let interH = max(0, min(a.y1, b.y1) - max(a.y0, b.y0))
        let inter = interW * interH
        let areaA = max(0, a.x1 - a.x0) * max(0, a.y1 - a.y0)
        let areaB = max(0, b.x1 - b.x0) * max(0, b.y1 - b.y0)
        let union = areaA + areaB - inter
        return union > 0 ? inter / union : 0
    }

    // MARK: – Mask assembly

    private func rasterise(
        _ detections: [Detection],
        proto: MLMultiArray,
        targetW: Int,
        targetH: Int
    ) -> [SegmentedObject] {
        guard !detections.isEmpty else { return [] }
        let shape = proto.shape.map { $0.intValue } // [1, 32, ph, pw]
        guard shape.count == 4 else { return [] }
        let strides = proto.strides.map { $0.intValue }
        let protoChannels = min(shape[1], protoCount)
        let ph = shape[2]
        let pw = shape[3]
        guard ph > 0, pw > 0 else { return [] }
        let strideK = strides[1]
        let strideY = strides[2]
        let strideX = strides[3]
        let read = Self.makeReader(proto)

        // YOLO segmentation prototypes are at input/4 resolution, so the model
        // input square is pw*4 px. Both proto and target span that same square
        // FOV, so the box→proto and box→target scales below cancel the 640.
        let modelW = Float(pw * 4)
        let modelH = Float(ph * 4)
        let boxToProtoX = Float(pw) / modelW
        let boxToProtoY = Float(ph) / modelH
        let boxToTargetX = Float(targetW) / modelW
        let boxToTargetY = Float(targetH) / modelH
        let targetToProtoX = Float(pw) / Float(targetW)
        let targetToProtoY = Float(ph) / Float(targetH)

        var objects: [SegmentedObject] = []
        objects.reserveCapacity(detections.count)

        for detection in detections {
            autoreleasepool {
                // Proto-space bbox (only evaluate the mask inside the box).
                let py0 = clamp(Int((detection.y0 * boxToProtoY).rounded(.down)), 0, ph - 1)
                let py1 = clamp(Int((detection.y1 * boxToProtoY).rounded(.up)), py0 + 1, ph)
                let px0 = clamp(Int((detection.x0 * boxToProtoX).rounded(.down)), 0, pw - 1)
                let px1 = clamp(Int((detection.x1 * boxToProtoX).rounded(.up)), px0 + 1, pw)
                let bw = px1 - px0

                var protoLogits = [Float](repeating: 0, count: (py1 - py0) * bw)
                for y in py0..<py1 {
                    let rowBase = y * strideY
                    for x in px0..<px1 {
                        let base = rowBase + x * strideX
                        var logit: Float = 0
                        for c in 0..<protoChannels {
                            logit += detection.coeffs[c] * read(c * strideK + base)
                        }
                        protoLogits[(y - py0) * bw + (x - px0)] = logit
                    }
                }

                @inline(__always) func sampledLogit(protoY: Float, protoX: Float) -> Float {
                    let clampedY = min(max(protoY, Float(py0)), Float(py1 - 1))
                    let clampedX = min(max(protoX, Float(px0)), Float(px1 - 1))
                    let y0 = Int(floor(clampedY))
                    let x0 = Int(floor(clampedX))
                    let y1 = min(py1 - 1, y0 + 1)
                    let x1 = min(px1 - 1, x0 + 1)
                    let ty = clampedY - Float(y0)
                    let tx = clampedX - Float(x0)
                    let v00 = protoLogits[(y0 - py0) * bw + (x0 - px0)]
                    let v01 = protoLogits[(y0 - py0) * bw + (x1 - px0)]
                    let v10 = protoLogits[(y1 - py0) * bw + (x0 - px0)]
                    let v11 = protoLogits[(y1 - py0) * bw + (x1 - px0)]
                    let top = v00 * (1 - tx) + v01 * tx
                    let bottom = v10 * (1 - tx) + v11 * tx
                    return top * (1 - ty) + bottom * ty
                }

                // Target-space bbox, clipped to the frame.
                let ty0 = clamp(Int((detection.y0 * boxToTargetY).rounded(.down)), 0, targetH - 1)
                let ty1 = clamp(Int((detection.y1 * boxToTargetY).rounded(.up)), ty0 + 1, targetH)
                let tx0 = clamp(Int((detection.x0 * boxToTargetX).rounded(.down)), 0, targetW - 1)
                let tx1 = clamp(Int((detection.x1 * boxToTargetX).rounded(.up)), tx0 + 1, targetW)

                var mask = [[UInt8]](
                    repeating: [UInt8](repeating: 0, count: targetW),
                    count: targetH
                )
                var pixelCount = 0
                for r in ty0..<ty1 {
                    for c in tx0..<tx1 {
                        let protoY = (Float(r) + 0.5) * targetToProtoY
                        let protoX = (Float(c) + 0.5) * targetToProtoX
                        if Self.sigmoid(sampledLogit(protoY: protoY, protoX: protoX)) > maskThreshold {
                            mask[r][c] = 1
                            pixelCount += 1
                        }
                    }
                }

                guard pixelCount > 0 else { return }
                // Drop disconnected speckle: keep only mask components that are a
                // meaningful fraction of the dominant blob. This removes stray
                // proto-bleed pixels that YOLO's low-res prototypes scatter along
                // an edge WITHOUT low-pass smoothing the true silhouette (the
                // exact outline the 3-D hull is built from is preserved).
                guard let cleaned = Self.keepDominantComponents(
                    &mask, y0: ty0, y1: ty1, x0: tx0, x1: tx1
                ) else { return }
                pixelCount = cleaned.pixelCount
                let centroid = cleaned.centroid
                let label = labels[detection.classIndex] ?? "others"
                objects.append(SegmentedObject(
                    label: label,
                    classIndex: detection.classIndex,
                    mask: mask,
                    pixelCount: pixelCount,
                    centroid: centroid,
                    confidence: detection.score
                ))
            }
        }

        // Largest instance first: matches the dense-seg convention so the
        // pipeline's "segments[0] = largest" label-refinement logic holds, and
        // the bigger food wins any rare overlapping pixel in DepthFusion.
        objects.sort { $0.pixelCount > $1.pixelCount }
        return objects
    }

    // MARK: – Helpers

    /// Bounds-checked element reader that supports the float16/float32/double
    /// layouts Core ML emits, using the array's own strides.
    private static func makeReader(_ array: MLMultiArray) -> (Int) -> Float {
        let shape = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        var maxIndex = 1
        for dimension in 0..<shape.count {
            maxIndex += (shape[dimension] - 1) * strides[dimension]
        }
        switch array.dataType {
        case .float32:
            let pointer = array.dataPointer.assumingMemoryBound(to: Float32.self)
            return { index in (index >= 0 && index < maxIndex) ? pointer[index] : 0 }
        case .float16:
            let pointer = array.dataPointer.assumingMemoryBound(to: Float16.self)
            return { index in (index >= 0 && index < maxIndex) ? Float(pointer[index]) : 0 }
        case .double:
            let pointer = array.dataPointer.assumingMemoryBound(to: Double.self)
            return { index in (index >= 0 && index < maxIndex) ? Float(pointer[index]) : 0 }
        @unknown default:
            return { _ in 0 }
        }
    }

    private static func sigmoid(_ x: Float) -> Float {
        1 / (1 + expf(-x))
    }

    /// Remove disconnected speckle from an instance mask, keeping the dominant
    /// blob plus any component at least `minFraction` of its area (so a peanut
    /// pile keeps all its real lobes but stray edge pixels are dropped). Runs a
    /// 4-connected flood fill inside the detection bbox only. Returns the new
    /// pixel count and centroid, or nil if nothing survives. This is noise
    /// removal — it never low-passes or reshapes the true silhouette.
    private static func keepDominantComponents(
        _ mask: inout [[UInt8]],
        y0: Int, y1: Int, x0: Int, x1: Int,
        minFraction: Float = 0.06
    ) -> (pixelCount: Int, centroid: (row: Int, col: Int))? {
        let h = y1 - y0
        let w = x1 - x0
        guard h > 0, w > 0 else { return nil }
        var labelOf = [Int](repeating: 0, count: h * w) // 0 = unvisited/empty
        var componentSizes: [Int] = [0] // index 0 unused
        var stack: [(Int, Int)] = []
        var nextLabel = 0
        for r in y0..<y1 {
            for c in x0..<x1 {
                if mask[r][c] == 0 { continue }
                let li = (r - y0) * w + (c - x0)
                if labelOf[li] != 0 { continue }
                nextLabel += 1
                var size = 0
                stack.removeAll(keepingCapacity: true)
                stack.append((r, c))
                labelOf[li] = nextLabel
                while let (cr, cc) = stack.popLast() {
                    size += 1
                    for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nr = cr + dr, nc = cc + dc
                        if nr < y0 || nr >= y1 || nc < x0 || nc >= x1 { continue }
                        if mask[nr][nc] == 0 { continue }
                        let ni = (nr - y0) * w + (nc - x0)
                        if labelOf[ni] != 0 { continue }
                        labelOf[ni] = nextLabel
                        stack.append((nr, nc))
                    }
                }
                componentSizes.append(size)
            }
        }
        guard nextLabel > 0 else { return nil }
        let largest = componentSizes.max() ?? 0
        guard largest > 0 else { return nil }
        let minSize = Int(Float(largest) * minFraction)
        var keep = [Bool](repeating: false, count: nextLabel + 1)
        for lbl in 1...nextLabel {
            keep[lbl] = componentSizes[lbl] >= minSize
        }
        var pixelCount = 0, sumRow = 0, sumCol = 0
        for r in y0..<y1 {
            for c in x0..<x1 {
                if mask[r][c] == 0 { continue }
                let lbl = labelOf[(r - y0) * w + (c - x0)]
                if keep[lbl] {
                    pixelCount += 1
                    sumRow += r
                    sumCol += c
                } else {
                    mask[r][c] = 0
                }
            }
        }
        guard pixelCount > 0 else { return nil }
        return (pixelCount, (row: sumRow / pixelCount, col: sumCol / pixelCount))
    }

    private func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }
}
