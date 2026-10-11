import ARKit
import AVFoundation
import CoreImage
import CoreMedia
import Flutter
import QuartzCore
import simd
import UIKit

/// Embeds a live ARKit camera feed as a Flutter platform view.
///
/// Uses AVSampleBufferDisplayLayer (a plain Core Animation layer) instead of
/// ARSCNView so there are no Metal-compositor conflicts with Flutter's renderer.
/// Frames are polled from ARSessionManager.latestFrame via CADisplayLink at
/// ≈30 fps and pushed to the display layer as CMSampleBuffers.
///
/// The view also hosts the live "AI glow": a throttled on-device food detector
/// (see `LiveFoodDetector`) whose exact live mask is drawn as translucent themed layers
/// exactly over the aspect-fit preview (see `LiveGlowLayers`). It is driven
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
    var glow: LiveGlowLayers? {
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
    private var overlayTimestamp: TimeInterval?
    private var overlayCameraTransform: simd_float4x4?

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
        // 30 fps for a smooth camera preview.
        displayLink?.preferredFrameRateRange =
            CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
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
            guard let manager = sessionManager, let frame = manager.latestFrame,
                  UIApplication.shared.applicationState == .active,
                  hostView.window != nil, !hostView.isHidden
            else {
                if liveContext != nil { invalidateLiveOverlay() }
                return
            }
            let pixelBuffer = frame.capturedImage
            let now = CACurrentMediaTime()
            if let timestamp = overlayTimestamp,
               !LiveFoodOverlayPolicy.isFresh(timestamp: timestamp, now: now)
                || overlayCameraTransform.map({
                    !LiveFoodOverlayPolicy.cameraIsAligned($0, frame.camera.transform)
                }) == true {
                hostView.glow?.setVisible(false)
                overlayTimestamp = nil
                overlayCameraTransform = nil
                LiveFoodGlowController.shared.clearDetection()
            }
            guard now - frame.timestamp <= LiveFoodOverlayPolicy.maxAge else {
                if liveContext != nil { invalidateLiveOverlay() }
                return
            }
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
        let cameraTransform = frame.camera.transform
        detector.submit(frame.capturedImage, roi: roi, at: now, frameTimestamp: timestamp) { [weak self] result in
            guard let self, let glow = self.hostView.glow,
                  self.liveContext == context,
                  self.hostView.window != nil, !self.hostView.isHidden,
                  self.hostView.bounds == context.bounds,
                  self.hostView.window?.windowScene?.interfaceOrientation == context.orientation,
                  self.sessionManager?.generation == context.generation,
                  UIApplication.shared.applicationState == .active,
                  LiveFoodGlowController.shared.enabled,
                  let current = self.sessionManager?.latestFrame,
                  LiveFoodOverlayPolicy.isFresh(timestamp: timestamp, now: CACurrentMediaTime()),
                  LiveFoodOverlayPolicy.cameraIsAligned(cameraTransform, current.camera.transform)
            else { return }
            if result.present, let fill = result.fill, let edge = result.edge, let core = result.core {
                glow.update(fill: fill, edge: edge, core: core)
                glow.setVisible(true)
            } else {
                glow.setVisible(false)
            }
            self.overlayTimestamp = timestamp
            self.overlayCameraTransform = cameraTransform
            LiveFoodGlowController.shared.report(
                detected: result.present,
                available: result.available,
                backend: result.backend)
        }
    }

    private func invalidateLiveOverlay() {
        detector?.reset()
        liveContext = nil
        lastFrameTimestamp = nil
        overlayTimestamp = nil
        overlayCameraTransform = nil
        hostView.glow?.setVisible(false)
        LiveFoodGlowController.shared.clearDetection()
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
            let glow = LiveGlowLayers(style: controller.style)
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
                print("[LiveGlow] start premium=\(style.premium) reduceMotion=\(style.reduceMotion)")
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
    let fill: CGImage?
    let edge: CGImage?
    let core: CGImage?
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

    static func accepts(label: String, confidence: Float) -> Bool {
        let name = label.lowercased().replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return confidence.isFinite && confidence >= 0.55 && foodLabels.contains(name)
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
        return translation <= 0.01 && abs(simd_dot(rotationA.vector, rotationB.vector)) >= cos(Float.pi / 120)
    }

    /// Exact current support: holes and disconnected components stay empty.
    static func glowFields(_ mask: [Float], grid g: Int)
        -> (fill: [Float], edge: [Float], core: [Float])? {
        let n = g * g
        guard g > 0, mask.count == n else { return nil }
        var fill = [Float](repeating: 0, count: n)
        for i in 0..<n {
            fill[i] = mask[i].isFinite && mask[i] > 0.5 ? 1 : 0
        }
        let empty = [Float](repeating: 0, count: n)
        return (fill, empty, empty)
    }

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

    /// Premultiplied white RGBA image whose alpha is `values` (0…1).
    static func alphaImage(_ values: [Float], _ g: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: g * g * 4)
        for i in 0..<(g * g) {
            let a = UInt8(max(0, min(255, values[i] * 255)))
            let o = i * 4
            bytes[o] = a
            bytes[o + 1] = a
            bytes[o + 2] = a
            bytes[o + 3] = a
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: g, height: g,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: g * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }
}

struct LiveFoodFrameGate {
    private(set) var busy = false
    private(set) var generation = 0
    private var lastSubmit: TimeInterval = -.infinity

    func canAccept(at now: TimeInterval) -> Bool {
        now.isFinite && !busy && now - lastSubmit >= 0.12
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
/// background serial queue, frames dropped while busy, ~8 Hz cap, and the
/// camera buffer released right after a small square copy is made (so ARKit's
/// frame pool is never starved). Backends, in order: the bundled YOLO-seg
/// food model, then the dense food segmenter. No class-agnostic fallback.
/// Current masks become exact alpha images without temporal smearing.
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
                completion(LiveGlowResult(fill: nil, edge: nil, core: nil,
                                          present: false, available: false, backend: "copy_failed"))
            }
            return
        }
        let prepMs = (CACurrentMediaTime() - copyStarted) * 1000
        queue.async { [self] in
            let queueMs = (CACurrentMediaTime() - copyStarted) * 1000 - prepMs
            let result: LiveGlowResult? = autoreleasepool {
                guard LiveFoodOverlayPolicy.isFresh(timestamp: frameTimestamp, now: CACurrentMediaTime())
                else { return nil }
                return process(input, roi: roi, crop: crop, prepMs: prepMs, queueMs: queueMs)
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
                         prepMs: Double, queueMs: Double) -> LiveGlowResult? {
        let t1 = CACurrentMediaTime()

        if backend == .undecided { decideBackend() }

        var masks = 0
        var union = [Float](repeating: 0, count: Self.grid * Self.grid)
        var ran = false
        if backend != .none {
            do {
                masks = try runBackend(input, crop: crop, originalROI: roi, into: &union)
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

        let post = postProcess(union, roi: roi)
        let t3 = CACurrentMediaTime()
        runs += 1
        if ran && (runs <= 5 || runs % 10 == 0) {
            print(String(
                format: "[LiveGlow] infer=%.1fms masks=%d backend=%@ prep=%.1fms queue=%.1fms post=%.1fms present=%@",
                inferMs, masks, backend.rawValue, prepMs, queueMs,
                (t3 - t2) * 1000, post.present ? "1" : "0"))
        }
        return LiveGlowResult(
            fill: post.images?.fill,
            edge: post.images?.edge,
            core: post.images?.core,
            present: post.present,
            available: ran && backend != .none,
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

    /// Runs the active backend and ORs the kept food masks into `union`.
    private func runBackend(_ input: CVPixelBuffer, crop: LiveFoodCrop,
                            originalROI: LiveGlowGridROI, into union: inout [Float]) throws -> Int {
        switch backend {
        case .yolo:
            guard let yolo else { return 0 }
            let objects = try yolo.segmentForLivePreview(pixelBuffer: input, roi: crop.roi)
            return accumulate(objects, crop: crop, roi: originalROI, into: &union)
        case .segformer:
            guard let segformer else { return 0 }
            let objects = try segformer.segmentForLivePreview(pixelBuffer: input)
            return accumulate(objects, crop: crop, roi: originalROI, into: &union)
        case .undecided, .none:
            return 0
        }
    }

    private func accumulate(
        _ objects: [SegmentationService.SegmentedObject],
        crop: LiveFoodCrop, roi: LiveGlowGridROI,
        into union: inout [Float]
    ) -> Int {
        let g = Self.grid
        let inputPoints = (0..<(g * g)).map { index -> CGPoint? in
            let x = CGFloat(index % g) + 0.5, y = CGFloat(index / g) + 0.5
            guard roi.contains(x: x, y: y) else { return nil }
            let p = crop.inputPoint(x: x, y: y, grid: g)
            return p.x >= 0 && p.y >= 0 && p.x < CGFloat(g) && p.y < CGFloat(g) ? p : nil
        }
        var kept = 0
        for object in objects {
            guard LiveFoodOverlayPolicy.accepts(label: object.label, confidence: object.confidence) else { continue }
            let rows = object.mask.count
            guard rows > 0, let cols = object.mask.first?.count, cols > 0,
                  object.mask.allSatisfy({ $0.count == cols }) else { continue }
            let fraction = Float(object.pixelCount) / Float(rows * cols)
            guard fraction >= 0.002 else { continue }
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
            if kept >= 8 { break }
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
    ) -> (images: (fill: CGImage, edge: CGImage, core: CGImage)?, present: Bool) {
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
        guard present,
              let f = LiveFoodOverlayPolicy.glowFields(union, grid: g),
              let fill = LiveFoodOverlayPolicy.alphaImage(f.fill, g),
              let edge = LiveFoodOverlayPolicy.alphaImage(f.edge, g),
              let core = LiveFoodOverlayPolicy.alphaImage(f.core, g)
        else { return (nil, present) }
        return ((fill, edge, core), present)
    }
}

// MARK: – Glow layers

/// Core Animation layers that draw the glow on the food, aligned with the
/// aspect-fit, orientation-rotated preview. The `content` layer mirrors the
/// display layer's geometry, so the mask images (sensor-oriented, centre
/// square of the frame) land exactly on the food in every orientation. The
/// glow is clipped to the capture ROI drawn in that same centred square, so it
/// matches the pipeline's capture geometry exactly (only food inside counts).
private final class LiveGlowLayers {

    let root = CALayer()
    private let roiMask = CAShapeLayer()
    private let content = CALayer()
    private let crop = CALayer()
    private let fillSource = CAGradientLayer()
    private let fillMask = CALayer()
    private let shimmer = CAGradientLayer()
    private let shimmerMask = CALayer()
    private let edgeContainer = CALayer()
    private let edgeSource = CAGradientLayer()
    private let edgeMask = CALayer()
    private let coreContainer = CALayer()
    private let coreMask = CALayer()

    var videoSize = CGSize(width: 1920, height: 1440)
    private var style: LiveGlowStyle
    private var styleApplied = false
    private var roi: LiveGlowROI?
    /// Landscape UI: world-horizontal follows the frame columns.
    private var longAxisAlongColumns = true
    private var visible = false

    init(style: LiveGlowStyle) {
        self.style = style
        root.opacity = 0
        roiMask.fillColor = UIColor.white.cgColor
        root.addSublayer(content)
        content.addSublayer(crop)
        crop.masksToBounds = true
        crop.mask = roiMask

        fillSource.mask = fillMask
        shimmer.mask = shimmerMask
        edgeContainer.mask = edgeMask
        edgeContainer.addSublayer(edgeSource)
        coreContainer.mask = coreMask
        coreContainer.backgroundColor = UIColor.white.cgColor
        crop.addSublayer(fillSource)
        crop.addSublayer(shimmer)
        crop.addSublayer(edgeContainer)
        crop.addSublayer(coreContainer)
        for mask in [fillMask, shimmerMask, edgeMask, coreMask] {
            mask.contentsGravity = .resize
            mask.magnificationFilter = .nearest
            mask.minificationFilter = .nearest
        }
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
        for layer in [fillSource, fillMask, shimmer, shimmerMask,
                      edgeContainer, edgeMask, coreContainer, coreMask] as [CALayer] {
            layer.frame = b
        }
        // Oversized so the rotating conic gradient always covers the square.
        let d = b.width * 1.5
        edgeSource.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        edgeSource.position = CGPoint(x: b.midX, y: b.midY)
        roiMask.frame = b
        roiMask.path = roiPath()
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [shimmer, edgeSource, edgeContainer] as [CALayer] {
            layer.removeAllAnimations()
        }
        edgeContainer.isHidden = true
        coreContainer.isHidden = true

        if style.premium {
            fillSource.type = .axial
            fillSource.startPoint = CGPoint(x: 0, y: 0)
            fillSource.endPoint = CGPoint(x: 1, y: 1)
            fillSource.colors = (colors.count > 1 ? colors : [accent, accent])
                .map { $0.withAlphaComponent(0.22).cgColor }
            fillSource.backgroundColor = nil

            edgeSource.type = .conic
            edgeSource.startPoint = CGPoint(x: 0.5, y: 0.5)
            edgeSource.endPoint = CGPoint(x: 0.5, y: 0)
            edgeSource.colors = (colors + [colors[0]]).map {
                $0.mixed(with: .white, amount: 0.12).cgColor
            }
            edgeSource.backgroundColor = nil
            coreContainer.opacity = 0.55
        } else {
            fillSource.colors = nil
            fillSource.backgroundColor = accent.withAlphaComponent(0.20).cgColor
            edgeSource.colors = nil
            edgeSource.backgroundColor = accent.mixed(with: .white, amount: 0.25).cgColor
            coreContainer.isHidden = true
        }

        let shimmerAlpha: CGFloat = style.premium ? 0.30 : 0.16
        shimmer.type = .axial
        shimmer.startPoint = CGPoint(x: 0, y: 0.35)
        shimmer.endPoint = CGPoint(x: 1, y: 0.65)
        shimmer.colors = [
            accent.withAlphaComponent(0).cgColor,
            accent.withAlphaComponent(shimmerAlpha).cgColor,
            accent.withAlphaComponent(0).cgColor,
        ]
        shimmer.locations = [-0.5, -0.25, 0]
        shimmer.isHidden = style.reduceMotion
        CATransaction.commit()

        guard !style.reduceMotion else { return }

        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.5, -0.25, 0.0]
        sweep.toValue = [1.0, 1.25, 1.5]
        sweep.duration = style.premium ? 2.2 : 3.2
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmer.add(sweep, forKey: "shimmer")

    }

    func update(fill: CGImage, edge: CGImage, core: CGImage) {
        set(fillMask, fill)
        set(shimmerMask, fill)
        set(edgeMask, edge)
        if style.premium { set(coreMask, core) }
    }

    /// Never blend previous support into a new camera frame.
    private func set(_ layer: CALayer, _ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.contents = image
        CATransaction.commit()
    }

    func setVisible(_ show: Bool) {
        visible = show
        let to: Float = show ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.removeAllAnimations()
        root.opacity = to
        root.speed = show ? 1 : 0
        if !show {
            for mask in [fillMask, shimmerMask, edgeMask, coreMask] {
                mask.removeAllAnimations()
                mask.contents = nil
            }
        }
        CATransaction.commit()
    }
}
