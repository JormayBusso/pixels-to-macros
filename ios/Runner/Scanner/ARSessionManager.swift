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
            break // RGB only — no depth semantics
        }

        // Limit frame rate to save memory (Part 3 — performance safety)
        config.videoFormat = ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { $0.imageResolution.width <= 640 }
            .first ?? ARWorldTrackingConfiguration.supportedVideoFormats.first!

        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Notify any camera preview platform views that the session is live
        NotificationCenter.default.post(name: .arSessionDidStart, object: session)

        // ARKit doesn't have a "ready" callback — treat run() as success
        // unless configuration itself is unsupported.
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
    }
}

// MARK: – Notification names

extension Notification.Name {
    /// Posted (with the ARSession as object) once session.run() is called.
    static let arSessionDidStart = Notification.Name("com.pixelstomacros.arSessionDidStart")
}
