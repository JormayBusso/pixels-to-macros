import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register the native scanner plugin on the Flutter MethodChannel.
        let controller = window?.rootViewController as! FlutterViewController
        ScannerPlugin.register(with: controller.binaryMessenger)

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
