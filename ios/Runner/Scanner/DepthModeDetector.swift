import ARKit
import AVFoundation
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
///
/// LiDAR is detected via `AVCaptureDevice` hardware discovery first, because
/// the ARKit `supportsFrameSemantics` / `supportsSceneReconstruction` checks
/// can wrongly return `false` on some iOS 26 builds even on LiDAR devices.
final class DepthModeDetector {

    /// Scan tiers. Raw values are persisted in Dart scan history, so keep them
    /// stable and descriptive.
    enum Mode: String {
        case lidarMesh      = "lidar_mesh"
        case lidarDepth     = "lidar_depth"
        case monocularScale = "monocular_scale"
        case unsupported    = "unsupported"
    }

    /// Detect LiDAR hardware via AVCaptureDevice discovery session.
    static var hasLiDARHardware: Bool {
        if #available(iOS 15.4, *) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInLiDARDepthCamera],
                mediaType: .video,
                position: .back
            )
            return !discovery.devices.isEmpty
        }
        return false
    }

    /// Detect any depth-capable camera (triple, dual-wide).
    static var hasDepthCamera: Bool {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )
        return !discovery.devices.isEmpty
    }

    /// Run detection once (result is deterministic per device).
    func detect() -> Mode {
        let hasLiDAR    = DepthModeDetector.hasLiDARHardware
        let hasDepth    = DepthModeDetector.hasDepthCamera
        let arSupported = ARWorldTrackingConfiguration.isSupported

        // ARKit capability checks — used only as a secondary signal and for
        // diagnostics. On some iOS 26 builds these wrongly return `false` even
        // on LiDAR hardware, so they must never be the sole source of truth.
        let arkitMesh     = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let arkitSmoothed = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
        let arkitDepth    = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

        #if targetEnvironment(simulator)
        let deviceModel = "simulator"
        #else
        var sysinfo = utsname()
        uname(&sysinfo)
        let deviceModel = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
        #endif

        print("[LIDAR] hardwareDetected=\(hasLiDAR)")
        print("[LIDAR] depthCameraDetected=\(hasDepth)")
        print("[LIDAR] deviceModel=\(deviceModel)")
        print("[LIDAR] arSupported=\(arSupported), arkitMesh=\(arkitMesh), arkitSmoothed=\(arkitSmoothed), arkitDepth=\(arkitDepth)")

        guard arSupported else {
            print("[LIDAR] mode=unsupported (AR not supported)")
            return .unsupported
        }

        // Primary: LiDAR hardware detected via AVCaptureDevice discovery. This
        // is robust on iOS 26 where the ARKit capability checks misreport.
        if hasLiDAR {
            print("[LIDAR] mode=lidarMesh (LiDAR hardware)")
            return .lidarMesh
        }

        // Secondary: ARKit reports mesh/depth even though AVCapture found no
        // dedicated LiDAR camera (future hardware).
        if arkitMesh {
            print("[LIDAR] mode=lidarMesh (ARKit mesh)")
            return .lidarMesh
        }
        if arkitSmoothed || arkitDepth {
            print("[LIDAR] mode=lidarDepth (ARKit depth)")
            return .lidarDepth
        }

        // Non-LiDAR devices still scan with segmentation + scale references.
        print("[LIDAR] mode=monocularScale (depthCamera=\(hasDepth))")
        return .monocularScale
    }
}
