import Foundation
import CoreImage
import ImageIO
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads grocery receipts / packaging text in any script with Vision OCR and,
/// when Apple Intelligence is available (iOS 26+), asks the on-device
/// Foundation Model which lines are food or drink products. Dart validates
/// every model item against its source line and falls back to its lexicon.
enum GroceryTextReader {
    static let maxModelLines = 120

    static func read(path: String, kind: String) async throws -> [String: Any] {
        let lines = try recognizeRows(path: path, enhanceReceipt: kind == "receipt")
        var payload: [String: Any] = ["lines": lines, "engine": "vision"]
        guard !lines.isEmpty else { return payload }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let items = await GroceryModelExtractor.extract(lines: lines, kind: kind) {
                payload["items"] = items
                payload["engine"] = "vision+fm"
            }
        }
        #endif
        return payload
    }

    /// Vision text lines regrouped into visual rows (receipt name … price).
    static func recognizeRows(path: String) throws -> [String] {
        try recognizeRows(path: path, enhanceReceipt: false)
    }

    private static func recognizeRows(path: String, enhanceReceipt: Bool) throws -> [String] {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "GroceryTextReader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Image could not be decoded"])
        }
        var orientation = CGImagePropertyOrientation.up
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let raw = props[kCGImagePropertyOrientation] as? UInt32,
           let value = CGImagePropertyOrientation(rawValue: raw) {
            orientation = value
        }

        let original = try recognize(image: image, orientation: orientation)
        var selected = original
        if enhanceReceipt {
            // Keep the source pixels and EXIF orientation unchanged; enhance only the OCR copy.
            do {
                let input = CIImage(cgImage: image)
                if let filter = CIFilter(name: "CIColorControls") {
                    filter.setValue(input, forKey: kCIInputImageKey)
                    filter.setValue(0.0, forKey: kCIInputSaturationKey)
                    filter.setValue(1.35, forKey: kCIInputContrastKey)
                    filter.setValue(0.0, forKey: kCIInputBrightnessKey)
                    if let output = filter.outputImage,
                       let enhanced = CIContext(options: [.cacheIntermediates: false])
                        .createCGImage(output, from: input.extent) {
                        let second = try recognize(image: enhanced, orientation: orientation)
                        selected = selectReceiptObservations(original: original, enhanced: second)
                        print("[GROCERY_TEXT] receipt OCR original=\(original.count) enhanced=\(second.count) selected=\(selected.count)")
                    } else {
                        print("[GROCERY_TEXT] receipt contrast render unavailable; using original OCR")
                    }
                } else {
                    print("[GROCERY_TEXT] receipt contrast filter unavailable; using original OCR")
                }
            } catch {
                print("[GROCERY_TEXT] receipt contrast OCR failed; using original OCR: \(error)")
            }
        }
        return rows(from: selected)
    }

    struct Observation {
        let box: CGRect
        let text: String
        let confidence: Float
    }

    private static func recognize(
        image: CGImage, orientation: CGImagePropertyOrientation
    ) throws -> [Observation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            .perform([request])

        return (request.results ?? []).compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Observation(box: obs.boundingBox, text: text, confidence: candidate.confidence)
        }
    }

    static func selectReceiptObservations(
        original: [Observation], enhanced: [Observation]
    ) -> [Observation] {
        let all = original + enhanced
        var neighbors = Array(repeating: [Int](), count: all.count)
        for i in original.indices {
            for j in enhanced.indices {
                let other = original.count + j
                let a = all[i].box
                let b = all[other].box
                let intersection = a.intersection(b)
                let smallerArea = min(a.width * a.height, b.width * b.height)
                guard smallerArea > 0, !intersection.isNull,
                      intersection.width * intersection.height / smallerArea >= 0.45,
                      abs(a.midY - b.midY) <= 0.5 * min(a.height, b.height) else { continue }
                neighbors[i].append(other)
                neighbors[other].append(i)
            }
        }
        var visited = Set<Int>()
        var selected: [Observation] = []
        for index in all.indices where !visited.contains(index) {
            var pending = [index]
            var first: [Observation] = []
            var second: [Observation] = []
            while let next = pending.popLast() {
                guard visited.insert(next).inserted else { continue }
                if next < original.count { first.append(all[next]) } else { second.append(all[next]) }
                pending.append(contentsOf: neighbors[next])
            }
            // A pass can split one row into several boxes. Choose the whole overlapping
            // region from one pass, not both sets of text (which would duplicate purchases).
            if first.isEmpty {
                selected.append(contentsOf: second)
            } else if second.isEmpty || evidence(first) >= evidence(second) {
                selected.append(contentsOf: first)
            } else {
                selected.append(contentsOf: second)
            }
        }
        return selected
    }

    private static func evidence(_ observations: [Observation]) -> Float {
        let weight = observations.reduce(0) { $0 + $1.text.count }
        guard weight > 0 else { return 0 }
        return observations.reduce(Float(0)) {
            $0 + $1.confidence * Float($1.text.count)
        } / Float(weight)
    }

    static func rows(from observations: [Observation]) -> [String] {
        // Vision's origin is bottom-left: higher midY is nearer the top.
        let sorted = observations.sorted {
            if $0.box.midY != $1.box.midY { return $0.box.midY > $1.box.midY }
            if $0.box.minX != $1.box.minX { return $0.box.minX < $1.box.minX }
            return $0.text < $1.text
        }
        var rows: [[Observation]] = []
        for obs in sorted {
            if let last = rows.last, let anchor = last.first {
                let tolerance = 0.5 * min(anchor.box.height, obs.box.height)
                if abs(anchor.box.midY - obs.box.midY) <= tolerance {
                    rows[rows.count - 1].append(obs)
                    continue
                }
            }
            rows.append([obs])
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GroceryModelLine {
    @Guide(description: "Zero-based index of the numbered input line containing the product")
    var line: Int
    @Guide(description: "Short generic English grocery name, e.g. 'Milk', 'Chicken breast', 'Whole wheat bread'")
    var name: String
}

@available(iOS 26.0, *)
@Generable
struct GroceryModelResult {
    @Guide(description: "Only edible food and drink products; empty when there are none")
    var items: [GroceryModelLine]
}

@available(iOS 26.0, *)
enum GroceryModelExtractor {
    static func extract(lines: [String], kind: String) async -> [[String: Any]]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("[GROCERY_TEXT] foundation model unavailable: \(model.availability)")
            return nil
        }
        let source = kind == "receipt" ? "a shop receipt" : "food packaging photographed at home"
        let instructions = """
        You read OCR text from \(source). The text can be in any language and \
        product names are often abbreviated or misspelled by OCR. Return only \
        edible food and drink products that a person could cook or eat. \
        Translate each product into a short generic English grocery name \
        without brand, size, weight, price or quantity. Never return store \
        names, receipt or ticket numbers, dates, totals, taxes, payment, \
        discounts, deposits, bags, loyalty points, addresses, household, \
        cleaning, hygiene, pet or pharmacy products, ingredient lists or \
        nutrition facts.
        """
        let numbered = lines.prefix(GroceryTextReader.maxModelLines).enumerated()
            .map { "\($0.offset): \($0.element)" }.joined(separator: "\n")
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "OCR lines:\n\(numbered)",
                generating: GroceryModelResult.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.items.map { ["line": $0.line, "name": $0.name] }
        } catch {
            print("[GROCERY_TEXT] foundation model failed: \(error)")
            return nil
        }
    }
}
#endif
