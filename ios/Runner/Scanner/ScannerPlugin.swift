import Flutter
import Foundation
import AVFoundation
import UIKit

/// Central MethodChannel handler.
///
/// Routes every call from the Dart `NativeBridge` to the correct
/// native service. All JSON encoding / decoding happens here so
/// the individual services stay transport-agnostic.
final class ScannerPlugin {

    // MARK: - Channel name (must match Dart side)

    private static let channelName = "com.pixelstomacros/scanner"

    // MARK: - Services

    private static let depthDetector = DepthModeDetector()
    /// Exposed (internal) so AppDelegate can pass it to ARCameraPreviewFactory.
    static let sessionManager = ARSessionManager()
    private static let captureService = FrameCaptureService()
    private static let pipeline = InferencePipeline()
    private static let pointCloudExporter = PointCloudExporter()
    /// Accumulates frames during a video-sweep recording session.
    private static let recorder = MultiFrameRecorder()

    // MARK: - Registration

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )

        channel.setMethodCallHandler { call, result in
            handleMethodCall(call, result: result)
        }
    }

    // MARK: - Method routing

    private static func handleMethodCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {

        case "getDepthMode":
            let mode = depthDetector.detect()
            result(mode.rawValue)

        case "startSession":
            sessionManager.start { error in
                if let error {
                    result(FlutterError(
                        code: "AR_START_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    // Return the generation number so Dart doesn't need a
                    // second round-trip to call getSessionGeneration.
                    result(sessionManager.generation)
                }
            }

        case "stopSession":
            // Support generation-aware stop to prevent stale dispose() calls
            // from killing a freshly started session.
            if let args = call.arguments as? [String: Any],
               let gen = args["generation"] as? Int {
                sessionManager.stop(generation: gen)
            } else {
                sessionManager.stop()
            }
            result(nil)

        case "getSessionGeneration":
            result(sessionManager.generation)

        case "captureFrame":
            handleCaptureFrame(call, result: result)

        case "runInference":
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let json = try pipeline.run(captureService: captureService)
                    DispatchQueue.main.async { result(json) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "INFERENCE_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
                }
            }

        case "startRecording":
            // Must run on main thread — Timer requires a RunLoop.
            DispatchQueue.main.async {
                recorder.startRecording(sessionManager: sessionManager)
                result(nil)
            }

        case "stopRecording":
            recorder.stopRecording()
            result(nil)

        case "runVideoInference":
            DispatchQueue.global(qos: .userInitiated).async {
                // Capture result callback — must be called exactly once.
                var resultCalled = false
                let safeResult: FlutterResult = { value in
                    guard !resultCalled else { return }
                    resultCalled = true
                    DispatchQueue.main.async { result(value) }
                }

                do {
                    let json = try pipeline.runVideoScan(recorder: recorder)
                    recorder.releaseAll()
                    safeResult(json)
                } catch {
                    recorder.releaseAll()
                    print("[ScannerPlugin] runVideoInference failed: \(error)")
                    safeResult(FlutterError(
                        code: "VIDEO_INFERENCE_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }

        case "exportPointCloud":
            DispatchQueue.global(qos: .userInitiated).async {
                let ply = pointCloudExporter.exportFromCapture(
                    captureService: captureService
                )
                DispatchQueue.main.async {
                    if let ply {
                        result(ply)
                    } else {
                        result(FlutterError(
                            code: "PLY_EXPORT_FAILED",
                            message: "No depth data available for point cloud",
                            details: nil
                        ))
                    }
                }
            }

        case "getPhonePitch":
            // Return phone pitch in radians.
            // -π/2 ≈ pointing straight down (top-view), 0 ≈ horizontal.
            recorder.updatePitch(from: sessionManager)
            result(Double(recorder.currentPitch))

        case "getMemoryUsage":
            result(getResidentMemory())

        case "getSessionError":
            if let error = sessionManager.lastSessionError {
                result(error.localizedDescription)
            } else {
                result(nil)
            }

        case "upgradeDepthConfig":
            sessionManager.upgradeToDepthConfig()
            result(nil)

        case "scanBarcode":
            // Present the native barcode scanner, query OpenFoodFacts,
            // and return a JSON string (or nil on cancel/not found).
            var color: UIColor? = nil
            if let args = call.arguments as? [String: Any],
               let r = args["r"] as? Double,
               let g = args["g"] as? Double,
               let b = args["b"] as? Double {
                color = UIColor(red: r, green: g, blue: b, alpha: 1)
            }
            BarcodeScannerPlugin.present(result: result, themeColor: color)

        case "setTorch":
            // Toggle the device flashlight. Args: { "on": Bool }.
            // Returns true on success, false otherwise.
            let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
            result(setTorch(on: on))

        case "getAmbientIntensity":
            // Returns ARFrame.lightEstimate.ambientIntensity in lux.
            // ~1000 lux = neutral, < 200 lux is "dark".
            // Returns -1 if no estimate yet.
            if let frame = sessionManager.latestFrame,
               let est = frame.lightEstimate {
                result(Double(est.ambientIntensity))
            } else {
                result(-1.0)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Torch helper

    /// Best-effort flashlight toggle. Returns whether we successfully changed state.
    private static func setTorch(on: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        guard device.hasTorch, device.isTorchAvailable else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            return true
        } catch {
            print("[ScannerPlugin] Torch toggle failed: \(error)")
            return false
        }
    }

    // MARK: - captureFrame helper

    private static func handleCaptureFrame(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard
            let args = call.arguments as? [String: Any],
            let frameType = args["type"] as? String
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing 'type' argument (top | side)",
                details: nil
            ))
            return
        }

        captureService.capture(
            session: sessionManager.session,
            frameType: frameType
        ) { captureResult in
            switch captureResult {
            case .success(let json):
                result(json)
            case .failure(let error):
                result(FlutterError(
                    code: "CAPTURE_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    // MARK: - Memory helper

    private static func getResidentMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
