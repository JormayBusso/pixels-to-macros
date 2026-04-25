import ARKit
import Foundation

/// Manages the ARKit world-tracking session lifecycle.
///
/// - Configures the session for the best depth mode available.
/// - Automatically falls back to simpler configs if the session fails.
/// - Verifies frame production before reporting success to Dart.
/// - Uses a generation counter so stale stop() calls never kill a new session.
final class ARSessionManager: NSObject, ARSessionDelegate {

    // MARK: – Public

    /// The underlying ARKit session. `nil` until `start()` succeeds.
    private(set) var session: ARSession?

    /// Monotonically increasing counter. Each `start()` increments it;
    /// `stop(generation:)` only acts when the generation matches, preventing
    /// a fire-and-forget stop from a disposed screen from killing a fresh session.
    private(set) var generation: Int = 0

    /// Last error reported by the ARSession delegate (cleared on each start).
    private(set) var lastSessionError: Error?

    /// The most recent AR frame.
    var latestFrame: ARFrame? {
        return session?.currentFrame
    }

    // MARK: – Session lifecycle

    /// Start (or restart) the AR session with automatic fallback.
    /// Completion is called on the main thread once a frame is verified
    /// or all config levels have been exhausted.
    func start(completion: @escaping (Error?) -> Void) {
        generation += 1
        startWithLevel(0, generation: generation, completion: completion)
    }

    /// Pause and release the session.
    /// If `generation` is provided, only stops when it matches the current
    /// generation — this prevents a stale stop() from killing a newer session.
    func stop(generation: Int? = nil) {
        if let gen = generation, gen != self.generation {
            print("[ARSessionManager] Ignoring stale stop (gen \(gen) vs current \(self.generation))")
            return
        }
        session?.pause()
        session = nil
    }

    // MARK: – Private: config levels

    /// Configuration levels (automatic fallback chain):
    ///   0 = full depth + mesh (LiDAR/TrueDepth as detected)
    ///   1 = basic world tracking (no depth semantics)
    ///   2 = minimal (no depth, low-res video format)
    private func startWithLevel(
        _ level: Int,
        generation gen: Int,
        completion: @escaping (Error?) -> Void
    ) {
        // Abort if a newer start() has been issued while we were falling back.
        guard gen == generation else { return }

        lastSessionError = nil

        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                completion(NSError(
                    domain: "ARSessionManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "ARWorldTrackingConfiguration is not supported on this device"]
                ))
            }
            return
        }

        session?.pause()
        session = nil

        let newSession = ARSession()
        newSession.delegate = self
        self.session = newSession

        let config = makeConfig(level: level)

        print("[ARSessionManager] Starting session (gen \(gen), config level \(level))")
        newSession.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Notify camera preview platform views that the session is live.
        NotificationCenter.default.post(name: .arSessionDidStart, object: newSession)

        // Wait for the first frame or an async session error before telling
        // Dart the session is ready.  15 attempts × 100 ms = 1.5 s max.
        verifySession(
            attemptsRemaining: 15,
            configLevel: level,
            generation: gen,
            completion: completion
        )
    }

    /// Build an ARWorldTrackingConfiguration for the given fallback level.
    private func makeConfig(level: Int) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()

        guard level == 0 else {
            // Level 1+: basic world tracking, no depth semantics.
            if level >= 2 {
                if let lowRes = ARWorldTrackingConfiguration.supportedVideoFormats
                    .filter({ $0.imageResolution.width <= 1280 })
                    .min(by: { $0.imageResolution.width < $1.imageResolution.width }) {
                    config.videoFormat = lowRes
                }
            }
            return config
        }

        // Level 0: full depth support based on device capabilities.
        let mode = DepthModeDetector().detect()
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
            if let lowRes = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter({ $0.imageResolution.width <= 1280 })
                .min(by: { $0.imageResolution.width < $1.imageResolution.width }) {
                config.videoFormat = lowRes
            }
        }
        return config
    }

    // MARK: – Verification loop

    /// Poll for first AR frame or session error.
    private func verifySession(
        attemptsRemaining: Int,
        configLevel: Int,
        generation gen: Int,
        completion: @escaping (Error?) -> Void
    ) {
        // Stale generation — abort.
        guard gen == generation else { return }

        // 1. Check for async error from the delegate.
        if let error = lastSessionError {
            print("[ARSessionManager] Session failed at level \(configLevel): "
                  + "\(error.localizedDescription)")
            if configLevel < 2 {
                print("[ARSessionManager] Falling back to level \(configLevel + 1)")
                startWithLevel(configLevel + 1, generation: gen, completion: completion)
            } else {
                DispatchQueue.main.async { completion(error) }
            }
            return
        }

        // 2. Check for first frame.
        if session?.currentFrame != nil {
            print("[ARSessionManager] Session verified — frame available (level \(configLevel))")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // 3. Timeout — no frame and no error; proceed optimistically.
        if attemptsRemaining <= 0 {
            print("[ARSessionManager] Verification timeout (level \(configLevel)) — proceeding")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // 4. Poll again in 100 ms.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.verifySession(
                attemptsRemaining: attemptsRemaining - 1,
                configLevel: configLevel,
                generation: gen,
                completion: completion
            )
        }
    }

    // MARK: – ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[ARSessionManager] Session error: \(error.localizedDescription)")
        lastSessionError = error
        NotificationCenter.default.post(
            name: .arSessionDidFail,
            object: error
        )
    }

    /// ARKit may attempt to recover after certain interruptions.
    func sessionWasInterrupted(_ session: ARSession) {
        print("[ARSessionManager] Session interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("[ARSessionManager] Interruption ended — resetting tracking")
        session.run(session.configuration!, options: [.resetTracking])
        NotificationCenter.default.post(name: .arSessionDidStart, object: session)
    }
}

// MARK: – Notification names

extension Notification.Name {
    static let arSessionDidStart = Notification.Name("com.pixelstomacros.arSessionDidStart")
    static let arSessionDidFail  = Notification.Name("com.pixelstomacros.arSessionDidFail")
}
