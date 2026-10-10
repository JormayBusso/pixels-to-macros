import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// Open-vocabulary food recogniser (Apple MobileCLIP, free / pretrained).
///
/// Why this beats a fixed classifier
/// ---------------------------------
/// A Food-101 head can only ever name its 101 classes. MobileCLIP embeds the
/// crop into the same vector space as a set of **text** labels, so it can name
/// *any* food whose label was embedded once, offline. We precompute a text
/// embedding for every entry in the app's food vocabulary (`food_vocab.txt`)
/// and ship that table (`FoodLabelEmbeddings.json`); on device we only run the
/// lightweight **image encoder** and pick the nearest label by cosine
/// similarity. Adding a new food = adding a line to the vocab and re-exporting,
/// no retraining.
///
/// Memory policy mirrors `FoodClassifierService`: run once per scan over the
/// top instance crops, then `unload()` before the 3-D phase. Inert until the
/// `MobileCLIPImage.mlmodelc` + `FoodLabelEmbeddings.json` are bundled.
final class MobileCLIPService {

    enum CLIPError: Error {
        case modelNotFound
        case embeddingsNotFound
        case unexpectedOutput
    }

    struct Prediction {
        let label: String
        let confidence: Float
        let cosine: Float
    }

    /// Keep the encoder resident between scans (faster, more RAM). Default off.
    var keepLoaded = false

    private static let modelCandidates = [
        "MobileCLIPImage", "MobileCLIP", "FoodCLIPImage",
    ]
    private static let embeddingsCandidates = [
        "FoodLabelEmbeddings",
    ]

    private struct LabelEmbeddings {
        let labels: [String]
        let vectors: [[Float]] // each L2-normalised, length == dim
        let logitScale: Float
    }

    private let lock = NSLock()
    private var model: VNCoreMLModel?
    private var table: LabelEmbeddings?
    private var loadAttempted = false
    private(set) var loadedResource: String?

    /// `true` when both the image encoder and the label-embedding table are
    /// bundled and loadable.
    var isAvailable: Bool {
        do {
            try ensureLoaded()
            return model != nil && (table?.labels.isEmpty == false)
        } catch {
            return false
        }
    }

    // MARK: - Loading

    private func ensureLoaded() throws {
        lock.lock()
        defer { lock.unlock() }
        if model != nil, table != nil { return }
        if loadAttempted { throw CLIPError.modelNotFound }
        loadAttempted = true

        guard let table = Self.loadEmbeddings() else {
            throw CLIPError.embeddingsNotFound
        }

        var found: (url: URL, name: String)?
        for name in Self.modelCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                found = (url, name)
                break
            }
        }
        guard let resource = found else { throw CLIPError.modelNotFound }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let mlModel = try MLModel(contentsOf: resource.url, configuration: config)
        self.model = try VNCoreMLModel(for: mlModel)
        self.table = table
        loadedResource = resource.name
        print("[MobileCLIP] Loaded \(resource.name).mlmodelc + \(table.labels.count) label vectors")
    }

    /// Release the encoder; the (small) embedding table stays cached.
    func unload() {
        guard !keepLoaded else { return }
        lock.lock()
        defer { lock.unlock() }
        model = nil
        loadAttempted = false
    }

    private static func loadEmbeddings() -> LabelEmbeddings? {
        var url: URL?
        for name in embeddingsCandidates {
            if let u = Bundle.main.url(forResource: name, withExtension: "json") {
                url = u
                break
            }
        }
        guard let url,
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let labels = obj["labels"] as? [String],
              let rawVectors = obj["vectors"] as? [[Any]],
              labels.count == rawVectors.count,
              !labels.isEmpty
        else { return nil }

        let logitScale = (obj["logit_scale"] as? NSNumber)?.floatValue ?? 100.0
        var vectors: [[Float]] = []
        vectors.reserveCapacity(rawVectors.count)
        for row in rawVectors {
            var v = [Float]()
            v.reserveCapacity(row.count)
            for value in row {
                if let n = value as? NSNumber { v.append(n.floatValue) }
            }
            // Defensive re-normalisation so on-device cosine == dot product.
            var norm: Float = 0
            for x in v { norm += x * x }
            norm = norm.squareRoot()
            if norm > 0 { for i in 0..<v.count { v[i] /= norm } }
            vectors.append(v)
        }
        return LabelEmbeddings(labels: labels, vectors: vectors, logitScale: logitScale)
    }

    // MARK: - Classification

    func predict(
        _ pixelBuffer: CVPixelBuffer,
        in regionOfInterest: CGRect
    ) async throws -> (label: String, confidence: Float)? {
        try Task.checkCancellation()
        return try classify(pixelBuffer: pixelBuffer, regionOfInterest: regionOfInterest)
    }

    /// Embed a normalised sub-region of the frame and return the nearest food
    /// label by cosine similarity, with a softmax-over-labels confidence.
    func classify(
        pixelBuffer: CVPixelBuffer,
        regionOfInterest roi: CGRect
    ) throws -> (label: String, confidence: Float)? {
        guard let top = try classifyTopK(
            pixelBuffer: pixelBuffer,
            regionOfInterest: roi,
            limit: 1
        ).first else { return nil }
        return (top.label, top.confidence)
    }

    /// Return the top open-vocabulary candidates so the fusion layer can use
    /// the best-vs-runner-up margin instead of trusting a single softmax score.
    func classifyTopK(
        pixelBuffer: CVPixelBuffer,
        regionOfInterest roi: CGRect,
        limit: Int = 5
    ) throws -> [Prediction] {
        try ensureLoaded()
        guard let table else {
            throw CLIPError.modelNotFound
        }

        guard let vec = try imageEmbedding(
            pixelBuffer: pixelBuffer,
            regionOfInterest: roi
        ) else { return [] }

        return Self.nearestLabels(
            imageEmbedding: vec,
            table: table,
            limit: max(1, limit)
        )
    }

    private func imageEmbedding(
        pixelBuffer: CVPixelBuffer,
        regionOfInterest roi: CGRect
    ) throws -> [Float]? {
        guard let visionModel = model else { throw CLIPError.modelNotFound }

        var embedding: [Float]?
        var requestError: Error?

        autoreleasepool {
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error { requestError = error; return }
                if let array = (request.results as? [VNCoreMLFeatureValueObservation])?
                    .first?.featureValue.multiArrayValue {
                    embedding = Self.floats(from: array)
                    return
                }
                requestError = CLIPError.unexpectedOutput
            }
            request.regionOfInterest = roi
            request.imageCropAndScaleOption = .centerCrop
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                try handler.perform([request])
            } catch {
                requestError = error
            }
        }

        if let requestError { throw requestError }
        guard var vec = embedding, !vec.isEmpty else { return nil }

        // L2-normalise the image embedding so dot product == cosine.
        var norm: Float = 0
        for x in vec { norm += x * x }
        norm = norm.squareRoot()
        guard norm > 0 else { return nil }
        for i in 0..<vec.count { vec[i] /= norm }

        return vec
    }

    // MARK: - Helpers

    private static func nearestLabels(
        imageEmbedding vec: [Float],
        table: LabelEmbeddings,
        limit: Int
    ) -> [Prediction] {
        var scored: [(index: Int, cosine: Float)] = []
        scored.reserveCapacity(table.vectors.count)
        for (index, vector) in table.vectors.enumerated() {
            guard vector.count == vec.count else { continue }
            var dot: Float = 0
            for component in 0..<vec.count { dot += vec[component] * vector[component] }
            scored.append((index, dot))
        }
        scored.sort { $0.cosine > $1.cosine }
        guard let best = scored.first else { return [] }

        // Softmax over (cosine * logit_scale) for a calibrated confidence.
        let scale = table.logitScale
        let maxScaled = best.cosine * scale
        var sum: Float = 0
        for score in scored { sum += expf(score.cosine * scale - maxScaled) }
        return scored.prefix(limit).map { score in
            let confidence = sum > 0
                ? expf(score.cosine * scale - maxScaled) / sum
                : 0
            return Prediction(
                label: table.labels[score.index],
                confidence: confidence,
                cosine: score.cosine
            )
        }
    }

    private static func floats(from array: MLMultiArray) -> [Float] {
        let count = array.count
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        switch array.dataType {
        case .float32:
            let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<count { out[i] = ptr[i] }
        case .double:
            let ptr = array.dataPointer.assumingMemoryBound(to: Double.self)
            for i in 0..<count { out[i] = Float(ptr[i]) }
        default:
            for i in 0..<count { out[i] = array[i].floatValue }
        }
        return out
    }
}
