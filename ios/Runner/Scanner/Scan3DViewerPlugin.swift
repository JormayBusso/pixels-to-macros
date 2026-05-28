import Flutter
import SceneKit
import UIKit

/// Flutter platform-view factory for the interactive Stage 3 viewer.
///
/// The factory wires in the Flutter messenger so each created view can
/// open its own `MethodChannel` for bidirectional commands (selection,
/// view mode, debug overlays) between Flutter and SceneKit.
final class Scan3DViewerFactory: NSObject, FlutterPlatformViewFactory {

    static let viewType = "com.pixelstomacros/scan_3d_viewer"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return Scan3DViewer(
            frame: frame,
            viewId: viewId,
            args: args,
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: – View mode

/// View modes drive how non-selected food objects are rendered.
private enum ViewMode: String {
    /// All food objects visible. Non-selected ones fade to low alpha when a
    /// selection exists; otherwise all render at full opacity.
    case combined
    /// Only the selected food object is rendered. When entering isolated
    /// mode without a selection, the object with the largest volume is
    /// auto-selected so the scene never appears empty.
    case isolated
}

// MARK: – Viewer

/// Interactive SceneKit viewer. Owns one `SCNScene`, one `MethodChannel`
/// (per-view, indexed by Flutter view id), and the gesture recognisers
/// required for tap-to-select + standard orbit / pan / pinch camera control.
///
/// ## Selection contract (single source of truth)
///
/// ALL selection state mutations — from native tap, Flutter list tap, focus
/// request, mode change, or auto-select — route through ONE method:
///
///     setSelectedClusterId(_ id: String?, animated:focusCamera:)
///
/// This method is the ONLY writer of `selectedClusterId`. After every
/// mutation it pushes `onSelectionChanged` to Flutter so the Dart layer
/// always REFLECTS (never owns) selection state. Flutter must never assume
/// a selection succeeded — it waits for the callback.
private final class Scan3DViewer: NSObject, FlutterPlatformView {

    // MARK: – UI

    private let sceneView: SCNView
    private let placeholderLabel: UILabel
    private let container: UIView

    // MARK: – Channel

    private let channel: FlutterMethodChannel

    // MARK: – Scene state

    /// Root pivot containing every food MDLMesh node imported from disk.
    private weak var foodRoot: SCNNode?

    /// Stable cluster id → SCNNode. Built once after loading the scene.
    private var foodNodes: [String: SCNNode] = [:]
    /// Stable cluster id → original opacity (typically 1.0).
    private var originalOpacities: [String: CGFloat] = [:]
    /// id → metadata supplied by Flutter (label, volume_cm3, voxel_count).
    private var objectMeta: [String: [String: Any]] = [:]

    // MARK: – Selection (single source of truth)

    /// The authoritative selection state. Only mutated inside
    /// `setSelectedClusterId(_:animated:focusCamera:)`.
    private var selectedClusterId: String?

    private var viewMode: ViewMode = .combined
    private var wireframeOn: Bool = false
    private var labelsOn: Bool = false

    /// Per-node floating volume labels (SCNText), keyed by cluster id.
    private var labelNodes: [String: SCNNode] = [:]

    // MARK: – Camera

    private weak var cameraNode: SCNNode?

    /// Immutable home camera transform — captured once when the scene is
    /// configured. `resetCamera` always restores this exactly.
    private var homeCameraTransform: SCNMatrix4 = SCNMatrix4Identity

    /// Immutable scene-centre anchor (plate centre). Focus operations use
    /// a TEMPORARY orbit target; `resetCamera` always restores this one.
    /// NEVER overwritten after initial assignment.
    private var homeCameraTarget: SCNVector3 = SCNVector3Zero

    /// Scene-scale unit (set when wrapping the imported geometry); used to
    /// frame the camera proportional to object size in focus mode.
    private var sceneScale: Float = 1.0

    // MARK: – Init

    init(
        frame: CGRect,
        viewId: Int64,
        args: Any?,
        messenger: FlutterBinaryMessenger
    ) {
        let scnView = SCNView(frame: frame)
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        if let camController = scnView.defaultCameraController as SCNCameraController? {
            camController.interactionMode = .orbitTurntable
            camController.inertiaEnabled = true
        }
        self.sceneView = scnView

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor(white: 0.7, alpha: 1.0)
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        self.placeholderLabel = label

        let host = UIView(frame: frame)
        host.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        host.addSubview(scnView)
        host.addSubview(label)
        NSLayoutConstraint.activate([
            scnView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scnView.topAnchor.constraint(equalTo: host.topAnchor),
            scnView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -24),
        ])
        self.container = host

        let channelName = "com.pixelstomacros/scan_3d_viewer/\(viewId)"
        self.channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )

        super.init()

        self.channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        scnView.addGestureRecognizer(tap)

        // Parse creation params.
        let dict = args as? [String: Any]
        let modelPath = dict?["modelPath"] as? String
        let objects = dict?["objects"] as? [[String: Any]] ?? []
        for o in objects {
            if let id = o["id"] as? String {
                objectMeta[id] = o
            }
        }
        loadModel(at: modelPath)
    }

    func view() -> UIView { return container }

    // MARK: – Channel handler

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "selectObject":
            let id = (call.arguments as? [String: Any])?["id"] as? String
            setSelectedClusterId(id, animated: true, focusCamera: false)
            result(nil)

        case "focusObject":
            let id = (call.arguments as? [String: Any])?["id"] as? String
            setSelectedClusterId(id, animated: true, focusCamera: true)
            result(nil)

        case "clearSelection":
            setSelectedClusterId(nil, animated: true, focusCamera: false)
            result(nil)

        case "setViewMode":
            if let raw = (call.arguments as? [String: Any])?["mode"] as? String,
               let mode = ViewMode(rawValue: raw) {
                setViewMode(mode, animated: true)
                result(nil)
            } else {
                result(FlutterError(code: "bad_args", message: "Unknown view mode", details: nil))
            }

        case "setDebugOverlay":
            let args = call.arguments as? [String: Any] ?? [:]
            if let w = args["wireframe"] as? Bool { wireframeOn = w }
            if let l = args["labels"] as? Bool { labelsOn = l }
            applyDebugOverlay()
            result(nil)

        case "resetCamera":
            resetCamera(animated: true)
            result(nil)

        case "listObjects":
            result(Array(foodNodes.keys).sorted())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: – Scene loading

    private func loadModel(at path: String?) {
        guard let path, !path.isEmpty else {
            showPlaceholder("No 3D model available for this scan.")
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showPlaceholder("3D model file missing:\n\(url.lastPathComponent)")
            return
        }

        do {
            let scene = try SCNScene(url: url, options: [
                .checkConsistency: false,
                .createNormalsIfAbsent: true,
            ])
            configure(scene: scene)
            sceneView.scene = scene
            placeholderLabel.isHidden = true

            // ── Verification gate ───────────────────────────────────────
            // Validate that the number of scene food nodes matches the
            // metadata object count Flutter passed at creation. A mismatch
            // means the USDZ file has drifted from the pipeline output and
            // downstream selection / volume display will be wrong.
            let sceneNodeCount = foodNodes.count
            let metaCount = objectMeta.count
            if sceneNodeCount != metaCount && metaCount > 0 {
                print("[Scan3DViewer] ⚠️ scene_metadata_desync — " +
                      "scene nodes: \(sceneNodeCount), metadata objects: \(metaCount)")
                channel.invokeMethod("onError", arguments: [
                    "error": "scene_metadata_desync",
                    "expected": metaCount,
                    "actual": sceneNodeCount,
                ])
            }

            channel.invokeMethod("onObjectsReady", arguments: [
                "ids": Array(foodNodes.keys).sorted()
            ])
        } catch {
            print("[Scan3DViewer] Failed to load \(url.lastPathComponent): \(error)")
            showPlaceholder("Couldn't load 3D model:\n\(error.localizedDescription)")
        }
    }

    /// CONTRACT: this method must NEVER flatten the imported node graph.
    private func configure(scene: SCNScene) {
        scene.background.contents = UIColor(white: 0.06, alpha: 1.0)

        scene.rootNode.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .physicallyBased
                material.isDoubleSided = true
            }
        }

        // Centre + scale.
        let (minVec, maxVec) = scene.rootNode.boundingBox
        let size = SCNVector3(
            maxVec.x - minVec.x,
            maxVec.y - minVec.y,
            maxVec.z - minVec.z
        )
        let maxDim = max(size.x, max(size.y, size.z))
        let pivot = SCNNode()
        pivot.name = "foodRoot"
        if maxDim > 0.0001 {
            let scale = 0.5 / maxDim
            sceneScale = Float(scale)
            let centre = SCNVector3(
                (minVec.x + maxVec.x) * 0.5,
                (minVec.y + maxVec.y) * 0.5,
                (minVec.z + maxVec.z) * 0.5
            )
            for child in scene.rootNode.childNodes {
                child.removeFromParentNode()
                pivot.addChildNode(child)
            }
            pivot.pivot = SCNMatrix4MakeTranslation(centre.x, centre.y, centre.z)
            pivot.scale = SCNVector3(scale, scale, scale)
            scene.rootNode.addChildNode(pivot)
        } else {
            for child in scene.rootNode.childNodes {
                child.removeFromParentNode()
                pivot.addChildNode(child)
            }
            scene.rootNode.addChildNode(pivot)
        }
        foodRoot = pivot
        indexFoodNodes(under: pivot)

        // Camera.
        let cam = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 50
        cam.camera = camera
        cam.position = SCNVector3(0, 0.35, 1.1)
        cam.eulerAngles = SCNVector3(-0.25, 0, 0)
        scene.rootNode.addChildNode(cam)
        sceneView.pointOfView = cam
        self.cameraNode = cam
        homeCameraTransform = cam.transform
        // Immutable anchor — always the plate centre (origin after pivot).
        homeCameraTarget = SCNVector3Zero

        // Lights.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 400
        fill.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        ambient.light?.color = UIColor(white: 1.0, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)
    }

    private func indexFoodNodes(under root: SCNNode) {
        foodNodes.removeAll()
        originalOpacities.removeAll()
        root.enumerateHierarchy { node, _ in
            guard let raw = node.name, !raw.isEmpty, node.geometry != nil else { return }
            let id = raw.components(separatedBy: "/").last ?? raw
            if Self.looksLikeFoodId(id) {
                foodNodes[id] = node
                originalOpacities[id] = node.opacity
            }
        }
    }

    private static func looksLikeFoodId(_ s: String) -> Bool {
        guard let underscore = s.lastIndex(of: "_") else { return false }
        let suffix = s[s.index(after: underscore)...]
        return !suffix.isEmpty && suffix.allSatisfy { $0.isNumber }
    }

    // MARK: – Selection (single source of truth)

    /// The ONE method that mutates selection state. Every path (tap, Flutter
    /// call, mode auto-select) MUST route here. After mutation it pushes
    /// `onSelectionChanged` to Flutter so Dart always reflects native truth.
    private func setSelectedClusterId(_ id: String?, animated: Bool, focusCamera: Bool) {
        // Guard: ignore unknown ids.
        if let id = id, foodNodes[id] == nil { return }

        selectedClusterId = id
        applyVisualState(animated: animated)

        // Push authoritative state to Flutter.
        channel.invokeMethod("onSelectionChanged", arguments: [
            "id": id as Any
        ])

        if focusCamera, let id = id, let node = foodNodes[id] {
            focusCameraOn(node: node, animated: animated)
        }
    }

    // MARK: – View mode

    /// Set the view mode. When entering `.isolated` with no active selection,
    /// the object with the largest `volume_cm3` is auto-selected so the user
    /// never sees an empty black scene.
    private func setViewMode(_ mode: ViewMode, animated: Bool) {
        viewMode = mode
        if mode == .isolated && selectedClusterId == nil {
            let largestId = objectMeta
                .max(by: { ($0.value["volume_cm3"] as? Double ?? 0) < ($1.value["volume_cm3"] as? Double ?? 0) })?
                .key
            if let id = largestId {
                // Route through the single writer — Flutter will be notified.
                setSelectedClusterId(id, animated: animated, focusCamera: true)
                return  // applyVisualState already called inside
            }
        }
        applyVisualState(animated: animated)
    }

    // MARK: – Visual state

    /// Recompute every food node's opacity / hidden state. Centralised so
    /// the rules can never drift.
    private func applyVisualState(animated: Bool) {
        let duration: TimeInterval = animated ? 0.25 : 0.0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        for (id, node) in foodNodes {
            let baseOpacity = originalOpacities[id] ?? 1.0
            switch viewMode {
            case .combined:
                node.isHidden = false
                if let sel = selectedClusterId {
                    node.opacity = (id == sel) ? baseOpacity : 0.15
                } else {
                    node.opacity = baseOpacity
                }
            case .isolated:
                if let sel = selectedClusterId {
                    node.isHidden = (id != sel)
                    node.opacity = baseOpacity
                } else {
                    node.isHidden = false
                    node.opacity = baseOpacity
                }
            }
        }
        SCNTransaction.commit()
        applyDebugOverlay()
    }

    // MARK: – Debug overlay

    /// Labels are only rendered when BOTH conditions hold:
    ///   1. `labelsOn == true` (user toggled debug overlay), AND
    ///   2. EITHER `viewMode == .isolated` OR `wireframeOn` is active.
    /// In combined mode with wireframe off, labels are stripped to avoid
    /// silent FPS drops on mid-range devices (SCNText is expensive).
    private var shouldRenderLabels: Bool {
        guard labelsOn else { return false }
        return viewMode == .isolated || wireframeOn
    }

    private func applyDebugOverlay() {
        // Wireframe.
        for (_, node) in foodNodes {
            guard let geom = node.geometry else { continue }
            for material in geom.materials {
                material.fillMode = wireframeOn ? .lines : .fill
            }
        }
        // Floating labels — gated by `shouldRenderLabels`.
        if shouldRenderLabels {
            for (id, node) in foodNodes {
                if labelNodes[id] == nil {
                    let lbl = makeFloatingLabel(forId: id)
                    node.addChildNode(lbl)
                    labelNodes[id] = lbl
                }
                labelNodes[id]?.isHidden = node.isHidden
            }
        } else {
            // Strip labels from scene graph entirely to reclaim GPU budget.
            for (_, lbl) in labelNodes {
                lbl.removeFromParentNode()
            }
            labelNodes.removeAll()
        }
    }

    private func makeFloatingLabel(forId id: String) -> SCNNode {
        let meta = objectMeta[id]
        let label = (meta?["label"] as? String) ?? id
        let volume = (meta?["volume_cm3"] as? Double) ?? 0
        let voxels = (meta?["voxel_count"] as? Int) ?? 0
        let text = "\(label)\n\(String(format: "%.1f", volume)) cm³ · \(voxels) vx"

        let scnText = SCNText(string: text, extrusionDepth: 0)
        scnText.font = UIFont.systemFont(ofSize: 4, weight: .semibold)
        scnText.flatness = 0.2
        scnText.firstMaterial?.diffuse.contents = UIColor.white
        scnText.firstMaterial?.isDoubleSided = true
        scnText.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: scnText)
        let (minV, maxV) = scnText.boundingBox
        let textWidth = maxV.x - minV.x
        node.pivot = SCNMatrix4MakeTranslation(textWidth * 0.5, 0, 0)
        node.scale = SCNVector3(0.01, 0.01, 0.01)

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        node.constraints = [billboard]
        return node
    }

    // MARK: – Camera

    /// Focus camera on a specific node. Sets a TEMPORARY orbit target so
    /// subsequent gestures rotate around the focused object. This NEVER
    /// overwrites `homeCameraTarget` — `resetCamera` always restores the
    /// immutable plate centre.
    private func focusCameraOn(node: SCNNode, animated: Bool) {
        guard let cameraNode = cameraNode else { return }
        let (minV, maxV) = node.boundingBox
        let centreLocal = SCNVector3(
            (minV.x + maxV.x) * 0.5,
            (minV.y + maxV.y) * 0.5,
            (minV.z + maxV.z) * 0.5
        )
        let worldCentre = node.convertPosition(centreLocal, to: nil)
        let extent = max(
            Float(maxV.x - minV.x),
            max(Float(maxV.y - minV.y), Float(maxV.z - minV.z))
        )
        let nodeWorldScale = max(sceneScale, 0.0001)
        let distance = max(0.25, Double(extent * nodeWorldScale * 2.2))

        let target = SCNVector3(
            worldCentre.x,
            worldCentre.y + 0.05,
            worldCentre.z + Float(distance)
        )
        let duration: TimeInterval = animated ? 0.4 : 0.0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        cameraNode.position = target
        cameraNode.look(at: worldCentre)
        SCNTransaction.commit()

        // Temporary orbit target — NOT persisted in `homeCameraTarget`.
        if let controller = sceneView.defaultCameraController as SCNCameraController? {
            controller.target = worldCentre
        }
    }

    /// Always restores the immutable `homeCameraTransform` + `homeCameraTarget`.
    private func resetCamera(animated: Bool) {
        guard let cameraNode = cameraNode else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.4 : 0.0
        cameraNode.transform = homeCameraTransform
        SCNTransaction.commit()
        if let controller = sceneView.defaultCameraController as SCNCameraController? {
            controller.target = homeCameraTarget
        }
    }

    // MARK: – Gestures

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let pt = gr.location(in: sceneView)
        let hits = sceneView.hitTest(pt, options: [
            .boundingBoxOnly: false,
            .ignoreHiddenNodes: true,
            .searchMode: SCNHitTestSearchMode.closest.rawValue as NSNumber,
        ])
        guard let hit = hits.first else {
            setSelectedClusterId(nil, animated: true, focusCamera: false)
            return
        }
        var node: SCNNode? = hit.node
        var resolved: String?
        while let n = node {
            if let name = n.name {
                let id = name.components(separatedBy: "/").last ?? name
                if foodNodes[id] != nil {
                    resolved = id
                    break
                }
            }
            node = n.parent
        }
        guard let id = resolved else { return }
        if id == selectedClusterId {
            setSelectedClusterId(nil, animated: true, focusCamera: false)
        } else {
            setSelectedClusterId(id, animated: true, focusCamera: false)
        }
    }

    // MARK: – Placeholder

    private func showPlaceholder(_ message: String) {
        placeholderLabel.text = message
        placeholderLabel.isHidden = false
        sceneView.scene = nil
    }
}
