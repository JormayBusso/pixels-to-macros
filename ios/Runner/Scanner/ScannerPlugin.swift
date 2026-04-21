import Flutter
import Foundation

/// Central MethodChannel handler.
///
/// Routes every call from the Dart `NativeBridge` to the correct
/// native service. All JSON encoding / decoding happens here so
/// the individual services stay transport-agnostic.
final class ScannerPlugin {

    // MARK: – Channel name (must match Dart side)

    private static let channelName = "com.pixelstomacros/scanner"

    // MARK: – Services

    private static let depthDetector = DepthModeDetector()
    private static let sessionManager = ARSessionManager()
    private static let captureService = FrameCaptureService()
    private static let pipeline = InferencePipeline()

    // MARK: – Registration

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )

        channel.setMethodCallHandler { call, result in
            switch call.method {

            // ── Device capabilities ──────────────────────────────────
            case "getDepthMode":
                let mode = depthDetector.detect()
                result(mode.rawValue)

            // ── AR session lifecycle ─────────────────────────────────
            case "startSession":
                sessionManager.start { error in
                    if let error {
                        result(FlutterError(
                            code: "AR_START_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    } else {
                        result(nil) // void success
                    }
                }

            case "stopSession":
                sessionManager.stop()
                result(nil)

            // ── Frame capture ────────────────────────────────────────
            case "captureFrame":
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

            // ── ML inference ─────────────────────────────────────────
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

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
