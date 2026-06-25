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
    /// Accumulates frames for a scan. With the guided dual-photo flow it holds
    /// the two deliberate captures (top + side); the legacy video sweep filled
    /// the same slots frame-by-frame.
    private static let recorder = MultiFrameRecorder()
    /// CoreMotion stability monitor driving the auto-shutter "hold steady" gate.
    private static let motionMonitor = MotionStabilityMonitor()
    /// PLY snapshot from the most recent scan. The recorder releases buffers
    /// after inference, so export keeps this lightweight text copy.
    private static var lastVideoPLY: String?

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
                    // Begin device-motion monitoring so the guided dual-photo
                    // capture can gate its auto-shutter on a stable hold.
                    motionMonitor.start()
                    // Return the generation number so Dart doesn't need a
                    // second round-trip to call getSessionGeneration.
                    result(sessionManager.generation)
                }
            }

        case "stopSession":
            // Support generation-aware stop to prevent stale dispose() calls
            // from killing a freshly started session.
            motionMonitor.stop()
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

        // ── Guided dual-photo capture ───────────────────────────────────────
        case "beginScan":
            // Reset the recorder for a fresh top→side capture session.
            DispatchQueue.main.async {
                lastVideoPLY = nil
                recorder.beginTwoShotCapture()
                result(nil)
            }

        case "captureTopFrame":
            let ok = recorder.captureTopFrame(from: sessionManager)
            result(ok)

        case "captureSideFrame":
            let ok = recorder.captureSideFrame(from: sessionManager)
            result(ok)

        case "getMotionStability":
            // 0…1 where 1 = perfectly still. Drives the auto-shutter gate.
            result(motionMonitor.stability)

        case "startRecording":
            // Must run on main thread — Timer requires a RunLoop.
            DispatchQueue.main.async {
                lastVideoPLY = nil
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

                var swiftError: Error? = nil
                var jsonResult: String? = nil
                var objcException: NSException? = nil
                let ok = tryCatchObjC({
                    do {
                        jsonResult = try pipeline.runVideoScan(recorder: recorder)
                        lastVideoPLY = pointCloudExporter.exportFromRecorder(recorder: recorder)
                    } catch {
                        swiftError = error
                    }
                }, &objcException)
                recorder.releaseAll()
                if let json = jsonResult {
                    safeResult(json)
                } else if !ok, let ex = objcException {
                    let reason = ex.reason ?? "unknown"
                    print("[ScannerPlugin] runVideoInference ObjC exception: \(ex.name.rawValue): \(reason)")
                    safeResult(FlutterError(
                        code: "VIDEO_INFERENCE_FAILED",
                        message: "\(ex.name.rawValue): \(reason)",
                        details: nil
                    ))
                } else if let err = swiftError {
                    print("[ScannerPlugin] runVideoInference failed: \(err)")
                    if let pipelineError = err as? InferencePipeline.PipelineError,
                       case .noFoodDetected(let reason) = pipelineError {
                        safeResult(FlutterError(
                            code: "NO_FOOD_DETECTED",
                            message: "No food detected.",
                            details: reason
                        ))
                        return
                    }
                    if let pipelineError = err as? InferencePipeline.PipelineError,
                       case .dualSilhouetteFailed(let reason, let debug) = pipelineError {
                        safeResult(FlutterError(
                            code: "DUAL_SILHOUETTE_FAILED",
                            message: reason,
                            details: debug
                        ))
                        return
                    }
                    safeResult(FlutterError(
                        code: "VIDEO_INFERENCE_FAILED",
                        message: err.localizedDescription,
                        details: nil
                    ))
                } else {
                    safeResult(FlutterError(code: "VIDEO_INFERENCE_FAILED", message: "Unknown error", details: nil))
                }
            }

        case "exportPointCloud":
            DispatchQueue.global(qos: .userInitiated).async {
                let ply = pointCloudExporter.exportFromCapture(
                    captureService: captureService
                ) ?? lastVideoPLY
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

        case "getPhoneRoll":
            // Return device roll about the viewing axis in radians, or 999 when
            // the phone is flat (orientation ambiguous). 0 ≈ portrait,
            // ±π/2 ≈ landscape, ±π ≈ upside-down.
            recorder.updateRoll(from: sessionManager)
            result(Double(recorder.currentRoll))

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

        case "getModel3DPath":
            let model3dPath = pipeline.lastModel3DPath
            print("[ScannerPlugin] model3dPath = \(model3dPath ?? "nil")")
            result(model3dPath)

        case "getScanCapturePaths":
            var payload: [String: Any] = [:]
            if let path = recorder.topImagePath { payload["topImagePath"] = path }
            if let path = recorder.sideImagePath { payload["sideImagePath"] = path }
            if let path = pipeline.lastModel3DPath { payload["modelPath"] = path }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let json = String(data: data, encoding: .utf8) {
                result(json)
            } else {
                result(nil)
            }

        case "getModel3DObjects":
            // Per-object metadata for the most-recent 3-D model. Mirrors the
            // MDLMesh order in the USDZ exactly so Flutter UI can address
            // the same objects the SceneKit viewer hit-tests by `id`.
            result(pipeline.lastModel3DObjects)

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
