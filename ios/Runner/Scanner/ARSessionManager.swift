import ARKit
import Foundation

/// Manages the ARKit world-tracking session lifecycle.
///
/// - Configures the session for the best depth mode available.
/// - Stores the running `ARSession` so other services can read frames.
/// - Cleans up resources on stop.
final class ARSessionManager: NSObject, ARSessionDelegate {

    // MARK: – Public

    /// The underlying ARKit session. `nil` until `start()` succeeds.
    private(set) var session: ARSession?

    /// The most recent AR frame.
    ///
    /// Reads directly from `session.currentFrame` so it works even when
    /// `ARSCNView` has taken over as the session delegate (which prevents
    /// the `didUpdate` callback from reaching this manager).
    var latestFrame: ARFrame? {
        return session?.currentFrame
    }

    /// Start (or restart) the AR session.
    /// Completion is called on the main thread.
    func start(completion: @escaping (Error?) -> Void) {
        // Guard: ARWorldTracking requires an A9 chip or newer.
        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                completion(NSError(
                    domain: "ARSessionManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "ARWorldTrackingConfiguration is not supported on this device"]
                ))
            }
            return
        }

        let session = ARSession()
        session.delegate = self
        self.session = session

        let config = ARWorldTrackingConfiguration()

        // Enable depth semantics when available
        let detector = DepthModeDetector()
        let mode = detector.detect()

        switch mode {
        case .lidar:
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
        case .cameraDepth:
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
        case .plateFallback:
            // RGB only — no depth semantics.
            // Safe to limit resolution here since no depth formats are needed.
            if let lowResFormat = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter({ $0.imageResolution.width <= 1280 })
                .min(by: { $0.imageResolution.width < $1.imageResolution.width }) {
                config.videoFormat = lowResFormat
            }
        }

        // NOTE: Do NOT restrict videoFormat when depth semantics are enabled.
        // Many depth-capable formats require the native high-res sensor output;
        // forcing a 640-wide format conflicts with sceneDepth and causes silent
        // session failures on LiDAR and TrueDepth devices.

        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Notify any camera preview platform views that the session is live
        NotificationCenter.default.post(name: .arSessionDidStart, object: session)

        // ARKit doesn't have a synchronous "ready" callback — treat run() as
        // success; any hardware failure will surface via didFailWithError.
        DispatchQueue.main.async {
            completion(nil)
        }
    }

    /// Pause and release the session.
    func stop() {
        session?.pause()
        session = nil
    }

    // MARK: – ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[ARSessionManager] Session error: \(error.localizedDescription)")
        // Post a notification so the camera preview (and any interested party)
        // knows the session is no longer running.
        NotificationCenter.default.post(
            name: .arSessionDidFail,
            object: error
        )
    }
}

// MARK: – Notification names

extension Notification.Name {
    /// Posted (with the ARSession as object) once session.run() is called.
    static let arSessionDidStart = Notification.Name("com.pixelstomacros.arSessionDidStart")
    /// Posted (with the Error as object) when the session fails.
    static let arSessionDidFail  = Notification.Name("com.pixelstomacros.arSessionDidFail")
}
