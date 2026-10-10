"""Exercise production live-only Swift policies without an iOS build."""
from pathlib import Path
import subprocess


def declaration(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


root = Path(__file__).resolve().parents[2]
scanner = root / "ios/Runner/Scanner"
preview = (scanner / "ARCameraPreviewPlugin.swift").read_text()
dense = (scanner / "SegmentationService.swift").read_text()
yolo = (scanner / "YOLOSegmentationService.swift").read_text()
pipeline = (scanner / "InferencePipeline.swift").read_text()
subprocess.run(
    [
        "xcrun", "swiftc", "-typecheck", "-module-cache-path",
        str(root / ".dart_tool/native-live-overlay-cache"), "-",
    ],
    input="\n".join([
        "import Foundation\nimport CoreGraphics\nimport simd",
        declaration(preview, "enum LiveFoodOverlayPolicy"),
        "enum LiveFoodDetector { static let grid = 160 }",
        dense, yolo,
    ]),
    text=True,
    cwd=root,
    check=True,
)
print("PASS production YOLO/dense services typecheck (macOS SDK)", flush=True)
sdk = subprocess.check_output(
    ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True
).strip()
subprocess.run(
    [
        "xcrun", "swiftc", "-typecheck", "-target", "arm64-apple-ios18.0-simulator",
        "-sdk", sdk, "-module-cache-path",
        str(root / ".dart_tool/native-live-overlay-ios-cache"), "-",
    ],
    input="\n".join([
        """import UIKit
import ARKit
protocol FlutterBinaryMessenger {}
protocol FlutterMessageCodec {}
protocol FlutterPlatformView { func view() -> UIView }
protocol FlutterPlatformViewFactory {}
class FlutterStandardMessageCodec: NSObject, FlutterMessageCodec {
    static func sharedInstance() -> FlutterStandardMessageCodec { FlutterStandardMessageCodec() }
}
typealias FlutterResult = (Any?) -> Void
struct FlutterMethodCall { let method: String; let arguments: Any? }
let FlutterMethodNotImplemented = NSObject()
class FlutterMethodChannel {
    init(name: String, binaryMessenger: FlutterBinaryMessenger) {}
    func setMethodCallHandler(_ handler: @escaping (FlutterMethodCall, FlutterResult) -> Void) {}
    func invokeMethod(_ method: String, arguments: Any?) {}
}
class HostMessenger: FlutterBinaryMessenger {}
class HostEngine { let binaryMessenger = HostMessenger() }
class AppDelegate: UIResponder, UIApplicationDelegate { let flutterEngine = HostEngine() }
class ARSessionManager {
    var session: ARSession?
    var latestFrame: ARFrame?
    var generation = 0
}
extension Notification.Name {
    static let arSessionDidStart = Notification.Name("arSessionDidStart")
    static let arSessionDidFail = Notification.Name("arSessionDidFail")
}""",
        declaration(pipeline, "enum ScanMaskGeometry"),
        preview.replace("import Flutter\n", ""),
        dense, yolo,
    ]),
    text=True,
    cwd=root,
    check=True,
)
print("PASS live preview/services typecheck (iOS SDK; Flutter/session host stubs)", flush=True)
source = [
    "import Foundation\nimport CoreGraphics\nimport simd",
    declaration(preview, "enum LiveFoodOverlayPolicy"),
    declaration(preview, "struct LiveFoodFrameGate"),
    declaration(preview, "struct LiveGlowROI"),
    declaration(pipeline, "enum ScanMaskGeometry"),
    "final class SegmentationService {\n"
    + dense[dense.index("private static let miniLabelMap"):
            dense.index("private static func buildLabelMap")].replace("private ", "")
    + "\n".join(
        declaration(dense, marker).replace("private ", "")
        for marker in [
            "struct SegmentedObject",
            "private static func buildLabelMap",
            "private func label(for",
            "private func buildObjects(",
        ]
    )
    + "\nvar labelMap: [Int: String] = [:]\n}",
    "enum YOLOLabels {\n"
    + declaration(yolo, "private static func parseNames").replace("private ", "")
    + "\n}",
    r'''
func check(_ name: String, _ body: () -> Void) {
    body()
    print("PASS \(name)")
}
check("semantic food-only labels, not filename or class-zero heuristics") {
    for name in ["background", "others", "other", "other ingredients", "plate",
                 "dining table", "bowl", "cup", "person", "fork", "chair",
                 "object", "class_25", "unknown"] {
        precondition(!LiveFoodOverlayPolicy.accepts(label: name, confidence: 1))
    }
    for name in ["candy", "steak", "apple", "hot_dog", " WHITE BUTTON MUSHROOM "] {
        precondition(LiveFoodOverlayPolicy.accepts(label: name, confidence: 0.8))
    }
    for confidence in [Float(0.54), .nan, .infinity, -.infinity] {
        precondition(!LiveFoodOverlayPolicy.accepts(label: "steak", confidence: confidence))
    }
}
check("bounded slot survives repeated resets and discards old completions") {
    var gate = LiveFoodFrameGate()
    let first = gate.begin(at: 10)!
    precondition(gate.begin(at: 11) == nil)
    gate.invalidate()
    gate.invalidate()
    precondition(gate.busy && gate.begin(at: 12) == nil)
    precondition(!gate.finish(token: first, timestamp: 12, now: 12.1))
    let second = gate.begin(at: 12.1)!
    precondition(gate.finish(token: second, timestamp: 12.1, now: 12.2))
    precondition(gate.begin(at: 12.21) == nil)
    precondition(gate.begin(at: 12.3) != nil)
}
check("late, nonfinite and future timestamps are rejected") {
    precondition(LiveFoodOverlayPolicy.isFresh(timestamp: 1, now: 1.3))
    for timestamp in [0.6, 1.1, .nan, .infinity] {
        precondition(!LiveFoodOverlayPolicy.isFresh(timestamp: timestamp, now: 1))
    }
    var gate = LiveFoodFrameGate()
    let token = gate.begin(at: 1)!
    precondition(!gate.finish(token: token, timestamp: 1, now: 1.4))
    precondition(!gate.busy)
}
check("camera motion suppresses old contours") {
    let identity = matrix_identity_float4x4
    precondition(LiveFoodOverlayPolicy.cameraIsAligned(identity, identity))
    var moved = identity
    moved.columns.3.x = 0.02
    precondition(!LiveFoodOverlayPolicy.cameraIsAligned(identity, moved))
    let rotated = simd_float4x4(simd_quatf(angle: Float.pi / 40, axis: SIMD3(0, 1, 0)))
    precondition(!LiveFoodOverlayPolicy.cameraIsAligned(identity, rotated))
}
check("glow fields are smooth, bounded and empty for an empty mask") {
    let g = 40
    var mask = [Float](repeating: 0, count: g * g)
    for y in 10..<30 { for x in 10..<30 { mask[y * g + x] = 1 } }
    let f = LiveFoodOverlayPolicy.glowFields(mask, grid: g)!
    for field in [f.fill, f.edge, f.core] {
        precondition(field.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
    var maxStep: Float = 0
    for y in 0..<g { for x in 1..<g { maxStep = max(maxStep, abs(f.fill[y * g + x] - f.fill[y * g + x - 1])) } }
    let ramp = (0..<g).filter { f.fill[20 * g + $0] > 0.03 && f.fill[20 * g + $0] < 0.97 }.count
    precondition(maxStep < 0.9 && ramp >= 4)
    precondition(f.fill[20 * g + 20] > 0.9 && f.fill[2 * g + 2] == 0)
    precondition(f.edge[20 * g + 10] > 0.5 && f.edge[20 * g + 20] < 0.2)
    let empty = LiveFoodOverlayPolicy.glowFields([Float](repeating: 0, count: g * g), grid: g)!
    precondition(empty.fill.allSatisfy { $0 == 0 } && empty.edge.allSatisfy { $0 == 0 })
    precondition(LiveFoodOverlayPolicy.glowFields([], grid: g) == nil)
}
check("dense 104-class live labels correct YOLO JSON offset without changing saved mapping") {
    let service = SegmentationService()
    let json = try! Data(contentsOf: URL(fileURLWithPath: "ios/Runner/FoodSegmentationLabels.json"))
    let labels = try! JSONSerialization.jsonObject(with: json) as! [String: String]
    service.labelMap = Dictionary(uniqueKeysWithValues: labels.map { (Int($0.key)!, $0.value) })
    func objects(_ cls: Int, _ live: Bool, _ confidence: Float = 0.8,
                 _ classes: Int = 104) -> [SegmentationService.SegmentedObject] {
        service.buildObjects(classGrid: Array(repeating: cls, count: 400),
            confGrid: Array(repeating: confidence, count: 400),
            height: 20, width: 20, totalClasses: classes, livePreview: live)
    }
    precondition(objects(25, false).first!.label == "date")
    precondition(objects(25, true).first!.label == "apple")
    precondition(objects(0, true).isEmpty)
    precondition(objects(103, true).isEmpty)
    precondition(!objects(25, false, 0.4).isEmpty)
    precondition(objects(25, true, 0.4).isEmpty)
    precondition(objects(4, true, 0.8, 10).first!.label == "bread")
}
check("actual bundled YOLO metadata is zero-based food with a rejected generic class") {
    let data = try! Data(contentsOf: URL(fileURLWithPath: "ios/Runner/FoodSegYolo.mlmodelc/metadata.json"))
    let model = (try! JSONSerialization.jsonObject(with: data) as! [[String: Any]])[0]
    let metadata = model["userDefinedMetadata"] as! [String: String]
    let labels = YOLOLabels.parseNames(metadata["names"]!)
    precondition(labels.count == 103 && labels[0] == "candy")
    precondition(labels[24] == "apple" && labels[102] == "other ingredients")
    precondition(LiveFoodOverlayPolicy.accepts(label: labels[0]!, confidence: 0.8))
    precondition(!LiveFoodOverlayPolicy.accepts(label: labels[102]!, confidence: 0.8))
    for label in labels.values where label != "other ingredients" {
        precondition(LiveFoodOverlayPolicy.accepts(label: label, confidence: 0.8))
    }
}
check("TOP circle and SIDE ROI preserve portrait and landscape mapping") {
    let top = LiveGlowROI(roundedRect: false)
    precondition(top.geometry(side: 160, longAxisAlongColumns: true).rect
        == top.geometry(side: 160, longAxisAlongColumns: false).rect)
    let side = LiveGlowROI(roundedRect: true)
    let landscape = side.geometry(side: 160, longAxisAlongColumns: true).rect
    let portrait = side.geometry(side: 160, longAxisAlongColumns: false).rect
    precondition(landscape.width == portrait.height && landscape.height == portrait.width)
    precondition(landscape.midX == 80 && landscape.midY == 80)
}
''',
]
subprocess.run(
    [
        "xcrun", "swift", "-module-cache-path",
        str(root / ".dart_tool/native-live-overlay-cache"), "-",
    ],
    input="\n".join(source),
    text=True,
    cwd=root,
    check=True,
)
