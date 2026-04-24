import ARKit
import Flutter
import SceneKit
import UIKit

/// Embeds a live ARKit camera feed as a Flutter platform view.
///
/// Register once in AppDelegate, then use
/// `UiKitView(viewType: ARCameraPreviewFactory.viewType)` in Dart.
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

// MARK: -

final class ARCameraPreviewView: NSObject, FlutterPlatformView {

    private let sceneView: ARSCNView
    private weak var sessionManager: ARSessionManager?

    init(frame: CGRect, sessionManager: ARSessionManager?) {
        self.sessionManager = sessionManager

        sceneView = ARSCNView(frame: frame)
        sceneView.autoenablesDefaultLighting = false
        sceneView.automaticallyUpdatesLighting = false
        sceneView.scene = SCNScene()   // empty scene — camera fill only
        sceneView.backgroundColor = .black
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init()

        // Attach immediately if the session is already running
        if let session = sessionManager?.session {
            sceneView.session = session
        }

        // Also listen for late-start notifications (session starts after view creation)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSessionDidStart(_:)),
            name: .arSessionDidStart,
            object: nil
        )
    }

    func view() -> UIView { sceneView }

    @objc private func onSessionDidStart(_ note: Notification) {
        guard let session = note.object as? ARSession else { return }
        DispatchQueue.main.async { [weak self] in
            self?.sceneView.session = session
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
