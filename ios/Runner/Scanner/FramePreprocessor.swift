import CoreImage
import CoreVideo
import Foundation
import Accelerate

/// Prepares a captured AR frame for CoreML inference (Part 8).
///
/// Steps performed (all in native Swift):
///   1. Crop to plate region
///   2. Resize to model input dimensions (e.g. 513×513 for DeepLabV3)
///   3. Orientation correction
///   4. Normalise pixel values
///   5. Convert to CVPixelBuffer in the format CoreML expects
final class FramePreprocessor {

    // MARK: – Configuration

    /// DeepLabV3 MobileNet default input size.
    let modelInputWidth  = 513
    let modelInputHeight = 513

    // MARK: – Private state

    /// Shared CIContext — creating one per call is expensive (GPU setup).
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: – Public

    /// Preprocess a raw camera pixel buffer for CoreML.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The raw ARFrame.capturedImage (BGRA or YCbCr).
    ///   - plateRect: Normalised plate region (0…1). Pass `nil` to use full frame.
    /// - Returns: A new CVPixelBuffer sized to model input, or `nil` on failure.
    func preprocess(
        pixelBuffer: CVPixelBuffer,
        plateRect: CGRect? = nil
    ) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 1. Crop to plate region (normalised → pixel coords)
        let fullWidth  = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let fullHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let cropRect: CGRect
        if let plate = plateRect {
            cropRect = CGRect(
                x: plate.origin.x * fullWidth,
                y: (1.0 - plate.origin.y - plate.height) * fullHeight, // CIImage is bottom-left origin
                width: plate.width * fullWidth,
                height: plate.height * fullHeight
            )
        } else {
            cropRect = CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight)
        }

        var processed = ciImage.cropped(to: cropRect)

        // 2. Translate to origin after crop
        processed = processed.transformed(
            by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        )

        // 3. Resize to model input size
        let scaleX = CGFloat(modelInputWidth)  / processed.extent.width
        let scaleY = CGFloat(modelInputHeight) / processed.extent.height
        processed = processed.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 4. Render into a new CVPixelBuffer (BGRA, 8-bit)
        guard let output = createPixelBuffer(
            width: modelInputWidth,
            height: modelInputHeight
        ) else { return nil }

        ciContext.render(processed, to: output)

        return output
    }

    /// Preprocess a depth map: crop + resize to match the RGB model input.
    func preprocessDepth(
        depthBuffer: CVPixelBuffer,
        plateRect: CGRect? = nil,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil
    ) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: depthBuffer)

        let fullWidth  = CGFloat(CVPixelBufferGetWidth(depthBuffer))
        let fullHeight = CGFloat(CVPixelBufferGetHeight(depthBuffer))

        let cropRect: CGRect
        if let plate = plateRect {
            cropRect = CGRect(
                x: plate.origin.x * fullWidth,
                y: (1.0 - plate.origin.y - plate.height) * fullHeight,
                width: plate.width * fullWidth,
                height: plate.height * fullHeight
            )
        } else {
            cropRect = CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight)
        }

        var processed = ciImage.cropped(to: cropRect)
        processed = processed.transformed(
            by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        )

        let outW = outputWidth  ?? modelInputWidth
        let outH = outputHeight ?? modelInputHeight
        let scaleX = CGFloat(outW) / processed.extent.width
        let scaleY = CGFloat(outH) / processed.extent.height
        processed = processed.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Depth is Float32 — create matching buffer
        guard let output = createDepthBuffer(width: outW, height: outH) else {
            return nil
        }

        ciContext.render(processed, to: output)
        return output
    }

    // MARK: – Buffer creation

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        return status == kCVReturnSuccess ? buffer : nil
    }

    private func createDepthBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &buffer
        )
        return status == kCVReturnSuccess ? buffer : nil
    }
}
