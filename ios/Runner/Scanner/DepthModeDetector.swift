import ARKit
import Foundation

/// Detects the best available depth mode at runtime (Part 2).
///
/// Priority:
///   1. LiDAR  (ARWorldTrackingConfiguration.supportsSceneReconstruction)
///   2. Camera depth  (ARWorldTrackingConfiguration.supportsFrameSemantics)
///   3. Plate-based 2D fallback
final class DepthModeDetector {

    /// The three depth tiers — raw values match the Dart `DepthMode` enum.
    enum Mode: String {
        case lidar          = "lidar"
        case cameraDepth    = "camera_depth"
        case plateFallback  = "plate_fallback"
    }

    /// Run detection once (result is deterministic per device).
    func detect() -> Mode {
        guard ARWorldTrackingConfiguration.isSupported else {
            return .plateFallback
        }

        // LiDAR — available on Pro models (iPhone 12 Pro+, iPad Pro 2020+)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            return .lidar
        }

        // Camera-based depth (sceneDepth via neural engine, iOS 14+)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            return .cameraDepth
        }

        return .plateFallback
    }
}
