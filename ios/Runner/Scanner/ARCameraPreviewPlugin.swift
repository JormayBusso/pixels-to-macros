import ARKit
import AVFoundation
import CoreImage
import CoreMedia
import Flutter
import QuartzCore
import UIKit
import Vision

/// Embeds a live ARKit camera feed as a Flutter platform view.
///
/// Uses AVSampleBufferDisplayLayer (a plain Core Animation layer) instead of
/// ARSCNView so there are no Metal-compositor conflicts with Flutter's renderer.
/// Frames are polled from ARSessionManager.latestFrame via CADisplayLink at
/// ≈30 fps and pushed to the display layer as CMSampleBuffers.
///
/// The view also hosts the live "AI glow": a throttled on-device food detector
/// (see `LiveFoodDetector`) whose soft mask is drawn as Core Animation layers
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
    }

    // MARK: – Frame rendering

    fileprivate func renderTick() {
        autoreleasepool {
            // Hold a strong reference for the duration of this tick so
            // the manager can't be deallocated mid-access.
            guard let manager = sessionManager,
                  let pixelBuffer = manager.latestFrame?.capturedImage
            else { return }

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

            feedLiveDetector(pixelBuffer)
        }
    }

    // MARK: – Live food glow

    /// Offers the current camera frame to the detector. Never blocks: the
    /// detector drops the frame when it is busy or throttled.
    private func feedLiveDetector(_ pixelBuffer: CVPixelBuffer) {
        let controller = LiveFoodGlowController.shared
        guard controller.enabled,
              hostView.window != nil, !hostView.isHidden,
              let glow = hostView.glow, let detector
        else { return }

        let now = CACurrentMediaTime()
        guard detector.canAccept(at: now),
              let roi = glow.roiInMaskGrid(LiveFoodDetector.grid)
        else { return }

        detector.submit(pixelBuffer, roi: roi, at: now) { [weak self] result in
            guard let self, let glow = self.hostView.glow,
                  LiveFoodGlowController.shared.enabled
            else { return }
            glow.update(fill: result.fill, edge: result.edge, core: result.core)
            glow.setVisible(result.present)
            LiveFoodGlowController.shared.report(
                detected: result.present,
                available: result.available,
                backend: result.backend)
        }
    }

    /// Applies the current controller state (enabled / style / ROI).
    fileprivate func applyLiveGlowState() {
        let controller = LiveFoodGlowController.shared
        guard controller.enabled else {
            detector?.reset()
            hostView.glow?.setVisible(false)
            return
        }
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

    private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
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
            result(nil)
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
}

struct LiveGlowResult {
    let fill: CGImage
    let edge: CGImage
    let core: CGImage
    let present: Bool
    let available: Bool
    let backend: String
}

/// Throttled live food detection on the AR preview.
///
/// Follows Apple's real-time Vision/Core ML guidance: one frame in flight on a
/// background serial queue, frames dropped while busy, ~5 Hz cap, and the
/// camera buffer released right after a small square copy is made (so ARKit's
/// frame pool is never starved). Backends, in order: the bundled YOLO-seg
/// food model, the SegFormer food segmenter, then Vision's class-agnostic
/// foreground instance mask (live preview only). Masks are fused on a
/// 160×160 grid with temporal smoothing and turned into soft alpha images for
/// the glow layers.
final class LiveFoodDetector {

    static let grid = 160
    static let inputSide = 320
    static let minInterval: CFTimeInterval = 0.2

    enum Backend: String {
        case undecided, yolo, segformer, vision, none
    }

    // Main-thread state.
    private var busy = false
    private var lastSubmit: CFTimeInterval = 0
    private var generation = 0

    // Queue state.
    private let queue = DispatchQueue(
        label: "com.pixelstomacros.liveglow", qos: .userInitiated)
    private var backend: Backend = .undecided
    private var yolo: YOLOSegmentationService?
    private var segformer: SegmentationService?
    private var cocoWhitelist = false
    private var accumulator: [Float]?
    private var positives = 0
    private var negatives = 0
    private var visible = false
    private var runs = 0
    private var consecutiveFailures = 0
    private var timedRuns = 0
    private var timedTotalMs = 0.0
    private var pool: CVPixelBufferPool?
    private lazy var ciContext = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull(),
        .cacheIntermediates: false,
    ])

    private static let cocoFood: Set<String> = [
        "banana", "apple", "sandwich", "orange", "broccoli", "carrot",
        "hot dog", "pizza", "donut", "cake",
    ]
    private static let denied: Set<String> = [
        "background", "plate", "bowl", "table", "dining table", "cup",
        "fork", "knife", "spoon", "cutlery", "tableware", "wine glass",
        "bottle", "other",
    ]

    func canAccept(at now: CFTimeInterval) -> Bool {
        !busy && now - lastSubmit >= Self.minInterval
    }

    /// Invalidates in-flight work and clears the temporal state.
    func reset() {
        generation += 1
        busy = false
        queue.async { [self] in
            accumulator = nil
            positives = 0
            negatives = 0
            visible = false
        }
    }

    func submit(
        _ pixelBuffer: CVPixelBuffer,
        roi: LiveGlowGridROI,
        at now: CFTimeInterval,
        completion: @escaping (LiveGlowResult) -> Void
    ) {
        busy = true
        lastSubmit = now
        let gen = generation
        queue.async { [self] in
            let result = autoreleasepool { process(pixelBuffer, roi: roi) }
            DispatchQueue.main.async { [self] in
                guard gen == generation else { return }
                busy = false
                if let result { completion(result) }
            }
        }
    }

    // MARK: Pipeline (queue)

    private func process(_ source: CVPixelBuffer, roi: LiveGlowGridROI) -> LiveGlowResult? {
        let t0 = CACurrentMediaTime()
        guard let input = makeSquareInput(source) else { return nil }
        let t1 = CACurrentMediaTime()

        if backend == .undecided { decideBackend() }

        var masks = 0
        var union = [Float](repeating: 0, count: Self.grid * Self.grid)
        var ran = false
        if backend != .none {
            do {
                masks = try runBackend(input, into: &union)
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

        if ran { trackSpeed(inferMs) }

        let post = postProcess(union, roi: roi)
        let t3 = CACurrentMediaTime()
        runs += 1
        if ran && (runs <= 5 || runs % 10 == 0) {
            print(String(
                format: "[LiveGlow] infer=%.1fms masks=%d backend=%@ prep=%.1fms post=%.1fms present=%@",
                inferMs, masks, backend.rawValue, (t1 - t0) * 1000,
                (t3 - t2) * 1000, post.present ? "1" : "0"))
        }
        guard let images = post.images else { return nil }
        return LiveGlowResult(
            fill: images.fill,
            edge: images.edge,
            core: images.core,
            present: visible,
            available: backend != .none,
            backend: backend.rawValue)
    }

    private func decideBackend() {
        let y = YOLOSegmentationService()
        if y.isAvailable {
            yolo = y
            cocoWhitelist = y.loadedResource != "FoodSegYolo"
            backend = .yolo
        } else {
            let s = SegmentationService()
            if (try? s.loadModel()) != nil {
                segformer = s
                backend = .segformer
            } else {
                backend = .vision
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
                next = .vision
            }
        case .segformer:
            segformer = nil
            next = .vision
        default:
            next = .none
        }
        print("[LiveGlow] backend \(backend.rawValue) → \(next.rawValue)")
        backend = next
        consecutiveFailures = 0
        timedRuns = 0
        timedTotalMs = 0
    }

    /// After two warm-up runs, switch to the lighter Vision detector when the
    /// model backend averages more than 400 ms (it would lag the preview).
    private func trackSpeed(_ ms: Double) {
        guard backend == .yolo || backend == .segformer else { return }
        timedRuns += 1
        guard timedRuns > 2 else { return }
        timedTotalMs += ms
        if timedRuns == 7 {
            let avg = timedTotalMs / 5
            if avg > 400 {
                print(String(format: "[LiveGlow] %@ too slow (avg %.0fms) → vision",
                             backend.rawValue, avg))
                yolo = nil
                segformer = nil
                backend = .vision
            }
        }
    }

    /// Runs the active backend and ORs the kept food masks into `union`.
    private func runBackend(_ input: CVPixelBuffer, into union: inout [Float]) throws -> Int {
        switch backend {
        case .yolo:
            guard let yolo else { return 0 }
            let objects = try yolo.segment(pixelBuffer: input)
            return accumulate(objects, into: &union)
        case .segformer:
            guard let segformer else { return 0 }
            let objects = try segformer.segment(pixelBuffer: input)
            return accumulate(objects, into: &union)
        case .vision:
            return try runVision(input, into: &union)
        case .undecided, .none:
            return 0
        }
    }

    private func accumulate(
        _ objects: [SegmentationService.SegmentedObject],
        into union: inout [Float]
    ) -> Int {
        let g = Self.grid
        var kept = 0
        for object in objects {
            let label = object.label.lowercased()
            if Self.denied.contains(label) { continue }
            if cocoWhitelist && backend == .yolo && !Self.cocoFood.contains(label) { continue }
            if object.confidence < 0.30 { continue }
            let rows = object.mask.count
            guard rows > 0, let cols = object.mask.first?.count, cols > 0 else { continue }
            if Float(object.pixelCount) < 0.002 * Float(rows * cols) { continue }
            kept += 1
            for gy in 0..<g {
                let sy = min(rows - 1, Int((Float(gy) + 0.5) * Float(rows) / Float(g)))
                let row = object.mask[sy]
                let base = gy * g
                for gx in 0..<g {
                    let sx = min(cols - 1, Int((Float(gx) + 0.5) * Float(cols) / Float(g)))
                    if row[sx] != 0 { union[base + gx] = 1 }
                }
            }
        }
        return kept
    }

    private func runVision(_ input: CVPixelBuffer, into union: inout [Float]) throws -> Int {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: input, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { return 0 }
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let g = Self.grid
        for gy in 0..<g {
            let sy = min(h - 1, Int((Float(gy) + 0.5) * Float(h) / Float(g)))
            for gx in 0..<g {
                let sx = min(w - 1, Int((Float(gx) + 0.5) * Float(w) / Float(g)))
                if bytes[sy * stride + sx] != 0 { union[gy * g + gx] = 1 }
            }
        }
        return observation.allInstances.count
    }

    /// Centre-square crop of the camera frame, scaled to `inputSide`² BGRA.
    /// The ARKit buffer is released as soon as this returns.
    private func makeSquareInput(_ source: CVPixelBuffer) -> CVPixelBuffer? {
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
        let crop = min(extent.width, extent.height)
        let square = CGRect(
            x: extent.midX - crop / 2, y: extent.midY - crop / 2,
            width: crop, height: crop)
        let scale = CGFloat(side) / crop
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

    private struct Images {
        let fill: CGImage
        let edge: CGImage
        let core: CGImage
    }

    private func postProcess(
        _ union: [Float], roi: LiveGlowGridROI
    ) -> (images: Images?, present: Bool) {
        let g = Self.grid
        let n = g * g
        var acc = accumulator ?? union
        if accumulator != nil {
            for i in 0..<n { acc[i] = 0.45 * acc[i] + 0.55 * union[i] }
        }
        accumulator = acc

        let soft = Self.boxBlur(Self.boxBlur(acc, g, 2), g, 1)

        // Presence: smoothed food area inside the capture guide.
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
                    if soft[y * g + x] > 0.5 { inside += 1 }
                }
            }
        }
        let present = roiArea > 0 && inside >= max(40, Int(Double(roiArea) * 0.004))
        if present {
            positives += 1
            negatives = 0
            if positives >= 1 { visible = true }
        } else {
            negatives += 1
            positives = 0
            if negatives >= 3 { visible = false }
        }

        var fill = [Float](repeating: 0, count: n)
        var rim = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let s = soft[i]
            let t = max(0, min(1, (s - 0.35) / 0.30))
            fill[i] = t * t * (3 - 2 * t)
            rim[i] = max(0, min(1, 1 - abs(s - 0.5) * 3.2))
        }
        let halo = Self.boxBlur(Self.boxBlur(rim, g, 4), g, 4)
        var edge = [Float](repeating: 0, count: n)
        var core = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let h = min(1, halo[i] * 2.2)
            edge[i] = max(rim[i] * 0.9, h * 0.6)
            core[i] = rim[i] * rim[i] * rim[i]
        }

        guard let fillImage = Self.alphaImage(fill, g),
              let edgeImage = Self.alphaImage(edge, g),
              let coreImage = Self.alphaImage(core, g)
        else { return (nil, present) }
        return (Images(fill: fillImage, edge: edgeImage, core: coreImage), present)
    }

    /// Separable box blur with clamped edges (running sums, O(n)).
    private static func boxBlur(_ src: [Float], _ g: Int, _ radius: Int) -> [Float] {
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
    private static func alphaImage(_ values: [Float], _ g: Int) -> CGImage? {
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
            provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)
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
            mask.magnificationFilter = .linear
            mask.minificationFilter = .linear
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
            coreContainer.isHidden = false
            coreContainer.opacity = 0.55
        } else {
            fillSource.colors = nil
            fillSource.backgroundColor = accent.withAlphaComponent(0.13).cgColor
            edgeSource.colors = nil
            edgeSource.backgroundColor = accent.mixed(with: .white, amount: 0.25).cgColor
            coreContainer.isHidden = true
        }

        let shimmerAlpha: CGFloat = style.premium ? 0.30 : 0.16
        shimmer.type = .axial
        shimmer.startPoint = CGPoint(x: 0, y: 0.35)
        shimmer.endPoint = CGPoint(x: 1, y: 0.65)
        shimmer.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(shimmerAlpha).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
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

        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = style.premium ? 0.8 : 0.65
        breathe.toValue = 1.0
        breathe.duration = 1.3
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.isRemovedOnCompletion = false
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        edgeContainer.add(breathe, forKey: "breathe")

        if style.premium {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 6
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            edgeSource.add(spin, forKey: "spin")
        }
    }

    func update(fill: CGImage, edge: CGImage, core: CGImage) {
        set(fillMask, fill)
        set(shimmerMask, fill)
        set(edgeMask, edge)
        if style.premium { set(coreMask, core) }
    }

    /// Cross-fades a mask to the new image so contours glide, not jump.
    private func set(_ layer: CALayer, _ image: CGImage) {
        let previous = layer.presentation()?.contents ?? layer.contents
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
        guard previous != nil else { return }
        let anim = CABasicAnimation(keyPath: "contents")
        anim.fromValue = previous
        anim.toValue = image
        anim.duration = 0.2
        layer.add(anim, forKey: "contents")
    }

    func setVisible(_ show: Bool) {
        guard show != visible else { return }
        visible = show
        let from = root.presentation()?.opacity ?? root.opacity
        let to: Float = show ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = to
        CATransaction.commit()
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = show ? 0.35 : 0.45
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        root.add(anim, forKey: "fade")
    }
}
