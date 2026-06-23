import CoreML
import CoreVideo
import Foundation
import Vision

/// On-device **metric** monocular depth (Depth Anything V2, metric-indoor Small).
///
/// Why this exists
/// ----------------
/// The non-LiDAR camera path estimates food height from a fixed per-class prior
/// — the biggest accuracy gap for iPhones without LiDAR. When `MonoDepth.mlmodelc`
/// is bundled, this service predicts an absolute depth (metres) per pixel so the
/// food's height above the table can be *measured* and integrated into a real
/// volume, instead of extruding the silhouette by a guess.
///
/// It is fully **additive and gated**: `isAvailable` is false until the model is
/// bundled, and `MonocularVolumeEstimator` falls back to the prior-based prism
/// path unchanged. Same proven pattern as `YOLOSegmentationService` /
/// `FoodClassifierService`.
final class MonoDepthService {

    enum MonoDepthError: Error {
        case modelNotFound
        case unexpectedOutput
    }

    /// A metric depth map resampled to the segmentation mask grid. `meters[r*width+c]`
    /// is the predicted distance from the camera in metres (row-major).
    struct DepthGrid {
        let meters: [Float]
        let width: Int
        let height: Int

        @inline(__always) func at(_ r: Int, _ c: Int) -> Float {
            meters[r * width + c]
        }
    }

    /// Per-food volume measured by integrating height above the local table plane.
    struct FoodDepthResult {
        let volumeCm3: Double
        let meanHeightCm: Double
        let peakHeightCm: Double
        /// Fraction of food pixels with a valid (positive) height. Low = unreliable.
        let coverage: Double
    }

    // MARK: – Tunables

    /// Plausible food-height band (cm) for rejecting depth noise / bad scale.
    private let minHeightCm: Double = 0.3
    private let maxHeightCm: Double = 25.0

    private static let resourceCandidates = ["MonoDepth"]

    // MARK: – Model state

    private let modelLock = NSLock()
    private var model: VNCoreMLModel?
    private var loadAttempted = false
    private(set) var loadedResource: String?

    /// `true` when a metric-depth model is bundled and loaded.
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
        if loadAttempted { throw MonoDepthError.modelNotFound }
        loadAttempted = true

        var found: (url: URL, name: String)?
        for name in Self.resourceCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                found = (url, name)
                break
            }
        }
        guard let resource = found else { throw MonoDepthError.modelNotFound }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let mlModel = try MLModel(contentsOf: resource.url, configuration: config)
        model = try VNCoreMLModel(for: mlModel)
        loadedResource = resource.name
        print("[MonoDepth] Loaded \(resource.name).mlmodelc")
    }

    // MARK: – Inference

    /// Predict a metric depth map and resample it onto a `targetW × targetH` grid
    /// aligned with the segmentation mask (run on the SAME preprocessed RGB buffer
    /// the segmenter used, so the grids line up 1:1).
    func depthGrid(
        pixelBuffer: CVPixelBuffer,
        targetW: Int,
        targetH: Int
    ) -> DepthGrid? {
        do {
            try ensureLoaded()
        } catch {
            return nil
        }
        guard let visionModel = model else { return nil }

        var raw: MLMultiArray?
        var requestError: Error?

        autoreleasepool {
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error { requestError = error; return }
                guard let obs = request.results as? [VNCoreMLFeatureValueObservation] else {
                    requestError = MonoDepthError.unexpectedOutput
                    return
                }
                // Single depth output: the highest-rank float multiarray.
                for o in obs where o.featureValue.multiArrayValue != nil {
                    raw = o.featureValue.multiArrayValue
                    break
                }
            }
            request.imageCropAndScaleOption = .scaleFill
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                try handler.perform([request])
            } catch {
                requestError = error
            }
        }

        if requestError != nil { return nil }
        guard let depth = raw else { return nil }
        return resample(depth, targetW: targetW, targetH: targetH)
    }

    /// Resample a CoreML depth array (`[1,H,W]` or `[1,1,H,W]` or `[H,W]`) to the
    /// mask grid via nearest-neighbour. Depth output uses scaleFill (no aspect
    /// distortion since the input buffer is already square), so a uniform map is
    /// correct.
    private func resample(_ array: MLMultiArray, targetW: Int, targetH: Int) -> DepthGrid? {
        let shape = array.shape.map { $0.intValue }
        guard shape.count >= 2 else { return nil }
        let srcH = shape[shape.count - 2]
        let srcW = shape[shape.count - 1]
        guard srcH > 0, srcW > 0 else { return nil }

        let strides = array.strides.map { $0.intValue }
        let strideH = strides[strides.count - 2]
        let strideW = strides[strides.count - 1]
        // Leading (batch/channel) indices are all 0.
        let leadOffset = 0

        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(array.dataPointer))
        let isFloat32 = array.dataType == .float32
        let ptr16: UnsafeMutablePointer<Float16>? = isFloat32
            ? nil
            : UnsafeMutablePointer<Float16>(OpaquePointer(array.dataPointer))

        @inline(__always) func read(_ idx: Int) -> Float {
            if isFloat32 { return ptr[idx] }
            return Float(ptr16![idx])
        }

        var out = [Float](repeating: 0, count: targetW * targetH)
        for r in 0..<targetH {
            let sr = min(srcH - 1, r * srcH / targetH)
            for c in 0..<targetW {
                let sc = min(srcW - 1, c * srcW / targetW)
                out[r * targetW + c] = read(leadOffset + sr * strideH + sc * strideW)
            }
        }
        return DepthGrid(meters: out, width: targetW, height: targetH)
    }

    // MARK: – Volume from depth

    /// Integrate food height above the surrounding table plane into a metric
    /// volume. The table reference depth is the median of a thin ring just
    /// OUTSIDE the food mask; per-pixel height = (tableDepth − foodDepth).
    ///
    /// - Parameters:
    ///   - depth:        Metric depth grid aligned to the mask.
    ///   - mask:         Binary food mask (`mask[r][c] == 1`).
    ///   - pixelsPerCm:  Mask-space scale (same value the prism path uses).
    /// - Returns: nil when the result is implausible (caller falls back to prior).
    func foodVolume(
        depth: DepthGrid,
        mask: [[UInt8]],
        maskWidth: Int,
        maskHeight: Int,
        pixelsPerCm: Double
    ) -> FoodDepthResult? {
        guard pixelsPerCm > 0.0001,
              maskWidth == depth.width, maskHeight == depth.height else { return nil }

        // 1. Table reference = median depth of a 2-px ring just outside the mask.
        var ring: [Float] = []
        ring.reserveCapacity(2048)
        for r in 0..<maskHeight {
            for c in 0..<maskWidth where mask[r][c] == 0 {
                if isBorderNeighbour(mask, r: r, c: c, w: maskWidth, h: maskHeight) {
                    let d = depth.at(r, c)
                    if d.isFinite && d > 0 { ring.append(d) }
                }
            }
        }
        guard ring.count >= 12 else { return nil }
        ring.sort()
        let tableDepth = Double(ring[ring.count / 2])
        guard tableDepth > 0.05, tableDepth < 5.0 else { return nil }

        // 2. Integrate height above the table over the food mask.
        let cmPerPx = 1.0 / pixelsPerCm
        let pxAreaCm2 = cmPerPx * cmPerPx
        var volume = 0.0
        var heightSum = 0.0
        var peak = 0.0
        var foodPixels = 0
        var validPixels = 0

        for r in 0..<maskHeight {
            for c in 0..<maskWidth where mask[r][c] == 1 {
                foodPixels += 1
                let d = Double(depth.at(r, c))
                guard d.isFinite, d > 0 else { continue }
                var h = (tableDepth - d) * 100.0 // metres → cm
                if h <= 0 { continue }
                if h > maxHeightCm { h = maxHeightCm }
                validPixels += 1
                heightSum += h
                peak = max(peak, h)
                volume += pxAreaCm2 * h
            }
        }

        guard foodPixels > 0, validPixels > 0 else { return nil }
        let coverage = Double(validPixels) / Double(foodPixels)
        let meanHeight = heightSum / Double(validPixels)
        // Reject implausible reconstructions; the prior path is safer there.
        guard meanHeight >= minHeightCm, peak >= minHeightCm,
              coverage >= 0.25, volume > 1.0 else { return nil }

        return FoodDepthResult(
            volumeCm3: volume,
            meanHeightCm: meanHeight,
            peakHeightCm: peak,
            coverage: coverage
        )
    }

    /// True when `(r,c)` (a background pixel) is orthogonally adjacent to a food
    /// pixel — i.e. it sits on the thin ring hugging the mask boundary.
    @inline(__always)
    private func isBorderNeighbour(
        _ mask: [[UInt8]], r: Int, c: Int, w: Int, h: Int
    ) -> Bool {
        if r > 0, mask[r - 1][c] == 1 { return true }
        if r < h - 1, mask[r + 1][c] == 1 { return true }
        if c > 0, mask[r][c - 1] == 1 { return true }
        if c < w - 1, mask[r][c + 1] == 1 { return true }
        return false
    }
}
