import UIKit
import Flutter

@main
@objc class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var flutterEngine = FlutterEngine(name: "io.flutter", project: nil)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Start the Flutter engine explicitly — this guarantees the engine is
        // running and registrarForPlugin: returns non-nil registrars.
        // Using FlutterAppDelegate + scene lifecycle on iOS 26 was returning nil
        // registrars, causing swift_getObjectType(nil) → EXC_BAD_ACCESS.
        flutterEngine.run()

        GeneratedPluginRegistrant.register(with: flutterEngine)

        let flutterVC = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = flutterVC
        window?.makeKeyAndVisible()
        window?.backgroundColor = .black

        // ── Custom scanner method channel ──────────────────────────────────
        let scannerReg = flutterEngine.registrar(forPlugin: "ScannerPlugin")!
        ScannerPlugin.register(with: scannerReg.messenger())

        // ── Live AR camera platform view ───────────────────────────────────
        let cameraFactory = ARCameraPreviewFactory(
            sessionManager: ScannerPlugin.sessionManager
        )
        let cameraReg = flutterEngine.registrar(forPlugin: "ARCameraPreviewPlugin")!
        cameraReg.register(cameraFactory, withId: ARCameraPreviewFactory.viewType)

        // ── Post-scan 3D viewer platform view ──────────────────────────────
        let viewerReg = flutterEngine.registrar(forPlugin: "Scan3DViewerPlugin")!
        viewerReg.register(
            Scan3DViewerFactory(messenger: viewerReg.messenger()),
            withId: Scan3DViewerFactory.viewType
        )

        // ── Premium RealityView food viewer (Step 3) ───────────────────────
        let realityReg = flutterEngine.registrar(forPlugin: "Food3DRealityPlugin")!
        realityReg.register(
            Food3DRealityFactory(),
            withId: Food3DRealityFactory.viewType
        )

        return true
    }
}
