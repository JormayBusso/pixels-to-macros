import Flutter
import RealityKit
import SwiftUI
import UIKit

/// Step 3 — the premium, interactive 3-D food viewer.
///
/// Renders the textured `.usdz` from the scan pipeline with studio lighting and
/// touch rotate / pinch-zoom. It is a SwiftUI view hosted inside a Flutter
/// `PlatformView`, kept SEPARATE from the existing feature-rich SceneKit
/// `Scan3DViewer` (selection / isolation / labels) so neither regresses.
///
/// iOS version note
/// ----------------
/// SwiftUI `RealityView` is **iOS 18+**. The app targets iOS 17, so iOS 18+
/// uses `RealityView` and iOS 17 falls back to a RealityKit `ARView` in
/// `.nonAR` mode. Both share `Food3DSceneBuilder` for loading + lighting.

// MARK: - Flutter PlatformView

final class Food3DRealityFactory: NSObject, FlutterPlatformViewFactory {

    static let viewType = "com.pixelstomacros/food_3d_realityview"

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        Food3DRealityPlatformView(frame: frame, args: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Hosts the SwiftUI scene in a `UIHostingController` and exposes it to Flutter.
final class Food3DRealityPlatformView: NSObject, FlutterPlatformView {

    private let hostingController: UIViewController

    init(frame: CGRect, args: Any?) {
        let modelPath = (args as? [String: Any])?["modelPath"] as? String
        let controller = UIHostingController(rootView: Food3DSceneView(modelPath: modelPath))
        controller.view.frame = frame
        controller.view.backgroundColor = .clear
        self.hostingController = controller
        super.init()
    }

    func view() -> UIView { hostingController.view }
}

// MARK: - SwiftUI scene (version router)

struct Food3DSceneView: View {
    let modelPath: String?

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                RealityFoodView(modelPath: modelPath)
            } else {
                ARFoodView(modelPath: modelPath)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - iOS 18+ RealityView

@available(iOS 18.0, *)
private struct RealityFoodView: View {
    let modelPath: String?

    @State private var pivot = Entity()
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0.2
    @State private var baseYaw: Float = 0
    @State private var basePitch: Float = 0.2
    @State private var zoom: Float = 1
    @State private var baseZoom: Float = 1

    var body: some View {
        RealityView { content in
            content.add(pivot)
            for light in Food3DSceneBuilder.studioLights() {
                content.add(light)
            }
            if let modelPath, let fitted = await Food3DSceneBuilder.loadFitted(path: modelPath) {
                pivot.addChild(fitted)
            }
        } update: { _ in
            pivot.transform.rotation = Food3DSceneBuilder.rotation(yaw: yaw, pitch: pitch)
            pivot.transform.scale = SIMD3<Float>(repeating: zoom)
        }
        .background(Color(white: 0.06))
        .gesture(
            DragGesture()
                .onChanged { value in
                    yaw = baseYaw + Float(value.translation.width) * 0.01
                    pitch = max(-1.4, min(1.4, basePitch + Float(value.translation.height) * 0.01))
                }
                .onEnded { _ in
                    baseYaw = yaw
                    basePitch = pitch
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = max(0.3, min(4, baseZoom * Float(value.magnification)))
                }
                .onEnded { _ in baseZoom = zoom }
        )
    }
}

// MARK: - iOS 17 ARView fallback

private struct ARFoodView: UIViewRepresentable {
    let modelPath: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.environment.background = .color(UIColor(white: 0.06, alpha: 1))
        arView.backgroundColor = UIColor(white: 0.06, alpha: 1)

        let worldAnchor = AnchorEntity(world: .zero)
        let pivot = Entity()
        worldAnchor.addChild(pivot)
        for light in Food3DSceneBuilder.studioLights() {
            worldAnchor.addChild(light)
        }
        arView.scene.addAnchor(worldAnchor)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 50
        camera.position = [0, 0.12, 0.6]
        camera.look(at: .zero, from: camera.position, upVector: [0, 1, 0], relativeTo: nil)
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)

        context.coordinator.pivot = pivot

        let pan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan(_:))
        )
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePinch(_:))
        )
        arView.addGestureRecognizer(pan)
        arView.addGestureRecognizer(pinch)

        if let modelPath, let fitted = Food3DSceneBuilder.loadFittedSync(path: modelPath) {
            pivot.addChild(fitted)
        }
        context.coordinator.apply()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator: NSObject {
        weak var pivot: Entity?
        private var yaw: Float = 0
        private var pitch: Float = 0.2
        private var baseYaw: Float = 0
        private var basePitch: Float = 0.2
        private var zoom: Float = 1
        private var baseZoom: Float = 1

        func apply() {
            guard let pivot else { return }
            pivot.transform.rotation = Food3DSceneBuilder.rotation(yaw: yaw, pitch: pitch)
            pivot.transform.scale = SIMD3<Float>(repeating: zoom)
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let t = recognizer.translation(in: recognizer.view)
            yaw = baseYaw + Float(t.x) * 0.01
            pitch = max(-1.4, min(1.4, basePitch + Float(t.y) * 0.01))
            apply()
            if recognizer.state == .ended || recognizer.state == .cancelled {
                baseYaw = yaw
                basePitch = pitch
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            zoom = max(0.3, min(4, baseZoom * Float(recognizer.scale)))
            apply()
            if recognizer.state == .ended || recognizer.state == .cancelled {
                baseZoom = zoom
            }
        }
    }
}

// MARK: - Shared loading + lighting

enum Food3DSceneBuilder {

    /// Normalised display size of the model's largest dimension (metres).
    private static let targetSize: Float = 0.3

    static func rotation(yaw: Float, pitch: Float) -> simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    @available(iOS 18.0, *)
    static func loadFitted(path: String) async -> Entity? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let entity = try? await Entity(contentsOf: url) else { return nil }
        return fit(entity)
    }

    static func loadFittedSync(path: String) -> Entity? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let entity = try? Entity.load(contentsOf: url) else { return nil }
        return fit(entity)
    }

    /// Centre the model on the origin and scale its largest extent to
    /// `targetSize`, returning a container the caller can freely rotate/scale.
    private static func fit(_ entity: Entity) -> Entity {
        let container = Entity()
        container.addChild(entity)
        let bounds = entity.visualBounds(relativeTo: container)
        let extents = bounds.extents
        let maxExtent = max(extents.x, max(extents.y, extents.z))
        entity.position -= bounds.center
        if maxExtent > 0.0001 {
            container.scale = SIMD3<Float>(repeating: targetSize / maxExtent)
        }
        return container
    }

    /// Three-point studio lighting so the textured food looks premium without
    /// needing a bundled HDR environment. (Swap for `ImageBasedLightComponent`
    /// if a `.exr` environment is added later.)
    static func studioLights() -> [Entity] {
        let key = DirectionalLight()
        key.light.intensity = 6000
        key.light.color = .white
        key.look(at: .zero, from: [0.5, 0.8, 1.0], upVector: [0, 1, 0], relativeTo: nil)

        let fill = DirectionalLight()
        fill.light.intensity = 2500
        fill.light.color = .white
        fill.look(at: .zero, from: [-0.8, 0.3, 0.6], upVector: [0, 1, 0], relativeTo: nil)

        let rim = DirectionalLight()
        rim.light.intensity = 3500
        rim.light.color = .white
        rim.look(at: .zero, from: [0, 0.6, -1.0], upVector: [0, 1, 0], relativeTo: nil)

        return [key, fill, rim]
    }
}
