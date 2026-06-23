import ARKit
import AVFoundation
import CoreMedia
import Flutter
import UIKit

/// Embeds a live ARKit camera feed as a Flutter platform view.
///
/// Uses AVSampleBufferDisplayLayer (a plain Core Animation layer) instead of
/// ARSCNView so there are no Metal-compositor conflicts with Flutter's renderer.
/// Frames are polled from ARSessionManager.latestFrame via CADisplayLink at
/// ≈15 fps and pushed to the display layer as CMSampleBuffers.
final class ARCameraPreviewFactory: NSObject, FlutterPlatformViewFactory {

    static let viewType = "com.pixelstomacros/ar_camera"

    private weak var sessionManager: ARSessionManager?

    init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
        super.init()
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
    }
}

// MARK: – Platform view

final class ARCameraPreviewView: NSObject, FlutterPlatformView {

    private let hostView: CameraHostView
    private weak var sessionManager: ARSessionManager?
    private var displayLink: CADisplayLink?

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
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
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

    @objc private func tick() {
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
            // which is always satisfied by our iOS 17.0 deployment target.
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
        }
    }

    deinit {
        stopDisplayLink()
        NotificationCenter.default.removeObserver(self)
    }
}

