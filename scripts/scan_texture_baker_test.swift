import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

@main
struct ScanTextureBakerTests {
    enum Failure: Error { case colorMismatch([UInt8], [UInt8]) }

    static func main() throws {
        setbuf(stdout, nil)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_texture_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        func image(_ upper: [UInt8], _ lower: [UInt8]) throws -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
            guard let buffer else { throw CocoaError(.coderInvalidValue) }
            CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey,
                CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for r in 0..<64 { for c in 0..<64 {
                let rgb = r < 32 ? upper : lower
                let i = r * stride + c * 4
                bytes[i] = rgb[2]; bytes[i + 1] = rgb[1]
                bytes[i + 2] = rgb[0]; bytes[i + 3] = 255
            } }
            return buffer
        }
        func expect(u: CGFloat, vTop: CGFloat, rgb: [UInt8]) throws {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let data = image.dataProvider?.data else {
                throw CocoaError(.fileReadCorruptFile)
            }
            precondition(image.bitsPerComponent == 8 && image.bitsPerPixel == 32)
            let offset = Int(floor(vTop * CGFloat(image.height))) * image.bytesPerRow +
                Int(floor(u * CGFloat(image.width))) * 4
            let pixel = Array((data as Data)[offset..<offset + 4])
            for (actual, expected) in zip(pixel.prefix(3), rgb) {
                if abs(Int(actual) - Int(expected)) > 2 {
                    throw Failure.colorMismatch(pixel, rgb)
                }
            }
        }
        let calibrated = try image([128, 96, 64], [128, 96, 64])
        guard let bgra = Food3DTextureBaker.bgraCopy(of: calibrated) else {
            throw CocoaError(.coderInvalidValue)
        }
        CVPixelBufferLockBaseAddress(bgra, .readOnly)
        let bytes = CVPixelBufferGetBaseAddress(bgra)!.assumingMemoryBound(to: UInt8.self)
        precondition(abs(Int(bytes[2]) - 128) <= 2 &&
            abs(Int(bytes[1]) - 96) <= 2 && abs(Int(bytes[0]) - 64) <= 2)
        CVPixelBufferUnlockBaseAddress(bgra, .readOnly)
        precondition(Food3DTextureBaker.writeTexture(from: calibrated, to: url))
        try expect(u: 0.5, vTop: 0.5, rgb: [128, 96, 64])
        let coverage: [[UInt8]] = [[1, 1], [1, 1]]
        precondition(Food3DTextureBaker.writeTextureAtlas(top: calibrated, side: calibrated,
            topCoverage: coverage, sideCoverage: coverage, baseColor: (0, 0, 0), to: url))
        for u: CGFloat in [0.1, 0.6] {
            try expect(u: u, vTop: 0.25, rgb: [128, 96, 64])
        }
        let top = try image([220, 20, 30], [30, 220, 40])
        let side = try image([60, 80, 220], [240, 160, 30])
        precondition(Food3DTextureBaker.writeTextureAtlas(top: top, side: side,
            topCoverage: coverage, sideCoverage: coverage, baseColor: (0, 0, 0), to: url))
        try expect(u: 0.1, vTop: 0.25, rgb: [220, 20, 30])
        try expect(u: 0.1, vTop: 0.75, rgb: [30, 220, 40])
        try expect(u: 0.6, vTop: 0.25, rgb: [60, 80, 220])
        try expect(u: 0.6, vTop: 0.75, rgb: [240, 160, 30])
        for (u0, u1) in [(Food3DTextureBaker.atlasTopU0, Food3DTextureBaker.atlasTopU1),
                         (Food3DTextureBaker.atlasSideU0, Food3DTextureBaker.atlasSideU1)] {
            for value: Float in [0, 1] {
                let uv = Food3DTextureBaker.atlasUV(sourceUV: SIMD2(value, value), u0: u0, u1: u1)
                precondition(uv.x > u0 && uv.x < u1 && uv.y > 0 && uv.y < 1,
                    "atlas edge bleeds into another tile")
            }
        }
        print("PASS captured photo color, atlas orientation and filtering boundaries")
    }
}
