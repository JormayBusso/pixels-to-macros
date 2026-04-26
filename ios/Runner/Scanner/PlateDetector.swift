import CoreImage
import CoreVideo
import Foundation
import Accelerate

/// Detects the plate boundary in an RGB frame using a simplified
/// circle-detection approach (Hough-inspired edge analysis).
///
/// Falls back to center-crop if no plate is found. Returns a
/// normalised bounding rect so downstream code is resolution-agnostic.
final class PlateDetector {

    // MARK: – Types

    struct PlateResult {
        /// Normalised rect (0…1) of the plate region within the frame.
        let rect: CGRect
        /// Estimated plate diameter in pixels (before normalisation).
        let diameterPx: CGFloat
        /// Whether detection succeeded or we fell back to center.
        let detected: Bool
    }

    // MARK: – Configuration

    /// Default real-world plate diameter (cm) — Part 5.
    static let defaultDiameterCm: CGFloat = 26.0

    /// Minimum fraction of image width the plate circle must occupy.
    private let minDiameterFraction: CGFloat = 0.20
    /// Maximum fraction.
    private let maxDiameterFraction: CGFloat = 0.90

    // MARK: – Public

    /// Detect plate circle in a pixel buffer.
    func detect(in pixelBuffer: CVPixelBuffer) -> PlateResult {
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Convert to grayscale vImage buffer for edge detection
        guard let grayscale = grayscaleBuffer(from: pixelBuffer) else {
            return centerFallback(width: width, height: height)
        }

        // Apply simple Sobel edge detection
        guard let edges = sobelEdges(from: grayscale, width: width, height: height) else {
            free(grayscale.data)
            return centerFallback(width: width, height: height)
        }

        // Accumulate circle votes (simplified Hough)
        let result = houghCircle(
            edges: edges,
            imageWidth: width,
            imageHeight: height
        )

        free(grayscale.data)
        free(edges.data)

        if let result {
            return result
        }
        return centerFallback(width: width, height: height)
    }

    /// Pixels-per-cm scale factor given a detected plate.
    func pixelsPerCm(plate: PlateResult, frameWidth: Int) -> CGFloat {
        let diamPx = plate.diameterPx > 0
            ? plate.diameterPx
            : CGFloat(frameWidth) * 0.5
        return diamPx / PlateDetector.defaultDiameterCm
    }

    // MARK: – Grayscale conversion

    private func grayscaleBuffer(from pixelBuffer: CVPixelBuffer) -> vImage_Buffer? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        // Source is typically BGRA
        var src = vImage_Buffer(
            data: base,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )

        let destBytes = width * height
        guard let destData = malloc(destBytes) else { return nil }
        var dest = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width
        )

        // BGRA → Planar8 (luminance)
        let divisor: Int32 = 0x1000
        let rWeight: Int16 = Int16(0.2126 * Float(divisor))
        let gWeight: Int16 = Int16(0.7152 * Float(divisor))
        let bWeight: Int16 = Int16(0.0722 * Float(divisor))
        var coefficients: [Int16] = [bWeight, gWeight, rWeight, 0] // BGRA order

        let error = vImageMatrixMultiply_ARGB8888ToPlanar8(
            &src, &dest, &coefficients, divisor, nil, 0, vImage_Flags(kvImageNoFlags)
        )
        guard error == kvImageNoError else {
            free(destData)
            return nil
        }
        return dest
    }

    // MARK: – Sobel edge detection

    private func sobelEdges(from gray: vImage_Buffer, width: Int, height: Int) -> vImage_Buffer? {
        let count = width * height
        guard let edgeData = malloc(count) else { return nil }
        var edgeBuf = vImage_Buffer(
            data: edgeData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width
        )
        var src = gray  // copy struct (data pointer shared)

        // 3×3 Sobel horizontal
        let kernel: [Int16] = [
            -1, 0, 1,
            -2, 0, 2,
            -1, 0, 1
        ]
        let err = vImageConvolve_Planar8(
            &src, &edgeBuf,
            nil, 0, 0,
            kernel, 3, 3,
            0, 0,
            vImage_Flags(kvImageEdgeExtend)
        )
        guard err == kvImageNoError else {
            free(edgeData)
            return nil
        }
        return edgeBuf
    }

    // MARK: – Simplified Hough circle

    private func houghCircle(
        edges: vImage_Buffer,
        imageWidth: Int,
        imageHeight: Int
    ) -> PlateResult? {
        guard let edgeData = edges.data else { return nil }
        let ptr = edgeData.assumingMemoryBound(to: UInt8.self)
        let minR = Int(CGFloat(imageWidth) * minDiameterFraction / 2)
        let maxR = Int(CGFloat(imageWidth) * maxDiameterFraction / 2)
        let step = 4  // sample every 4th pixel for speed
        let edgeThreshold: UInt8 = 80

        // Accumulator: (cx, cy, r) → votes
        var bestVotes = 0
        var bestCx = imageWidth / 2
        var bestCy = imageHeight / 2
        var bestR  = (minR + maxR) / 2

        // Coarse grid search
        let rStep = max((maxR - minR) / 8, 1)
        let cStep = max(imageWidth / 20, 1)

        for r in stride(from: minR, through: maxR, by: rStep) {
            for cx in stride(from: r, to: imageWidth - r, by: cStep) {
                for cy in stride(from: r, to: imageHeight - r, by: cStep) {
                    var votes = 0
                    // Sample points on the circle perimeter
                    let numSamples = 36
                    for i in 0..<numSamples {
                        let angle = Double(i) * (2.0 * .pi / Double(numSamples))
                        let px = cx + Int(Double(r) * cos(angle))
                        let py = cy + Int(Double(r) * sin(angle))
                        guard px >= 0, px < imageWidth, py >= 0, py < imageHeight else { continue }
                        if ptr[py * imageWidth + px] >= edgeThreshold {
                            votes += 1
                        }
                    }
                    if votes > bestVotes {
                        bestVotes = votes
                        bestCx = cx
                        bestCy = cy
                        bestR  = r
                    }
                }
            }
        }

        // Require at least 40% of perimeter samples to be edges
        guard bestVotes >= 14 else { return nil }

        let diameter = CGFloat(bestR * 2)
        let x = CGFloat(bestCx - bestR) / CGFloat(imageWidth)
        let y = CGFloat(bestCy - bestR) / CGFloat(imageHeight)
        let w = diameter / CGFloat(imageWidth)
        let h = diameter / CGFloat(imageHeight)

        return PlateResult(
            rect: CGRect(x: x, y: y, width: w, height: h),
            diameterPx: diameter,
            detected: true
        )
    }

    // MARK: – Fallback

    private func centerFallback(width: Int, height: Int) -> PlateResult {
        // Assume plate occupies the center 60% of the frame
        let fraction: CGFloat = 0.60
        let inset = (1.0 - fraction) / 2.0
        return PlateResult(
            rect: CGRect(x: inset, y: inset, width: fraction, height: fraction),
            diameterPx: CGFloat(width) * fraction,
            detected: false
        )
    }
}
