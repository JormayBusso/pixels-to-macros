import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bakes the locked top-frame RGB into a texture image that `Food3DExporter`
/// maps onto the food mesh.
///
/// Why this is needed (the "white cubes" fix)
/// ------------------------------------------
/// Two things made the exported meshes render grey:
///   1. USDZ / QuickLook / RealityKit ignore per-vertex colours; they shade
///      from the material's baseColor.
///   2. ARKit `capturedImage` is planar YCbCr, so the exporter's BGRA
///      `CVPixelBufferGetBaseAddress` colour sampling returns nil and every
///      vertex falls back to grey 200.
///
/// CoreImage decodes the YCbCr buffer correctly, so writing it to a PNG and
/// using it as the material's baseColor texture (with the projected per-vertex
/// UVs from `DepthFusion`) gives a real, appetising food surface that renders
/// everywhere.
enum Food3DTextureBaker {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Maximum texture width; the full sensor frame is downscaled to keep the
    /// `.usdz` small. UVs are normalised, so downscaling does not shift them.
    private static let maxWidth: CGFloat = 1024

    /// Render `pixelBuffer` (BGRA or planar YCbCr) to an opaque PNG at `url`.
    /// Returns `true` on success.
    @discardableResult
    static func writeTexture(from pixelBuffer: CVPixelBuffer, to url: URL) -> Bool {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return false }

        if extent.width > maxWidth {
            let scale = maxWidth / extent.width
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("[Food3DTextureBaker] createCGImage failed")
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            print("[Food3DTextureBaker] destination create failed")
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        let ok = CGImageDestinationFinalize(destination)
        if !ok { print("[Food3DTextureBaker] finalize failed") }
        return ok
    }

    /// Decode any pixel buffer (notably ARKit's planar YCbCr `capturedImage`)
    /// into a fresh **BGRA** buffer, so byte-level colour sampling reads real
    /// pixels instead of failing on the planar layout (nil base address).
    static func bgraCopy(of pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferCGImageCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &output
        ) == kCVReturnSuccess, let dst = output else { return nil }
        context.render(CIImage(cvPixelBuffer: pixelBuffer), to: dst)
        return dst
    }
}
