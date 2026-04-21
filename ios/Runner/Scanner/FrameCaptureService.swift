import ARKit
import CoreVideo
import Foundation

/// Captures a single AR frame (RGB + optional depth + camera pose),
/// serialises the metadata to JSON, and returns it to the plugin.
///
/// Heavy pixel data stays native; only metadata crosses the bridge.
/// Full pixel buffers will be consumed by CoreML in Step 3.
final class FrameCaptureService {

    // MARK: – Types

    enum CaptureError: LocalizedError {
        case noSession
        case noFrame
        case unsupportedFrameType

        var errorDescription: String? {
            switch self {
            case .noSession:           return "AR session is not running"
            case .noFrame:             return "No AR frame available"
            case .unsupportedFrameType: return "Frame type must be 'top' or 'side'"
            }
        }
    }

    /// Stored frame data — kept in memory until consumed or overwritten.
    /// Part 3 mandates max 2 frames (top + side).
    struct CapturedFrame {
        let pixelBuffer: CVPixelBuffer
        let depthBuffer: CVPixelBuffer?
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let timestamp: TimeInterval
    }

    // MARK: – Storage (max 2 frames)

    private(set) var topFrame: CapturedFrame?
    private(set) var sideFrame: CapturedFrame?

    // MARK: – Public

    /// Capture the current AR frame and store it as either `top` or `side`.
    /// Returns a JSON string with frame metadata for the Dart side.
    func capture(
        session: ARSession?,
        frameType: String,
        completion: @escaping (Result<String, CaptureError>) -> Void
    ) {
        guard let session else {
            completion(.failure(.noSession))
            return
        }
        guard let arFrame = session.currentFrame else {
            completion(.failure(.noFrame))
            return
        }
        guard frameType == "top" || frameType == "side" else {
            completion(.failure(.unsupportedFrameType))
            return
        }

        // Build captured frame (autoreleasepool for pixel buffer safety)
        let captured = autoreleasepool { () -> CapturedFrame in
            CapturedFrame(
                pixelBuffer: arFrame.capturedImage,
                depthBuffer: arFrame.sceneDepth?.depthMap,
                cameraTransform: arFrame.camera.transform,
                cameraIntrinsics: arFrame.camera.intrinsics,
                timestamp: arFrame.timestamp
            )
        }

        // Store — overwriting any previous frame of same type
        switch frameType {
        case "top":
            topFrame = captured
        case "side":
            sideFrame = captured
        default:
            break
        }

        // Build metadata JSON to return to Dart
        let meta = buildMetadata(frame: captured, type: frameType)
        completion(.success(meta))
    }

    /// Release all stored frames.
    func releaseAll() {
        topFrame = nil
        sideFrame = nil
    }

    // MARK: – Private helpers

    private func buildMetadata(frame: CapturedFrame, type: String) -> String {
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        let hasDepth = frame.depthBuffer != nil

        let pose = frame.cameraTransform
        let position: [Float] = [pose.columns.3.x, pose.columns.3.y, pose.columns.3.z]

        // Flatten 4×4 transform to array for JSON
        let transform: [Float] = [
            pose.columns.0.x, pose.columns.0.y, pose.columns.0.z, pose.columns.0.w,
            pose.columns.1.x, pose.columns.1.y, pose.columns.1.z, pose.columns.1.w,
            pose.columns.2.x, pose.columns.2.y, pose.columns.2.z, pose.columns.2.w,
            pose.columns.3.x, pose.columns.3.y, pose.columns.3.z, pose.columns.3.w,
        ]

        let dict: [String: Any] = [
            "type": type,
            "width": width,
            "height": height,
            "has_depth": hasDepth,
            "depth_width": hasDepth ? CVPixelBufferGetWidth(frame.depthBuffer!) : 0,
            "depth_height": hasDepth ? CVPixelBufferGetHeight(frame.depthBuffer!) : 0,
            "timestamp": frame.timestamp,
            "camera_position": position,
            "camera_transform": transform,
        ]

        // Safe JSON serialisation
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}
