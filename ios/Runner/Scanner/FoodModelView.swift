import Flutter
import SceneKit
import UIKit

/// Flutter platform view that renders the most recent scan's food as a live,
/// rotatable 3-D object built from the `FoodMeshStore` height-field surfaces.
///
/// Each food becomes a height-field mesh (to real-world cm scale) laid out on a
/// shared table plane, so the model the user rotates is the *same* geometry the
/// volume calculation was derived from.
final class FoodModelViewFactory: NSObject, FlutterPlatformViewFactory {

    static let viewType = "com.pixelstomacros/food_model"

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        FoodModelView(frame: frame)
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol) {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

final class FoodModelView: NSObject, FlutterPlatformView {

    private let scnView: SCNView

    init(frame: CGRect) {
        scnView = SCNView(frame: frame)
        super.init()
        configureScene()
        buildFood()
    }

    func view() -> UIView { scnView }

    // MARK: – Scene setup

    private func configureScene() {
        let scene = SCNScene()
        scnView.scene = scene
        scnView.allowsCameraControl = true          // pinch / rotate / pan
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(white: 0.07, alpha: 1.0)

        // Soft key light for nicer shading.
        let light = SCNLight()
        light.type = .directional
        light.intensity = 600
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(lightNode)
    }

    // MARK: – Geometry

    private func buildFood() {
        guard let scene = scnView.scene else { return }
        let surfaces = FoodMeshStore.shared.surfaces
        guard !surfaces.isEmpty else {
            addPlaceholder(to: scene.rootNode)
            return
        }

        let container = SCNNode()

        // Palette so multiple foods are visually distinct.
        let palette: [UIColor] = [
            UIColor(red: 0.93, green: 0.55, blue: 0.30, alpha: 1),
            UIColor(red: 0.45, green: 0.78, blue: 0.45, alpha: 1),
            UIColor(red: 0.40, green: 0.62, blue: 0.92, alpha: 1),
            UIColor(red: 0.86, green: 0.40, blue: 0.55, alpha: 1),
            UIColor(red: 0.80, green: 0.74, blue: 0.36, alpha: 1),
        ]

        var offsetXcm: Float = 0
        for (i, surface) in surfaces.enumerated() {
            guard let geometry = heightFieldGeometry(surface.grid) else { continue }
            geometry.firstMaterial?.diffuse.contents = palette[i % palette.count]
            geometry.firstMaterial?.isDoubleSided = true
            let node = SCNNode(geometry: geometry)
            // Spread foods apart along X (in cm → metres for SceneKit units).
            node.position = SCNVector3(offsetXcm / 100.0, 0, 0)
            container.addChildNode(node)
            let widthCm = Float(surface.grid.cellWcm) * Float(surface.grid.cols)
            offsetXcm += widthCm + 2.0
        }

        // Centre the container and frame it for the camera.
        container.position = SCNVector3(-(offsetXcm / 2) / 100.0, 0, 0)
        scene.rootNode.addChildNode(container)
    }

    /// Build a triangulated height-field surface (SceneKit units = metres).
    private func heightFieldGeometry(_ grid: FoodSurfaceGrid) -> SCNGeometry? {
        let cols = grid.cols, rows = grid.rows
        guard cols >= 2, rows >= 2 else { return nil }

        let dx = Float(grid.cellWcm) / 100.0   // cm → m
        let dz = Float(grid.cellHcm) / 100.0

        var vertices = [SCNVector3]()
        vertices.reserveCapacity(cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let h = Float(grid.heightsCm[r * cols + c]) / 100.0
                let x = (Float(c) - Float(cols) / 2) * dx
                let z = (Float(r) - Float(rows) / 2) * dz
                vertices.append(SCNVector3(x, h, z))
            }
        }

        var indices = [Int32]()
        indices.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let tl = Int32(r * cols + c)
                let tr = Int32(r * cols + c + 1)
                let bl = Int32((r + 1) * cols + c)
                let br = Int32((r + 1) * cols + c + 1)
                indices.append(contentsOf: [tl, bl, tr,  tr, bl, br])
            }
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.lightingModel = .physicallyBased
        return geometry
    }

    /// Shown when there is no surface data (e.g. opened without a fresh scan).
    private func addPlaceholder(to root: SCNNode) {
        let box = SCNBox(width: 0.06, height: 0.02, length: 0.06, chamferRadius: 0.004)
        box.firstMaterial?.diffuse.contents = UIColor(white: 0.4, alpha: 1)
        let node = SCNNode(geometry: box)
        root.addChildNode(node)
    }
}
