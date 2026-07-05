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

    /// Atlas regions used by the monocular dual-silhouette path. The left tile
    /// stores the top photo, the middle tile stores the side photo, and the
    /// narrow right strip marks surfaces that neither input image observes
    /// (typically the plate-facing underside).
    static let atlasTopU0: Float = 0.0
    static let atlasTopU1: Float = 0.46
    static let atlasSideU0: Float = 0.46
    static let atlasSideU1: Float = 0.92
    static let atlasUnknownU0: Float = 0.92
    static let atlasUnknownU1: Float = 1.0

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

    /// Bake top + side captures into one deterministic atlas. Geometry UVs use
    /// the constants above, so each surface samples from the source view that
    /// actually saw it instead of from a global average colour.
    @discardableResult
    static func writeTextureAtlas(
        top topPixelBuffer: CVPixelBuffer,
        side sidePixelBuffer: CVPixelBuffer,
        to url: URL
    ) -> Bool {
        guard let top = cgImage(from: topPixelBuffer),
              let side = cgImage(from: sidePixelBuffer) else {
            return false
        }

        let atlasWidth = 2048
        let atlasHeight = 1024
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cg = CGContext(
            data: nil,
            width: atlasWidth,
            height: atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("[Food3DTextureBaker] atlas CGContext failed")
            return false
        }

        cg.setFillColor(blendedPhotoColor(top: top, side: side))
        cg.fill(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))
        cg.interpolationQuality = .high

        func draw(_ image: CGImage, u0: Float, u1: Float) {
            let x = CGFloat(u0) * CGFloat(atlasWidth)
            let w = CGFloat(u1 - u0) * CGFloat(atlasWidth)
            cg.draw(image, in: CGRect(x: x, y: 0, width: w, height: CGFloat(atlasHeight)))
        }

        draw(top, u0: atlasTopU0, u1: atlasTopU1)
        draw(side, u0: atlasSideU0, u1: atlasSideU1)

        guard let atlas = cg.makeImage() else {
            print("[Food3DTextureBaker] atlas makeImage failed")
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            print("[Food3DTextureBaker] atlas destination create failed")
            return false
        }
        CGImageDestinationAddImage(destination, atlas, nil)
        let ok = CGImageDestinationFinalize(destination)
        if !ok { print("[Food3DTextureBaker] atlas finalize failed") }
        return ok
    }

    private typealias RGBA = (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

    private static func blendedPhotoColor(top: CGImage, side: CGImage) -> CGColor {
        let t = averageRGBA(top)
        let s = averageRGBA(side)
        switch (t, s) {
        case let (top?, side?):
            return CGColor(
                red: (top.r + side.r) * 0.5,
                green: (top.g + side.g) * 0.5,
                blue: (top.b + side.b) * 0.5,
                alpha: 1.0
            )
        case let (top?, nil):
            return CGColor(red: top.r, green: top.g, blue: top.b, alpha: 1.0)
        case let (nil, side?):
            return CGColor(red: side.r, green: side.g, blue: side.b, alpha: 1.0)
        default:
            return CGColor(red: 0.35, green: 0.32, blue: 0.28, alpha: 1.0)
        }
    }

    private static func averageRGBA(_ image: CGImage) -> RGBA? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: ciImage.extent),
            ]
        ), let output = filter.outputImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                output,
                toBitmap: base,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return (
            CGFloat(pixel[0]) / 255.0,
            CGFloat(pixel[1]) / 255.0,
            CGFloat(pixel[2]) / 255.0,
            CGFloat(pixel[3]) / 255.0
        )
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
        // Prefer an IOSurface-backed buffer (zero-copy, GPU-friendly). Under the
        // memory pressure of the 3-D reconstruction phase that allocation can
        // fail; fall back to a plain malloc-backed buffer so colour sampling
        // still gets real pixels instead of silently collapsing to flat beige.
        var result = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &output
        )
        if result != kCVReturnSuccess || output == nil {
            result = CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32BGRA, nil, &output
            )
        }
        guard result == kCVReturnSuccess, let dst = output else {
            print("[TextureBaker] ⚠️ bgraCopy failed to allocate \(width)x\(height) BGRA buffer")
            return nil
        }
        context.render(CIImage(cvPixelBuffer: pixelBuffer), to: dst)
        return dst
    }

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        if extent.width > maxWidth {
            let scale = maxWidth / extent.width
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}
