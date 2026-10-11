"""Execute production Swift on the host, not full-app AR/ML/ModelIO export.

Plate detection is fixture-injected; AR/ML inference and segmentation/matching
entry points are not executed. Height statements are extracted verbatim after profile construction; todo02
checks the repaired occupied-column endpoints rather than requiring HEAD parity.
Todo03 executes the full monocular estimator, reconstruction/color methods and
real sidecar serializer. The ModelIO export wrapper and disabled MonoDepth are
stubbed; no USDZ/texture-bake integration or full-app XCTest pass is implied.
"""
from pathlib import Path
import re
import subprocess


def declaration(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


def statements(text, start_marker, end_marker):
    start = text.index(start_marker)
    return text[start:text.index(end_marker, start)]


root = Path(__file__).resolve().parents[2]
scanner = root / "ios/Runner/Scanner"
pipeline = (scanner / "InferencePipeline.swift").read_text()
monocular = (scanner / "MonocularVolumeEstimator.swift").read_text()
fusion = (scanner / "DepthFusion.swift").read_text()
tests = (root / "ios/RunnerTests/RunnerTests.swift").read_text()
plugin = (scanner / "ScannerPlugin.swift").read_text()
segmentation = (scanner / "SegmentationService.swift").read_text()
plate = (scanner / "PlateDetector.swift").read_text()
baker = (scanner / "Food3DTextureBaker.swift").read_text()
exporter = (scanner / "Food3DExporter.swift").read_text()
mono_depth = (scanner / "MonoDepthService.swift").read_text()
baseline_pipeline = subprocess.run(
    ["git", "show", "HEAD:ios/Runner/Scanner/InferencePipeline.swift"],
    cwd=root, text=True, capture_output=True, check=True,
).stdout
baseline_monocular = subprocess.run(
    ["git", "show", "HEAD:ios/Runner/Scanner/MonocularVolumeEstimator.swift"],
    cwd=root, text=True, capture_output=True, check=True,
).stdout
# Explicit boundaries exclude profile construction, matching and subsequent logs.
height_block = statements(
    pipeline, "            let bottomUV = profile.sourceUV(",
    '            print("[SIDEMATCH] top#\\(topIndex)(\\(top.label)) ← sides',
)
baseline_height_block = statements(
    baseline_pipeline,
    "            if let calibration,\n               let centre = calibration.topWorld(",
    '            print("[SIDEMATCH] top#\\(topIndex)(\\(top.label)) ← sides',
)
host_tests = re.findall(r"func (test\w+)\(", tests)
# UIKit image/EXIF integration belongs to the real app XCTest target, not this
# macOS extraction harness.
host_tests = [name for name in host_tests if not name.startswith("testPantryUIKit")]
source = [
    "import Foundation\nimport CoreGraphics\nimport CoreVideo\nimport CoreImage\nimport Accelerate\nimport simd",
    """func XCTAssertTrue(_ x: Bool) { precondition(x) }
func XCTAssertFalse(_ x: Bool) { precondition(!x) }
func XCTAssertNotNil<T>(_ x: T?) { precondition(x != nil) }
func XCTAssertNil<T>(_ x: T?) { precondition(x == nil) }
func XCTFail(_ message: String) { preconditionFailure(message) }
func XCTUnwrap<T>(_ x: T?) throws -> T {
    guard let value = x else { preconditionFailure("expected nonnil fixture") }
    return value
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) {
    precondition(a == b, "actual=\\(a) expected=\\(b)")
}
func XCTAssertEqual(_ a: Float, _ b: Float, accuracy: Float) {
    precondition(abs(a - b) <= accuracy, "actual=\\(a) expected=\\(b) tolerance=\\(accuracy)")
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) {
    precondition(abs(a - b) <= accuracy, "actual=\\(a) expected=\\(b) tolerance=\\(accuracy)")
}""",
    declaration(pipeline, "enum ScanMaskGeometry"),
    "final class SegmentationService {\n"
    + declaration(segmentation, "struct SegmentedObject") + "\n}",
    "final class FrameCaptureService {\n"
    + declaration((scanner / "FrameCaptureService.swift").read_text(), "struct CapturedFrame")
    + "\n" + declaration((scanner / "FrameCaptureService.swift").read_text(), "struct SupportingPlane") + "\n}",
    declaration((scanner / "FramePreprocessor.swift").read_text(), "final class FramePreprocessor"),
    "final class PlateDetector {\n"
    + declaration(plate, "struct PlateResult") + "\n"
    + re.search(r"    static let defaultDiameterCm:[^\n]+", plate).group(0)
    + """
    var fixture = PlateResult(rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                              diameterPx: 0, detected: false)
    func detect(in pixelBuffer: CVPixelBuffer) -> PlateResult { fixture }
    \n}""",
    fusion[fusion.index("final class DepthFusion"):fusion.index("    func exportFoodObjects(")]
    + "\n".join(
        declaration(fusion, marker)
        for marker in [
            "private struct ColumnKey",
            "private func solidifyColumns(",
            "private func robustMinY(",
            "private func connectedComponents(",
        ]
    )
    + "\n}",
    "final class Food3DTextureBaker {\n"
    + re.search(r"    private static let context =[^\n]+", baker).group(0) + "\n"
    + "\n".join(re.findall(r"    static let atlas[^\n]+", baker)) + "\n"
    + declaration(baker, "static func bgraCopy(") + "\n}",
    "final class MonoDepthService {\n"
    + declaration(mono_depth, "struct DepthGrid") + "\n"
    + declaration(mono_depth, "struct ReliefGrid") + """
    var isAvailable: Bool { false }
    func depthGrid(pixelBuffer: CVPixelBuffer, targetW: Int, targetH: Int) -> DepthGrid? {
        preconditionFailure("disabled MonoDepth must not execute")
    }
    func reliefGrid(depth: DepthGrid, mask: [[UInt8]], maskWidth: Int, maskHeight: Int) -> ReliefGrid? {
        preconditionFailure("disabled relief must not execute")
    }
    \n}""",
    "final class Food3DExporter {\n"
    + declaration(exporter, "static func validDisplayObject(") + "\n"
    + declaration(exporter, "private func writeMeshSidecar(") + "\n"
    + declaration(exporter, "static func averageColor(") + """
    func export(objects: [DepthFusion.Food3DObject], baseName: String,
                textureSource: CVPixelBuffer?, sideTextureSource: CVPixelBuffer?,
                topCoverage: [[UInt8]]?, sideCoverage: [[UInt8]]?) -> URL? {
        guard objects.allSatisfy(Self.validDisplayObject) else { return nil }
        let directory = URL(fileURLWithPath: ".dart_tool/native-repeatability-exports", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(baseName + ".p2mesh")
        writeMeshSidecar(objects: objects, to: url)
        return url
    }
    \n}""",
    "final class InferencePipeline {\n"
    + "\n".join(
        declaration(pipeline, marker)
        for marker in [
            "enum PipelineError",
            "static func monocularSideViewFailure(",
            "static func lidarUnresolvedFailure(",
            "static func isContainerLabel(",
            "static func containerReviewReason(",
            "static func pantryRecognitionPayload(",
            "static func approximateRecognitionPayload(",
            "func sideProfileAxes(",
            "func uncalibratedAspectFailure(",
            "func makeSideProfile(",
            "func lidarSideSilhouette(",
        ]
    ) + """
    private let monocularEstimator = MonocularVolumeEstimator()
    typealias SideProfileAxes = (
        verticalUsesColumns: Bool,
        topAxis: MonocularVolumeEstimator.SideProfile.TopAxis,
        reversed: Bool,
        verticalIndexIncreasesUp: Bool
    )
    \n}""",
    """struct FlutterError {
    let code: String
    let message: String?
    let details: Any?
}""",
    "final class ScannerPlugin {\n"
    + declaration(plugin, "static func flutterError(") + "\n}",
    declaration(monocular, "final class MonocularVolumeEstimator")
    + "\nextension MonocularVolumeEstimator {"
    + """
    func fixtureScale(frame: FrameCaptureService.CapturedFrame,
                      plate: PlateDetector.PlateResult, distance: Double?)
        -> (pixelsPerCm: Double, source: String, confidence: Double,
            fallbackReason: String?, provenance: String) {
        let result = estimateScale(topFrame: frame, maskWidth: 640,
                                   maskHeight: 640, tableDistanceCm: distance,
                                   preprocessingPlate: plate)
        return (result.pixelsPerCm, result.source, result.confidence,
                result.fallbackReason, result.provenance)
    }
    \n}""",
    "final class BaselineScale {\n"
    + "\n".join(declaration(baseline_monocular, marker) for marker in [
        "private struct ScaleEstimate", "private func estimateScale(",
        "private func logScaleValidation("])
    + "\n" + re.search(r"    private let guidedDistanceCm:[^\n]+", baseline_monocular).group(0)
    + """
    private let plateDetector = PlateDetector()
    func source(frame: FrameCaptureService.CapturedFrame,
                plate: PlateDetector.PlateResult, distance: Double?) -> String {
        plateDetector.fixture = plate
        return estimateScale(topFrame: frame, maskWidth: 640, maskHeight: 640,
                             tableDistanceCm: distance).source
    }
    \n}""",
    "class RunnerTests {\n"
    + "\n".join(declaration(tests, f"func {name}(") for name in host_tests)
    + "\n" + declaration(tests, "private func side(")
    + "\n" + declaration(tests, "private func sparseDepthLidarFusion(")
    + "\n" + "\n".join(declaration(tests, marker) for marker in [
        "private func hullProfile(", "private func signedHullVolume(",
        "private func assertClosedHull(", "private func hullContains(",
    ])
    + "\n}",
    "let tests = RunnerTests()",
]
for name in host_tests:
    method = declaration(tests, f"func {name}(")
    prefix = "try " if " throws " in method[:method.index("{")] else ""
    source.append(f'fputs("RUN {name}\\n", stderr); {prefix}tests.{name}(); fputs("PASS {name}\\n", stderr)')
source.extend([
    """
func currentHeight(profile: inout MonocularVolumeEstimator.SideProfile,
                   calibration: MonocularVolumeEstimator.PhotoCalibration?,
                   top: SegmentationService.SegmentedObject,
                   axes: InferencePipeline.SideProfileAxes, pieceMask: [[UInt8]]) {
    let topIndex = 0
    var descriptor = ScanMaskGeometry.SideMatchTop(
        lo: 0.2, hi: 0.8, area: 9, label: "fixture", classIndex: 1)
    descriptor.projectedLo = 0.2; descriptor.projectedHi = 0.8
    descriptor.cameraDepth = 0.5
    let tops = [descriptor]
    let sideList = "0(fixture)[0.2,0.8]single"
    """ + height_block + "\n}",
    """
func baselineHeight(profile: inout MonocularVolumeEstimator.SideProfile,
                    calibration: MonocularVolumeEstimator.PhotoCalibration?,
                    top: SegmentationService.SegmentedObject) {
    """ + baseline_height_block + "\n}",
    r"""
func fixtureBuffer(width: Int, height: Int) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
        kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    return buffer!
}
func fixtureFrame(buffer: CVPixelBuffer, fx: Float, depth: CVPixelBuffer? = nil)
    -> FrameCaptureService.CapturedFrame {
    let k = simd_float3x3(columns: (SIMD3(fx, 0, 0), SIMD3(0, 900, 0), SIMD3(500, 250, 1)))
    let pose = simd_float4x4(columns: (
        SIMD4(1, 2, 3, 4), SIMD4(5, 6, 7, 8),
        SIMD4(9, 10, 11, 12), SIMD4(13, 14, 15, 16)))
    return FrameCaptureService.CapturedFrame(pixelBuffer: buffer, depthBuffer: depth,
        cameraTransform: pose, cameraIntrinsics: k, timestamp: 123.25)
}
let buffer = fixtureBuffer(width: 1000, height: 500)
let frame = fixtureFrame(buffer: buffer, fx: 1000)
let crop = CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
let expectedFrame = "timestamp=123.25 image=1000x500 cropTL=0.2,0.1,0.6,0.8 " +
    "K=1000.0,900.0,500.0,250.0 " +
    "poseColumnMajor=[1.000000,2.000000,3.000000,4.000000,5.000000,6.000000,7.000000,8.000000," +
    "9.000000,10.000000,11.000000,12.000000,13.000000,14.000000,15.000000,16.000000] depth="
XCTAssertEqual(frame.measurementProvenance(crop: crop), expectedFrame + "false")
XCTAssertEqual(fixtureFrame(buffer: buffer, fx: 1000, depth: buffer)
    .measurementProvenance(crop: crop), expectedFrame + "true")
fputs("PASS assessmentCapturedFrameProvenance actual_dimensions_intrinsics_pose_crop_timestamp_depth\n", stderr)

let mask: [[UInt8]] = [[0, 1, 0], [0, 0, 0], [0, 1, 1]]
let summary = ScanMaskGeometry.maskProvenance(mask)
XCTAssertEqual(summary, ScanMaskGeometry.maskProvenance(mask))
XCTAssertTrue(summary.hasPrefix("mask=3x3 pixels=3 bbox=1,0,3,3 edgePixels=3 horizontal=columns " +
    "emptyColumns=0 gapColumns=1 centreIndex=1 centrePixels=2 hash="))
XCTAssertTrue(ScanMaskGeometry.maskProvenance(mask, horizontalAlongRows: true)
    .hasPrefix("mask=3x3 pixels=3 bbox=1,0,3,3 edgePixels=3 horizontal=rows " +
        "emptyColumns=1 gapColumns=0 centreIndex=1 centrePixels=0 hash="))
XCTAssertEqual(ScanMaskGeometry.maskProvenance([]), "mask=empty")
XCTAssertEqual(ScanMaskGeometry.maskProvenance([[]]), "mask=empty")
XCTAssertTrue(ScanMaskGeometry.maskProvenance([[0, 0], [0, 0]])
    .hasPrefix("mask=2x2 pixels=0 hash="))
let ragged: [[UInt8]] = [[0, 1, 0], [], [0, 1, 1, 1]]
let raggedSummary = ScanMaskGeometry.maskProvenance(ragged)
XCTAssertTrue(raggedSummary.hasPrefix("mask=3x3 pixels=3 bbox=1,0,3,3 edgePixels=3"))
XCTAssertFalse(summary.components(separatedBy: "hash=")[1] ==
    raggedSummary.components(separatedBy: "hash=")[1])
fputs("PASS assessmentMaskProvenance deterministic_orientation_empty_ragged_fingerprint\n", stderr)

// Only plate detection is stubbed. Scale selection, constants, candidate
// formatter and logScaleValidation are verbatim production declarations.
let scaleFixtures: [(String, CGFloat, Bool, Float, Double?, String, String?, Double, Double, String, String)] = [
    ("accepted_plate", 1000, true, 1000, 22, "plate_diameter", nil, 640 / 26, 0.86, "gate=accepted", "gate=accepted"),
    ("plate_no_intrinsics", 1000, true, 0, nil, "plate_diameter", nil, 640 / 26, 0.80, "gate=accepted", "unavailable"),
    ("plate_not_gated_by_assumption", 203.125, true, 1000, 22, "plate_diameter", nil, 5, 0.86, "gate=accepted", "gate=accepted"),
    ("invalid_plate_accepted_plane", 1, true, 1000, 22, "arkit_plane", nil, 640 / 22, 0.82, "invalid_or_out_of_range", "gate=accepted"),
    ("far_plane_rejected", 0, false, 1000, 100, "intrinsic_guided", "invalid_arkit_plane_distance", 640 / 22, 0.60, "unavailable", "invalid_or_out_of_range"),
    ("missing_plane", 0, false, 1000, nil, "intrinsic_guided", "no_arkit_plane", 640 / 22, 0.60, "unavailable", "unavailable"),
    ("below_threshold_plane", 0, false, 1000, 1, "intrinsic_guided", "invalid_arkit_plane_distance", 640 / 22, 0.60, "unavailable", "invalid_or_out_of_range"),
    ("missing_intrinsics", 0, false, 0, nil, "calibration_invalid", "no_camera_intrinsics", .nan, 0, "unavailable", "unavailable"),
]
for (name, diameter, detected, fx, distance, expectedSource, fallback, pxPerCm,
     confidence, plateGate, planeGate) in scaleFixtures {
    var pose = matrix_identity_float4x4
    pose.columns.1 = SIMD4(0, 0, -1, 0)
    pose.columns.2 = SIMD4(0, 1, 0, 0)
    pose.columns.3 = SIMD4(0, 0.22, 0, 1)
    let k = simd_float3x3(columns: (SIMD3(fx, 0, 0), SIMD3(0, fx, 0), SIMD3(500, 250, 1)))
    let result = MonocularVolumeEstimator().fixtureScale(
        frame: FrameCaptureService.CapturedFrame(pixelBuffer: buffer, depthBuffer: nil,
            cameraTransform: pose, cameraIntrinsics: k, timestamp: 123.25),
        plate: PlateDetector.PlateResult(rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            diameterPx: diameter, detected: detected), distance: distance)
    XCTAssertEqual(result.source, expectedSource)
    XCTAssertEqual(result.fallbackReason, fallback)
    if pxPerCm.isFinite {
        XCTAssertEqual(result.pixelsPerCm, pxPerCm * sqrt(2), accuracy: 0.005)
    } else { XCTAssertFalse(result.pixelsPerCm.isFinite) }
    XCTAssertEqual(result.confidence, confidence)
    XCTAssertTrue(result.provenance.contains("scaleSource=\(expectedSource) scaleFallback=\(fallback ?? "none")"))
    XCTAssertTrue(result.provenance.contains("scaleActualCropTL=0.0,0.0,1.0,1.0 scaleCropWidthPx=1000.0 mask=640x640"))
    XCTAssertTrue(result.provenance.contains("assumedPlateDiameterCm=26.0"))
    XCTAssertTrue(result.provenance.contains("assumedGuidedDistanceCm=22.0"))
    XCTAssertTrue(result.provenance.contains("guidedDistanceIsAssumption=true"))
    let plateCandidate = result.provenance.components(separatedBy: "plateCandidate={")[1]
        .components(separatedBy: "}")[0]
    let planeCandidate = result.provenance.components(separatedBy: "planeCandidate={")[1]
        .components(separatedBy: "}")[0]
    XCTAssertTrue(plateCandidate.contains(plateGate))
    XCTAssertTrue(planeCandidate.contains(planeGate))
    fputs("PASS assessmentScaleFixture \(name)\n", stderr)
}

var regressionPose = matrix_identity_float4x4
regressionPose.columns.1 = SIMD4(0, 0, -1, 0)
regressionPose.columns.2 = SIMD4(0, 1, 0, 0)
regressionPose.columns.3 = SIMD4(0, 0.1, 0, 1)
let regressionK = simd_float3x3(columns: (
    SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(500, 250, 1)))
let regressionFrame = FrameCaptureService.CapturedFrame(pixelBuffer: buffer, depthBuffer: nil,
    cameraTransform: regressionPose, cameraIntrinsics: regressionK, timestamp: 10)
for detected in [false, true] {
    let plate = PlateDetector.PlateResult(
        rect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
        diameterPx: detected ? 220 : 0, detected: detected)
    XCTAssertEqual(BaselineScale().source(frame: regressionFrame, plate: plate, distance: 10),
                   "intrinsic_guided")
    let current = MonocularVolumeEstimator().estimateScale(topFrame: regressionFrame,
        maskWidth: 640, maskHeight: 640, tableDistanceCm: 10, preprocessingPlate: plate)
    XCTAssertEqual(current.source, detected ? "plate_diameter" : "arkit_plane")
}
fputs("PASS baselineScaleRegressions HEAD discards valid 10cm plane/plate against assumed 22cm; current preserves sources\n", stderr)

let heightK = simd_float3x3(columns: (
    SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
var heightTopPose = regressionPose
heightTopPose.columns.3.y = 0.5
var heightSidePose = matrix_identity_float4x4
let roll = Float.pi / 4
heightSidePose.columns.0 = SIMD4(cos(roll), sin(roll), 0, 0)
heightSidePose.columns.1 = SIMD4(-sin(roll), cos(roll), 0, 0)
heightSidePose.columns.3 = SIMD4(0, 0.04, 0.5, 1)
let heightCrop = CGRect(x: 0, y: 0, width: 1, height: 1)
let heightCalibration = MonocularVolumeEstimator.PhotoCalibration(
    topTransform: heightTopPose, topIntrinsics: heightK, topWidth: 200, topHeight: 100,
    topCrop: heightCrop, sideTransform: heightSidePose, sideIntrinsics: heightK,
    sideWidth: 200, sideHeight: 100, sideCrop: heightCrop, tableY: 0)
var heightMask = Array(repeating: Array(repeating: UInt8(0), count: 200), count: 100)
for x in [Float(-0.06), Float(0.06)] {
    for step in 0...60 {
        let uv = heightCalibration.sideUV(world: SIMD3(x, Float(step) / 1000, 0))!
        heightMask[Int(uv.y * 100)][Int(uv.x * 200)] = 1
    }
}
let heightSegment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
    mask: heightMask, pixelCount: heightMask.flatMap { $0 }.filter { $0 != 0 }.count,
    centroid: (row: 50, col: 100), confidence: 1)
var oldHeightProfile = InferencePipeline().makeSideProfile(segment: heightSegment,
    axes: (true, .columns, false, true), imageWidth: 200, imageHeight: 100)!
baselineHeight(profile: &oldHeightProfile, calibration: heightCalibration, top: heightSegment)
let repairedHeight = heightCalibration.silhouetteHeight(
    mask: heightMask, through: SIMD3(0, 0, 0), verticalUsesColumns: true)
XCTAssertEqual(repairedHeight.heightCm!, 6, accuracy: 0.5)
var repairedProfile = oldHeightProfile
currentHeight(profile: &repairedProfile, calibration: heightCalibration, top: heightSegment,
              axes: (true, .columns, false, true), pieceMask: heightMask)
XCTAssertEqual(repairedProfile.measuredHeightCm!, 6, accuracy: 0.5)
XCTAssertTrue(oldHeightProfile.measuredHeightCm! > 8)
fputs("PASS baselineHeightRegression rolled disconnected 6cm silhouette: HEAD bbox ray >8cm; occupied endpoints within 0.5cm raster bound\n", stderr)

func checkHeightFixture(_ name: String, reason: String, axes: InferencePipeline.SideProfileAxes) {
    var topPose = matrix_identity_float4x4
    topPose.columns.1 = SIMD4(0, 0, -1, 0)
    topPose.columns.2 = SIMD4(0, 1, 0, 0)
    topPose.columns.3 = SIMD4(0, 0.5, 0, 1)
    var sidePose = matrix_identity_float4x4
    sidePose.columns.3 = SIMD4(0, 0.04, name == "side_behind_object" ? -0.5 : 0.5, 1)
    let k = simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
    let calibration: MonocularVolumeEstimator.PhotoCalibration? = name == "no_calibration" ? nil :
        MonocularVolumeEstimator.PhotoCalibration(
            topTransform: topPose,
            topIntrinsics: name == "invalid_top_intrinsics" ? simd_float3x3() : k,
            topWidth: 200, topHeight: 100, topCrop: CGRect(x: 0, y: 0, width: 1, height: 1),
            sideTransform: sidePose,
            sideIntrinsics: name == "invalid_side_intrinsics" ? simd_float3x3() : k,
            sideWidth: 200, sideHeight: 100,
            sideCrop: CGRect(x: 0, y: 0, width: 1, height: name == "degenerate_side_crop" ? 0 : 1),
            tableY: 0)
    let pieceMask: [[UInt8]] = [
        [0,0,0,0,0], [0,1,1,1,0], [0,1,1,1,0], [0,1,1,1,0], [0,0,0,0,0]]
    let top = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
        mask: pieceMask, pixelCount: 9, centroid: (row: 2, col: 2), confidence: 1)
    var profile = InferencePipeline().makeSideProfile(
        segment: top, axes: axes, imageWidth: 5, imageHeight: 5)!
    profile.calibration = calibration
    profile.sourceMask = pieceMask
    var baseline = profile
    currentHeight(profile: &profile, calibration: calibration, top: top, axes: axes, pieceMask: pieceMask)
    baselineHeight(profile: &baseline, calibration: calibration, top: top)
    XCTAssertTrue(profile.measurementProvenance.hasPrefix("heightReason=\(reason) bottomUV="))
    XCTAssertTrue(profile.measurementProvenance.contains("upperUV="))
    XCTAssertTrue(profile.measurementProvenance.contains("verticalAxis=rows verticalIndexIncreasesUp=false topAxis=columns reversed=false"))
    XCTAssertTrue(profile.measurementProvenance.contains("projectedSpan=0.2,0.8 cameraDepth=0.5 pieces=[0(fixture)[0.2,0.8]single]"))
    XCTAssertTrue(profile.measurementProvenance.contains(ScanMaskGeometry.maskProvenance(pieceMask)))
    if name == "valid" {
        XCTAssertEqual(profile.measuredHeightCm!, 15, accuracy: 0.00001)
        XCTAssertEqual(profile.sourceBaseHeightM, -0.035, accuracy: 0.000001)
        XCTAssertEqual(profile.measuredHeightCm, baseline.measuredHeightCm)
        XCTAssertEqual(profile.sourceBaseHeightM, baseline.sourceBaseHeightM)
    } else {
        XCTAssertNil(profile.measuredHeightCm)
        XCTAssertEqual(profile.sourceBaseHeightM, 0)
        if calibration != nil { XCTAssertEqual(profile.calibrationFailure, reason) }
    }
    fputs("PASS assessmentHeightBlock \(name) occupied_endpoints reason=\(reason)\n", stderr)
}
for (name, reason) in [
    ("valid", "side_pose_ray"), ("no_calibration", "no_table_calibration"),
    ("invalid_top_intrinsics", "top_ray_unavailable"),
    ("invalid_side_intrinsics", "side_endpoint_ray_invalid"),
    ("side_behind_object", "side_endpoint_ray_invalid"),
    ("degenerate_side_crop", "side_endpoint_ray_invalid")
] {
    checkHeightFixture(name, reason: reason, axes: (false, .columns, false, false))
}
fputs("PASS supplemental production diagnostics: 10 metadata/scale groups + 6 height fixtures; not full-app XCTest/exporter/AR/ML execution\n", stderr)
""",
])
subprocess.run(
    [
        "xcrun", "swift", "-module-cache-path",
        str(root / ".dart_tool/native-repeatability-cache"), "-",
    ],
    input="\n".join(source),
    text=True,
    cwd=root,
    check=True,
)
