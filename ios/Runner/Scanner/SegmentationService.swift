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

    /// Label map — index 0 is background. Populated from model metadata
    /// or hardcoded for DeepLabV3 / FoodSeg103 classes.
    private(set) var labelMap: [Int: String] = [
        0:  "background",
        1:  "apple",
        2:  "rice",
        3:  "chicken",
        4:  "bread",
        5:  "salad",
        6:  "pasta",
        7:  "egg",
        8:  "fish",
        9:  "potato",
        10: "soup",
        // Extend as FoodSeg103 model expands
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
