import ARKit
import Foundation
import simd

/// A per-device scanning strategy. Encapsulates the **only** things that truly
/// differ between the two supported tiers (iPhone 15+):
///
///   • how the ARKit session is configured,
///   • where the reference [TablePlane] comes from,
///   • whether real per-pixel depth is available, and
///   • the base confidence of the resulting volume.
///
/// The shared volume integration (height-above-plane) lives in the volume
/// engine and consumes whatever a strategy provides, so the pipeline never
/// branches on the device tier itself.
protocol ScanStrategy: AnyObject {

    /// The tier this strategy implements.
    var tier: DepthModeDetector.ScanTier { get }

    /// Base confidence (0…1) for volumes produced under this strategy, before
    /// any per-scan adjustments. LiDAR measures real geometry, the camera tier
    /// estimates it — so they start from very different priors.
    var baseConfidence: Float { get }

    /// Whether this strategy yields a real, dense depth map per frame.
    var providesMeasuredDepth: Bool { get }

    /// Hold distance (metres) assumed when synthesising the virtual table
    /// plane / deriving camera-tier scale.
    var assumedDistanceM: Float { get }

    /// Apply the tier-specific ARKit configuration (depth, mesh, plane
    /// detection) onto a world-tracking config before it is run.
    func configure(_ config: ARWorldTrackingConfiguration)
}

// MARK: – Volume estimate

/// A coarse height-field describing one food's 3-D surface, used to render the
/// live 3-D object. Heights are in cm above the table plane; `0` marks cells
/// with no food. Cell size is real-world cm so the rendered model is to scale.
struct FoodSurfaceGrid {
    let cols: Int
    let rows: Int
    let cellWcm: Double
    let cellHcm: Double
    /// Row-major heights (cm), length = cols * rows.
    let heightsCm: [Double]
}

/// Result of converting one segmented food region into a 3-D volume.
struct FoodVolumeEstimate {
    let label: String
    let volumeCm3: Double
    /// Mean height of the food above the table plane (cm) — diagnostic.
    let heightCm: Double
    /// 0…1 confidence in this estimate (tier + data driven).
    let confidence: Float
    /// How the volume was derived.
    let source: TablePlane.Source
    /// Coarse surface for 3-D rendering (nil if it could not be built).
    let surface: FoodSurfaceGrid?
}

// MARK: – LiDAR strategy

/// Pro / LiDAR devices: real `sceneDepth` + scene-reconstruction mesh.
///
/// Volume is integrated from the measured depth map relative to the detected
/// table plane, and the reconstructed mesh drives the live 3-D food object.
final class LiDARScanStrategy: ScanStrategy {

    let tier: DepthModeDetector.ScanTier = .lidar
    let baseConfidence: Float = 0.85
    let providesMeasuredDepth = true
    let assumedDistanceM: Float

    init(assumedDistanceCm: Double = DepthModeDetector.assumedDistanceCm) {
        self.assumedDistanceM = Float(assumedDistanceCm / 100.0)
    }

    func configure(_ config: ARWorldTrackingConfiguration) {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        // Horizontal plane detection anchors the table datum.
        config.planeDetection = [.horizontal]
    }
}

// MARK: – Camera strategy

/// Non-Pro devices: monocular camera, no depth sensor.
///
/// Real-world scale is derived from the camera intrinsics at the pre-programmed
/// hold distance (30 cm), optionally refined by reference objects (plate /
/// cutlery — added in the reference-scale phase). Food height comes from
/// per-class priors, and the extruded segmentation mask becomes the estimated
/// 3-D food object.
final class CameraScanStrategy: ScanStrategy {

    let tier: DepthModeDetector.ScanTier = .camera
    let baseConfidence: Float = 0.5
    let providesMeasuredDepth = false
    let assumedDistanceM: Float

    init(assumedDistanceCm: Double = DepthModeDetector.assumedDistanceCm) {
        self.assumedDistanceM = Float(assumedDistanceCm / 100.0)
    }

    func configure(_ config: ARWorldTrackingConfiguration) {
        // No depth or mesh on these devices; horizontal plane detection still
        // improves tracking stability for the top-down hold.
        config.planeDetection = [.horizontal]
    }
}

// MARK: – Factory

enum ScanStrategyFactory {
    /// Build the strategy that matches the device's detected capabilities.
    static func make(for caps: DepthModeDetector.DeviceCapabilities) -> ScanStrategy {
        switch caps.tier {
        case .lidar:
            return LiDARScanStrategy(assumedDistanceCm: caps.assumedDistanceCm)
        case .camera:
            return CameraScanStrategy(assumedDistanceCm: caps.assumedDistanceCm)
        }
    }
}
