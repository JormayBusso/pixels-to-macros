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
        declaration(preview, "struct LiveGlowGridROI"),
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
typealias FlutterResult = @convention(block) (Any?) -> Void
struct FlutterMethodCall { let method: String; let arguments: Any? }
let FlutterMethodNotImplemented = NSObject()
class FlutterMethodChannel {
    init(name: String, binaryMessenger: FlutterBinaryMessenger) {}
    func setMethodCallHandler(_ handler: @escaping (FlutterMethodCall, @escaping FlutterResult) -> Void) {}
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
    "import Foundation\nimport CoreGraphics\nimport CoreML\nimport simd",
    declaration(preview, "enum LiveFoodOverlayPolicy"),
    declaration(preview, "struct LiveFoodFrameGate"),
    declaration(preview, "struct LiveGlowROI"),
    declaration(preview, "struct LiveGlowGridROI"),
    declaration(preview, "struct LiveFoodCrop"),
    "enum LiveFoodDetector { static let grid = 160 }",
    "final class LiveAccumulationHost {\nstatic let grid = 160\n"
    + declaration(preview, "private func accumulate(").replace("private ", "")
    + "\n}",
    "final class LiveDrainHost {\n"
    + declaration(preview, "func reset()")
    + "\n"
    + declaration(preview, "func drain(completion:")
    + """
var gate = LiveFoodFrameGate()
let queue = DispatchQueue(label: "live-drain-check")
}""",
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
    "final class YOLODecode {\n"
    + "\n".join(
        declaration(yolo, marker).replace("private ", "")
        for marker in ["private struct Detection", "private func decode(",
                       "private static func makeReader", "private func rasterise(",
                       "private static func sigmoid", "private static func keepDominantComponents",
                       "private func clamp("]
    )
    + """
var hasMetadataLabels = true
var labels = [Int: String]()
var liveLabelWarningIssued = false
var loadedResource: String?
typealias SegmentedObject = SegmentationService.SegmentedObject
let protoCount = 32
let maxPreNMS = 300
let confThreshold: Float = 0.15
let maskThreshold: Float = 0.5
}""",
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
    check("capture drain waits for in-flight serial work and invalidates its completion") {
        let host = LiveDrainHost()
        let token = host.gate.begin(at: 10)!
        let workFinished = DispatchSemaphore(value: 0)
        host.queue.async {
            Thread.sleep(forTimeInterval: 0.01)
            workFinished.signal()
        }
        var drained = false
        host.drain {
            precondition(workFinished.wait(timeout: .now()) == .success)
            precondition(!host.gate.finish(token: token, timestamp: 10, now: 10.1))
            drained = true
        }
        precondition(host.gate.busy && host.gate.begin(at: 11) == nil)
        let deadline = Date().addingTimeInterval(1)
        while !drained && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(drained && !host.gate.busy)
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
check("exact fill preserves holes, components and empty support without a halo") {
    let g = 40
    var mask = [Float](repeating: 0, count: g * g)
    for y in 10..<30 { for x in 10..<30 { mask[y * g + x] = 1 } }
    mask[20 * g + 20] = 0
    mask[2 * g + 2] = 1
    let f = LiveFoodOverlayPolicy.glowFields(mask, grid: g)!
    for field in [f.fill, f.edge, f.core] {
        precondition(field.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
    precondition(f.fill == mask)
    precondition(f.edge.allSatisfy { $0 == 0 } && f.core.allSatisfy { $0 == 0 })
    let empty = LiveFoodOverlayPolicy.glowFields([Float](repeating: 0, count: g * g), grid: g)!
    precondition(empty.fill.allSatisfy { $0 == 0 } && empty.edge.allSatisfy { $0 == 0 })
    precondition(LiveFoodOverlayPolicy.glowFields([], grid: g) == nil)
}
check("guide crop and inverse mapping preserve TOP and SIDE support") {
    for rounded in [false, true] {
        for columns in [false, true] {
            let geometry = LiveGlowROI(roundedRect: rounded)
                .geometry(side: 160, longAxisAlongColumns: columns)
            let original = LiveGlowGridROI(rect: geometry.rect, radius: geometry.corner)
            let crop = LiveFoodCrop(roi: original, grid: 160)
            precondition(crop.rect.width == crop.rect.height && crop.rect.width <= 160)
            let centre = crop.inputPoint(x: 80, y: 80, grid: 160)
            precondition(abs(centre.x - 80) < 1e-9 && abs(centre.y - 80) < 1e-9)
            for y in 0..<160 { for x in 0..<160 {
                let p = crop.inputPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5, grid: 160)
                precondition(original.contains(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    == crop.roi.contains(x: p.x, y: p.y))
            } }
            precondition(!original.contains(x: 1, y: 1))
        }
    }
}
check("production YOLO rejects background anchors BEFORE NMS but saved decode stays unchanged") {
    let decoder = YOLODecode()
    decoder.labels = Dictionary(uniqueKeysWithValues: (0..<103).map { ($0, "apple") })
    let det = try! MLMultiArray(shape: [1, 139, 2], dataType: .float32)
    for i in 0..<det.count { det[i] = 0 }
    func put(_ channel: Int, _ anchor: Int, _ value: Float) {
        det[channel * det.strides[1].intValue + anchor * det.strides[2].intValue] = NSNumber(value: value)
    }
    check("production YOLO live raster retains small components and holes, saved cleanup unchanged") {
        let decoder = YOLODecode()
        decoder.labels = [0: "apple"]
        let proto = try! MLMultiArray(shape: [1, 32, 40, 40], dataType: .float32)
        for i in 0..<proto.count { proto[i] = -10 }
        for y in 5..<15 { for x in 5..<15 { proto[y * 40 + x] = 10 } }
        for y in 8..<11 { for x in 8..<11 { proto[y * 40 + x] = -10 } }
        proto[30 * 40 + 30] = 10
        var coefficients = Array(repeating: Float(0), count: 32)
        coefficients[0] = 1
        let box = YOLODecode.Detection(x0: 0, y0: 0, x1: 160, y1: 160,
                                      score: 0.8, classIndex: 0, coeffs: coefficients)
        let live = decoder.rasterise([box], proto: proto, targetW: 160, targetH: 160, livePreview: true)[0]
        let saved = decoder.rasterise([box], proto: proto, targetW: 160, targetH: 160, livePreview: false)[0]
        precondition(live.mask[120][120] == 1 && saved.mask[120][120] == 0)
        precondition(live.mask[37][37] == 0 && live.pixelCount > saved.pixelCount)
    }
    check("production foreground accumulation keeps large food and clips only the guide") {
        let geometry = LiveGlowROI(roundedRect: false).geometry(side: 160, longAxisAlongColumns: true)
        let roi = LiveGlowGridROI(rect: geometry.rect, radius: geometry.corner)
        let crop = LiveFoodCrop(roi: roi, grid: 160)
        let food = SegmentationService.SegmentedObject(label: "apple", classIndex: 25,
            mask: Array(repeating: Array(repeating: UInt8(1), count: 160), count: 160),
            pixelCount: 160 * 160, centroid: (80, 80), confidence: 0.8)
        let host = LiveAccumulationHost()
        var union = Array(repeating: Float(0), count: 160 * 160)
        precondition(host.accumulate([food], crop: crop, roi: roi, into: &union) == 1)
        for y in 0..<160 { for x in 0..<160 {
            precondition((union[y * 160 + x] == 1)
                == roi.contains(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
        } }
    }
    for a in 0..<2 {
        put(0, a, a == 0 ? 20 : 320)
        put(1, a, a == 0 ? 20 : 320)
        put(2, a, 160); put(3, a, 160)
        put(4, a, a == 0 ? 0.99 : 0.80)
    }
    let roi = LiveGlowGridROI(rect: CGRect(x: 20, y: 20, width: 120, height: 120), radius: 60)
    let size = CGSize(width: 640, height: 640)
    let live = decoder.decode(det: det, livePreview: true, roi: roi, modelSize: size)
    let saved = decoder.decode(det: det, livePreview: false, roi: roi, modelSize: size)
    precondition(live.count == 1 && live[0].score == Float(0.80))
    precondition(saved.count == 2)
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
