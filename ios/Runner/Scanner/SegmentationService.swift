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

    /// Label map for the full FoodSeg103 model. The app can also ship a
    /// smaller thesis/demo model, so label lookup is selected from the model's
    /// output class count at parse time.
    private(set) var labelMap: [Int: String] = SegmentationService.buildLabelMap()

    /// Labels for the bundled 10-class mini model generated from
    /// data/FoodSeg103_mini/category_id.txt.
    private static let miniLabelMap: [Int: String] = [
        0: "background",
        1: "apple",
        2: "rice",
        3: "chicken",
        4: "bread",
        5: "salad",
        6: "pasta",
        7: "egg",
        8: "fish",
        9: "potato",
    ]

    private static func buildLabelMap() -> [Int: String] {
        var m = [Int: String]()
        m[0]   = "background"
        m[1]   = "candy"
        m[2]   = "egg tart"
        m[3]   = "french fries"
        m[4]   = "chocolate"
        m[5]   = "biscuit"
        m[6]   = "popcorn"
        m[7]   = "pudding"
        m[8]   = "ice cream"
        m[9]   = "cheese butter"
        m[10]  = "cake"
        m[11]  = "wine"
        m[12]  = "milkshake"
        m[13]  = "coffee"
        m[14]  = "juice"
        m[15]  = "milk"
        m[16]  = "tea"
        m[17]  = "almond"
        m[18]  = "red beans"
        m[19]  = "cashew"
        m[20]  = "dried cranberries"
        m[21]  = "soy"
        m[22]  = "walnut"
        m[23]  = "peanut"
        m[24]  = "egg"
        m[25]  = "apple"
        m[26]  = "date"
        m[27]  = "apricot"
        m[28]  = "avocado"
        m[29]  = "banana"
        m[30]  = "strawberry"
        m[31]  = "cherry"
        m[32]  = "blueberry"
        m[33]  = "raspberry"
        m[34]  = "mango"
        m[35]  = "olives"
        m[36]  = "peach"
        m[37]  = "lemon"
        m[38]  = "pear"
        m[39]  = "fig"
        m[40]  = "pineapple"
        m[41]  = "grape"
        m[42]  = "kiwi"
        m[43]  = "melon"
        m[44]  = "orange"
        m[45]  = "watermelon"
        m[46]  = "steak"
        m[47]  = "pork"
        m[48]  = "chicken duck"
        m[49]  = "sausage"
        m[50]  = "fried meat"
        m[51]  = "lamb"
        m[52]  = "sauce"
        m[53]  = "crab"
        m[54]  = "fish"
        m[55]  = "shellfish"
        m[56]  = "shrimp"
        m[57]  = "bread"
        m[58]  = "corn"
        m[59]  = "hamburg"
        m[60]  = "pizza"
        m[61]  = "hanamaki baozi"
        m[62]  = "wonton dumplings"
        m[63]  = "taro"
        m[64]  = "rice"
        m[65]  = "tofu"
        m[66]  = "eggplant"
        m[67]  = "potato"
        m[68]  = "garlic"
        m[69]  = "cauliflower"
        m[70]  = "tomato"
        m[71]  = "kelp"
        m[72]  = "seaweed"
        m[73]  = "spring onion"
        m[74]  = "rape"
        m[75]  = "ginger"
        m[76]  = "okra"
        m[77]  = "lettuce"
        m[78]  = "pumpkin"
        m[79]  = "cucumber"
        m[80]  = "white radish"
        m[81]  = "carrot"
        m[82]  = "asparagus"
        m[83]  = "bamboo shoots"
        m[84]  = "broccoli"
        m[85]  = "celery stick"
        m[86]  = "cilantro mint"
        m[87]  = "snow peas"
        m[88]  = "cabbage"
        m[89]  = "bean sprouts"
        m[90]  = "onion"
        m[91]  = "pepper"
        m[92]  = "green beans"
        m[93]  = "french beans"
        m[94]  = "king oyster mushroom"
        m[95]  = "white mushroom"
        m[96]  = "shiitake"
        m[97]  = "enoki mushroom"
        m[98]  = "oyster mushroom"
        m[99]  = "black fungus"
        m[100] = "dough"
        m[101] = "noodles"
        m[102] = "rice noodle"
        m[103] = "others"
        return m
    }

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

    /// Parse the MLMultiArray logits/probabilities into per-class binary masks.
    /// Supports channels-first [1, C, H, W], channels-last [1, H, W, C],
    /// [1, H, W] argmax, and [H, W] argmax outputs.
    private func parseSegmentationOutput(_ output: MLMultiArray) -> [SegmentedObject] {
        let shape = output.shape.map { $0.intValue }

        // Strides from the array's own metadata — avoids assuming contiguous layout.
        let strides = output.strides.map { $0.intValue }

        var height = 0
        var width = 0
        var numClasses = 0
        var classOffset: ((Int, Int, Int) -> Int)?
        var argmaxOffset: ((Int, Int) -> Int)?

        if shape.count == 4 {
            // [1, C, H, W] or [1, H, W, C]
            if shape[1] <= 256 && shape[2] > 1 && shape[3] > 1 {
                numClasses = shape[1]
                height = shape[2]
                width = shape[3]
                let sC = strides[1]
                let sR = strides[2]
                let sCol = strides[3]
                classOffset = { cls, row, col in cls * sC + row * sR + col * sCol }
            } else if shape[3] <= 256 && shape[1] > 1 && shape[2] > 1 {
                numClasses = shape[3]
                height = shape[1]
                width = shape[2]
                let sR = strides[1]
                let sCol = strides[2]
                let sC = strides[3]
                classOffset = { cls, row, col in row * sR + col * sCol + cls * sC }
            } else {
                return []
            }
        } else if shape.count == 3 {
            // [1, H, W] argmax indices.
            height = shape[1]
            width = shape[2]
            let sR = strides[1]
            let sCol = strides[2]
            argmaxOffset = { row, col in row * sR + col * sCol }
        } else if shape.count == 2 {
            // [H, W] argmax indices.
            height = shape[0]
            width = shape[1]
            let sR = strides[0]
            let sCol = strides[1]
            argmaxOffset = { row, col in row * sR + col * sCol }
        } else {
            return []
        }

        // Build class-index grid + confidence grid
        var classGrid = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var confGrid  = [[Float]](repeating: [Float](repeating: 0, count: width), count: height)

        // Compute the actual addressable element count from the underlying buffer.
        // output.count is the *logical* element count, but stride-based indexing
        // can reach beyond that when the layout is non-contiguous.
        let bufferLen: Int = {
            var maxOffset = 0
            for dim in 0..<shape.count {
                maxOffset += (shape[dim] - 1) * strides[dim]
            }
            return maxOffset + 1
        }()
        let maxIdx = bufferLen

        let valueAt: (Int) -> Float
        switch output.dataType {
        case .float32:
            let ptr = output.dataPointer.assumingMemoryBound(to: Float32.self)
            valueAt = { idx in
                guard idx >= 0 && idx < maxIdx else { return -Float.greatestFiniteMagnitude }
                return ptr[idx]
            }
        case .float16:
            let ptr = output.dataPointer.assumingMemoryBound(to: Float16.self)
            valueAt = { idx in
                guard idx >= 0 && idx < maxIdx else { return -Float.greatestFiniteMagnitude }
                return Float(ptr[idx])
            }
        case .double:
            let ptr = output.dataPointer.assumingMemoryBound(to: Double.self)
            valueAt = { idx in
                guard idx >= 0 && idx < maxIdx else { return -Float.greatestFiniteMagnitude }
                return Float(ptr[idx])
            }
        case .int32:
            let ptr = output.dataPointer.assumingMemoryBound(to: Int32.self)
            valueAt = { idx in
                guard idx >= 0 && idx < maxIdx else { return 0 }
                return Float(ptr[idx])
            }
        @unknown default:
            return parseSegmentationOutputSafe(output,
                height: height, width: width, numClasses: numClasses)
        }

        if let classOffset, numClasses > 0 {
            // Softmax output — argmax per pixel, resolve overlaps by confidence.
            // We also compute a true softmax probability and the top-1 vs top-2
            // margin so downstream gates can reject low-margin ("could be
            // anything") pixels rather than trusting raw logits.
            for r in 0..<height {
                for c in 0..<width {
                    var bestClass = 0
                    var bestVal: Float = -Float.infinity
                    var secondVal: Float = -Float.infinity
                    // Pass 1: argmax + second-best logit.
                    for cls in 0..<numClasses {
                        let val = valueAt(classOffset(cls, r, c))
                        if val > bestVal {
                            secondVal = bestVal
                            bestVal = val
                            bestClass = cls
                        } else if val > secondVal {
                            secondVal = val
                        }
                    }
                    // Pass 2: numerically-stable softmax probability of the
                    // winning class. Using true probabilities (rather than the
                    // raw logit value the previous code stored) makes the
                    // confidence threshold meaningful across models and stops
                    // the labeler over-trusting confident-but-wrong outputs.
                    var sumExp: Float = 0
                    for cls in 0..<numClasses {
                        sumExp += expf(valueAt(classOffset(cls, r, c)) - bestVal)
                    }
                    let prob: Float = sumExp > 0 ? 1.0 / sumExp : 1.0
                    // Margin between top-1 and top-2 logits — small margins
                    // mean the pixel could plausibly belong to several
                    // classes, which is a strong hallucination signal on the
                    // 10-class mini model where every non-food pixel gets
                    // forced into one of the food classes.
                    let margin = bestVal - secondVal
                    classGrid[r][c] = bestClass
                    // Encode margin into the stored confidence by attenuating
                    // probability when the margin is tiny (< 0.5 in logit
                    // space). This pushes ambiguous pixels below the gate.
                    let marginScale: Float = margin >= 1.5 ? 1.0
                        : margin <= 0.0 ? 0.4
                        : 0.4 + (margin / 1.5) * 0.6
                    confGrid[r][c]  = prob * marginScale
                }
            }
        } else if let argmaxOffset {
            // Argmax indices directly
            for r in 0..<height {
                for c in 0..<width {
                    classGrid[r][c] = max(0, Int(valueAt(argmaxOffset(r, c))))
                    confGrid[r][c]  = 1.0
                }
            }
        }

        return buildObjects(classGrid: classGrid, confGrid: confGrid,
                            height: height, width: width,
                            totalClasses: numClasses)
    }

    /// Safe fallback that uses `MLMultiArray`'s subscript (handles any data type).
    private func parseSegmentationOutputSafe(
        _ output: MLMultiArray,
        height: Int, width: Int, numClasses: Int
    ) -> [SegmentedObject] {
        let strides = output.strides.map { $0.intValue }

        var classGrid = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var confGrid  = [[Float]](repeating: [Float](repeating: 0, count: width), count: height)

        if numClasses > 0 {
            let sC   = strides.count == 4 ? strides[1] : strides[0]
            let sR   = strides.count == 4 ? strides[2] : strides[1]
            let sCol = strides.count == 4 ? strides[3] : strides[2]
            for r in 0..<height {
                for c in 0..<width {
                    var bestClass = 0
                    var bestConf: Float = -Float.infinity
                    for cls in 0..<numClasses {
                        let val = output[cls * sC + r * sR + c * sCol].floatValue
                        if val > bestConf { bestConf = val; bestClass = cls }
                    }
                    classGrid[r][c] = bestClass
                    confGrid[r][c]  = bestConf
                }
            }
        } else {
            let sR   = strides.count == 3 ? strides[1] : strides[0]
            let sCol = strides.count == 3 ? strides[2] : strides[1]
            for r in 0..<height {
                for c in 0..<width {
                    classGrid[r][c] = output[r * sR + c * sCol].intValue
                    confGrid[r][c]  = 1.0
                }
            }
        }

        return buildObjects(classGrid: classGrid, confGrid: confGrid,
                            height: height, width: width,
                            totalClasses: numClasses)
    }

    private func label(for classIndex: Int, totalClasses: Int) -> String {
        if totalClasses == SegmentationService.miniLabelMap.count {
            return SegmentationService.miniLabelMap[classIndex] ?? "others"
        }
        return labelMap[classIndex] ?? "others"
    }

    /// Convert per-pixel class/confidence grids into `SegmentedObject` list.
    private func buildObjects(
        classGrid: [[Int]], confGrid: [[Float]],
        height: Int, width: Int,
        totalClasses: Int
    ) -> [SegmentedObject] {
        // Group pixels by class
        var classPixels: [Int: [(row: Int, col: Int, conf: Float)]] = [:]
        for r in 0..<height {
            for c in 0..<width {
                let cls = classGrid[r][c]
                guard cls != 0 else { continue } // skip background
                classPixels[cls, default: []].append((r, c, confGrid[r][c]))
            }
        }

        // Build SegmentedObject per class.
        // Tightened thresholds (May 2026): the mini 10-class model needs to
        // be very strict to avoid hallucinating food on non-food scenes —
        // ML Kit's food-presence gate in InferencePipeline is the first line
        // of defence, but a stricter per-class floor here catches the case
        // where ML Kit accepts the scene but the segmentation hardly agrees.
        var objects: [SegmentedObject] = []
        let totalPixels = max(1, width * height)
        let isMiniModel = totalClasses == SegmentationService.miniLabelMap.count
        let minPixels = max(
            isMiniModel ? 600 : 450,
            Int(Double(totalPixels) * (isMiniModel ? 0.008 : 0.006))
        )
        // Confidence is now a true softmax probability (see parse step)
        // attenuated by top-1 vs top-2 margin. We keep floors low here
        // because the ML Kit food-presence gate in InferencePipeline is
        // the primary hallucination defence. Over-filtering here causes
        // the mini model to reject valid out-of-vocabulary foods (e.g.
        // banana, tomato) before the ML Kit label-override can fix them.
        let minConfidence: Float = isMiniModel ? 0.35 : 0.40
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
            let avgConfidence = sumConf / Float(max(count, 1))
            guard count >= minPixels, avgConfidence >= minConfidence else {
                continue
            }
            let label = label(for: cls, totalClasses: totalClasses)
            objects.append(SegmentedObject(
                label: label,
                classIndex: cls,
                mask: mask,
                pixelCount: count,
                centroid: (row: sumR / max(count, 1), col: sumC / max(count, 1)),
                confidence: avgConfidence
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
