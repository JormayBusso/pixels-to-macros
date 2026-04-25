import ARKit
import AVFoundation
import Foundation

/// Manages the ARKit world-tracking session lifecycle.
///
/// Key design decisions:
///   - Camera authorisation is verified natively (AVCaptureDevice) before
///     touching ARKit, so a missing or broken permission_handler pod can
///     never leave us in limbo.
///   - The session starts with the **simplest possible** config (no depth,
///     no mesh, no custom video format). Depth features are added later via
///     `upgradeToDepthConfig()` once the camera is proven to work.
///   - Two attempts are made (first try + one retry). Each attempt waits up
///     to 5 s for the first frame. On timeout the session is treated as
///     failed (no optimistic fallthrough).
///   - A generation counter prevents stale `stop()` calls from killing a
///     freshly started session.
final class ARSessionManager: NSObject, ARSessionDelegate {

    // MARK: – Public state

    /// The live ARKit session.  `nil` until `start()` succeeds.
    private(set) var session: ARSession?

    /// Monotonically increasing counter — prevents stale stops.
    private(set) var generation: Int = 0

    /// Last error reported by `session(_:didFailWithError:)`.
    private(set) var lastSessionError: Error?

    /// Convenience accessor — always reads from the session directly so it
    /// works even if the delegate is hijacked.
    var latestFrame: ARFrame? { session?.currentFrame }

    // MARK: – Start

    /// Start (or restart) the AR session.
    ///
    /// 1. Checks native camera authorisation.
    /// 2. Starts a bare `ARWorldTrackingConfiguration`.
    /// 3. Verifies frame production (up to 5 s).
    /// 4. Retries once if the first attempt fails.
    ///
    /// `completion` is always called on the **main thread**.
    func start(completion: @escaping (Error?) -> Void) {
        generation += 1
        let gen = generation
        lastSessionError = nil

        // ── 1. Native camera authorisation ──────────────────────────────
        let auth = AVCaptureDevice.authorizationStatus(for: .video)

        switch auth {
        case .authorized:
            // Camera is ready — proceed.
            beginSession(generation: gen, attempt: 0, completion: completion)

        case .notDetermined:
            // First launch — ask the user.  The callback fires on an
            // arbitrary queue, so dispatch back to main.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, gen == self.generation else { return }
                    if granted {
                        // Small delay so iOS fully releases the camera from
                        // the permission-dialog process.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            guard gen == self.generation else { return }
                            self.beginSession(generation: gen, attempt: 0,
                                              completion: completion)
                        }
                    } else {
                        completion(self.makeError(
                            code: -2,
                            msg: "Camera permission denied. Open Settings → "
                               + "Privacy → Camera and enable access for this app."
                        ))
                    }
                }
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                completion(self.makeError(
                    code: -3,
                    msg: "Camera access is denied or restricted. Open Settings → "
                       + "Privacy → Camera and enable access for this app."
                ))
            }

        @unknown default:
            beginSession(generation: gen, attempt: 0, completion: completion)
        }
    }

    /// Pause and release the session.
    func stop(generation gen: Int? = nil) {
        if let gen, gen != self.generation {
            print("[ARSession] Ignoring stale stop (gen \(gen) vs \(self.generation))")
            return
        }
        session?.delegate = nil
        session?.pause()
        session = nil
    }

    /// After the base session is running, call this to add depth/mesh
    /// features without tearing down the camera.  Safe to call repeatedly.
    func upgradeToDepthConfig() {
        guard let session else { return }

        let config = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        // `run(_:)` on an already-running session reconfigures without
        // restarting the camera pipeline.
        session.run(config)
        print("[ARSession] Upgraded to depth config")
    }

    // MARK: – Private: session lifecycle

    /// Actually create and run the ARSession (called after auth check).
    private func beginSession(
        generation gen: Int,
        attempt: Int,
        completion: @escaping (Error?) -> Void
    ) {
        guard gen == generation else { return }

        lastSessionError = nil

        guard ARWorldTrackingConfiguration.isSupported else {
            completion(makeError(code: -1,
                msg: "ARWorldTrackingConfiguration is not supported on this device."))
            return
        }

        // ── Tear down any previous session ──────────────────────────────
        session?.delegate = nil
        session?.pause()
        session = nil

        // ── Create a fresh session with the simplest possible config ────
        let config = ARWorldTrackingConfiguration()
        // No depth, no mesh, no custom video format — this must work on
        // every ARKit-capable device.

        let s = ARSession()
        s.delegate = self
        session = s

        print("[ARSession] run() — gen \(gen), attempt \(attempt)")
        s.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Tell platform views the session is live.
        NotificationCenter.default.post(name: .arSessionDidStart, object: s)

        // ── Verify first frame (50 × 100 ms = 5 s) ─────────────────────
        verifySession(
            attemptsRemaining: 50,
            attempt: attempt,
            generation: gen,
            completion: completion
        )
    }

    // MARK: – Verification

    private func verifySession(
        attemptsRemaining: Int,
        attempt: Int,
        generation gen: Int,
        completion: @escaping (Error?) -> Void
    ) {
        guard gen == generation else { return }

        // 1. Delegate reported an error → retry or fail.
        if let error = lastSessionError {
            print("[ARSession] Error on attempt \(attempt): \(error.localizedDescription)")
            if attempt < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, gen == self.generation else { return }
                    self.beginSession(generation: gen, attempt: attempt + 1,
                                      completion: completion)
                }
            } else {
                DispatchQueue.main.async { completion(error) }
            }
            return
        }

        // 2. First frame arrived → success.
        if session?.currentFrame != nil {
            print("[ARSession] Verified — frames flowing (attempt \(attempt))")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // 3. Still waiting — poll again.
        if attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.verifySession(
                    attemptsRemaining: attemptsRemaining - 1,
                    attempt: attempt,
                    generation: gen,
                    completion: completion
                )
            }
            return
        }

        // 4. Timeout — no frames AND no error.
        print("[ARSession] Timeout on attempt \(attempt) — no frames received")
        if attempt < 1 {
            // One more try with a completely fresh session.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, gen == self.generation else { return }
                self.beginSession(generation: gen, attempt: attempt + 1,
                                  completion: completion)
            }
        } else {
            completion(makeError(code: -4,
                msg: "Camera timed out — no frames received after 5 s. "
                   + "Try closing other apps using the camera and restart."))
        }
    }

    // MARK: – ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard session === self.session else {
            print("[ARSession] Ignoring error from stale session")
            return
        }
        print("[ARSession] didFailWithError: \(error.localizedDescription)")
        lastSessionError = error
        NotificationCenter.default.post(name: .arSessionDidFail, object: error)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("[ARSession] Interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("[ARSession] Interruption ended — resetting tracking")
        if let cfg = session.configuration {
            session.run(cfg, options: [.resetTracking])
        }
        NotificationCenter.default.post(name: .arSessionDidStart, object: session)
    }

    // MARK: – Helpers

    private func makeError(code: Int, msg: String) -> NSError {
        NSError(domain: "ARSessionManager", code: code,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

// MARK: – Notification names

extension Notification.Name {
    static let arSessionDidStart = Notification.Name("com.pixelstomacros.arSessionDidStart")
    static let arSessionDidFail  = Notification.Name("com.pixelstomacros.arSessionDidFail")
}
