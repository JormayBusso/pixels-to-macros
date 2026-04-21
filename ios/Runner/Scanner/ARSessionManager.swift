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

    /// The most recent AR frame (updated every delegate callback).
    private(set) var latestFrame: ARFrame?

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

        // ARKit doesn't have a "ready" callback — treat run() as success
        // unless configuration itself is unsupported.
        DispatchQueue.main.async {
            completion(nil)
        }
    }

    /// Pause and release the session.
    func stop() {
        session?.pause()
        latestFrame = nil
        session = nil
    }

    // MARK: – ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[ARSessionManager] Session error: \(error.localizedDescription)")
    }
}
