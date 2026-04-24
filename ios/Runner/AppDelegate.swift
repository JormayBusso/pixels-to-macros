import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // GeneratedPluginRegistrant must be registered before super so that
        // Flutter's engine is fully initialised when super returns.
        GeneratedPluginRegistrant.register(with: self)
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // super.application sets up the FlutterViewController and assigns it
        // to window.rootViewController — only access it after that call.
        if let controller = window?.rootViewController as? FlutterViewController {
            ScannerPlugin.register(with: controller.binaryMessenger)
        }

        // Register the live AR camera preview as a Flutter platform view.
        // Must happen after super so the Flutter engine exists.
        let cameraFactory = ARCameraPreviewFactory(
            sessionManager: ScannerPlugin.sessionManager
        )
        registrar(forPlugin: "ARCameraPreviewPlugin")
            .register(cameraFactory, withId: ARCameraPreviewFactory.viewType)

        return result
    }
}
