import CoreML
import CoreVideo
import Foundation
import Vision

/// Runs semantic segmentation on a preprocessed frame using a CoreML model
/// (Part 6 — DeepLabV3 MobileNet or compatible).
///
/// Requirements:
///   - Pixel-level masks
///   - Multi-food detection
///   - Model < 30 MB
///   - Overlapping masks resolved by highest confidence → nearest centroid
final class SegmentationService {

    // MARK: – Types

    /// One segmented food region.
    struct SegmentedObject {
        let label: String
        let classIndex: Int
        /// Boolean mask: 1 = this object, 0 = background.
        /// Dimensions match the model output grid.
        let mask: [[UInt8]]
        /// Pixel count in the mask (used for area/volume).
        let pixelCount: Int
        /// Centroid (row, col) in mask coordinates.
        let centroid: (row: Int, col: Int)
        /// Average confidence for this class across its pixels.
        let confidence: Float
    }

    // MARK: – Model

    /// The compiled CoreML model. Loaded lazily on first inference.
    private var model: VNCoreMLModel?
    private let modelLock = NSLock()

    /// Label map — index 0 is background, 1–103 are FoodSeg103 classes.
    private(set) var labelMap: [Int: String] = [
        0:   "background",
        1:   "candy",
        2:   "egg tart",
        3:   "french fries",
        4:   "chocolate",
        5:   "biscuit",
        6:   "popcorn",
        7:   "pudding",
        8:   "ice cream",
        9:   "cheese butter",
        10:  "cake",
        11:  "wine",
        12:  "milkshake",
        13:  "coffee",
        14:  "juice",
        15:  "milk",
        16:  "tea",
        17:  "almond",
        18:  "red beans",
        19:  "cashew",
        20:  "dried cranberries",
        21:  "soy",
        22:  "walnut",
        23:  "peanut",
        24:  "egg",
        25:  "apple",
        26:  "date",
        27:  "apricot",
        28:  "avocado",
        29:  "banana",
        30:  "strawberry",
        31:  "cherry",
        32:  "blueberry",
        33:  "raspberry",
        34:  "mango",
        35:  "olives",
        36:  "peach",
        37:  "lemon",
        38:  "pear",
        39:  "fig",
        40:  "pineapple",
        41:  "grape",
        42:  "kiwi",
        43:  "melon",
        44:  "orange",
        45:  "watermelon",
        46:  "steak",
        47:  "pork",
        48:  "chicken duck",
        49:  "sausage",
        50:  "fried meat",
        51:  "lamb",
        52:  "sauce",
        53:  "crab",
        54:  "fish",
        55:  "shellfish",
        56:  "shrimp",
        57:  "bread",
        58:  "corn",
        59:  "hamburg",
        60:  "pizza",
        61:  "hanamaki baozi",
        62:  "wonton dumplings",
        63:  "taro",
        64:  "rice",
        65:  "tofu",
        66:  "eggplant",
        67:  "potato",
        68:  "garlic",
        69:  "cauliflower",
        70:  "tomato",
        71:  "kelp",
        72:  "seaweed",
        73:  "spring onion",
        74:  "rape",
        75:  "ginger",
        76:  "okra",
        77:  "lettuce",
        78:  "pumpkin",
        79:  "cucumber",
        80:  "white radish",
        81:  "carrot",
        82:  "asparagus",
        83:  "bamboo shoots",
        84:  "broccoli",
        85:  "celery stick",
        86:  "cilantro mint",
        87:  "snow peas",
        88:  "cabbage",
        89:  "bean sprouts",
        90:  "onion",
        91:  "pepper",
        92:  "green beans",
        93:  "french beans",
        94:  "king oyster mushroom",
        95:  "white mushroom",
        96:  "shiitake",
        97:  "enoki mushroom",
        98:  "oyster mushroom",
        99:  "black fungus",
        100: "dough",
        101: "noodles",
        102: "rice noodle",
        103: "others",
    ]

    // MARK: – Initialisation

    /// Load the CoreML model from the app bundle.
    /// Call once (e.g. at first inference). Thread-safe.
    func loadModel() throws {
        modelLock.lock()
        defer { modelLock.unlock() }

        guard model == nil else { return } // already loaded

        // Look for a compiled .mlmodelc in the bundle.
        // The actual file is added after training (Step 7 pipeline).
        guard let modelURL = Bundle.main.url(
            forResource: "FoodSegmentation",
            withExtension: "mlmodelc"
        ) else {
            throw SegmentationError.modelNotFound
        }

        let mlModel = try MLModel(contentsOf: modelURL, configuration: {
            let config = MLModelConfiguration()
            config.computeUnits = .all // ANE + GPU + CPU
            return config
        }())

        model = try VNCoreMLModel(for: mlModel)
    }

    // MARK: – Inference

    /// Run segmentation on a preprocessed pixel buffer.
    /// Returns one `SegmentedObject` per detected food class (background excluded).
    func segment(pixelBuffer: CVPixelBuffer) throws -> [SegmentedObject] {
        if model == nil { try loadModel() }

        guard let visionModel = model else {
            throw SegmentationError.modelNotLoaded
        }

        // Synchronous Vision request
        var results: [SegmentedObject] = []
        var inferenceError: Error?

        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let error {
                inferenceError = error
                return
            }
            guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
                  let multiArray = observations.first?.featureValue.multiArrayValue
            else {
                inferenceError = SegmentationError.unexpectedOutput
                return
            }
            results = self.parseSegmentationOutput(multiArray)
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        if let error = inferenceError { throw error }
        return results
    }

    // MARK: – Output parsing

    /// Parse the MLMultiArray argmax grid into per-class binary masks.
    ///
    /// The model outputs shape [1, numClasses, H, W] (softmax probabilities)
    /// or [1, H, W] (argmax class indices).
    private func parseSegmentationOutput(_ output: MLMultiArray) -> [SegmentedObject] {
        let shape = output.shape.map { $0.intValue }

        // Determine grid dimensions
        let (height, width, numClasses): (Int, Int, Int)
        if shape.count == 4 {
            // [1, C, H, W]
            numClasses = shape[1]
            height = shape[2]
            width = shape[3]
        } else if shape.count == 3 {
            // [1, H, W] — argmax indices
            numClasses = 0
            height = shape[1]
            width = shape[2]
        } else {
            return []
        }

        // Build class-index grid + confidence grid
        var classGrid = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var confGrid  = [[Float]](repeating: [Float](repeating: 0, count: width), count: height)

        let ptr = output.dataPointer.assumingMemoryBound(to: Float32.self)

        if numClasses > 0 {
            // Softmax output — argmax per pixel, resolve overlaps by confidence
            for r in 0..<height {
                for c in 0..<width {
                    var bestClass = 0
                    var bestConf: Float = -Float.infinity
                    for cls in 0..<numClasses {
                        let idx = cls * height * width + r * width + c
                        let val = ptr[idx]
                        if val > bestConf {
                            bestConf = val
                            bestClass = cls
                        }
                    }
                    classGrid[r][c] = bestClass
                    confGrid[r][c]  = bestConf
                }
            }
        } else {
            // Argmax indices directly
            for r in 0..<height {
                for c in 0..<width {
                    let idx = r * width + c
                    classGrid[r][c] = Int(ptr[idx])
                    confGrid[r][c]  = 1.0
                }
            }
        }

        // Group pixels by class
        var classPixels: [Int: [(row: Int, col: Int, conf: Float)]] = [:]
        for r in 0..<height {
            for c in 0..<width {
                let cls = classGrid[r][c]
                guard cls != 0 else { continue } // skip background
                classPixels[cls, default: []].append((r, c, confGrid[r][c]))
            }
        }

        // Build SegmentedObject per class
        var objects: [SegmentedObject] = []
        for (cls, pixels) in classPixels {
            var mask = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: height)
            var sumR = 0, sumC = 0
            var sumConf: Float = 0
            for p in pixels {
                mask[p.row][p.col] = 1
                sumR += p.row
                sumC += p.col
                sumConf += p.conf
            }
            let count = pixels.count
            let label = labelMap[cls] ?? "food_\(cls)"
            objects.append(SegmentedObject(
                label: label,
                classIndex: cls,
                mask: mask,
                pixelCount: count,
                centroid: (row: sumR / max(count, 1), col: sumC / max(count, 1)),
                confidence: sumConf / Float(max(count, 1))
            ))
        }

        return objects.sorted { $0.pixelCount > $1.pixelCount }
    }

    // MARK: – Errors

    enum SegmentationError: LocalizedError {
        case modelNotFound
        case modelNotLoaded
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .modelNotFound:   return "FoodSegmentation.mlmodelc not found in bundle"
            case .modelNotLoaded:  return "Segmentation model is not loaded"
            case .unexpectedOutput: return "Model output format not recognised"
            }
        }
    }
}
