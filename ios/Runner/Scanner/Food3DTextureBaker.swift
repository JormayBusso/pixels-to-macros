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
        let workingExtent = ciImage.extent

        // De-glare: the phone's light makes shiny food (a tomato, an apple) blow
        // out to a white specular highlight that the raw photo would paste onto
        // the mesh as a white blob. Pull the highlights down and lift saturation
        // so the food's TRUE colour (its diffuse component, still from THIS
        // photo) survives instead of the light's reflection.
        if let highlight = CIFilter(name: "CIHighlightShadowAdjust") {
            highlight.setValue(ciImage, forKey: kCIInputImageKey)
            highlight.setValue(0.35, forKey: "inputHighlightAmount")
            highlight.setValue(0.0, forKey: "inputShadowAmount")
            if let out = highlight.outputImage { ciImage = out }
        }
        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(ciImage, forKey: kCIInputImageKey)
            controls.setValue(1.22, forKey: kCIInputSaturationKey)
            if let out = controls.outputImage { ciImage = out }
        }
        ciImage = ciImage.cropped(to: workingExtent)

        guard let cgImage = context.createCGImage(ciImage, from: workingExtent) else {
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

    /// Bake the top + side captures into one deterministic atlas, using the
    /// SAME CoreImage pipeline as `writeTexture` so each tile keeps the exact
    /// orientation the projected UVs assume. The top photo fills the left tile
    /// (`atlasTopU*`), the side photo the middle tile (`atlasSideU*`); the mesh
    /// UVs route top-facing/underside vertices to the top tile and side-facing
    /// vertices to the side tile, so each surface shows the view that saw it.
    @discardableResult
    static func writeTextureAtlas(
        top topPixelBuffer: CVPixelBuffer,
        side sidePixelBuffer: CVPixelBuffer,
        to url: URL
    ) -> Bool {
        let atlasW: CGFloat = 2048
        let atlasH: CGFloat = 1024
        guard let topTile = processedTile(
                topPixelBuffer,
                targetW: CGFloat(atlasTopU1 - atlasTopU0) * atlasW,
                targetH: atlasH),
              let sideTile = processedTile(
                sidePixelBuffer,
                targetW: CGFloat(atlasSideU1 - atlasSideU0) * atlasW,
                targetH: atlasH) else {
            return false
        }
        // Placement is translation + per-axis scale only, which preserves
        // orientation, so the top tile matches a standalone `writeTexture` bake
        // exactly and the projected UVs index both tiles correctly.
        let topPlaced = topTile.transformed(
            by: CGAffineTransform(translationX: CGFloat(atlasTopU0) * atlasW, y: 0))
        let sidePlaced = sideTile.transformed(
            by: CGAffineTransform(translationX: CGFloat(atlasSideU0) * atlasW, y: 0))
        let background = CIImage(color: CIColor(red: 0.35, green: 0.32, blue: 0.28))
            .cropped(to: CGRect(x: 0, y: 0, width: atlasW, height: atlasH))
        let atlas = sidePlaced
            .composited(over: topPlaced)
            .composited(over: background)
            .cropped(to: CGRect(x: 0, y: 0, width: atlasW, height: atlasH))
        guard let cgImage = context.createCGImage(
            atlas, from: CGRect(x: 0, y: 0, width: atlasW, height: atlasH)) else {
            print("[Food3DTextureBaker] atlas createCGImage failed")
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            print("[Food3DTextureBaker] atlas destination create failed")
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        let ok = CGImageDestinationFinalize(destination)
        if !ok { print("[Food3DTextureBaker] atlas finalize failed") }
        return ok
    }

    /// Decode → de-glare → scale a capture to fill one atlas tile, matching the
    /// `writeTexture` colour pipeline so both tiles look consistent.
    private static func processedTile(
        _ pixelBuffer: CVPixelBuffer, targetW: CGFloat, targetH: CGFloat
    ) -> CIImage? {
        var ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard ci.extent.width > 0, ci.extent.height > 0 else { return nil }
        if let highlight = CIFilter(name: "CIHighlightShadowAdjust") {
            highlight.setValue(ci, forKey: kCIInputImageKey)
            highlight.setValue(0.35, forKey: "inputHighlightAmount")
            highlight.setValue(0.0, forKey: "inputShadowAmount")
            if let out = highlight.outputImage { ci = out }
        }
        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(ci, forKey: kCIInputImageKey)
            controls.setValue(1.22, forKey: kCIInputSaturationKey)
            if let out = controls.outputImage { ci = out }
        }
        ci = ci.transformed(by: CGAffineTransform(
            translationX: -ci.extent.origin.x, y: -ci.extent.origin.y))
        guard ci.extent.width > 0, ci.extent.height > 0 else { return nil }
        ci = ci.transformed(by: CGAffineTransform(
            scaleX: targetW / ci.extent.width, y: targetH / ci.extent.height))
        return ci.cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))
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
