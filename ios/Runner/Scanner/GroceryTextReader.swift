import Foundation
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
        let lines = try recognizeRows(path: path)
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

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            .perform([request])

        let observations = (request.results ?? []).compactMap { obs -> (box: CGRect, text: String)? in
            guard let text = obs.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return (obs.boundingBox, text)
        }
        // Vision's origin is bottom-left: higher midY is nearer the top.
        let sorted = observations.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(box: CGRect, text: String)]] = []
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
