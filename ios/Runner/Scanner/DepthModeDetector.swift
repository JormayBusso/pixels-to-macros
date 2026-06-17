import ARKit
import Foundation

/// Detects the device's scanning capabilities at runtime and selects a
/// scan **tier**.
///
/// Target devices: **iPhone 15 and newer**. Across this range, ARKit
/// `sceneDepth` / scene-reconstruction mesh is available **only** on the Pro
/// models that carry a LiDAR sensor (15 Pro / 15 Pro Max / 16 Pro / 16 Pro
/// Max). The non-Pro models (15 / 15 Plus / 16 / 16 Plus) have **no** depth
/// sensor, so they fall back to the camera + reference-scale strategy.
///
/// There are therefore only **two** real tiers — a separate "camera depth"
/// tier (estimated monocular depth) never materialises on these devices, so it
/// is deliberately not modelled.
final class DepthModeDetector {

    // MARK: – Tier

    /// The two scanning strategies supported on iPhone 15+.
    enum ScanTier: String {
        /// LiDAR Pro models: real `sceneDepth` + reconstructed food mesh.
        case lidar  = "lidar"
        /// Non-Pro models: monocular camera + reference-scale estimation.
        case camera = "camera"
    }

    // MARK: – Capabilities

    /// Snapshot of what the current device can do for scanning.
    struct DeviceCapabilities {
        let tier: ScanTier
        let hasLiDAR: Bool
        let supportsSceneDepth: Bool
        let supportsMesh: Bool
        /// Pre-programmed hold distance (cm) used by the camera tier to derive
        /// real-world scale from the camera intrinsics.
        let assumedDistanceCm: Double

        /// JSON dictionary sent across the method channel to Dart.
        var json: [String: Any] {
            [
                "tier":               tier.rawValue,
                "hasLiDAR":           hasLiDAR,
                "supportsSceneDepth": supportsSceneDepth,
                "supportsMesh":       supportsMesh,
                "assumedDistanceCm":  assumedDistanceCm,
            ]
        }
    }

    /// Default hold distance (cm) for the camera tier.
    static let assumedDistanceCm: Double = 30.0

    // MARK: – Detection

    /// Inspect ARKit support flags and build a capability snapshot.
    /// The result is deterministic per device, so callers may cache it.
    func detectCapabilities() -> DeviceCapabilities {
        guard ARWorldTrackingConfiguration.isSupported else {
            // No ARKit at all — treat as the camera tier so the app still runs.
            return DeviceCapabilities(
                tier: .camera,
                hasLiDAR: false,
                supportsSceneDepth: false,
                supportsMesh: false,
                assumedDistanceCm: DepthModeDetector.assumedDistanceCm
            )
        }

        let supportsMesh =
            ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let supportsSceneDepth =
            ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

        // On iPhone 15+, both flags imply a LiDAR sensor is present.
        let hasLiDAR = supportsMesh || supportsSceneDepth
        let tier: ScanTier = hasLiDAR ? .lidar : .camera

        return DeviceCapabilities(
            tier: tier,
            hasLiDAR: hasLiDAR,
            supportsSceneDepth: supportsSceneDepth,
            supportsMesh: supportsMesh,
            assumedDistanceCm: DepthModeDetector.assumedDistanceCm
        )
    }

    /// Convenience accessor for the selected tier.
    func detectTier() -> ScanTier {
        detectCapabilities().tier
    }

    // MARK: – Legacy depth-mode string

    /// Legacy raw value kept for backward compatibility with stored scan
    /// history / benchmarks (the `depthMode` column). New code should prefer
    /// `detectCapabilities()`.
    func detect() -> String {
        let caps = detectCapabilities()
        return caps.tier == .lidar ? "lidar" : "plate_fallback"
    }
}
