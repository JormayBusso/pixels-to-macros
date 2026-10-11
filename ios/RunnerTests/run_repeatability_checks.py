"""Run the platform-independent production Swift helpers without an iOS build."""
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


root = Path(__file__).resolve().parents[2]
scanner = root / "ios/Runner/Scanner"
pipeline = (scanner / "InferencePipeline.swift").read_text()
monocular = (scanner / "MonocularVolumeEstimator.swift").read_text()
fusion = (scanner / "DepthFusion.swift").read_text()
tests = (root / "ios/RunnerTests/RunnerTests.swift").read_text()
plugin = (scanner / "ScannerPlugin.swift").read_text()
segmentation = (scanner / "SegmentationService.swift").read_text()
host_tests = [
    name for name in re.findall(r"func (test\w+)\(", tests)
    if name != "testMonocularMissingSideExportsUnmeasuredTopMaskSheet"
]
source = [
    "import Foundation\nimport CoreGraphics\nimport CoreVideo\nimport simd",
    """func XCTAssertTrue(_ x: Bool) { precondition(x) }
func XCTAssertFalse(_ x: Bool) { precondition(!x) }
func XCTAssertNotNil<T>(_ x: T?) { precondition(x != nil) }
func XCTAssertNil<T>(_ x: T?) { precondition(x == nil) }
func XCTFail(_ message: String) { preconditionFailure(message) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) {
    precondition(a == b, "actual=\\(a) expected=\\(b)")
}
func XCTAssertEqual(_ a: Float, _ b: Float, accuracy: Float) {
    precondition(abs(a - b) <= accuracy)
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) {
    precondition(abs(a - b) <= accuracy)
}""",
    declaration(pipeline, "enum ScanMaskGeometry"),
    "final class SegmentationService {\n"
    + declaration(segmentation, "struct SegmentedObject") + "\n}",
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
    "final class InferencePipeline {\n"
    + "\n".join(
        declaration(pipeline, marker)
        for marker in [
            "enum PipelineError",
            "static func monocularSideViewFailure(",
            "static func lidarUnresolvedFailure(",
        ]
    ) + "\n}",
    """struct FlutterError {
    let code: String
    let message: String?
    let details: Any?
}""",
    "final class ScannerPlugin {\n"
    + declaration(plugin, "static func flutterError(") + "\n}",
    "final class MonocularVolumeEstimator {\n"
    + "\n".join(
        declaration(monocular, marker)
        for marker in [
            "struct PhotoCalibration",
            "struct SideProfile",
            "enum EstimateError",
            "func usableSideProfile(",
        ]
    )
    + "\n}",
    "class RunnerTests {\n"
    + "\n".join(declaration(tests, f"func {name}(") for name in host_tests)
    + "\n" + declaration(tests, "private func side(")
    + "\n" + declaration(tests, "private func sparseDepthLidarFusion(")
    + "\n}",
    "let tests = RunnerTests()",
]
for name in host_tests:
    source.append(f'fputs("RUN {name}\\n", stderr); tests.{name}(); fputs("PASS {name}\\n", stderr)')
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
