import CoreML
import CoreVideo
import Foundation
import Vision

/// Box-prompted **MobileSAM** mask refiner (TinyViT encoder + prompt decoder).
///
/// Turns a coarse YOLO/SegFormer food mask into a *pixel-exact* silhouette: the
/// image is encoded once, then each detected food's bounding box prompts the
/// decoder for a tight mask that replaces the coarse one. This directly improves
/// the top/side silhouettes the monocular 3-D reconstruction is hard-forced to.
///
/// Fully **additive, gated and fail-safe**, matching `MonoDepthService` /
/// `FoodClassifierService`:
///   • Inert unless BOTH `MobileSamEncoder.mlmodelc` and `MobileSamDecoder.mlmodelc`
///     are bundled (register with `ruby scripts/add_yolo_model.rb <name>`).
///   • Any per-segment failure or an implausible refined mask keeps the ORIGINAL
///     mask, so a scan is never worse than before the refiner ran.
///   • `enabled` is the master switch; the refiner must be validated on-device
///     before being trusted (the render is device-only validatable).
final class MobileSamRefiner {

    static let shared = MobileSamRefiner()
    private init() {}

    /// Master switch. **OFF** — device scans regressed after this shipped (a
    /// drifting SAM box mask can make a round food elongated AND include plate
    /// pixels, which then get sampled as the food colour → white). Re-enable only
    /// after an IoU-vs-original shape gate is added and validated on-device.
    static var enabled = false

    /// SAM works at a fixed 1024-pixel square input.
    private static let samSize = 1024

    private let lock = NSLock()
    private var encoder: VNCoreMLModel?
    private var decoder: MLModel?
    private var loadAttempted = false

    /// True when both models are bundled, loaded, and the refiner is enabled.
    var isAvailable: Bool {
        guard Self.enabled else { return false }
        ensureLoaded()
        return encoder != nil && decoder != nil
    }

    // MARK: – Loading

    private func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        if loadAttempted { return }
        loadAttempted = true

        guard
            let encURL = Bundle.main.url(forResource: "MobileSamEncoder", withExtension: "mlmodelc"),
            let decURL = Bundle.main.url(forResource: "MobileSamDecoder", withExtension: "mlmodelc")
        else {
            print("[MobileSAM] models not bundled — refiner inert")
            return
        }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let encModel = try MLModel(contentsOf: encURL, configuration: cfg)
            encoder = try VNCoreMLModel(for: encModel)
            decoder = try MLModel(contentsOf: decURL, configuration: cfg)
            print("[MobileSAM] loaded encoder + decoder")
        } catch {
            print("[MobileSAM] load failed: \(error) — refiner inert")
            encoder = nil
            decoder = nil
        }
    }

    // MARK: – Refinement

    /// Replace each segment's mask with a box-prompted SAM silhouette. `pixelBuffer`
    /// is the SAME preprocessed RGB the segmenter saw, so boxes and masks align.
    func refine(
        segments: [SegmentationService.SegmentedObject],
        pixelBuffer: CVPixelBuffer
    ) -> [SegmentationService.SegmentedObject] {
        guard isAvailable, let encoder, let decoder, !segments.isEmpty else {
            return segments
        }
        guard let embeddings = encode(pixelBuffer: pixelBuffer, model: encoder) else {
            print("[MobileSAM] encode failed — keeping original masks")
            return segments
        }
        var refinedCount = 0
        var out: [SegmentationService.SegmentedObject] = []
        out.reserveCapacity(segments.count)
        for seg in segments {
            if let refined = refineOne(seg: seg, embeddings: embeddings, decoder: decoder) {
                out.append(refined)
                refinedCount += 1
            } else {
                out.append(seg)
            }
        }
        print("[MobileSAM] refined \(refinedCount)/\(segments.count) segment masks")
        return out
    }

    /// Encode the frame once → image embeddings [1,256,64,64]. Vision resizes the
    /// (square) preprocessed buffer to the model's 1024² input.
    private func encode(pixelBuffer: CVPixelBuffer, model: VNCoreMLModel) -> MLMultiArray? {
        var result: MLMultiArray?
        autoreleasepool {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
                if let obs = request.results as? [VNCoreMLFeatureValueObservation] {
                    for o in obs where o.featureValue.multiArrayValue != nil {
                        result = o.featureValue.multiArrayValue
                        break
                    }
                }
            } catch {
                print("[MobileSAM] encoder request failed: \(error)")
            }
        }
        return result
    }

    private func refineOne(
        seg: SegmentationService.SegmentedObject,
        embeddings: MLMultiArray,
        decoder: MLModel
    ) -> SegmentationService.SegmentedObject? {
        let h = seg.mask.count
        guard h > 0 else { return nil }
        let w = seg.mask[0].count
        guard w > 0 else { return nil }

        // Bounding box of the coarse mask (mask coordinates).
        var minR = h, maxR = -1, minC = w, maxC = -1
        for r in 0..<h {
            let row = seg.mask[r]
            for c in 0..<w where row[c] == 1 {
                if r < minR { minR = r }
                if r > maxR { maxR = r }
                if c < minC { minC = c }
                if c > maxC { maxC = c }
            }
        }
        guard maxR >= minR, maxC >= minC else { return nil }

        // Scale the box into 1024 space with a small pad so the true edge is inside.
        let sx = Double(Self.samSize) / Double(w)
        let sy = Double(Self.samSize) / Double(h)
        let pad = 2.0
        let x0 = max(0.0, (Double(minC) - pad) * sx)
        let y0 = max(0.0, (Double(minR) - pad) * sy)
        let x1 = min(Double(Self.samSize), (Double(maxC) + 1 + pad) * sx)
        let y1 = min(Double(Self.samSize), (Double(maxR) + 1 + pad) * sy)

        guard let box = try? MLMultiArray(shape: [1, 4], dataType: .float32) else { return nil }
        box[0] = NSNumber(value: Float(x0))
        box[1] = NSNumber(value: Float(y0))
        box[2] = NSNumber(value: Float(x1))
        box[3] = NSNumber(value: Float(y1))

        guard
            let provider = try? MLDictionaryFeatureProvider(dictionary: [
                "image_embeddings": MLFeatureValue(multiArray: embeddings),
                "box": MLFeatureValue(multiArray: box),
            ]),
            let result = try? decoder.prediction(from: provider),
            let maskArr = result.featureValue(for: "mask")?.multiArrayValue,
            maskArr.shape.count == 4
        else {
            return nil
        }

        // Mask is [1,1,mH,mW] logits; threshold at 0 and resample to the w×h grid.
        let mH = maskArr.shape[2].intValue
        let mW = maskArr.shape[3].intValue
        guard mH > 0, mW > 0 else { return nil }

        var newMask = [[UInt8]](repeating: [UInt8](repeating: 0, count: w), count: h)
        var count = 0
        var sumR = 0, sumC = 0
        let idx = [NSNumber(value: 0), NSNumber(value: 0), NSNumber(value: 0), NSNumber(value: 0)]
        var key = idx
        for r in 0..<h {
            let my = min(mH - 1, Int((Double(r) + 0.5) * Double(mH) / Double(h)))
            key[2] = NSNumber(value: my)
            for c in 0..<w {
                let mx = min(mW - 1, Int((Double(c) + 0.5) * Double(mW) / Double(w)))
                key[3] = NSNumber(value: mx)
                if maskArr[key].floatValue > 0 {
                    newMask[r][c] = 1
                    count += 1
                    sumR += r
                    sumC += c
                }
            }
        }

        // Fail-safe plausibility guard: reject an empty mask or one that fills
        // (almost) the whole frame — keep the original in those cases.
        let area = w * h
        if count < 20 || count > (area * 95) / 100 {
            return nil
        }

        return SegmentationService.SegmentedObject(
            label: seg.label,
            classIndex: seg.classIndex,
            mask: newMask,
            pixelCount: count,
            centroid: (row: sumR / max(1, count), col: sumC / max(1, count)),
            confidence: seg.confidence
        )
    }
}
