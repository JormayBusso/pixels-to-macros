import ARKit
import Foundation

/// Detects the best available scan mode at runtime (Part 2).
///
/// This is deliberately capability-based, not model-name-based. It works for
/// iPhone 15/16/17 and future devices because ARKit is the source of truth.
///
/// Priority:
///   1. LiDAR mesh reconstruction  (highest accuracy)
///   2. LiDAR depth only           (metric depth, no mesh reconstruction)
///   3. Monocular scale estimate   (plate/utensil/30 cm camera fallback)
final class DepthModeDetector {

    /// Scan tiers. Raw values are persisted in Dart scan history, so keep them
    /// stable and descriptive.
    enum Mode: String {
        case lidarMesh      = "lidar_mesh"
        case lidarDepth     = "lidar_depth"
        case monocularScale = "monocular_scale"
        case unsupported    = "unsupported"
    }

    /// Run detection once (result is deterministic per device).
    func detect() -> Mode {
        guard ARWorldTrackingConfiguration.isSupported else {
            return .unsupported
        }

        // Highest tier: LiDAR-backed scene reconstruction mesh. This is the
        // correct check for "Pro-like" scanner hardware; never check the
        // marketing model name.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            return .lidarMesh
        }

        // Depth tier: future hardware may expose depth without mesh support.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            return .lidarDepth
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            return .lidarDepth
        }

        // Non-LiDAR devices still scan with segmentation + scale references.
        return .monocularScale
    }
}
