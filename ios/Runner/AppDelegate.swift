import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var flutterEngine = FlutterEngine(name: "io.flutter", project: nil)
    private var introOverlay: IntroOverlayView?

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
        flutterVC.view.backgroundColor = .black

        if let window = window {
            introOverlay = IntroOverlayView.present(on: window) { [weak self] in
                self?.introOverlay = nil
            }
        }

        // ── Custom scanner method channel ──────────────────────────────────
        let scannerReg = flutterEngine.registrar(forPlugin: "ScannerPlugin")!
        ScannerPlugin.register(with: scannerReg.messenger())

        // ── On-device recipe translation (Apple Translation) ───────────────
        let translationReg = flutterEngine.registrar(forPlugin: "TranslationPlugin")!
        TranslationPlugin.register(with: translationReg.messenger())

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

// MARK: - Native intro overlay

/// Plays `assets/ptm_enter.mp4` natively over Flutter from the first launch
/// frame. LaunchScreen.storyboard shows the video's first frame (the icon
/// crop, 710x720 of the 1280x720 video) edge-to-edge, so the overlay uses the
/// identical geometry and the OS launch zoom flows straight into the video.
final class IntroOverlayView: UIView {
    private static let videoSize = CGSize(width: 1280, height: 720)
    private static let cropRect = CGRect(x: 285, y: 0, width: 710, height: 720)
    private static let timeout: TimeInterval = 4

    private let content = UIView()
    private let imageView = UIImageView()
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var readyObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var onFinished: (() -> Void)?
    private var finishing = false

    static func present(on window: UIWindow, onFinished: @escaping () -> Void) -> IntroOverlayView {
        let overlay = IntroOverlayView(frame: window.bounds)
        overlay.onFinished = onFinished
        window.addSubview(overlay)
        overlay.start()
        return overlay
    }

    private override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.bounds = CGRect(origin: .zero, size: bounds.size)
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
        imageView.frame = content.bounds

        // Match the launch image's aspect-fill crop, including before playback.
        let s = max(bounds.width / Self.cropRect.width, bounds.height / Self.cropRect.height)
        let layerW = Self.videoSize.width * s
        let layerH = Self.videoSize.height * s
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = CGRect(
            x: content.bounds.midX - layerW / 2,
            y: content.bounds.midY - layerH / 2,
            width: layerW,
            height: layerH
        )
        CATransaction.commit()
    }

    private func start() {
        addSubview(content)

        imageView.image = UIImage(named: "IntroFirstFrame")
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        content.addSubview(imageView)
        setNeedsLayout()
        layoutIfNeeded()

        // Hard timeout: never leave the overlay stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            self?.finish()
        }

        let key = FlutterDartProject.lookupKey(forAsset: "assets/ptm_enter.mp4")
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
            finish()
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])

        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = UIColor.black.cgColor
        content.layer.insertSublayer(layer, below: imageView.layer)
        playerLayer = layer
        setNeedsLayout()
        layoutIfNeeded()

        // Keep the first-frame image on top until the video can display, so
        // there is never a black gap; then drop it (the frames are identical).
        readyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] l, _ in
            guard l.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.imageView.isHidden = true }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                DispatchQueue.main.async { self?.finish() }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.finish() }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.finish() }

        // Retain the original relative zoom, now starting from full-screen coverage.
        let widthFittedCropHeight = Self.cropRect.height * bounds.width / Self.cropRect.width
        let endScale = max(bounds.height / widthFittedCropHeight, 1)
        let duration = 1.3346
        player.play()
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
            self.content.transform = CGAffineTransform(scaleX: endScale, y: endScale)
        }
    }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
            self.alpha = 0
        }, completion: { _ in
            self.teardown()
        })
    }

    private func teardown() {
        readyObservation?.invalidate()
        statusObservation?.invalidate()
        readyObservation = nil
        statusObservation = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let o = failObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        failObserver = nil
        player?.pause()
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        removeFromSuperview()
        onFinished?()
        onFinished = nil
    }
}
