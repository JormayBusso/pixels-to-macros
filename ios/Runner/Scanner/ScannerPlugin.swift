import Flutter
import Foundation

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
                    result(nil)
                }
            }

        case "stopSession":
            sessionManager.stop()
            result(nil)

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
                do {
                    let json = try pipeline.runVideoScan(recorder: recorder)
                    recorder.releaseAll()
                    DispatchQueue.main.async { result(json) }
                } catch {
                    recorder.releaseAll()
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "VIDEO_INFERENCE_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    }
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

        case "getMemoryUsage":
            result(getResidentMemory())

        default:
            result(FlutterMethodNotImplemented)
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
