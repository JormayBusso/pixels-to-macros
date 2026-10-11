import ARKit
import CoreVideo
import Foundation

/// Captures a single AR frame (RGB + optional depth + camera pose),
/// serialises the metadata to JSON, and returns it to the plugin.
///
/// Heavy pixel data stays native; only metadata crosses the bridge.
/// Full pixel buffers will be consumed by CoreML in Step 3.
final class FrameCaptureService {

    // MARK: â€“ Types

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

    /// Stored frame data â€” kept in memory until consumed or overwritten.
    /// Part 3 mandates max 2 frames (top + side).
    struct CapturedFrame {
        let pixelBuffer: CVPixelBuffer
        let depthBuffer: CVPixelBuffer?
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let timestamp: TimeInterval

        func measurementProvenance(crop: CGRect) -> String {
            let pose = cameraTransform
            let transform = [pose.columns.0, pose.columns.1, pose.columns.2, pose.columns.3]
                .flatMap { [$0.x, $0.y, $0.z, $0.w] }
                .map { String(format: "%.6f", $0) }.joined(separator: ",")
            return "timestamp=\(timestamp) image=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) " +
                "cropTL=\(crop.minX),\(crop.minY),\(crop.width),\(crop.height) " +
                "K=\(cameraIntrinsics.columns.0.x),\(cameraIntrinsics.columns.1.y),\(cameraIntrinsics.columns.2.x),\(cameraIntrinsics.columns.2.y) " +
                "poseColumnMajor=[\(transform)] depth=\(depthBuffer != nil)"
        }
    }

    struct SupportingPlane {
        let transform: simd_float4x4
        let boundary: [SIMD3<Float>]

        func distance(camera: simd_float4x4, timestamp: TimeInterval,
                      currentTimestamp: TimeInterval, horizontal: Bool,
                      supportsFood: Bool = true) -> (meters: Float?, reason: String) {
            guard MonocularVolumeEstimator.PhotoCalibration.validPose(camera),
                  MonocularVolumeEstimator.PhotoCalibration.validPose(transform) else {
                return (nil, "invalid_plane_or_camera_pose")
            }
            guard timestamp.isFinite, currentTimestamp.isFinite,
                  currentTimestamp >= timestamp, currentTimestamp - timestamp <= 0.25 else {
                return (nil, "stale_capture_frame")
            }
            let normal = SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            guard horizontal, normal.y.isFinite, abs(normal.y) > 0.99 else {
                return (nil, "nonhorizontal_plane")
            }
            guard supportsFood else { return (nil, "nonfood_support_classification") }
            let origin = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
            let direction = -SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)
            let planeOrigin = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let distance = origin.y - planeOrigin.y
            guard distance.isFinite, distance > 0.05, distance < 1 else {
                return (nil, "plane_distance_out_of_range")
            }
            let denominator = simd_dot(direction, normal)
            guard denominator.isFinite, denominator < -0.05 else {
                return (nil, "plane_ray_parallel_or_away")
            }
            let t = simd_dot(planeOrigin - origin, normal) / denominator
            guard t.isFinite, t > 0, t < 2 else { return (nil, "plane_ray_out_of_range") }
            let hit = origin + direction * t
            let local = transform.inverse * SIMD4(hit.x, hit.y, hit.z, 1)
            guard local.x.isFinite, local.z.isFinite, boundary.count >= 3,
                  boundary.allSatisfy({ $0.x.isFinite && $0.z.isFinite }) else {
                return (nil, "invalid_plane_boundary")
            }
            var inside = false
            var j = boundary.count - 1
            for i in boundary.indices {
                let a = boundary[i], b = boundary[j]
                if (a.z > local.z) != (b.z > local.z),
                   local.x < (b.x - a.x) * (local.z - a.z) / (b.z - a.z) + a.x {
                    inside.toggle()
                }
                j = i
            }
            guard inside else { return (nil, "capture_ray_outside_plane_footprint") }
            return (distance, "captured_horizontal_support")
        }
    }

    // MARK: â€“ Storage (max 2 frames)

    private(set) var topFrame: CapturedFrame?
    private(set) var sideFrame: CapturedFrame?

    // MARK: â€“ Public

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
                depthBuffer: FrameCaptureService.preferredDepthMap(from: arFrame),
                cameraTransform: arFrame.camera.transform,
                cameraIntrinsics: arFrame.camera.intrinsics,
                timestamp: arFrame.timestamp
            )
        }

        // Store â€” overwriting any previous frame of same type
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

    // MARK: â€“ Private helpers

    private func buildMetadata(frame: CapturedFrame, type: String) -> String {
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        let hasDepth = frame.depthBuffer != nil

        let pose = frame.cameraTransform
        let position: [Float] = [pose.columns.3.x, pose.columns.3.y, pose.columns.3.z]

        // Flatten 4Ã—4 transform to array for JSON
        let transform: [Float] = [
            pose.columns.0.x, pose.columns.0.y, pose.columns.0.z, pose.columns.0.w,
            pose.columns.1.x, pose.columns.1.y, pose.columns.1.z, pose.columns.1.w,
            pose.columns.2.x, pose.columns.2.y, pose.columns.2.z, pose.columns.2.w,
            pose.columns.3.x, pose.columns.3.y, pose.columns.3.z, pose.columns.3.w,
        ]

        var dict = [String: Any]()
        dict["type"] = type
        dict["width"] = width
        dict["height"] = height
        dict["has_depth"] = hasDepth
        dict["depth_width"] = hasDepth ? CVPixelBufferGetWidth(frame.depthBuffer!) : 0
        dict["depth_height"] = hasDepth ? CVPixelBufferGetHeight(frame.depthBuffer!) : 0
        dict["timestamp"] = frame.timestamp
        dict["camera_position"] = position
        dict["camera_transform"] = transform

        // Safe JSON serialisation
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    /// Prefer temporally-smoothed LiDAR depth for food volume; fall back to
    /// raw scene depth. Non-LiDAR devices return nil and are handled by the
    /// monocular scale-estimation pipeline.
    static func preferredDepthMap(from frame: ARFrame) -> CVPixelBuffer? {
        return frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
    }
}
