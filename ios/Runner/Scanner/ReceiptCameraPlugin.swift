import AVFoundation
import Flutter
import UIKit
import VisionKit

final class ReceiptCameraPlugin: NSObject, VNDocumentCameraViewControllerDelegate {
    private var pendingResult: FlutterResult?
    private var activeController: VNDocumentCameraViewController?
    private var finishing = false

    func capture(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard self.pendingResult == nil else {
                result(FlutterError(code: "RECEIPT_CAMERA_BUSY", message: nil, details: nil))
                return
            }
            guard VNDocumentCameraViewController.isSupported else {
                print("[RECEIPT_CAMERA] unsupported")
                result(FlutterError(code: "RECEIPT_CAMERA_UNSUPPORTED", message: nil, details: nil))
                return
            }
            self.pendingResult = result
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                self.presentCamera()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted { self.presentCamera() } else { self.permissionDenied() }
                    }
                }
            case .denied, .restricted:
                self.permissionDenied()
            @unknown default:
                self.permissionDenied()
            }
        }
    }

    private func permissionDenied() {
        print("[RECEIPT_CAMERA] permission denied")
        complete(FlutterError(code: "RECEIPT_CAMERA_PERMISSION_DENIED", message: nil, details: nil))
    }

    private func presentCamera() {
        guard let presenter = Self.topViewController(),
              presenter.viewIfLoaded?.window != nil,
              !presenter.isBeingDismissed, !presenter.isBeingPresented else {
            print("[RECEIPT_CAMERA] no available presenter")
            complete(FlutterError(code: "RECEIPT_CAMERA_PRESENTATION_FAILED", message: nil, details: nil))
            return
        }
        let controller = VNDocumentCameraViewController()
        controller.delegate = self
        controller.modalPresentationStyle = .fullScreen
        activeController = controller
        presenter.present(controller, animated: true) {
            print("[RECEIPT_CAMERA] presented")
        }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
    ) {
        guard beginFinishing(controller) else { return }
        print("[RECEIPT_CAMERA] saved pages=\(scan.pageCount)")
        controller.dismiss(animated: true) {
            DispatchQueue.global(qos: .userInitiated).async {
                let value: Any
                do {
                    value = try Self.exportPages(scan)
                } catch {
                    print("[RECEIPT_CAMERA] export failed: \(error)")
                    value = FlutterError(code: "RECEIPT_CAMERA_EXPORT_FAILED", message: nil,
                                         details: (error as NSError).code)
                }
                DispatchQueue.main.async { self.complete(value) }
            }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        guard beginFinishing(controller) else { return }
        print("[RECEIPT_CAMERA] cancelled")
        controller.dismiss(animated: true) { self.complete([String]()) }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFailWithError error: Error
    ) {
        guard beginFinishing(controller) else { return }
        print("[RECEIPT_CAMERA] scan failed: \(error)")
        controller.dismiss(animated: true) {
            self.complete(FlutterError(code: "RECEIPT_CAMERA_FAILED", message: nil,
                                       details: ["domain": (error as NSError).domain,
                                                 "code": (error as NSError).code]))
        }
    }

    private func beginFinishing(_ controller: VNDocumentCameraViewController) -> Bool {
        guard controller === activeController, pendingResult != nil, !finishing else { return false }
        finishing = true
        return true
    }

    private func complete(_ value: Any) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        activeController?.delegate = nil
        activeController = nil
        finishing = false
        result(value)
    }

    private static func exportPages(_ scan: VNDocumentCameraScan) throws -> [String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var paths: [String] = []
        for index in 0..<scan.pageCount {
            let path = try autoreleasepool {
                let image = scan.imageOfPage(at: index)
                guard let data = image.jpegData(compressionQuality: 0.98) else {
                    throw NSError(domain: "ReceiptCameraPlugin", code: 1)
                }
                let url = directory.appendingPathComponent("page-\(index + 1).jpg")
                try data.write(to: url, options: .atomic)
                print("[RECEIPT_CAMERA] exported page=\(index + 1) pixels=\(image.cgImage?.width ?? 0)x\(image.cgImage?.height ?? 0) bytes=\(data.count)")
                return url.path
            }
            paths.append(path)
        }
        return paths
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .sorted { $0.session.persistentIdentifier < $1.session.persistentIdentifier }
        let windows = scenes.flatMap(\.windows)
        // Runner still creates its window in AppDelegate rather than a scene delegate.
        let legacyWindow = UIApplication.shared.delegate?.window ?? nil
        guard let window = windows.first(where: \.isKeyWindow)
            ?? windows.first(where: { !$0.isHidden }) ?? legacyWindow else { return nil }
        var top = window.rootViewController
        while let controller = top {
            if let presented = controller.presentedViewController {
                top = presented
            } else if let navigation = controller as? UINavigationController,
                      let visible = navigation.visibleViewController {
                top = visible
            } else if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
                top = selected
            } else {
                return controller
            }
        }
        return nil
    }
}
