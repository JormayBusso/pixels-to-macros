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
    ///
    /// Silhouette masking (the "grey/white edge" fix)
    /// ----------------------------------------------
    /// The raw captures include the plate, table and shadow around the food, so
    /// wherever a mesh UV lands slightly outside the food's true outline it used
    /// to paste that background (grey/white) onto the model. To stop that, each
    /// tile is composited in two layers, exactly as the user asked ("first put a
    /// layer of only the color underneath before applying that"):
    ///   1. an OPAQUE underlay filled entirely with the food's dominant colour
    ///      (`baseColor`), so any pixel the mask rejects reads as real food
    ///      colour instead of raw background, and
    ///   2. the de-glared REAL photo composited on top through the food
    ///      silhouette mask (`topCoverage` for the top tile, `sideCoverage` for
    ///      the side tile), so genuine food pixels still show the exact captured
    ///      picture — only the non-food pixels fall back to the underlay.
    /// When a coverage mask is `nil` the tile keeps the previous unmasked photo
    /// behaviour (the mesh never samples an unused tile, so this is a safe
    /// no-op fallback).
    @discardableResult
    static func writeTextureAtlas(
        top topPixelBuffer: CVPixelBuffer,
        side sidePixelBuffer: CVPixelBuffer,
        topCoverage: [[UInt8]]?,
        sideCoverage: [[UInt8]]?,
        baseColor: (r: CGFloat, g: CGFloat, b: CGFloat),
        to url: URL
    ) -> Bool {
        let atlasW: CGFloat = 2048
        let atlasH: CGFloat = 1024
        let baseCIColor = CIColor(red: baseColor.r, green: baseColor.g, blue: baseColor.b)
        guard let topTile = processedTile(
                topPixelBuffer,
                coverage: topCoverage,
                baseColor: baseCIColor,
                targetW: CGFloat(atlasTopU1 - atlasTopU0) * atlasW,
                targetH: atlasH),
              let sideTile = processedTile(
                sidePixelBuffer,
                coverage: sideCoverage,
                baseColor: baseCIColor,
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
        // The unknown strip (surfaces neither photo saw) uses the SAME food
        // dominant colour as the tile underlay, so nothing in the atlas can ever
        // read as grey/white background.
        let background = CIImage(color: baseCIColor)
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
    /// `writeTexture` colour pipeline so both tiles look consistent, then
    /// composite the real photo over an opaque `baseColor` underlay through the
    /// food-silhouette `coverage` mask. Genuine food pixels show the exact
    /// captured photo; every rejected (background/plate/shadow) pixel falls back
    /// to the food's own dominant colour instead of grey/white. A `nil`
    /// coverage keeps the previous full-photo behaviour.
    private static func processedTile(
        _ pixelBuffer: CVPixelBuffer,
        coverage: [[UInt8]]?,
        baseColor: CIColor,
        targetW: CGFloat, targetH: CGFloat
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
        let tileRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        let photo = ci.cropped(to: tileRect)

        // The opaque underlay: an infinite solid of the food's dominant colour,
        // cropped to the tile. This is the "colour layer underneath" — it makes
        // the tile fully opaque so no UV can ever reveal grey/white behind it.
        let base = CIImage(color: baseColor).cropped(to: tileRect)

        // Without a silhouette mask, keep the original unmasked photo (the mesh
        // never samples a tile it has no coverage for, so this stays a no-op for
        // those cases).
        guard let coverage, let maskRaw = maskImage(from: coverage) else {
            return photo
        }
        // Scale the coverage mask to fill the tile exactly like the photo (both
        // map their own normalized [0,1] image extent onto the same tile rect),
        // so a normalized food pixel in the mask lines up with the same food
        // pixel in the photo regardless of pixel aspect.
        let maskNorm = maskRaw.transformed(by: CGAffineTransform(
            translationX: -maskRaw.extent.origin.x, y: -maskRaw.extent.origin.y))
        guard maskNorm.extent.width > 0, maskNorm.extent.height > 0 else { return photo }
        let maskScaled = maskNorm
            .transformed(by: CGAffineTransform(
                scaleX: targetW / maskNorm.extent.width,
                y: targetH / maskNorm.extent.height))
            .cropped(to: tileRect)
        // CIBlendWithMask: white/opaque mask → the real photo; black/clear mask
        // → the dominant-colour underlay. The de-glare pipeline above still runs
        // on the photo, so only the compositing changed.
        let blended = photo.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: base,
            kCIInputMaskImageKey: maskScaled,
        ])
        return blended.cropped(to: tileRect)
    }

    /// Build a CoreImage mask from a row-major food-coverage grid (`1` = food,
    /// `0` = background), white+opaque where food so CIBlendWithMask keeps the
    /// real photo there and rejects everything else. Row 0 is the top row, the
    /// same top-down convention as `CIImage(cvPixelBuffer:)`, so the mask and the
    /// photo stay aligned once both are scaled to the tile.
    private static func maskImage(from coverage: [[UInt8]]) -> CIImage? {
        let h = coverage.count
        let w = coverage.first?.count ?? 0
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for r in 0..<h {
            let row = coverage[r]
            let rowBase = r * w * 4
            let cols = min(w, row.count)
            for c in 0..<cols where row[c] != 0 {
                let o = rowBase + c * 4
                bytes[o] = 255; bytes[o + 1] = 255; bytes[o + 2] = 255; bytes[o + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent) else {
            return nil
        }
        return CIImage(cgImage: cg)
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
