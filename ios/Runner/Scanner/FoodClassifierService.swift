import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// Optional fine-grained food classifier for the "crop-and-classify" hybrid.
///
/// Architecture / memory policy
/// ----------------------------
/// A dedicated classifier (e.g. a Food-101 ViT) names food far more accurately
/// than whole-frame ML Kit labelling, but a ViT is heavy. To stay clear of
/// Jetsam on a 2-second sweep this service is designed to run **once per scan**:
///   * `InferencePipeline` calls it only on the locked top frame,
///   * only over the **top-K largest instance crops** (via `regionOfInterest`,
///     so Vision crops internally — no extra pixel-buffer allocation),
///   * and the model is **unloaded before the voxel/3-D phase** (the real
///     memory peak) unless `keepLoaded` is set.
///
/// It is gated on a bundled model, so the app runs unchanged until a classifier
/// `.mlmodelc` is added. Add the export as `FoodClassifier.mlmodelc`.
final class FoodClassifierService {

    enum ClassifierError: Error {
        case modelNotFound
        case unexpectedOutput
    }

    /// Keep the model resident between scans (faster, but ~hundreds of MB held
    /// during the depth-fusion phase). Default `false` = unload after each scan.
    var keepLoaded = false

    private static let resourceCandidates = [
        "FoodClassifier", "FoodViT", "nateraw_food", "food_vit",
    ]

    private let modelLock = NSLock()
    private var model: VNCoreMLModel?
    private var labels: [Int: String] = [:]
    private var loadAttempted = false
    private(set) var loadedResource: String?

    /// `true` when a classifier model is bundled and loadable.
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
        if loadAttempted { throw ClassifierError.modelNotFound }
        loadAttempted = true

        var found: (url: URL, name: String)?
        for name in Self.resourceCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                found = (url, name)
                break
            }
        }
        guard let resource = found else { throw ClassifierError.modelNotFound }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let mlModel = try MLModel(contentsOf: resource.url, configuration: config)
        labels = Self.loadLabels(from: mlModel)
        model = try VNCoreMLModel(for: mlModel)
        loadedResource = resource.name
        print("[FoodClassifier] Loaded \(resource.name).mlmodelc")
    }

    /// Release the model. Called after refinement so the heavy weights are not
    /// resident during the depth-fusion / 3-D export memory peak.
    func unload() {
        guard !keepLoaded else { return }
        modelLock.lock()
        defer { modelLock.unlock() }
        model = nil
        loadAttempted = false // allow a reload on the next scan
        labels = [:]
    }

    private static func loadLabels(from model: MLModel) -> [Int: String] {
        if let url = Bundle.main.url(
            forResource: "FoodClassifierLabels", withExtension: "json"
        ),
            let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var map: [Int: String] = [:]
            for (key, value) in obj where Int(key) != nil {
                map[Int(key)!] = String(describing: value)
            }
            return map
        }
        return [:]
    }

    // MARK: – Classification

    /// Modern-concurrency entry point.
    func predict(
        _ pixelBuffer: CVPixelBuffer,
        in regionOfInterest: CGRect
    ) async throws -> (label: String, confidence: Float)? {
        try Task.checkCancellation()
        return try classify(pixelBuffer: pixelBuffer, regionOfInterest: regionOfInterest)
    }

    /// Classify a normalised sub-region (Vision's bottom-left origin) of the
    /// frame. Returns the top-1 label + confidence, or `nil` if nothing scored.
    func classify(
        pixelBuffer: CVPixelBuffer,
        regionOfInterest roi: CGRect
    ) throws -> (label: String, confidence: Float)? {
        try ensureLoaded()
        guard let visionModel = model else { throw ClassifierError.modelNotFound }

        var result: (String, Float)?
        var requestError: Error?

        autoreleasepool {
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error { requestError = error; return }
                // Native Core ML classifier: Vision returns ranked labels.
                if let top = (request.results as? [VNClassificationObservation])?.first {
                    result = (Self.normalise(top.identifier), top.confidence)
                    return
                }
                // Raw logits fallback (model exported as image→MultiArray).
                if let logits = (request.results as? [VNCoreMLFeatureValueObservation])?
                    .first?.featureValue.multiArrayValue {
                    result = self.topLabel(from: logits)
                    return
                }
                requestError = ClassifierError.unexpectedOutput
            }
            // Vision crops to `roi` internally, then centre-crops to the model's
            // square input — no manual CGImage allocation needed.
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
        return result
    }

    // MARK: – Helpers

    private func topLabel(from logits: MLMultiArray) -> (String, Float)? {
        let count = logits.count
        guard count > 0 else { return nil }
        var maxLogit = -Float.greatestFiniteMagnitude
        var bestIndex = 0
        for i in 0..<count {
            let value = logits[i].floatValue
            if value > maxLogit {
                maxLogit = value
                bestIndex = i
            }
        }
        var sumExp: Float = 0
        for i in 0..<count {
            sumExp += expf(logits[i].floatValue - maxLogit)
        }
        let confidence = sumExp > 0 ? 1 / sumExp : 1
        let label = labels[bestIndex] ?? "food"
        return (Self.normalise(label), confidence)
    }

    /// Food-101 style identifiers use snake_case ("club_sandwich"); normalise to
    /// the lowercase, space-separated form the food database expects.
    private static func normalise(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
