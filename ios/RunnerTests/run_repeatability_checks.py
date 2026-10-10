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
source = [
    "import Foundation\nimport CoreGraphics\nimport simd",
    """func XCTAssertTrue(_ x: Bool) { precondition(x) }
func XCTAssertFalse(_ x: Bool) { precondition(!x) }
func XCTAssertNotNil<T>(_ x: T?) { precondition(x != nil) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b) }
func XCTAssertEqual(_ a: Float, _ b: Float, accuracy: Float) {
    precondition(abs(a - b) <= accuracy)
}""",
    declaration(pipeline, "enum ScanMaskGeometry"),
    "final class DepthFusion {\n"
    + "\n".join(
        declaration(fusion, marker)
        for marker in [
            "struct VoxelKey",
            "static func projectToImage(",
            "struct SideSilhouette",
            "func setSideSilhouette(",
            "func carveBySideSilhouette(",
        ]
    )
    + "\n" + re.search(r"private let voxelSizeM: Float = [^\n]+", fusion).group()
    + "\nprivate var sideSilhouette: SideSilhouette?"
    + "\n}",
    "final class MonocularVolumeEstimator {\n"
    + "\n".join(
        declaration(monocular, marker)
        for marker in [
            "struct PhotoCalibration",
            "struct SideProfile",
            "func usableSideProfile(",
        ]
    )
    + "\n}",
    tests[tests.index("class RunnerTests"):].replace(": XCTestCase", ""),
    "let tests = RunnerTests()",
]
for name in re.findall(r"func (test\w+)\(", tests):
    source.append(f'tests.{name}(); print("PASS {name}")')
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
