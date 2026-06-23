import CoreMotion
import Foundation

/// Real-time device-motion stability monitor for the guided dual-photo capture.
///
/// Uses CoreMotion device-motion (fused gyroscope + accelerometer) to measure
/// how still the phone is being held. The capture state machine in Flutter
/// polls `stability` (0…1, where 1 == perfectly still) and only fires the
/// automatic shutter once the device is both correctly oriented AND stable —
/// this is what keeps the top/side photos sharp and free of motion blur.
///
/// CoreMotion device-motion does NOT require any privacy permission (unlike
/// pedometer / activity), so this is safe to start alongside the AR session.
final class MotionStabilityMonitor {

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()

    /// Rolling window of recent combined-motion magnitudes (gyro rad/s plus a
    /// weighted user-acceleration term in g). We report stability from the peak
    /// of this window so a brief jolt is not masked by an averaged value.
    private var samples: [Double] = []
    private let windowSize = 12

    /// Motion magnitude (combined units) at/above which the device is treated
    /// as "moving" → stability 0. Holding a phone still reads well under 0.05;
    /// natural hand tremor during a macro shot is often 0.08–0.22, while a
    /// deliberate reframing move reads 0.4–2.0. 0.38 keeps the shutter from
    /// firing during a real move but no longer demands perfect stillness.
    private let motionCeiling: Double = 0.38

    private(set) var isRunning = false

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        isRunning = true
        lock.lock(); samples.removeAll(); lock.unlock()

        manager.deviceMotionUpdateInterval = 1.0 / 50.0   // 50 Hz
        queue.maxConcurrentOperationCount = 1
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            // Gyroscope angular velocity magnitude (rad/s) — the dominant blur
            // cause for a hand-held macro shot.
            let r = m.rotationRate
            let rotMag = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            // User acceleration magnitude (g, gravity already removed). Weighted
            // up so translational shake also suppresses the shutter.
            let a = m.userAcceleration
            let accMag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let combined = rotMag + accMag * 2.5

            self.lock.lock()
            self.samples.append(combined)
            if self.samples.count > self.windowSize {
                self.samples.removeFirst(self.samples.count - self.windowSize)
            }
            self.lock.unlock()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopDeviceMotionUpdates()
        lock.lock(); samples.removeAll(); lock.unlock()
    }

    /// Stability in 0…1 (1 = perfectly still). Returns 0 until enough samples
    /// have accumulated so the shutter can never fire on a cold/empty window.
    var stability: Double {
        lock.lock()
        let window = samples
        lock.unlock()
        guard window.count >= 4 else { return 0 }
        let sorted = window.sorted()
        let percentileIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.75))
        let motion = sorted[percentileIndex]
        let normalized = 1.0 - min(1.0, motion / motionCeiling)
        return max(0.0, normalized)
    }
}
