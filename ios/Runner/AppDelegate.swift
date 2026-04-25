import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // GeneratedPluginRegistrant must run before super so Flutter pub-plugins
        // (sqflite, permission_handler, etc.) are ready when the engine starts.
        GeneratedPluginRegistrant.register(with: self)
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // ── Register custom scanner method channel ─────────────────────────
        // Use self.registrar(forPlugin:).messenger() — the canonical Flutter
        // approach.  This works regardless of the view-controller hierarchy and
        // does NOT depend on window.rootViewController being a
        // FlutterViewController (which can fail silently in some build configs).
        if let scannerReg = registrar(forPlugin: "ScannerPlugin") {
            ScannerPlugin.register(with: scannerReg.messenger())
        } else {
            // Fallback: direct cast (should never be needed but keeps us safe)
            if let vc = window?.rootViewController as? FlutterViewController {
                ScannerPlugin.register(with: vc.binaryMessenger)
            }
        }

        // ── Register the live AR camera platform view ──────────────────────
        let cameraFactory = ARCameraPreviewFactory(
            sessionManager: ScannerPlugin.sessionManager
        )
        if let cameraReg = registrar(forPlugin: "ARCameraPreviewPlugin") {
            cameraReg.register(cameraFactory, withId: ARCameraPreviewFactory.viewType)
        }

        return result
    }
}
