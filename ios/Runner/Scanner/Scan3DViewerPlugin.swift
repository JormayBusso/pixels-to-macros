import Flutter
import SceneKit
import UIKit
import simd

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
            print("[SCAN] SceneKit: loadModel called with nil/empty path")
            sendInvalidModel(reason: "missing_model_path", details: nil)
            showPlaceholder("No 3D model available for this scan.")
            return
        }
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let size: Int = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("[SCAN] SceneKit: loadModel path=\(url.lastPathComponent) exists=\(exists) size=\(size) bytes")
        guard exists else {
            sendInvalidModel(reason: "model_file_missing", details: url.path)
            showPlaceholder("3D model file missing:\n\(url.lastPathComponent)")
            return
        }

        // Prefer the per-vertex-colour mesh sidecar written next to the scene.
        // USD/USDZ export drops the vertex colour source, so the exported file
        // renders as a single dull averaged colour. Rebuilding the geometry in
        // process from the sidecar keeps a real SCNGeometrySource(.color), and
        // `configure(scene:)` then forces diffuse to white so the true sampled
        // food colours render at full brightness — the top crown, the silhouette
        // sides and the reasoned underside all in their captured colour.
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("p2mesh")
        let sidecarExists = FileManager.default.fileExists(atPath: sidecarURL.path)
        let sidecarSize: Int = (try? FileManager.default.attributesOfItem(atPath: sidecarURL.path)[.size] as? Int) ?? 0
        print("[SCAN] SceneKit: sidecar=\(sidecarURL.lastPathComponent) exists=\(sidecarExists) size=\(sidecarSize) bytes")
        if let objects = loadMeshSidecar(at: sidecarURL), !objects.isEmpty {
            let base = url.deletingPathExtension().lastPathComponent
            let textureURL = url.deletingLastPathComponent()
                .appendingPathComponent(base + "_texture.png")
            let scene = buildScene(fromSidecar: objects, textureURL: textureURL)
            configure(scene: scene, modelURL: url)
            sceneView.scene = scene
            placeholderLabel.isHidden = true
            print("[SCAN] SceneKit: LOADED from mesh sidecar " +
                  "\(sidecarURL.lastPathComponent), foodNodes=\(foodNodes.count)")
            announceLoaded()
            return
        }

        do {
            let scene = try SCNScene(url: url, options: [
                .checkConsistency: false,
                .createNormalsIfAbsent: true,
            ])
            configure(scene: scene, modelURL: url)
            sceneView.scene = scene
            placeholderLabel.isHidden = true
            print("[SCAN] SceneKit: LOADED scene successfully, foodNodes=\(foodNodes.count)")
            announceLoaded()
        } catch {
            print("[Scan3DViewer] Failed to load \(url.lastPathComponent): \(error)")
            sendInvalidModel(reason: "scenekit_load_failed", details: error.localizedDescription)
            showPlaceholder("Couldn't load 3D model:\n\(error.localizedDescription)")
        }
    }

    private func sendInvalidModel(reason: String, details: Any?) {
        channel.invokeMethod("onError", arguments: [
            "error": "invalid_model",
            "reason": reason,
            "details": details ?? NSNull(),
        ])
    }

    /// Push the loaded object list to Flutter and flag any drift between the
    /// number of food nodes in the scene and the metadata object count Flutter
    /// supplied at creation. A mismatch means selection / volume display would
    /// be wrong, so Dart is warned via `onError`.
    private func announceLoaded() {
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
    }

    // MARK: – Per-vertex colour sidecar

    /// One food object decoded from the `.p2mesh` sidecar. Positions share the
    /// USD coordinate space; colours are RGBA bytes (one per vertex).
    private struct SidecarObject {
        let id: String
        let averageColor: SCNVector3
        let positions: [SCNVector3]
        let colors: [UInt8]
        let uvs: [CGPoint]
        let indices: [UInt32]
    }

    /// Decode the binary sidecar written by `Food3DExporter.writeMeshSidecar`.
    /// Returns nil on any structural inconsistency so the caller falls back to
    /// loading the USD scene. Every read is bounds-checked — the file is app
    /// generated but treated defensively so a truncated file can never crash.
    private func loadMeshSidecar(at url: URL) -> [SidecarObject]? {
        guard let data = try? Data(contentsOf: url), data.count > 8 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x50, bytes[1] == 0x32, bytes[2] == 0x4D,
              bytes[3] == 0x31 || bytes[3] == 0x32 else { return nil } // 'P2M1'/'P2M2'
        let version = Int(bytes[3]) - 0x30 // 1 or 2 (v2 stores per-vertex UVs)

        var offset = 4
        func readU32() -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            let v = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
            offset += 4
            return v
        }
        func readF32() -> Float? {
            guard let bits = readU32() else { return nil }
            return Float(bitPattern: bits)
        }

        guard let objectCount = readU32() else { return nil }
        var objects: [SidecarObject] = []
        objects.reserveCapacity(Int(objectCount))

        for _ in 0..<objectCount {
            guard let idLen = readU32(),
                  offset + Int(idLen) <= bytes.count else { return nil }
            let id = String(bytes: bytes[offset..<offset + Int(idLen)], encoding: .utf8) ?? ""
            offset += Int(idLen)
            guard !id.isEmpty else { return nil }

            // Average colour (RGB, 0…1). Used as the material diffuse so the
            // food renders in its real sampled colour even when the device does
            // not honour the raw per-vertex colour source — it is never white.
            guard let avgR = readF32(), let avgG = readF32(), let avgB = readF32() else { return nil }

            guard let vCountRaw = readU32() else { return nil }
            let vCount = Int(vCountRaw)
            guard offset + vCount * 12 <= bytes.count else { return nil }
            var positions = [SCNVector3]()
            positions.reserveCapacity(vCount)
            for _ in 0..<vCount {
                guard let x = readF32(), let y = readF32(), let z = readF32() else { return nil }
                positions.append(SCNVector3(x, y, z))
            }

            guard offset + vCount * 4 <= bytes.count else { return nil }
            let colors = Array(bytes[offset..<offset + vCount * 4])
            offset += vCount * 4

            // Per-vertex UVs (v2 only). They index the baked capture photo so
            // the viewer can paste the real picture onto the mesh.
            var uvs: [CGPoint] = []
            if version >= 2 {
                guard let uvCountRaw = readU32() else { return nil }
                let uvCount = Int(uvCountRaw)
                guard offset + uvCount * 8 <= bytes.count else { return nil }
                uvs.reserveCapacity(uvCount)
                for _ in 0..<uvCount {
                    guard let u = readF32(), let v = readF32() else { return nil }
                    uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
                }
            }

            guard let iCountRaw = readU32() else { return nil }
            let iCount = Int(iCountRaw)
            guard offset + iCount * 4 <= bytes.count else { return nil }
            var indices = [UInt32]()
            indices.reserveCapacity(iCount)
            for _ in 0..<iCount {
                guard let idx = readU32() else { return nil }
                indices.append(idx)
            }

            objects.append(SidecarObject(
                id: id,
                averageColor: SCNVector3(avgR, avgG, avgB),
                positions: positions, colors: colors, uvs: uvs, indices: indices
            ))
        }
        return objects
    }

    /// Geometry-stage shader modifier: forward each vertex's sampled colour
    /// (`_geometry.color` is the `SCNGeometrySource(.color)` attribute) into a
    /// custom varying so the surface stage can read the interpolated value.
    private static let vertexColorGeometryModifier = """
    #pragma varyings
    float3 p2mVertexColor;
    #pragma body
    out.p2mVertexColor = _geometry.color.rgb;
    """

    /// Surface-stage shader modifier: write the interpolated per-vertex colour
    /// straight into the diffuse. This makes the captured photo colours render
    /// per-vertex regardless of whether the device multiplies the raw `.color`
    /// source under `.physicallyBased` — the cause of the earlier flat-white
    /// food. If the modifier fails to compile SceneKit ignores it and the
    /// material's average-colour diffuse (see buildScene) shows instead — still
    /// never white.
    private static let vertexColorSurfaceModifier = """
    #pragma body
    float3 p2mVC = in.p2mVertexColor;
    // If the per-vertex colour source failed to bind on this device it reads as
    // pure white (1,1,1); in that degenerate case keep the real average-colour
    // diffuse (set in buildScene from the sampled food colour) so the food can
    // never render flat white. Any real food vertex colour — even a light one —
    // sums below this threshold, so per-vertex colour still applies normally.
    if (p2mVC.r + p2mVC.g + p2mVC.b < 2.97) {
        _surface.diffuse.rgb = p2mVC;
    }
    """

    /// Build a scene whose geometry keeps a real `SCNGeometrySource(.color)` so
    /// the sampled per-vertex food colours render (USD would have dropped them).
    /// Node names are the stable food ids, matching the metadata Flutter passed,
    /// so selection / isolation keep working exactly as with the USD path.
    private func buildScene(fromSidecar objects: [SidecarObject], textureURL: URL?) -> SCNScene {
        let scene = SCNScene()

        // Load the baked capture photo once. When present, each food maps its
        // stored UVs onto this image so the mesh shows the REAL picture pasted
        // onto the food, instead of a per-vertex tint that some devices rendered
        // white. `.constant` (unlit) shading keeps the pasted photo at full
        // brightness regardless of scene lighting.
        var textureImage: UIImage?
        if let textureURL, FileManager.default.fileExists(atPath: textureURL.path) {
            textureImage = UIImage(contentsOfFile: textureURL.path)
        }
        print("[Scan3DViewer] sidecar texture=\(textureImage != nil ? (textureURL?.lastPathComponent ?? "?") : "none")")

        for object in objects {
            guard object.positions.count >= 3, object.indices.count >= 3 else { continue }

            let positionSource = SCNGeometrySource(vertices: object.positions)
            let normals = computeSmoothNormals(
                positions: object.positions, indices: object.indices
            )
            let normalSource = SCNGeometrySource(normals: normals)
            let colorSource = SCNGeometrySource(
                data: Data(object.colors),
                semantic: .color,
                vectorCount: object.positions.count,
                usesFloatComponents: false,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<UInt8>.size,
                dataOffset: 0,
                dataStride: 4
            )
            // Paste the captured photo when we have both the texture and one UV
            // per vertex. SceneKit texcoords are top-left origin, so flip V back
            // from the USD (bottom-left) convention the exporter stored. Drop the
            // per-vertex colour source in the textured case so SceneKit shows the
            // photo EXACTLY, with no vertex-colour modulation.
            let canTexture = textureImage != nil &&
                object.uvs.count == object.positions.count
            var sources = canTexture
                ? [positionSource, normalSource]
                : [positionSource, normalSource, colorSource]
            if canTexture {
                let texcoords = object.uvs.map { CGPoint(x: $0.x, y: 1.0 - $0.y) }
                sources.append(SCNGeometrySource(textureCoordinates: texcoords))
            }

            let element = SCNGeometryElement(
                indices: object.indices, primitiveType: .triangles
            )
            let geometry = SCNGeometry(sources: sources, elements: [element])

            let material = SCNMaterial()
            if canTexture, let textureImage {
                // The real photo, pasted onto the food. Unlit so it renders
                // exactly as captured; clamp wrapping so edge UVs don't bleed.
                material.diffuse.contents = textureImage
                material.diffuse.wrapS = .clamp
                material.diffuse.wrapT = .clamp
                material.lightingModel = .constant
                material.isDoubleSided = true
                print("[Scan3DViewer] sidecar node=\(object.id) verts=\(object.positions.count) textured=true")
            } else {
                // Fallback: sampled per-vertex colour (average diffuse + shader
                // modifier), never white.
                material.diffuse.contents = UIColor(
                    red: CGFloat(max(0, min(1, object.averageColor.x))),
                    green: CGFloat(max(0, min(1, object.averageColor.y))),
                    blue: CGFloat(max(0, min(1, object.averageColor.z))),
                    alpha: 1.0
                )
                material.shaderModifiers = [
                    .geometry: Self.vertexColorGeometryModifier,
                    .surface: Self.vertexColorSurfaceModifier,
                ]
                print("[Scan3DViewer] sidecar node=\(object.id) " +
                      "verts=\(object.positions.count) textured=false avgColor=(" +
                      "\(String(format: "%.2f", object.averageColor.x))," +
                      "\(String(format: "%.2f", object.averageColor.y))," +
                      "\(String(format: "%.2f", object.averageColor.z)))")
            }
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.name = object.id
            scene.rootNode.addChildNode(node)
        }
        return scene
    }

    /// Area-weighted smooth per-vertex normals from the triangle list. Smooth
    /// shading reads as a rounded food surface, matching the USD export (which
    /// used a moderate crease threshold) closely enough for the inline viewer.
    private func computeSmoothNormals(
        positions: [SCNVector3], indices: [UInt32]
    ) -> [SCNVector3] {
        // Weld by position first: meshes unwelded for texture atlasing (see
        // MonocularVolumeEstimator seam-split) duplicate seam vertices, so
        // accumulating per index alone would shade them faceted. Sharing a
        // normal bucket across coincident positions keeps the surface smooth.
        var repIndex = [SIMD3<Int>: Int]()
        repIndex.reserveCapacity(positions.count)
        var rep = [Int](repeating: 0, count: positions.count)
        @inline(__always) func key(_ p: SCNVector3) -> SIMD3<Int> {
            SIMD3<Int>(
                Int((Float(p.x) * 10000).rounded()),
                Int((Float(p.y) * 10000).rounded()),
                Int((Float(p.z) * 10000).rounded())
            )
        }
        for idx in 0..<positions.count {
            let k = key(positions[idx])
            if let r = repIndex[k] { rep[idx] = r } else { repIndex[k] = idx; rep[idx] = idx }
        }
        var accum = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            i += 3
            guard a < positions.count, b < positions.count, c < positions.count else { continue }
            let pa = SIMD3<Float>(Float(positions[a].x), Float(positions[a].y), Float(positions[a].z))
            let pb = SIMD3<Float>(Float(positions[b].x), Float(positions[b].y), Float(positions[b].z))
            let pc = SIMD3<Float>(Float(positions[c].x), Float(positions[c].y), Float(positions[c].z))
            let faceNormal = cross(pb - pa, pc - pa) // magnitude ∝ triangle area
            accum[rep[a]] += faceNormal
            accum[rep[b]] += faceNormal
            accum[rep[c]] += faceNormal
        }
        return (0..<positions.count).map { idx in
            let v = accum[rep[idx]]
            let length = simd_length(v)
            let unit = length > 1e-8 ? v / length : SIMD3<Float>(0, 1, 0)
            return SCNVector3(unit.x, unit.y, unit.z)
        }
    }

    /// CONTRACT: this method must NEVER flatten the imported node graph.
    private func configure(scene: SCNScene, modelURL: URL) {
        scene.background.contents = UIColor(white: 0.06, alpha: 1.0)

        // Render the mesh with its REAL per-vertex colours (each vertex is
        // sampled from the captured photos at its own position: the top crown
        // from the top photo, the sides from the silhouette rim = the true side
        // colour, and a reasoned darker underside). The per-vertex path avoids
        // the planar-projection artefacts a baked photo texture produced —
        // stretched vertical streaks down the sides, the top image bleeding onto
        // the underside, and edge seams — because every vertex simply carries
        // its own colour with no UV projection to stretch.
        //
        // The sidecar material (see buildScene) already carries a shader
        // modifier that writes each vertex's sampled colour into the diffuse,
        // plus a real average-colour diffuse as the fallback. Earlier this method
        // forced the diffuse to white expecting SceneKit to multiply it by the
        // `.color` source, but `.physicallyBased` does NOT reliably do that
        // multiply, so the food rendered flat WHITE. We therefore keep the
        // diffuse buildScene set and only apply shared PBR styling here.
        scene.rootNode.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let hasVertexColors = geometry.sources(for: .color).isEmpty == false
            if let name = node.name {
                print("[Scan3DViewer] node=\(name) vertexColors=\(hasVertexColors)")
            }
            for material in geometry.materials {
                // A material whose diffuse is an image is the REAL captured photo
                // pasted onto the food (buildScene set it from <base>_texture.png
                // with the projected per-vertex UVs). Render it unlit and NEVER
                // overwrite it — the flat-tint clobber below was exactly why a
                // textured food fell back to showing a single solid colour
                // instead of the picture.
                let isTextured = material.diffuse.contents is UIImage
                material.lightingModel =
                    (hasVertexColors || isTextured) ? .constant : .physicallyBased
                material.isDoubleSided = true
                if hasVertexColors || isTextured {
                    material.roughness.contents = 1.0
                    material.metalness.contents = 0.0
                } else {
                    material.roughness.contents = 0.68
                    material.metalness.contents = 0.0
                    // USD/ModelIO import drops the baked colour for our monocular
                    // meshes, so a node with neither a photo texture nor a
                    // per-vertex colour source renders flat white. Force a warm
                    // food tint so a food is never a white blob.
                    material.diffuse.contents = UIColor(
                        red: 0.78, green: 0.60, blue: 0.44, alpha: 1.0)
                }
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
