import ARKit
import AVFoundation
import CoreImage
import CoreMedia
import Flutter
import QuartzCore
import simd
import UIKit
import Vision

/// Embeds a live ARKit camera feed as a Flutter platform view.
///
/// Uses AVSampleBufferDisplayLayer (a plain Core Animation layer) instead of
/// ARSCNView so there are no Metal-compositor conflicts with Flutter's renderer.
/// Frames are polled from ARSessionManager.latestFrame via CADisplayLink at
/// ≈60 fps and pushed to the display layer as CMSampleBuffers.
///
/// The view also hosts the live food mesh: a throttled on-device food detector
/// (see `LiveFoodDetector`) whose live mask is triangulated into a themed
/// wireframe (see `LiveFoodMesh`) exactly over the aspect-fit preview (see
/// `LiveGlowLayers`). It is driven
/// from Flutter over `com.pixelstomacros/live_glow` (see
/// `LiveFoodGlowController`).
final class ARCameraPreviewFactory: NSObject, FlutterPlatformViewFactory {

    static let viewType = "com.pixelstomacros/ar_camera"

    private weak var sessionManager: ARSessionManager?

    init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
        super.init()
        if let messenger = (UIApplication.shared.delegate as? AppDelegate)?
            .flutterEngine.binaryMessenger {
            LiveFoodGlowController.shared.attach(messenger: messenger)
        }
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return ARCameraPreviewView(frame: frame, sessionManager: sessionManager)
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol) {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: – Host UIView

/// UIView that hosts an AVSampleBufferDisplayLayer.
/// Overrides layoutSubviews to keep the layer in sync with the view bounds and
/// to apply the 90° CW portrait rotation every time the view is resized.
private final class CameraHostView: UIView {

    let displayLayer = AVSampleBufferDisplayLayer()

    /// Live food glow drawn above the preview (created on first use).
    var glow: LiveFoodHighlights? {
        didSet {
            oldValue?.root.removeFromSuperlayer()
            if let glow {
                layer.addSublayer(glow.root)
                glow.layout(in: bounds, matching: displayLayer)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Aspect-FIT (not fill): show the full uncropped wide-angle frame so
        // food never looks "zoomed in". The scan camera is ARKit (there is no
        // AVCaptureDevice.videoZoomFactor here); the apparent zoom was this
        // fill-crop. Letterbox bars are fine for a measurement scanner that
        // needs to see the whole plate.
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(displayLayer)
        applyOrientationTransform(for: bounds)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyOrientationTransform(for: bounds)
    }

    /// ARKit captures in the camera sensor's native landscape orientation
    /// (landscapeRight). Rotate the display layer to match the current UI
    /// orientation so the preview is always upright — 0° in landscapeRight,
    /// 180° in landscapeLeft, and 90° CW in portrait. The scan flow forces
    /// landscape, but this keeps the preview correct in every orientation.
    func applyOrientationTransform(for rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        let orientation: UIInterfaceOrientation =
            window?.windowScene?.interfaceOrientation
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
                .first
            ?? .portrait

        let angle: CGFloat
        let layerSize: CGSize
        switch orientation {
        case .landscapeRight:
            angle = 0
            layerSize = rect.size
        case .landscapeLeft:
            angle = .pi
            layerSize = rect.size
        case .portraitUpsideDown:
            angle = -.pi / 2
            layerSize = CGSize(width: rect.height, height: rect.width)
        default: // portrait
            angle = .pi / 2
            layerSize = CGSize(width: rect.height, height: rect.width)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.bounds    = CGRect(origin: .zero, size: layerSize)
        displayLayer.position  = CGPoint(x: rect.midX, y: rect.midY)
        displayLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()

        glow?.layout(in: rect, matching: displayLayer)
    }
}

// MARK: – Platform view

/// Forwards CADisplayLink ticks without retaining the platform view (a
/// display link strongly retains its target, which otherwise keeps every
/// preview view — and its detector model — alive after Flutter disposes it).
private final class DisplayLinkProxy: NSObject {
    weak var target: ARCameraPreviewView?
    init(target: ARCameraPreviewView) { self.target = target }
    @objc func tick() {
        guard let target else { return }
        target.renderTick()
    }
}

final class ARCameraPreviewView: NSObject, FlutterPlatformView {

    private let hostView: CameraHostView
    private weak var sessionManager: ARSessionManager?
    private var displayLink: CADisplayLink?
    private var detector: LiveFoodDetector?
    private var videoSize: CGSize?
    private var liveContext: LivePreviewContext?
    private var lastFrameTimestamp: TimeInterval?
    /// Frame timestamp / camera pose of the last frame that confirmed food.
    private var confirmedTimestamp: TimeInterval?

    private struct LivePreviewContext: Equatable {
        let generation: Int
        let bounds: CGRect
        let orientation: UIInterfaceOrientation
        let roi: LiveGlowROI?
        let videoSize: CGSize
    }

    init(frame: CGRect, sessionManager: ARSessionManager?) {
        self.sessionManager = sessionManager
        hostView = CameraHostView(frame: frame)
        super.init()

        // Observe session lifecycle events.
        NotificationCenter.default.addObserver(
            self, selector: #selector(onSessionDidStart(_:)),
            name: .arSessionDidStart, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(onSessionDidFail(_:)),
            name: .arSessionDidFail, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(onSessionDidFail(_:)),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(onSessionDidStart(_:)),
            name: UIApplication.didBecomeActiveNotification, object: nil)

        // Begin rendering immediately if a session is already running.
        if sessionManager?.session != nil {
            startDisplayLink()
        }

        LiveFoodGlowController.shared.register(self)
    }

    func view() -> UIView { hostView }

    // MARK: – Notifications

    @objc private func onSessionDidStart(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.startDisplayLink() }
    }

    @objc private func onSessionDidFail(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.stopDisplayLink() }
    }

    // MARK: – Display link

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(
            target: DisplayLinkProxy(target: self),
            selector: #selector(DisplayLinkProxy.tick))
        // Match ARKit's 60 fps capture so preview + mesh stay fluid; the
        // mesh animations themselves run in the render server (up to 120 Hz).
        displayLink?.preferredFrameRateRange =
            CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        invalidateLiveOverlay()
    }

    // MARK: – Frame rendering

    fileprivate func renderTick() {
        autoreleasepool {
            // Hold a strong reference for the duration of this tick so
            // the manager can't be deallocated mid-access.
            guard UIApplication.shared.applicationState == .active,
                  hostView.window != nil, !hostView.isHidden
            else {
                if liveContext != nil { invalidateLiveOverlay() }
                return
            }
            let now = CACurrentMediaTime()
            // A stalled camera/inference must not leave a permanent highlight.
            if let confirmed = confirmedTimestamp,
               now - confirmed > LiveFoodOverlayPolicy.overlayHold {
                hideConfirmedOverlay()
            }
            guard let frame = sessionManager?.latestFrame,
                  LiveFoodOverlayPolicy.isFresh(timestamp: frame.timestamp, now: now) else { return }
            let pixelBuffer = frame.capturedImage
            guard frame.timestamp != lastFrameTimestamp else { return }
            lastFrameTimestamp = frame.timestamp

            // Build a CMVideoFormatDescription for this pixel buffer.
            var formatDesc: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDesc) == noErr,
                  let format = formatDesc
            else { return }

            // Wrap in a CMSampleBuffer with the current host time as the
            // presentation timestamp so the display layer shows it immediately.
            var timing = CMSampleTimingInfo(
                duration:              .invalid,
                presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                decodeTimeStamp:       .invalid)

            // CMSampleBufferCreateReadyWithImageBuffer is available iOS 16+,
            // which is always satisfied by our deployment target.
            var sampleBuffer: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator:         nil,
                imageBuffer:       pixelBuffer,
                formatDescription: format,
                sampleTiming:      &timing,
                sampleBufferOut:   &sampleBuffer) == noErr,
                  let sample = sampleBuffer
            else { return }

            let dl = hostView.displayLayer
            if dl.status == .failed { dl.flush() }
            if dl.isReadyForMoreMediaData { dl.enqueue(sample) }

            let size = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer))
            if size != videoSize {
                videoSize = size
                if let glow = hostView.glow {
                    glow.videoSize = size
                    glow.layout(in: hostView.bounds, matching: hostView.displayLayer)
                }
                LiveFoodGlowController.shared.reportVideoSize(size)
            }

            feedLiveDetector(frame)
        }
    }

    // MARK: – Live food glow

    /// Offers the latest frame, dropping it while busy or throttled. Only the
    /// small camera-buffer copy runs here; model inference stays off-main.
    private func feedLiveDetector(_ frame: ARFrame) {
        let controller = LiveFoodGlowController.shared
        guard controller.enabled,
              hostView.window != nil, !hostView.isHidden,
              let glow = hostView.glow, let detector
        else { return }

        let context = LivePreviewContext(
            generation: sessionManager?.generation ?? -1,
            bounds: hostView.bounds,
            orientation: hostView.window?.windowScene?.interfaceOrientation ?? .unknown,
            roi: controller.roi,
            videoSize: videoSize ?? .zero)
        if context != liveContext {
            invalidateLiveOverlay()
            liveContext = context
            hostView.applyOrientationTransform(for: hostView.bounds)
        }
        let now = CACurrentMediaTime()
        guard detector.canAccept(at: now),
              let roi = glow.roiInMaskGrid(LiveFoodDetector.grid)
        else { return }

        let timestamp = frame.timestamp
        detector.submit(frame.capturedImage, roi: roi, at: now, frameTimestamp: timestamp) { [weak self] result in
            guard let self, let glow = self.hostView.glow,
                  self.liveContext == context,
                  self.hostView.window != nil, !self.hostView.isHidden,
                  self.hostView.bounds == context.bounds,
                  self.hostView.window?.windowScene?.interfaceOrientation == context.orientation,
                  self.sessionManager?.generation == context.generation,
                  UIApplication.shared.applicationState == .active,
                  LiveFoodGlowController.shared.enabled,
                  LiveFoodOverlayPolicy.isFresh(timestamp: timestamp, now: CACurrentMediaTime())
            else { return }
            glow.update(tracks: result.tracks)
            if result.present {
                glow.setVisible(true)
                self.confirmedTimestamp = timestamp
            } else {
                self.hideConfirmedOverlay()
            }
            LiveFoodGlowController.shared.report(
                detected: self.confirmedTimestamp != nil,
                available: result.available,
                backend: result.backend)
        }
    }

    private func hideConfirmedOverlay() {
        confirmedTimestamp = nil
        hostView.glow?.setVisible(false)
        LiveFoodGlowController.shared.clearDetection()
    }

    private func invalidateLiveOverlay() {
        detector?.reset()
        liveContext = nil
        lastFrameTimestamp = nil
        hideConfirmedOverlay()
    }

    fileprivate func drainLiveDetector(completion: @escaping () -> Void) {
        guard let detector else { completion(); return }
        detector.drain(completion: completion)
    }

    /// Applies the current controller state (enabled / style / ROI).
    fileprivate func applyLiveGlowState() {
        let controller = LiveFoodGlowController.shared
        guard controller.enabled else {
            invalidateLiveOverlay()
            return
        }
        if liveContext?.roi != controller.roi { invalidateLiveOverlay() }
        if hostView.glow == nil {
            let glow = LiveFoodHighlights(style: controller.style)
            if let videoSize { glow.videoSize = videoSize }
            hostView.glow = glow
        }
        if detector == nil {
            detector = LiveFoodDetector()
        }
        hostView.glow?.apply(style: controller.style)
        hostView.glow?.setRoi(controller.roi)
    }

    deinit {
        stopDisplayLink()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: – Live glow controller (method channel)

struct LiveGlowStyle: Equatable {
    var colors: [UIColor]
    var premium: Bool
    var reduceMotion: Bool

    static let fallback = LiveGlowStyle(
        colors: [UIColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1)],
        premium: false,
        reduceMotion: false)
}

/// Capture guide the glow is clipped to: the TOP circle or the SIDE rounded
/// rectangle, laid out on the camera frame's centred square exactly like the
/// pipeline's capture ROI (`ScanMaskGeometry.ROI` — same constants).
struct LiveGlowROI: Equatable {
    var roundedRect: Bool

    /// The ROI inside a centred square crop of side `side` (frame
    /// orientation). The rectangle's long side runs along the frame columns
    /// when `longAxisAlongColumns` (world-horizontal in a landscape hold).
    func geometry(side: CGFloat, longAxisAlongColumns: Bool) -> (rect: CGRect, corner: CGFloat) {
        let radius = side * CGFloat(ScanMaskGeometry.roiRadiusFraction)
        var halfX = radius, halfY = radius, corner = radius
        if roundedRect {
            let halfShort = radius * CGFloat(ScanMaskGeometry.sideRectHeightRatio)
            halfX = longAxisAlongColumns ? radius : halfShort
            halfY = longAxisAlongColumns ? halfShort : radius
            corner = CGFloat(ScanMaskGeometry.sideRectCornerFraction) * 2 * halfShort
        }
        return (CGRect(x: side / 2 - halfX, y: side / 2 - halfY,
                       width: 2 * halfX, height: 2 * halfY), corner)
    }

    /// Same normalisation as the pipeline's `[ROI]` log (fraction of S).
    func logDescription(longAxisAlongColumns: Bool) -> String {
        let g = geometry(side: 1, longAxisAlongColumns: longAxisAlongColumns)
        guard roundedRect else {
            return String(format: "shape=circle centre=0.50,0.50 radius=%.3f", g.rect.width / 2)
        }
        return String(
            format: "shape=roundedRect centre=0.50,0.50 halfW=%.3f halfH=%.3f corner=%.3f",
            max(g.rect.width, g.rect.height) / 2, min(g.rect.width, g.rect.height) / 2, g.corner)
            + " longAxis=\(longAxisAlongColumns ? "columns" : "rows")"
    }
}

/// Owns the `com.pixelstomacros/live_glow` channel and the shared live-glow
/// state; preview views register themselves and follow it. All access is on
/// the main thread (Flutter delivers platform-channel calls on it).
final class LiveFoodGlowController {

    static let shared = LiveFoodGlowController()
    static let channelName = "com.pixelstomacros/live_glow"

    private(set) var enabled = false
    private(set) var style = LiveGlowStyle.fallback
    private(set) var roi: LiveGlowROI?

    private var channel: FlutterMethodChannel?
    private let views = NSHashTable<ARCameraPreviewView>.weakObjects()
    private var lastReport: (detected: Bool, available: Bool, backend: String)?

    private init() {}

    func attach(messenger: FlutterBinaryMessenger) {
        guard channel == nil else { return }
        let channel = FlutterMethodChannel(
            name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        self.channel = channel
    }

    func register(_ view: ARCameraPreviewView) {
        views.add(view)
        view.applyLiveGlowState()
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start":
            let colors = (args["colors"] as? [NSNumber] ?? [])
                .map { UIColor(argb: $0.uint32Value) }
            style = LiveGlowStyle(
                colors: colors.isEmpty ? LiveGlowStyle.fallback.colors : colors,
                premium: args["premium"] as? Bool ?? false,
                reduceMotion: args["reduceMotion"] as? Bool ?? false)
            roi = Self.parseRoi(args["roi"])
            if !enabled {
                print("[LiveGlow] start premium=\(style.premium) reduceMotion=\(style.reduceMotion) render=wire_mesh lattice=marching_triangles")
            }
            enabled = true
            applyToViews()
            result(nil)
        case "updateRoi":
            roi = Self.parseRoi(args["roi"]) ?? roi
            applyToViews()
            result(nil)
        case "stop":
            if enabled { print("[LiveGlow] stop") }
            enabled = false
            applyToViews()
            if let last = lastReport, last.detected {
                report(detected: false, available: last.available, backend: last.backend)
            }
            let group = DispatchGroup()
            for view in views.allObjects {
                group.enter()
                view.drainLiveDetector { group.leave() }
            }
            group.notify(queue: .main) { result(nil) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func applyToViews() {
        for view in views.allObjects { view.applyLiveGlowState() }
    }

    /// Tells Flutter the camera frame size so its guide uses the same
    /// aspect-fit square as the native capture ROI.
    func reportVideoSize(_ size: CGSize) {
        print("[LiveGlow] preview video=\(Int(size.width))x\(Int(size.height))")
        channel?.invokeMethod("onPreviewVideoSize", arguments: [
            "width": Double(size.width),
            "height": Double(size.height),
        ])
    }

    /// Pushes the detection state to Flutter, only when it changes.
    func report(detected: Bool, available: Bool, backend: String) {
        if let last = lastReport,
           last.detected == detected, last.available == available,
           last.backend == backend {
            return
        }
        lastReport = (detected, available, backend)
        channel?.invokeMethod("onLiveDetection", arguments: [
            "detected": detected,
            "available": available,
            "backend": backend,
        ])
    }

    func clearDetection() {
        guard let last = lastReport, last.detected else { return }
        report(detected: false, available: last.available, backend: last.backend)
    }

    private static func parseRoi(_ raw: Any?) -> LiveGlowROI? {
        guard let map = raw as? [String: Any],
              let shape = map["shape"] as? String
        else { return nil }
        return LiveGlowROI(roundedRect: shape == "roundedRect")
    }
}

private extension UIColor {
    convenience init(argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255)
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t)
    }
}

// MARK: – Live food detector

/// Region of interest in mask-grid cells (rounded rectangle; a circle is a
/// rounded square whose radius is half its side).
struct LiveGlowGridROI {
    var rect: CGRect
    var radius: CGFloat

    func contains(x: CGFloat, y: CGFloat) -> Bool {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let dx = max(abs(x - rect.midX) - (rect.width / 2 - r), 0)
        let dy = max(abs(y - rect.midY) - (rect.height / 2 - r), 0)
        return rect.contains(CGPoint(x: x, y: y)) && dx * dx + dy * dy <= r * r
    }
}

/// Live-only crop and inverse mask mapping in the original centre-square grid.
struct LiveFoodCrop {
    let rect: CGRect
    let roi: LiveGlowGridROI

    init(roi source: LiveGlowGridROI, grid: Int) {
        let g = CGFloat(grid)
        let side = min(g, max(source.rect.width, source.rect.height) + 2)
        rect = CGRect(x: max(0, min(g - side, source.rect.midX - side / 2)),
                      y: max(0, min(g - side, source.rect.midY - side / 2)),
                      width: side, height: side)
        let scale = g / side
        roi = LiveGlowGridROI(
            rect: CGRect(x: (source.rect.minX - rect.minX) * scale,
                         y: (source.rect.minY - rect.minY) * scale,
                         width: source.rect.width * scale, height: source.rect.height * scale),
            radius: source.radius * scale)
    }

    func inputPoint(x: CGFloat, y: CGFloat, grid: Int) -> CGPoint {
        let scale = CGFloat(grid) / rect.width
        return CGPoint(x: (x - rect.minX) * scale, y: (y - rect.minY) * scale)
    }
}

struct LiveGlowResult {
    let tracks: [LiveFoodTrack]
    let present: Bool
    let available: Bool
    let backend: String
}

/// A semantic allowlist, never a class-index guess: YOLO class zero is candy,
/// whereas the dense model's class zero is background. Unknown/generic classes
/// and class-agnostic foreground masks cannot identify food.
enum LiveFoodOverlayPolicy {
    static let maxAge: TimeInterval = 0.35
    static let foodLabels: Set<String> = [
        "candy", "egg tart", "french fries", "chocolate", "biscuit", "popcorn",
        "pudding", "ice cream", "cheese butter", "cake", "wine", "milkshake",
        "coffee", "juice", "milk", "tea", "almond", "red beans", "cashew",
        "dried cranberries", "soy", "walnut", "peanut", "egg", "apple", "date",
        "apricot", "avocado", "banana", "strawberry", "cherry", "blueberry",
        "raspberry", "mango", "olives", "peach", "lemon", "pear", "fig",
        "pineapple", "grape", "kiwi", "melon", "orange", "watermelon", "steak",
        "pork", "chicken duck", "sausage", "fried meat", "lamb", "sauce",
        "crab", "fish", "shellfish", "shrimp", "soup", "bread", "corn",
        "hamburg", "pizza", "hanamaki baozi", "wonton dumplings", "pasta",
        "noodles", "rice", "pie", "tofu", "eggplant", "potato", "garlic",
        "cauliflower", "tomato", "kelp", "seaweed", "spring onion", "rape",
        "ginger", "okra", "lettuce", "pumpkin", "cucumber", "white radish",
        "carrot", "asparagus", "bamboo shoots", "broccoli", "celery stick",
        "cilantro mint", "snow peas", "cabbage", "bean sprouts", "onion",
        "pepper", "green beans", "french beans", "king oyster mushroom",
        "shiitake", "enoki mushroom", "oyster mushroom", "white button mushroom",
        "salad", "taro", "white mushroom", "black fungus", "dough", "rice noodle",
        "chicken", "sandwich", "hot dog", "donut",
    ]

    static let creationConfidence: Float = 0.45
    static let maintenanceConfidence: Float = 0.30
    static let maxTracks = 24

    static func accepts(label: String, confidence: Float) -> Bool {
        let name = label.lowercased().replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return confidence.isFinite && confidence >= maintenanceConfidence && foodLabels.contains(name)
    }

    static func isFresh(timestamp: TimeInterval, now: TimeInterval) -> Bool {
        let age = now - timestamp
        return age.isFinite && age >= 0 && age <= maxAge
    }

    static func cameraIsAligned(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        let translation = simd_distance(
            SIMD3(a.columns.3.x, a.columns.3.y, a.columns.3.z),
            SIMD3(b.columns.3.x, b.columns.3.y, b.columns.3.z))
        let rotationA = simd_quatf(simd_float3x3(
            SIMD3(a.columns.0.x, a.columns.0.y, a.columns.0.z),
            SIMD3(a.columns.1.x, a.columns.1.y, a.columns.1.z),
            SIMD3(a.columns.2.x, a.columns.2.y, a.columns.2.z)))
        let rotationB = simd_quatf(simd_float3x3(
            SIMD3(b.columns.0.x, b.columns.0.y, b.columns.0.z),
            SIMD3(b.columns.1.x, b.columns.1.y, b.columns.1.z),
            SIMD3(b.columns.2.x, b.columns.2.y, b.columns.2.z)))
        // Half-angle quaternion test: |dot| >= cos(θ/2) ⇔ rotation <= θ (6°).
        // Hand tremor between ~15 Hz results stays well inside these bounds;
        // only a real re-aim drops the old contour.
        return translation <= 0.04 && abs(simd_dot(rotationA.vector, rotationB.vector)) >= cos(Float.pi / 60)
    }

    /// How long the last confirmed mesh survives detector misses before the
    /// food is reported as lost (temporal hysteresis against flicker).
    static let overlayHold: TimeInterval = 2.0

    /// Separable box blur with clamped edges (running sums, O(n)).
    static func boxBlur(_ src: [Float], _ g: Int, _ radius: Int) -> [Float] {
        guard radius > 0 else { return src }
        let norm = 1 / Float(2 * radius + 1)
        var tmp = [Float](repeating: 0, count: g * g)
        var out = [Float](repeating: 0, count: g * g)
        for y in 0..<g {
            let row = y * g
            var sum: Float = 0
            for k in -radius...radius { sum += src[row + min(max(k, 0), g - 1)] }
            for x in 0..<g {
                tmp[row + x] = sum * norm
                sum += src[row + min(x + radius + 1, g - 1)] - src[row + max(x - radius, 0)]
            }
        }
        for x in 0..<g {
            var sum: Float = 0
            for k in -radius...radius { sum += tmp[min(max(k, 0), g - 1) * g + x] }
            for y in 0..<g {
                out[y * g + x] = sum * norm
                sum += tmp[min(y + radius + 1, g - 1) * g + x] - tmp[max(y - radius, 0) * g + x]
            }
        }
        return out
    }
}

/// Live wireframe of the current food mask: marching triangles on a fixed,
/// screen-anchored equilateral lattice. Every lattice triangle fully inside
/// the iso-0.5 contour is kept; boundary triangles are clipped exactly at the
/// interpolated contour crossing (Sutherland–Hodgman), so the outer edge
/// follows the mask silhouette while interior lines never jitter between
/// frames. Display-only — saved scans never use this. Coordinates are in
/// mask-grid cells.
struct LiveFoodMesh {
    let wire: CGPath
    let outline: CGPath
    let region: CGPath
    let nodes: [CGPoint]
    let triangles: Int

    static func build(mask: [Float], grid g: Int, spacing h: CGFloat = 6,
                      aspectRatio: CGFloat = 1) -> LiveFoodMesh? {
        guard g > 1, mask.count == g * g, h.isFinite, h >= 1,
              aspectRatio.isFinite, aspectRatio > 0 else { return nil }
        var support = [Float](repeating: 0, count: g * g)
        for i in 0..<(g * g) where mask[i].isFinite && mask[i] > 0.5 { support[i] = 1 }
        // One tiny blur only gives the iso-line sub-cell precision; the 0.5
        // level set stays on the original mask boundary.
        let field = LiveFoodOverlayPolicy.boxBlur(support, g, 1)

        func sample(_ x: CGFloat, _ y: CGFloat) -> Float {
            guard x >= 0, y >= 0, x <= CGFloat(g), y <= CGFloat(g) else { return -0.5 }
            let fx = min(max(x - 0.5, 0), CGFloat(g - 1))
            let fy = min(max(y - 0.5, 0), CGFloat(g - 1))
            let x0 = Int(fx), y0 = Int(fy)
            let x1 = min(x0 + 1, g - 1), y1 = min(y0 + 1, g - 1)
            let tx = Float(fx - CGFloat(x0)), ty = Float(fy - CGFloat(y0))
            let top = field[y0 * g + x0] * (1 - tx) + field[y0 * g + x1] * tx
            let bottom = field[y1 * g + x0] * (1 - tx) + field[y1 * g + x1] * tx
            return top * (1 - ty) + bottom * ty - 0.5
        }

        let rowH = h * aspectRatio * CGFloat(3).squareRoot() / 2
        let cols = Int((CGFloat(g) / h).rounded(.up)) + 4
        let rows = Int((CGFloat(g) / rowH).rounded(.up)) + 3
        var points = [CGPoint](), values = [Float]()
        points.reserveCapacity(cols * rows)
        values.reserveCapacity(cols * rows)
        for j in 0..<rows {
            for i in 0..<cols {
                let p = CGPoint(x: CGFloat(i - 1) * h - (j % 2 == 0 ? 0 : h / 2),
                                y: CGFloat(j - 1) * rowH)
                points.append(p)
                values.append(sample(p.x, p.y))
            }
        }

        let wire = CGMutablePath(), outline = CGMutablePath(), region = CGMutablePath()
        var nodes = [CGPoint]()
        var used = [Bool](repeating: false, count: points.count)
        var triangles = 0

        func emit(_ poly: [CGPoint]) {
            region.addLines(between: poly)
            region.closeSubpath()
            wire.addLines(between: poly)
            wire.closeSubpath()
            if poly.count == 4 {
                wire.move(to: poly[0])
                wire.addLine(to: poly[2])
            }
            triangles += poly.count - 2
        }

        func triangle(_ a: Int, _ b: Int, _ c: Int) {
            let idx = [a, b, c]
            let v = idx.map { values[$0] }
            let inside = v.map { $0 >= 0 }
            if !inside.contains(true) { return }
            if !inside.contains(false) {
                emit(idx.map { points[$0] })
                for k in idx { used[k] = true }
                return
            }
            var poly = [CGPoint](), crossings = [CGPoint]()
            for k in 0..<3 {
                let n = (k + 1) % 3
                if inside[k] { poly.append(points[idx[k]]); used[idx[k]] = true }
                if inside[k] != inside[n] {
                    // Bisect on the field: lattice edges span several cells,
                    // so a linear guess could sit up to h/2 off the silhouette.
                    var pin = points[idx[inside[k] ? k : n]]
                    var pout = points[idx[inside[k] ? n : k]]
                    for _ in 0..<8 {
                        let mid = CGPoint(x: (pin.x + pout.x) / 2, y: (pin.y + pout.y) / 2)
                        if sample(mid.x, mid.y) >= 0 { pin = mid } else { pout = mid }
                    }
                    let q = CGPoint(x: (pin.x + pout.x) / 2, y: (pin.y + pout.y) / 2)
                    poly.append(q)
                    crossings.append(q)
                }
            }
            guard poly.count >= 3 else { return }
            emit(poly)
            if crossings.count == 2 {
                outline.move(to: crossings[0])
                outline.addLine(to: crossings[1])
            }
        }

        for j in 0..<(rows - 1) {
            let r0 = j * cols, r1 = (j + 1) * cols
            for i in 0..<(cols - 1) {
                if j % 2 == 0 {
                    // Row j+1 sits h/2 to the left of row j.
                    triangle(r0 + i, r1 + i + 1, r1 + i)
                    triangle(r0 + i, r0 + i + 1, r1 + i + 1)
                } else {
                    triangle(r0 + i, r0 + i + 1, r1 + i)
                    triangle(r0 + i + 1, r1 + i + 1, r1 + i)
                }
            }
        }
        guard triangles > 0 else { return nil }
        for k in 0..<points.count where used[k] && values[k] >= 0 { nodes.append(points[k]) }
        return LiveFoodMesh(wire: wire.copy() ?? wire, outline: outline.copy() ?? outline,
                            region: region.copy() ?? region, nodes: nodes, triangles: triangles)
    }
}

struct LiveFoodObservation {
    let label: String
    let confidence: Float
    let bounds: CGRect
    let mask: [Float]
}

enum LiveFoodTrackState: String {
    case new, confirmed, tracked, temporarilyOccluded, lost, removed
}

struct LiveFoodTrack {
    let id: Int
    let label: String
    var state: LiveFoodTrackState
    var confidence: Float
    var bounds: CGRect
    var mask: [Float]
    var meshMask: [Float]
    var mesh: LiveFoodMesh
    var meshAspect: CGFloat
    var revision: Int
    var hits: Int
    var misses: Int
    var lastDetection: TimeInterval
    var lastMotion: TimeInterval

    var visible: Bool { state != .lost && state != .removed }
}

/// Live-only identities and canonical silhouettes. No saved-scan geometry is used.
struct LiveFoodTrackStore {
    static let maskGrid = 96
    static let missedDetections = 6
    static let occlusionHold: TimeInterval = 1.6
    static let identityHold: TimeInterval = 5
    private(set) var tracks: [LiveFoodTrack] = []
    private var nextID = 1

    static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let area = intersection.width * intersection.height
        return area / max(1, a.width * a.height + b.width * b.height - area)
    }

    static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite }
            && rect.width >= 1 && rect.height >= 1
    }

    mutating func move(id: Int, bounds: CGRect, confidence: Float, at now: TimeInterval) {
        guard confidence.isFinite, confidence >= 0.5, Self.valid(bounds),
              let i = tracks.firstIndex(where: { $0.id == id && $0.visible })
        else { return }
        let old = tracks[i].bounds
        // Reject a tracker latching onto the plate or an unrelated ingredient.
        guard Self.overlap(old.insetBy(dx: -12, dy: -12), bounds) > 0.15,
              bounds.width / old.width > 0.65, bounds.width / old.width < 1.5,
              bounds.height / old.height > 0.65, bounds.height / old.height < 1.5
        else { return }
        tracks[i].bounds = bounds
        tracks[i].lastMotion = now
        if tracks[i].misses == 0 { tracks[i].state = .tracked }
    }

    mutating func expire(at now: TimeInterval) {
        for i in tracks.indices {
            let age = now - tracks[i].lastDetection
            if age > Self.identityHold {
                tracks[i].state = .removed
            } else if age > Self.occlusionHold
                        && tracks[i].misses >= Self.missedDetections {
                tracks[i].state = .lost
            }
        }
        tracks.removeAll { $0.state == .removed }
    }

    mutating func update(_ observations: [LiveFoodObservation], at now: TimeInterval) {
        expire(at: now)
        var assigned = Set<Int>()
        for observation in observations.sorted(by: { $0.confidence > $1.confidence }) {
            guard LiveFoodOverlayPolicy.accepts(label: observation.label, confidence: observation.confidence),
                  Self.valid(observation.bounds),
                  observation.mask.count == Self.maskGrid * Self.maskGrid
            else { continue }
            let candidates = tracks.indices.filter {
                let overlap = Self.overlap(tracks[$0].bounds, observation.bounds)
                return !assigned.contains(tracks[$0].id)
                    && (tracks[$0].label == observation.label ? overlap > 0.2 : overlap > 0.65)
            }
            if let i = candidates.max(by: {
                Self.overlap(tracks[$0].bounds, observation.bounds)
                    < Self.overlap(tracks[$1].bounds, observation.bounds)
            }) {
                assigned.insert(tracks[i].id)
                tracks[i].bounds = observation.bounds
                tracks[i].confidence = tracks[i].confidence * 0.65 + observation.confidence * 0.35
                tracks[i].lastDetection = now
                tracks[i].lastMotion = now
                tracks[i].hits += 1
                tracks[i].misses = 0
                tracks[i].state = .confirmed
                let changed = zip(tracks[i].meshMask, observation.mask).reduce(0) {
                    $0 + (($1.0 > 0.5) != ($1.1 > 0.5) ? 1 : 0)
                }
                // Keep topology for tiny segmentation changes. The renderer
                // independently clips to the latest silhouette, including holes.
                let aspect = observation.bounds.width / observation.bounds.height
                if Float(changed) / Float(observation.mask.count) > 0.025
                    || abs(aspect / tracks[i].meshAspect - 1) > 0.12,
                   let mesh = LiveFoodMesh.build(mask: observation.mask, grid: Self.maskGrid,
                                                 spacing: Self.spacing(for: observation.bounds),
                                                 aspectRatio: aspect) {
                    tracks[i].mesh = mesh
                    tracks[i].meshAspect = aspect
                    tracks[i].meshMask = observation.mask
                    tracks[i].revision += 1
                }
                tracks[i].mask = observation.mask
            } else {
                guard observation.confidence >= LiveFoodOverlayPolicy.creationConfidence,
                      tracks.filter({ $0.visible }).count < LiveFoodOverlayPolicy.maxTracks,
                      !tracks.contains(where: {
                          Self.overlap($0.bounds, observation.bounds) > 0.75
                      }),
                      let mesh = LiveFoodMesh.build(mask: observation.mask, grid: Self.maskGrid,
                                                   spacing: Self.spacing(for: observation.bounds),
                                                   aspectRatio: observation.bounds.width / observation.bounds.height)
                else { continue }
                let id = nextID
                nextID += 1
                assigned.insert(id)
                tracks.append(LiveFoodTrack(
                    id: id, label: observation.label,
                    state: observation.confidence >= 0.7 ? .confirmed : .new,
                    confidence: observation.confidence, bounds: observation.bounds,
                    mask: observation.mask, meshMask: observation.mask,
                    mesh: mesh, meshAspect: observation.bounds.width / observation.bounds.height,
                    revision: 1, hits: 1, misses: 0,
                    lastDetection: now, lastMotion: now))
            }
        }
        for i in tracks.indices where !assigned.contains(tracks[i].id) {
            tracks[i].misses += 1
            if tracks[i].visible { tracks[i].state = .temporarilyOccluded }
        }
        expire(at: now)
    }

    private static func spacing(for bounds: CGRect) -> CGFloat {
        max(3, min(32, CGFloat(maskGrid) * 4.5 / bounds.width))
    }

    static func observations(mask: [Float], label: String, confidence: Float,
                             grid: Int, splitComponents: Bool = true) -> [LiveFoodObservation] {
        guard mask.count == grid * grid else { return [] }
        var visited = [Bool](repeating: false, count: mask.count)
        var components = [[Int]]()
        for seed in mask.indices where mask[seed] > 0.5 && !visited[seed] {
            var pixels = [seed], cursor = 0
            visited[seed] = true
            while cursor < pixels.count {
                let index = pixels[cursor], x = index % grid, y = index / grid
                cursor += 1
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && nx < grid && ny >= 0 && ny < grid {
                    let n = ny * grid + nx
                    if mask[n] > 0.5 && !visited[n] { visited[n] = true; pixels.append(n) }
                }
            }
            guard pixels.count >= 6 else { continue }
            components.append(pixels)
        }
        guard !components.isEmpty else { return [] }
        if !splitComponents { components = [components.flatMap { $0 }] }
        return components.map { pixels in
            let x0 = pixels.map { $0 % grid }.min()!, x1 = pixels.map { $0 % grid }.max()!
            let y0 = pixels.map { $0 / grid }.min()!, y1 = pixels.map { $0 / grid }.max()!
            let bounds = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
            let component = Set(pixels)
            var canonical = [Float](repeating: 0, count: maskGrid * maskGrid)
            for y in 0..<maskGrid { for x in 0..<maskGrid {
                let sx = x0 + min(x1 - x0, Int((CGFloat(x) + 0.5) * bounds.width / CGFloat(maskGrid)))
                let sy = y0 + min(y1 - y0, Int((CGFloat(y) + 0.5) * bounds.height / CGFloat(maskGrid)))
                if component.contains(sy * grid + sx) { canonical[y * maskGrid + x] = 1 }
            } }
            return LiveFoodObservation(label: label, confidence: confidence,
                                       bounds: bounds, mask: canonical)
        }
    }
}

struct LiveFoodFrameGate {
    /// ~15 Hz cap; one request in flight, so slow inference self-throttles.
    static let minInterval: TimeInterval = 0.066
    private(set) var busy = false
    private(set) var generation = 0
    private var lastSubmit: TimeInterval = -.infinity

    func canAccept(at now: TimeInterval) -> Bool {
        now.isFinite && !busy && now - lastSubmit >= LiveFoodFrameGate.minInterval
    }

    mutating func begin(at now: TimeInterval) -> Int? {
        guard canAccept(at: now) else { return nil }
        busy = true
        lastSubmit = now
        return generation
    }

    mutating func invalidate() {
        generation += 1
        // Work still owns the only slot until it actually returns.
        lastSubmit = -.infinity
    }

    mutating func finish(token: Int, timestamp: TimeInterval, now: TimeInterval) -> Bool {
        busy = false
        return token == generation && LiveFoodOverlayPolicy.isFresh(timestamp: timestamp, now: now)
    }
}

/// Throttled live food detection on the AR preview.
///
/// Follows Apple's real-time Vision/Core ML guidance: one frame in flight on a
/// background serial queue, frames dropped while busy, ~15 Hz cap, and the
/// camera buffer released right after a small square copy is made (so ARKit's
/// frame pool is never starved). Backends, in order: the bundled YOLO-seg
/// food model, then the dense food segmenter. No class-agnostic fallback.
/// Each current mask becomes a wireframe triangle mesh without temporal smearing.
final class LiveFoodDetector {

    static let grid = 160
    static let inputSide = 320
    enum Backend: String {
        case undecided, yolo, segformer, none
    }

    // Main-thread state.
    private var gate = LiveFoodFrameGate()
    private var ready = false

    // Queue state.
    private let queue = DispatchQueue(
        label: "com.pixelstomacros.liveglow", qos: .userInitiated)
    private var backend: Backend = .undecided
    private var yolo: YOLOSegmentationService?
    private var segformer: SegmentationService?
    private var runs = 0
    private var consecutiveFailures = 0
    private var pool: CVPixelBufferPool?
    private var trackStore = LiveFoodTrackStore()
    private var sequence = VNSequenceRequestHandler()
    private var trackingRequests: [Int: VNTrackObjectRequest] = [:]
    private var lastSegmentation: TimeInterval = -.infinity
    private var trackingGeneration = -1
    private lazy var ciContext = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull(),
        .cacheIntermediates: false,
    ])

    init() {
        queue.async { [self] in
            let started = CACurrentMediaTime()
            autoreleasepool { decideBackend() }
            print(String(format: "[LiveGlow] warmup=%.1fms backend=%@",
                         (CACurrentMediaTime() - started) * 1000, backend.rawValue))
            DispatchQueue.main.async { [self] in ready = true }
        }
    }

    func canAccept(at now: CFTimeInterval) -> Bool {
        ready && gate.canAccept(at: now)
    }

    /// Invalidates results without freeing the occupied inference slot.
    func reset() {
        gate.invalidate()
    }

    func drain(completion: @escaping () -> Void) {
        reset()
        queue.async { DispatchQueue.main.async(execute: completion) }
    }

    func submit(
        _ pixelBuffer: CVPixelBuffer,
        roi: LiveGlowGridROI,
        at now: CFTimeInterval,
        frameTimestamp: TimeInterval,
        completion: @escaping (LiveGlowResult) -> Void
    ) {
        guard ready, let token = gate.begin(at: now) else { return }
        // Copy before dispatching: the inference closure retains only our small
        // buffer, never an ARKit frame-pool buffer for the whole model request.
        let copyStarted = CACurrentMediaTime()
        let crop = LiveFoodCrop(roi: roi, grid: Self.grid)
        guard let input = makeSquareInput(pixelBuffer, crop: crop) else {
            if gate.finish(token: token, timestamp: frameTimestamp, now: CACurrentMediaTime()) {
                print("[LiveGlow] copy_failed")
            }
            return
        }
        let prepMs = (CACurrentMediaTime() - copyStarted) * 1000
        queue.async { [self] in
            let queueMs = (CACurrentMediaTime() - copyStarted) * 1000 - prepMs
            let result: LiveGlowResult? = autoreleasepool {
                guard LiveFoodOverlayPolicy.isFresh(timestamp: frameTimestamp, now: CACurrentMediaTime())
                else { return nil }
                if trackingGeneration != token {
                    trackingGeneration = token
                    trackStore = LiveFoodTrackStore()
                    sequence = VNSequenceRequestHandler()
                    trackingRequests.removeAll()
                    lastSegmentation = -.infinity
                }
                return process(input, roi: roi, crop: crop, timestamp: frameTimestamp,
                               prepMs: prepMs, queueMs: queueMs)
            }
            DispatchQueue.main.async { [self] in
                guard gate.finish(token: token, timestamp: frameTimestamp, now: CACurrentMediaTime()) else {
                    print(String(format: "[LiveGlow] drop_stale age=%.0fms token=%d",
                                 (CACurrentMediaTime() - frameTimestamp) * 1000, token))
                    return
                }
                if runs <= 5 || runs % 10 == 0 {
                    print(String(format: "[LiveGlow] result_age=%.1fms",
                                 (CACurrentMediaTime() - frameTimestamp) * 1000))
                }
                if let result { completion(result) }
            }
        }
    }

    // MARK: Pipeline (queue)

    private func process(_ input: CVPixelBuffer, roi: LiveGlowGridROI, crop: LiveFoodCrop,
                         timestamp: TimeInterval, prepMs: Double, queueMs: Double) -> LiveGlowResult? {
        let t1 = CACurrentMediaTime()

        if backend == .undecided { decideBackend() }

        advanceTracks(input, crop: crop, timestamp: timestamp)
        var observations = [LiveFoodObservation]()
        var ran = false
        let thermal = ProcessInfo.processInfo.thermalState
        let detectionInterval: TimeInterval = thermal == .serious || thermal == .critical ? 0.30 : 0.18
        let detectionDue = timestamp - lastSegmentation >= detectionInterval
        if backend != .none && detectionDue {
            lastSegmentation = timestamp
            do {
                observations = try runBackend(input, crop: crop, originalROI: roi)
                consecutiveFailures = 0
                ran = true
            } catch {
                consecutiveFailures += 1
                print("[LiveGlow] \(backend.rawValue) failed (\(consecutiveFailures)): \(error)")
                if consecutiveFailures >= 3 { fallBack() }
            }
        }
        let t2 = CACurrentMediaTime()
        let inferMs = (t2 - t1) * 1000

        if detectionDue {
            trackStore.update(observations, at: timestamp)
            seedTrackingRequests(crop: crop)
        } else {
            trackStore.expire(at: timestamp)
        }
        let visible = trackStore.tracks.filter { $0.visible }
        let t3 = CACurrentMediaTime()
        runs += 1
        if runs <= 5 || runs % 10 == 0 {
            print(String(
                format: "[LiveGlow] infer=%.1fms masks=%d backend=%@ prep=%.1fms queue=%.1fms post=%.1fms present=%@ tris=%d",
                inferMs, observations.count, backend.rawValue, prepMs, queueMs,
                (t3 - t2) * 1000, visible.isEmpty ? "0" : "1",
                visible.reduce(0) { $0 + $1.mesh.triangles }))
            print("[LiveGlowTracks] " + trackStore.tracks.map {
                "id=\($0.id) label=\($0.label) state=\($0.state.rawValue) misses=\($0.misses) revision=\($0.revision)"
            }.joined(separator: " | "))
        }
        return LiveGlowResult(
            tracks: visible,
            present: !visible.isEmpty,
            available: backend != .none && (ran || !detectionDue),
            backend: backend.rawValue)
    }

    private func decideBackend() {
        let y = YOLOSegmentationService()
        if y.isAvailable {
            yolo = y
            backend = .yolo
        } else {
            let s = SegmentationService()
            if (try? s.loadModel()) != nil {
                segformer = s
                backend = .segformer
            } else {
                backend = .none
            }
        }
        print("[LiveGlow] backend=\(backend.rawValue) resource=\(yolo?.loadedResource ?? "-")")
    }

    private func fallBack() {
        let next: Backend
        switch backend {
        case .yolo:
            yolo = nil
            let s = SegmentationService()
            if (try? s.loadModel()) != nil {
                segformer = s
                next = .segformer
            } else {
                next = .none
            }
        case .segformer:
            segformer = nil
            next = .none
        default:
            next = .none
        }
        print("[LiveGlow] backend \(backend.rawValue) → \(next.rawValue)")
        backend = next
        consecutiveFailures = 0
    }

    private func advanceTracks(_ input: CVPixelBuffer, crop: LiveFoodCrop, timestamp: TimeInterval) {
        let active = trackingRequests.filter { id, _ in
            trackStore.tracks.contains { $0.id == id && $0.visible }
        }
        guard !active.isEmpty else { return }
        do {
            try sequence.perform(Array(active.values), on: input, orientation: .up)
            for (id, request) in active {
                guard let observation = request.results?.first as? VNDetectedObjectObservation else { continue }
                let box = observation.boundingBox
                let rect = CGRect(
                    x: crop.rect.minX + box.minX * crop.rect.width,
                    y: crop.rect.minY + (1 - box.maxY) * crop.rect.height,
                    width: box.width * crop.rect.width, height: box.height * crop.rect.height)
                trackStore.move(id: id, bounds: rect, confidence: observation.confidence, at: timestamp)
                request.inputObservation = observation
            }
        } catch {
            print("[LiveGlowTracks] motion_failed \(error)")
        }
    }

    private func seedTrackingRequests(crop: LiveFoodCrop) {
        let visibleIDs = Set(trackStore.tracks.filter { $0.visible }.map { $0.id })
        trackingRequests = trackingRequests.filter { visibleIDs.contains($0.key) }
        for track in trackStore.tracks where track.visible && track.misses == 0 {
            let rect = track.bounds
            let box = CGRect(
                x: (rect.minX - crop.rect.minX) / crop.rect.width,
                y: 1 - (rect.maxY - crop.rect.minY) / crop.rect.height,
                width: rect.width / crop.rect.width, height: rect.height / crop.rect.height)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !box.isNull, box.width > 0, box.height > 0 else { continue }
            let observation = VNDetectedObjectObservation(boundingBox: box)
            if let request = trackingRequests[track.id] {
                request.inputObservation = observation
            } else {
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .fast
                trackingRequests[track.id] = request
            }
        }
    }

    private func runBackend(_ input: CVPixelBuffer, crop: LiveFoodCrop,
                            originalROI: LiveGlowGridROI) throws -> [LiveFoodObservation] {
        let objects: [SegmentationService.SegmentedObject]
        switch backend {
        case .yolo:
            guard let yolo else { return [] }
            objects = try yolo.segmentForLivePreview(pixelBuffer: input, roi: crop.roi)
        case .segformer:
            guard let segformer else { return [] }
            objects = try segformer.segmentForLivePreview(pixelBuffer: input)
        case .undecided, .none:
            return []
        }
        let points = inputPoints(crop: crop, roi: originalROI)
        return objects.flatMap { object -> [LiveFoodObservation] in
            var mask = [Float](repeating: 0, count: Self.grid * Self.grid)
            guard accumulate([object], crop: crop, roi: originalROI, into: &mask, points: points) > 0 else { return [] }
            return LiveFoodTrackStore.observations(mask: mask, label: object.label,
                                                  confidence: object.confidence, grid: Self.grid,
                                                  splitComponents: backend != .yolo)
        }
    }

    private func inputPoints(crop: LiveFoodCrop, roi: LiveGlowGridROI) -> [CGPoint?] {
        let g = Self.grid
        return (0..<(g * g)).map { index -> CGPoint? in
            let x = CGFloat(index % g) + 0.5, y = CGFloat(index / g) + 0.5
            guard roi.contains(x: x, y: y) else { return nil }
            let p = crop.inputPoint(x: x, y: y, grid: g)
            return p.x >= 0 && p.y >= 0 && p.x < CGFloat(g) && p.y < CGFloat(g) ? p : nil
        }
    }

    private func accumulate(
        _ objects: [SegmentationService.SegmentedObject],
        crop: LiveFoodCrop, roi: LiveGlowGridROI,
        into union: inout [Float], points: [CGPoint?]? = nil
    ) -> Int {
        let g = Self.grid
        let inputPoints = points ?? inputPoints(crop: crop, roi: roi)
        var kept = 0
        for object in objects {
            guard LiveFoodOverlayPolicy.accepts(label: object.label, confidence: object.confidence) else { continue }
            let rows = object.mask.count
            guard rows > 0, let cols = object.mask.first?.count, cols > 0,
                  object.mask.allSatisfy({ $0.count == cols }) else { continue }
            let fraction = Float(object.pixelCount) / Float(rows * cols)
            guard fraction >= 0.0002 else { continue }
            var contributed = false
            for gy in 0..<g {
                let base = gy * g
                for gx in 0..<g {
                    guard let p = inputPoints[base + gx] else { continue }
                    let sy = min(rows - 1, Int(p.y * CGFloat(rows) / CGFloat(g)))
                    let sx = min(cols - 1, Int(p.x * CGFloat(cols) / CGFloat(g)))
                    if object.mask[sy][sx] != 0 {
                        union[base + gx] = 1
                        contributed = true
                    }
                }
            }
            if contributed { kept += 1 }
        }
        return kept
    }

    /// Centre-square crop of the camera frame, scaled to `inputSide`² BGRA.
    /// The ARKit buffer is released as soon as this returns.
    private func makeSquareInput(_ source: CVPixelBuffer, crop liveCrop: LiveFoodCrop) -> CVPixelBuffer? {
        let side = Self.inputSide
        if pool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: side,
                kCVPixelBufferHeightKey as String: side,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return nil }

        let image = CIImage(cvPixelBuffer: source)
        let extent = image.extent
        let fullSide = min(extent.width, extent.height)
        let gridScale = fullSide / CGFloat(Self.grid)
        // CI uses bottom-left coordinates; masks and the preview use top-left.
        let square = CGRect(
            x: extent.midX - fullSide / 2 + liveCrop.rect.minX * gridScale,
            y: extent.midY + fullSide / 2 - liveCrop.rect.maxY * gridScale,
            width: liveCrop.rect.width * gridScale, height: liveCrop.rect.height * gridScale)
        let scale = CGFloat(side) / square.width
        let scaled = image.cropped(to: square)
            .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        ciContext.render(
            scaled, to: out,
            bounds: CGRect(x: 0, y: 0, width: side, height: side),
            colorSpace: nil)
        return out
    }

    // MARK: Mask post-processing (queue)

    private func postProcess(
        _ union: [Float], roi: LiveGlowGridROI
    ) -> (mesh: LiveFoodMesh?, present: Bool) {
        let g = Self.grid
        var inside = 0
        var roiArea = 0
        let r = max(0, min(roi.radius, min(roi.rect.width, roi.rect.height) / 2))
        let cx = roi.rect.midX, cy = roi.rect.midY
        let hx = roi.rect.width / 2 - r, hy = roi.rect.height / 2 - r
        let y0 = max(0, Int(roi.rect.minY.rounded(.down)))
        let y1 = min(g, Int(roi.rect.maxY.rounded(.up)))
        let x0 = max(0, Int(roi.rect.minX.rounded(.down)))
        let x1 = min(g, Int(roi.rect.maxX.rounded(.up)))
        if y0 < y1 && x0 < x1 {
            for y in y0..<y1 {
                let dy = max(abs(CGFloat(y) + 0.5 - cy) - hy, 0)
                for x in x0..<x1 {
                    let dx = max(abs(CGFloat(x) + 0.5 - cx) - hx, 0)
                    if dx * dx + dy * dy > r * r { continue }
                    roiArea += 1
                    if union[y * g + x] > 0.5 { inside += 1 }
                }
            }
        }
        let present = roiArea > 0 && inside >= max(40, Int(Double(roiArea) * 0.004))
        guard present, let mesh = LiveFoodMesh.build(mask: union, grid: g)
        else { return (nil, present) }
        return (mesh, present)
    }
}

// MARK: – Mesh layers

private final class LiveFoodHighlights {
    let root = CALayer()
    private let clip = CAShapeLayer()
    private let guide: LiveGlowLayers
    private var foods: [Int: LiveGlowLayers] = [:]
    private var style: LiveGlowStyle
    private var roi: LiveGlowROI?
    private weak var display: CALayer?
    private var bounds = CGRect.zero
    var videoSize = CGSize(width: 1920, height: 1440) {
        didSet {
            guide.videoSize = videoSize
            for food in foods.values { food.videoSize = videoSize }
        }
    }

    init(style: LiveGlowStyle) {
        self.style = style
        guide = LiveGlowLayers(style: style)
        clip.fillColor = UIColor.white.cgColor
        root.mask = clip
    }

    func layout(in rect: CGRect, matching display: CALayer) {
        self.bounds = rect
        self.display = display
        root.frame = rect
        guide.layout(in: rect, matching: display)
        clip.frame = root.bounds
        clip.path = guide.guideClipPath()
        for food in foods.values { food.layout(in: rect, matching: display) }
    }

    func setRoi(_ roi: LiveGlowROI?) {
        self.roi = roi
        guide.setRoi(roi)
        clip.path = guide.guideClipPath()
        for food in foods.values { food.setRoi(roi) }
    }

    func roiInMaskGrid(_ grid: Int) -> LiveGlowGridROI? { guide.roiInMaskGrid(grid) }

    func apply(style: LiveGlowStyle) {
        self.style = style
        guide.apply(style: style)
        for food in foods.values { food.apply(style: style) }
    }

    func update(tracks: [LiveFoodTrack]) {
        guard let display else { return }
        let ids = Set(tracks.map { $0.id })
        for id in Array(foods.keys) where !ids.contains(id) {
            guard let food = foods.removeValue(forKey: id) else { continue }
            food.setVisible(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                food.root.removeFromSuperlayer()
            }
        }
        for track in tracks {
            let food: LiveGlowLayers
            if let existing = foods[track.id] {
                food = existing
            } else {
                food = LiveGlowLayers(style: style, clipsGuide: false)
                food.videoSize = videoSize
                food.setRoi(roi)
                food.layout(in: bounds, matching: display)
                foods[track.id] = food
                root.addSublayer(food.root)
            }
            food.update(track: track)
            food.setVisible(true)
        }
    }

    func setVisible(_ show: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = show ? 1 : 0
        CATransaction.commit()
        if !show {
            for food in foods.values { food.root.removeFromSuperlayer() }
            foods.removeAll()
        }
    }
}

/// Core Animation layers that draw the live food wireframe mesh, aligned with
/// the aspect-fit, orientation-rotated preview. The `content` layer mirrors
/// the display layer's geometry, so the mesh (sensor-oriented, centre square
/// of the frame) lands exactly on the food in every orientation. The mesh is
/// clipped to the capture ROI drawn in that same centred square, so it matches
/// the pipeline's capture geometry exactly (only food inside counts).
/// All motion (wire pulse, scan sweep, node twinkle, premium colour flow) is
/// render-server animation, so it runs at the display's full refresh rate
/// independent of the ~15 Hz detector and of main-thread load.
enum LiveFoodWave {
    static let duration: TimeInterval = 4
    static let alphas: [CGFloat] = (0...12).map {
        CGFloat(0.22 + 0.20 * cos(Double($0) * .pi / 2))
    }
    static let locations = (0...12).map { NSNumber(value: Double($0) / 12) }
}

private final class LiveGlowLayers {

    let root = CALayer()
    private let roiMask = CAShapeLayer()
    private let content = CALayer()
    private let crop = CALayer()
    private let geometry = CALayer()
    private let silhouetteMask = CALayer()
    private let fillLayer = CAShapeLayer()
    private let wireContainer = CALayer()
    private let wireSource = CAGradientLayer()
    private let wireMask = CAShapeLayer()
    private let sweepSource = CAGradientLayer()
    private let sweepContainer = CALayer()
    private let sweepMask = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let nodesLayer = CAShapeLayer()

    var videoSize = CGSize(width: 1920, height: 1440)
    private var style: LiveGlowStyle
    private var styleApplied = false
    private var roi: LiveGlowROI?
    private var mesh: LiveFoodMesh?
    private var meshGrid = LiveFoodDetector.grid
    private var revision = -1
    private var trackBounds: CGRect?
    private var lastMask: [Float] = []
    /// Landscape UI: world-horizontal follows the frame columns.
    private var longAxisAlongColumns = true
    private var visible = false

    init(style: LiveGlowStyle, clipsGuide: Bool = true) {
        self.style = style
        root.opacity = 0
        roiMask.fillColor = UIColor.white.cgColor
        root.addSublayer(content)
        content.addSublayer(crop)
        crop.masksToBounds = true
        if clipsGuide { crop.mask = roiMask }

        for shape in [wireMask, sweepMask] {
            shape.fillColor = nil
            shape.strokeColor = UIColor.white.cgColor
            shape.lineJoin = .round
            shape.lineCap = .round
        }
        wireMask.lineWidth = 0.9
        sweepMask.lineWidth = 1.6
        wireContainer.mask = wireMask
        wireContainer.addSublayer(wireSource)
        sweepContainer.mask = sweepMask
        sweepContainer.addSublayer(sweepSource)

        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 2
        outlineLayer.lineJoin = .round
        outlineLayer.lineCap = .round
        // A hairline dark shadow keeps the theme-coloured contour legible on
        // bright plates and food without turning it into a glow.
        outlineLayer.shadowColor = UIColor.black.cgColor
        outlineLayer.shadowOpacity = 0.35
        outlineLayer.shadowRadius = 1.2
        outlineLayer.shadowOffset = .zero

        geometry.anchorPoint = .zero
        geometry.position = .zero
        geometry.mask = silhouetteMask
        silhouetteMask.contentsGravity = .resize
        silhouetteMask.magnificationFilter = .nearest
        silhouetteMask.minificationFilter = .nearest
        crop.addSublayer(geometry)
        geometry.addSublayer(fillLayer)
        geometry.addSublayer(wireContainer)
        geometry.addSublayer(sweepContainer)
        geometry.addSublayer(outlineLayer)
        geometry.addSublayer(nodesLayer)
        apply(style: style)
    }

    func layout(in rect: CGRect, matching display: CALayer) {
        longAxisAlongColumns = rect.width >= rect.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = rect
        content.bounds = display.bounds
        content.position = display.position
        content.transform = display.transform

        let video = AVMakeRect(aspectRatio: videoSize, insideRect: content.bounds)
        let side = min(video.width, video.height)
        crop.frame = CGRect(
            x: video.midX - side / 2, y: video.midY - side / 2,
            width: side, height: side)
        let b = crop.bounds
        layoutGeometry()
        roiMask.frame = b
        roiMask.path = roiPath()
        applyMeshPaths()
        applyTrackTransform(animated: false)
        CATransaction.commit()
    }

    func setRoi(_ newRoi: LiveGlowROI?) {
        guard newRoi != roi else { return }
        let old = roiMask.path
        roi = newRoi
        if let newRoi {
            print("[LiveGlow] roi \(newRoi.logDescription(longAxisAlongColumns: longAxisAlongColumns)) crop=centred_square video=\(Int(videoSize.width))x\(Int(videoSize.height))")
        }
        let path = roiPath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        roiMask.path = path
        CATransaction.commit()
        if let old, path != nil, visible, !style.reduceMotion {
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = old
            anim.toValue = path
            anim.duration = 0.45
            anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
            roiMask.add(anim, forKey: "path")
        }
    }

    /// The capture ROI in `crop` coordinates (the frame's centred square),
    /// as a rounded rectangle built from tangent arcs so circle ↔ rectangle
    /// paths have identical structure and can be interpolated.
    private func roiPath() -> CGPath? {
        let side = crop.bounds.width
        guard let roi, side > 0 else { return nil }
        let g = roi.geometry(side: side, longAxisAlongColumns: longAxisAlongColumns)
        let rect = g.rect
        let r = max(0.5, min(g.corner, min(rect.width, rect.height) / 2))
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }

    func guideClipPath() -> CGPath? {
        guard let path = roiPath() else { return nil }
        let origin = root.convert(CGPoint.zero, from: crop)
        let x = root.convert(CGPoint(x: 1, y: 0), from: crop)
        let y = root.convert(CGPoint(x: 0, y: 1), from: crop)
        var transform = CGAffineTransform(
            a: x.x - origin.x, b: x.y - origin.y,
            c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
        return path.copy(using: &transform)
    }

    /// The guide in mask-grid cells (for the presence test).
    func roiInMaskGrid(_ grid: Int) -> LiveGlowGridROI? {
        guard let roi else { return nil }
        let g = roi.geometry(side: CGFloat(grid), longAxisAlongColumns: longAxisAlongColumns)
        return LiveGlowGridROI(rect: g.rect, radius: g.corner)
    }

    func apply(style newStyle: LiveGlowStyle) {
        guard !styleApplied || newStyle != style else { return }
        style = newStyle
        styleApplied = true
        let colors = style.colors.isEmpty ? LiveGlowStyle.fallback.colors : style.colors
        let accent = colors[0]
        let bright = accent.mixed(with: .white, amount: 0.35)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [wireContainer, wireSource, sweepSource, nodesLayer] as [CALayer] {
            layer.removeAllAnimations()
        }
        fillLayer.fillColor = accent.withAlphaComponent(style.premium ? 0.07 : 0.04).cgColor
        outlineLayer.strokeColor = bright.cgColor
        nodesLayer.fillColor = accent.mixed(with: .white, amount: 0.55).cgColor
        wireContainer.opacity = 0.85

        if style.premium && colors.count > 1 {
            wireSource.type = .conic
            wireSource.startPoint = CGPoint(x: 0.5, y: 0.5)
            wireSource.endPoint = CGPoint(x: 0.5, y: 0)
            wireSource.colors = (colors + [colors[0]]).map {
                $0.mixed(with: .white, amount: 0.15).cgColor
            }
            wireSource.backgroundColor = nil
        } else {
            wireSource.colors = nil
            wireSource.backgroundColor = accent.mixed(with: .white, amount: 0.15).cgColor
        }

        sweepSource.type = .axial
        sweepSource.startPoint = CGPoint(x: 0, y: 0)
        sweepSource.endPoint = CGPoint(x: 1, y: 1)
        sweepSource.colors = LiveFoodWave.alphas.map { bright.withAlphaComponent($0).cgColor }
        sweepSource.locations = LiveFoodWave.locations
        sweepSource.isHidden = style.reduceMotion
        CATransaction.commit()

        guard !style.reduceMotion else { return }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.72
        pulse.toValue = 0.88
        pulse.duration = 2.4
        pulse.autoreverses = true
        add(pulse, to: wireContainer, key: "pulse")

        animateWave()

        let twinkle = CABasicAnimation(keyPath: "opacity")
        twinkle.fromValue = 0.75
        twinkle.toValue = 0.9
        twinkle.duration = 2.4
        twinkle.autoreverses = true
        add(twinkle, to: nodesLayer, key: "twinkle")

        if style.premium && colors.count > 1 {
            let flow = CABasicAnimation(keyPath: "transform.rotation.z")
            flow.fromValue = 0
            flow.toValue = 2 * Double.pi
            flow.duration = 6
            flow.timingFunction = CAMediaTimingFunction(name: .linear)
            add(flow, to: wireSource, key: "flow")
        }
    }

    private func add(_ animation: CABasicAnimation, to layer: CALayer, key: String) {
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        if animation.timingFunction == nil {
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }

        animation.beginTime = layer.convertTime(floor(CACurrentMediaTime() / 8) * 8, from: nil)
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        layer.add(animation, forKey: key)
    }

    private func animateWave() {
        let b = geometry.bounds
        guard b.width > 0, b.height > 0, !style.reduceMotion else { return }
        let sweep = CABasicAnimation(keyPath: "position")
        sweep.fromValue = NSValue(cgPoint: .zero)
        sweep.toValue = NSValue(cgPoint: CGPoint(x: b.width, y: b.height))
        sweep.duration = LiveFoodWave.duration
        sweep.timingFunction = CAMediaTimingFunction(name: .linear)
        add(sweep, to: sweepSource, key: "sweep")
    }

    /// Replaces the mesh atomically — never blends previous support into a
    /// new camera frame.
    func update(mesh newMesh: LiveFoodMesh) {
        mesh = newMesh
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyMeshPaths()
        CATransaction.commit()
    }

    func update(track: LiveFoodTrack) {
        meshGrid = LiveFoodTrackStore.maskGrid
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sizeChanged = trackBounds?.size != track.bounds.size
        trackBounds = track.bounds
        layoutGeometry()
        if revision != track.revision || sizeChanged {
            revision = track.revision
            mesh = track.mesh
            applyMeshPaths()
        }
        if lastMask != track.mask {
            lastMask = track.mask
            var pixels = [UInt8](repeating: 255, count: meshGrid * meshGrid * 4)
            for i in track.mask.indices {
                let alpha: UInt8 = track.mask[i] > 0.5 ? 255 : 0
                for c in 0..<4 { pixels[i * 4 + c] = alpha }
            }
            if let provider = CGDataProvider(data: Data(pixels) as CFData) {
                silhouetteMask.contents = CGImage(
                    width: meshGrid, height: meshGrid, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: meshGrid * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            }
        }
        applyTrackTransform(animated: visible && !style.reduceMotion)
        CATransaction.commit()
    }

    private func applyTrackTransform(animated: Bool) {
        guard let bounds = trackBounds else { return }
        let side = crop.bounds.width, grid = CGFloat(LiveFoodDetector.grid)
        let position = CGPoint(x: bounds.minX * side / grid, y: bounds.minY * side / grid)
        let old = geometry.presentation()?.position ?? geometry.position
        geometry.position = position
        if animated {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(cgPoint: old)
            animation.toValue = NSValue(cgPoint: position)
            animation.duration = LiveFoodFrameGate.minInterval
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            geometry.add(animation, forKey: "tracking")
        }
    }

    private func layoutGeometry() {
        let scale = crop.bounds.width / CGFloat(LiveFoodDetector.grid)
        let size = trackBounds.map { CGSize(width: $0.width * scale, height: $0.height * scale) }
            ?? crop.bounds.size
        let b = CGRect(origin: .zero, size: size)
        let sizeChanged = geometry.bounds.size != b.size
        geometry.bounds = b
        silhouetteMask.frame = b
        for layer in [fillLayer, wireContainer, wireMask, sweepContainer, sweepMask,
                      outlineLayer, nodesLayer] as [CALayer] {
            layer.frame = b
        }
        let d = max(b.width, b.height) * 1.5
        wireSource.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        wireSource.position = CGPoint(x: b.midX, y: b.midY)
        sweepSource.bounds = CGRect(x: 0, y: 0, width: b.width * 3, height: b.height * 3)
        sweepSource.position = .zero
        if sizeChanged { animateWave() }
        wireMask.lineWidth = 0.8
        sweepMask.lineWidth = 1.0
        outlineLayer.lineWidth = 1.1
    }

    /// Maps the mesh from mask-grid cells into the crop square.
    private func applyMeshPaths() {
        let size = geometry.bounds.size
        guard let mesh, size.width > 0, size.height > 0 else {
            for shape in [fillLayer, wireMask, sweepMask, outlineLayer, nodesLayer] {
                shape.path = nil
            }
            return
        }
        let sx = size.width / CGFloat(meshGrid), sy = size.height / CGFloat(meshGrid)
        var t = CGAffineTransform(scaleX: sx, y: sy)
        let wire = mesh.wire.copy(using: &t)
        fillLayer.path = mesh.region.copy(using: &t)
        wireMask.path = wire
        sweepMask.path = wire
        outlineLayer.path = mesh.outline.copy(using: &t)
        let r: CGFloat = 0.75
        let dots = CGMutablePath()
        for p in mesh.nodes {
            dots.addEllipse(in: CGRect(x: p.x * sx - r, y: p.y * sy - r,
                                       width: 2 * r, height: 2 * r))
        }
        nodesLayer.path = dots
    }

    func setVisible(_ show: Bool) {
        guard show != visible else { return }
        visible = show
        let to: Float = show ? 1 : 0
        let from = root.presentation()?.opacity ?? root.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = to
        if !style.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = to
            fade.duration = show ? 0.18 : 0.28
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            root.add(fade, forKey: "fade")
        } else {
            root.removeAnimation(forKey: "fade")
        }
        CATransaction.commit()
    }
}
