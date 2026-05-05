import CoreMedia
import CoreVideo
import Foundation
import MLKitImageLabeling
import MLKitVision
import UIKit

/// Cross-checks the bundled CoreML segmentation result against Google ML Kit's
/// generic Image Labeling model.
///
/// Why this exists
/// ───────────────
/// The bundled `FoodSegmentation.mlmodelc` is the 10-class FoodSeg103 mini model
/// (background + apple, rice, chicken, bread, salad, pasta, egg, fish, potato).
/// Because it has no real "is this food?" capability, every non-food scene is
/// force-classified into one of those 9 foods — that is the source of the
/// "I see chicken even though I'm pointing at a desk" hallucinations.
///
/// ML Kit's base on-device labeler ships with ~400 labels (Food, Fruit,
/// Vegetable, Bread, Salad, Pasta, Pizza, Cake, Tomato, Banana, …). We use it
/// for two jobs:
///
///   1. **Food-presence gate** — if no food-related label scores ≥ 0.50,
///      we treat the scan as "no food" and refuse to return any segmentation
///      output. This is the single biggest hallucination-killer.
///
///   2. **Label override hint** — if ML Kit returns a *specific* food label
///      (e.g. "Tomato", "Banana") with high confidence, the inference pipeline
///      can swap the (probably wrong) mini-model label for ML Kit's label
///      while keeping the segmentation mask + 3-D depth volume unchanged.
///
/// The labeler is loaded lazily on first use and cached.
final class MLKitFoodValidator {

    // MARK: – Result types

    struct ValidationResult {
        /// True if at least one food-related label scored above the gate
        /// threshold. When false, the inference pipeline should return
        /// `[]` (no food detected) regardless of segmentation output.
        let hasFood: Bool

        /// All ML Kit labels above the score threshold, sorted by confidence
        /// (highest first). Useful for label-override hints and debug logging.
        let labels: [LabeledHint]

        /// Single best specific-food label with high confidence, if any.
        /// Used by the inference pipeline to override low-trust segmentation
        /// labels.
        let bestSpecificFood: LabeledHint?

        /// Aggregate "this is food" confidence (max of all category-level
        /// food labels). Used for telemetry and confidence display.
        let foodConfidence: Float
    }

    struct LabeledHint {
        let text: String           // ML Kit raw label, e.g. "Tomato"
        let normalised: String     // lowercased, e.g. "tomato"
        let confidence: Float      // 0…1
        let isSpecificFood: Bool   // true for "Tomato", false for generic "Food"
    }

    // MARK: – Configuration

    /// Minimum confidence for a label to be considered at all.
    static let minLabelConfidence: Float = 0.30

    /// Minimum confidence for the food-presence gate to pass.
    /// Must be hit by *any* food-related label (category or specific).
    /// Kept at 0.40 because packaged food (e.g. bananas in a bag) often
    /// scores lower than unpackaged items.
    static let foodPresenceThreshold: Float = 0.40

    /// Minimum confidence for a specific food label to override the
    /// segmentation label. Lowered from 0.70 to catch more out-of-vocabulary
    /// foods that the mini model can't classify.
    static let specificOverrideThreshold: Float = 0.55

    // MARK: – Internal

    private var labeler: ImageLabeler?
    private let labelerLock = NSLock()

    /// Generic / category-level food keywords. Hitting any of these is enough
    /// to satisfy the food-presence gate but is NOT specific enough to be used
    /// as an override label.
    private static let foodCategoryKeywords: Set<String> = [
        "food", "dish", "meal", "cuisine", "recipe", "ingredient", "produce",
        "vegetable", "fruit", "meat", "seafood", "dessert", "bakery",
        "snack", "beverage", "drink", "breakfast", "lunch", "dinner",
        "junk food", "fast food", "finger food", "natural foods",
        "leaf vegetable", "root vegetable", "cruciferous vegetables",
        "superfood", "comfort food", "staple food", "whole food",
        "side dish", "main course"
    ]

    /// Specific food labels we trust enough to override segmentation output.
    /// Mapped to the canonical name we want to display in the app — kept
    /// lowercase to match `food_data.dart` lookups.
    ///
    /// We also include things ML Kit recognises that the mini model does NOT
    /// know about (e.g. tomato, cucumber, banana) — those are exactly the
    /// cases where today's pipeline mis-labels them as "chicken" or "fish".
    private static let specificFoodMap: [String: String] = [
        // Direct matches with the 10-class mini model
        "apple": "apple",
        "rice": "rice",
        "chicken": "chicken",
        "chicken meat": "chicken",
        "bread": "bread",
        "loaf": "bread",
        "baguette": "bread",
        "toast": "bread",
        "salad": "salad",
        "garden salad": "salad",
        "caesar salad": "salad",
        "pasta": "pasta",
        "spaghetti": "pasta",
        "noodle": "pasta",
        "noodles": "pasta",
        "egg": "egg",
        "fried egg": "egg",
        "boiled egg": "egg",
        "fish": "fish",
        "fish slice": "fish",
        "salmon": "fish",
        "tuna": "fish",
        "potato": "potato",
        "french fries": "potato",
        "mashed potato": "potato",
        // Common foods the mini model can't classify but ML Kit can — these
        // are the high-value overrides that stop "tomato → chicken" type
        // hallucinations.
        "tomato": "tomato",
        "cherry tomato": "tomato",
        "banana": "banana",
        "orange": "orange",
        "strawberry": "strawberry",
        "blueberry": "blueberry",
        "raspberry": "raspberry",
        "grape": "grape",
        "grapes": "grape",
        "lemon": "lemon",
        "lime": "lemon",
        "pear": "pear",
        "peach": "peach",
        "mango": "mango",
        "pineapple": "pineapple",
        "watermelon": "watermelon",
        "melon": "melon",
        "kiwi": "kiwi",
        "avocado": "avocado",
        "cucumber": "cucumber",
        "carrot": "carrot",
        "broccoli": "broccoli",
        "cauliflower": "cauliflower",
        "lettuce": "lettuce",
        "cabbage": "cabbage",
        "onion": "onion",
        "garlic": "garlic",
        "pepper": "pepper",
        "bell pepper": "pepper",
        "corn": "corn",
        "mushroom": "mushroom",
        "pizza": "pizza",
        "hamburger": "hamburg",
        "burger": "hamburg",
        "cheeseburger": "hamburg",
        "hot dog": "sausage",
        "sausage": "sausage",
        "steak": "steak",
        "beef": "steak",
        "pork": "pork",
        "lamb": "lamb",
        "shrimp": "shrimp",
        "prawn": "shrimp",
        "cake": "cake",
        "cupcake": "cake",
        "cookie": "biscuit",
        "biscuit": "biscuit",
        "donut": "biscuit",
        "ice cream": "ice cream",
        "chocolate": "chocolate",
        "candy": "candy",
        "popcorn": "popcorn",
        "pudding": "pudding",
        "wine": "wine",
        "milk": "milk",
        "milkshake": "milkshake",
        "coffee": "coffee",
        "espresso": "coffee",
        "tea": "tea",
        "juice": "juice",
        "tofu": "tofu",
        "almond": "almond",
        "peanut": "peanut",
        "walnut": "walnut",
        "cashew": "cashew",
    ]

    // MARK: – Public API

    /// Run ML Kit Image Labeling on the given pixel buffer.
    /// `imageOrientation` should match the original device orientation of the
    /// frame; the inference pipeline always feeds top-frame buffers in their
    /// natural capture orientation, so the default `.up` is correct.
    ///
    /// On any internal failure (model download missing, etc.) this returns a
    /// **permissive** result (`hasFood = true`, no labels) so we degrade
    /// gracefully back to segmentation-only behaviour rather than blocking
    /// every scan. The pipeline still has its own confidence gates after this.
    func validate(
        pixelBuffer: CVPixelBuffer,
        imageOrientation: UIImage.Orientation = .up
    ) -> ValidationResult {
        let labeler = obtainLabeler()
        guard let labeler else {
            return permissiveFallback(reason: "labeler unavailable")
        }

        // Convert pixel buffer → MLImage. ML Kit handles BGRA/420f natively.
        let visionImage = VisionImage(buffer: makeSampleBuffer(from: pixelBuffer))
        visionImage.orientation = imageOrientation

        var labels: [ImageLabel] = []
        let semaphore = DispatchSemaphore(value: 0)
        var labelError: Error?

        labeler.process(visionImage) { result, error in
            labels = result ?? []
            labelError = error
            semaphore.signal()
        }
        // ML Kit on-device inference is fast (<100 ms) but synchronous wait
        // here keeps the existing pipeline ordering. 1 s is a generous cap.
        _ = semaphore.wait(timeout: .now() + 1.0)

        if let labelError {
            print("[MLKitFoodValidator] labeling error: \(labelError)")
            return permissiveFallback(reason: "labeling error")
        }

        return interpret(labels: labels)
    }

    // MARK: – Interpretation

    private func interpret(labels: [ImageLabel]) -> ValidationResult {
        var hints: [LabeledHint] = []
        var foodConfidence: Float = 0
        var bestSpecific: LabeledHint?

        for label in labels {
            let conf = Float(label.confidence)
            guard conf >= MLKitFoodValidator.minLabelConfidence else { continue }
            let normalised = label.text.lowercased()

            let isCategory = MLKitFoodValidator.foodCategoryKeywords.contains(normalised)
            let canonicalSpecific = MLKitFoodValidator.specificFoodMap[normalised]
            let isSpecific = canonicalSpecific != nil

            guard isCategory || isSpecific else { continue }

            let hint = LabeledHint(
                text: label.text,
                normalised: canonicalSpecific ?? normalised,
                confidence: conf,
                isSpecificFood: isSpecific
            )
            hints.append(hint)

            if isCategory || isSpecific {
                foodConfidence = max(foodConfidence, conf)
            }

            if isSpecific && conf >= MLKitFoodValidator.specificOverrideThreshold {
                if bestSpecific == nil || conf > bestSpecific!.confidence {
                    bestSpecific = hint
                }
            }
        }

        let hasFood = foodConfidence >= MLKitFoodValidator.foodPresenceThreshold
        return ValidationResult(
            hasFood: hasFood,
            labels: hints.sorted { $0.confidence > $1.confidence },
            bestSpecificFood: bestSpecific,
            foodConfidence: foodConfidence
        )
    }

    private func permissiveFallback(reason: String) -> ValidationResult {
        print("[MLKitFoodValidator] degrading: \(reason) — bypassing food gate")
        return ValidationResult(
            hasFood: true,
            labels: [],
            bestSpecificFood: nil,
            foodConfidence: 0
        )
    }

    // MARK: – Labeler lifecycle

    private func obtainLabeler() -> ImageLabeler? {
        labelerLock.lock()
        defer { labelerLock.unlock() }
        if let labeler { return labeler }

        let options = ImageLabelerOptions()
        // The base on-device model is bundled with the SDK and ships ~400
        // labels including comprehensive food coverage. We deliberately do NOT
        // use the AutoML custom-model path so there is nothing to download or
        // host.
        options.confidenceThreshold = NSNumber(value: MLKitFoodValidator.minLabelConfidence)
        let l = ImageLabeler.imageLabeler(options: options)
        labeler = l
        return l
    }

    // MARK: – Pixel buffer → CMSampleBuffer

    /// VisionImage requires either a UIImage or CMSampleBuffer.  Our scan
    /// pipeline only has CVPixelBuffers, so we wrap one in an empty timing
    /// info CMSampleBuffer — ML Kit doesn't read the timestamps.
    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer {
        var info = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        var sampleBuffer: CMSampleBuffer?
        if let formatDescription {
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: formatDescription,
                sampleTiming: &info,
                sampleBufferOut: &sampleBuffer
            )
        }
        // Force-unwrap is safe in practice — both calls above only fail under
        // OOM, in which case the whole scan is dead anyway.
        return sampleBuffer!
    }
}
