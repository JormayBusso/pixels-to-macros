import CoreVideo
import Foundation

/// Generates a PLY-format 3D point cloud from a depth buffer and
/// optional segmentation mask (Part 15).
///
/// The PLY can be used for thesis visualisation, 3D validation,
/// and scientific diagrams.
final class PointCloudExporter {

    struct Point3D {
        let x: Float
        let y: Float
        let z: Float
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    /// Build a coloured point cloud from depth + RGB + optional mask.
    ///
    /// - Parameters:
    ///   - depthBuffer: Float32 depth map (metres).
    ///   - rgbBuffer: The camera RGB frame.
    ///   - intrinsics: 3×3 camera intrinsics matrix.
    ///   - mask: Optional 2D food mask — if provided, only food pixels are included.
    ///   - maskWidth: Width of the mask grid (may differ from depth grid).
    ///   - maskHeight: Height of the mask grid.
    /// - Returns: PLY file contents as a UTF-8 string, or nil on failure.
    func generatePLY(
        depthBuffer: CVPixelBuffer,
        rgbBuffer: CVPixelBuffer,
        intrinsics: [Float],     // 9-element [fx, 0, 0, 0, fy, 0, cx, cy, 1] column-major
        mask: [[Int]]? = nil,
        maskWidth: Int = 0,
        maskHeight: Int = 0
    ) -> String? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(rgbBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(rgbBuffer, .readOnly)
        }

        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let depthBase = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let depthPtr = depthBase.assumingMemoryBound(to: Float32.self)
        let depthFloatsPerRow = depthRowBytes / MemoryLayout<Float32>.stride

        let rgbW = CVPixelBufferGetWidth(rgbBuffer)
        let rgbH = CVPixelBufferGetHeight(rgbBuffer)
        let rgbRowBytes = CVPixelBufferGetBytesPerRow(rgbBuffer)
        guard let rgbBase = CVPixelBufferGetBaseAddress(rgbBuffer) else { return nil }
        let rgbPtr = rgbBase.assumingMemoryBound(to: UInt8.self)

        // Camera intrinsics — extract focal length and principal point
        let fx: Float = intrinsics.count >= 9 ? intrinsics[0] : 500
        let fy: Float = intrinsics.count >= 9 ? intrinsics[4] : 500
        let cx: Float = intrinsics.count >= 9 ? intrinsics[6] : Float(depthW) / 2
        let cy: Float = intrinsics.count >= 9 ? intrinsics[7] : Float(depthH) / 2

        // Subsample for performance — every 2nd pixel
        let step = 2
        var points: [Point3D] = []
        points.reserveCapacity((depthW * depthH) / (step * step))

        for row in stride(from: 0, to: depthH, by: step) {
            for col in stride(from: 0, to: depthW, by: step) {

                // Apply mask filter if provided
                if let mask, maskWidth > 0, maskHeight > 0 {
                    let mr = min(Int(Float(row) * Float(maskHeight) / Float(depthH)), maskHeight - 1)
                    let mc = min(Int(Float(col) * Float(maskWidth) / Float(depthW)), maskWidth - 1)
                    if mask[mr][mc] == 0 { continue }
                }

                let depth = depthPtr[row * depthFloatsPerRow + col]

                // Skip invalid / too-far depths
                guard depth > 0.01, depth < 5.0 else { continue }

                // Back-project to 3D (camera coords)
                let x = (Float(col) - cx) * depth / fx
                let y = (Float(row) - cy) * depth / fy
                let z = depth

                // Sample RGB colour (map depth coords → RGB coords)
                let rgbCol = min(Int(Float(col) * Float(rgbW) / Float(depthW)), rgbW - 1)
                let rgbRow = min(Int(Float(row) * Float(rgbH) / Float(depthH)), rgbH - 1)

                let bytesPerPixel = rgbRowBytes / rgbW
                let pixelOffset = rgbRow * rgbRowBytes + rgbCol * bytesPerPixel

                // BGRA format — common for iOS camera buffers
                let b = rgbPtr[pixelOffset]
                let g = rgbPtr[pixelOffset + 1]
                let r = rgbPtr[pixelOffset + 2]

                points.append(Point3D(x: x, y: y, z: z, r: r, g: g, b: b))
            }
        }

        guard !points.isEmpty else { return nil }

        // Build ASCII PLY
        var ply = """
        ply
        format ascii 1.0
        element vertex \(points.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header\n
        """

        for p in points {
            ply += "\(String(format: "%.4f", p.x)) "
            ply += "\(String(format: "%.4f", p.y)) "
            ply += "\(String(format: "%.4f", p.z)) "
            ply += "\(p.r) \(p.g) \(p.b)\n"
        }

        return ply
    }

    /// Generate a PLY from the captured frames in the capture service.
    /// Returns the PLY string or nil if depth data isn't available.
    func exportFromCapture(captureService: FrameCaptureService) -> String? {
        guard let topFrame = captureService.topFrame else { return nil }
        guard let depthBuffer = captureService.topFrame?.depthBuffer
                ?? captureService.sideFrame?.depthBuffer else { return nil }

        // Flatten intrinsics to 9-element array (column-major)
        let intr = topFrame.cameraIntrinsics
        let intrinsics: [Float] = [
            intr.columns.0.x, intr.columns.0.y, intr.columns.0.z,
            intr.columns.1.x, intr.columns.1.y, intr.columns.1.z,
            intr.columns.2.x, intr.columns.2.y, intr.columns.2.z,
        ]

        return generatePLY(
            depthBuffer: depthBuffer,
            rgbBuffer: topFrame.pixelBuffer,
            intrinsics: intrinsics
        )
    }
}
