import Flutter
import UIKit
import XCTest
import simd
@testable import Runner

class RunnerTests: XCTestCase {

  func testCalibratedSideSplitUsesProjectedOrder() {
    var right = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.3, area: 1000, label: "beef", classIndex: 1)
    right.projectedLo = 0.65; right.projectedHi = 0.85; right.cameraDepth = 0.4
    var left = ScanMaskGeometry.SideMatchTop(lo: 0.7, hi: 0.9, area: 1000, label: "beef", classIndex: 1)
    left.projectedLo = 0.15; left.projectedHi = 0.35; left.cameraDepth = 0.4
    var extent = Array(repeating: 20, count: 100)
    extent[50] = 1
    let side = ScanMaskGeometry.SideMatchSide(lo: 0, hi: 99, area: 1000, label: "beef",
      classIndex: 1, centredness: 1, verticalExtent: extent)
    let matches = ScanMaskGeometry.matchSideSegments(tops: [right, left], sides: [side], horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [0, 1])
    XCTAssertEqual(matches.map(\.from), [51, 0])
    XCTAssertEqual(matches.map(\.to), [99, 50])
    XCTAssertTrue(matches.allSatisfy(\.isSplit))
  }

  func testCalibratedSideSplitSearchesBetweenProjectedCentres() {
    var left = ScanMaskGeometry.SideMatchTop(lo: 0, hi: 0.2, area: 1000, label: "beef", classIndex: 1)
    left.projectedLo = 0.05; left.projectedHi = 0.25; left.cameraDepth = 0.4
    var right = ScanMaskGeometry.SideMatchTop(lo: 0.6, hi: 0.8, area: 1000, label: "beef", classIndex: 1)
    right.projectedLo = 0.45; right.projectedHi = 0.65; right.cameraDepth = 0.4
    var extent = Array(repeating: 20, count: 100)
    extent[35] = 1; extent[50] = 1
    let side = ScanMaskGeometry.SideMatchSide(lo: 0, hi: 99, area: 1000, label: "beef",
      classIndex: 1, centredness: 1, verticalExtent: extent)
    let matches = ScanMaskGeometry.matchSideSegments(tops: [left, right], sides: [side], horizontalDim: 100)
    XCTAssertEqual(matches.map(\.from), [0, 36])
    XCTAssertEqual(matches.map(\.to), [35, 99])
  }

  func testSideSplitFallsBackOnlyForUncalibratedTop() {
    var left = ScanMaskGeometry.SideMatchTop(lo: 0, hi: 0.2, area: 1000, label: "beef", classIndex: 1)
    left.projectedLo = 0.4; left.projectedHi = 0.6; left.cameraDepth = 0.4
    let right = ScanMaskGeometry.SideMatchTop(lo: 0.6, hi: 0.8, area: 1000, label: "beef", classIndex: 1)
    var extent = Array(repeating: 20, count: 100)
    extent[50] = 1; extent[69] = 1
    let side = ScanMaskGeometry.SideMatchSide(lo: 0, hi: 99, area: 1000, label: "beef",
      classIndex: 1, centredness: 1, verticalExtent: extent)
    let calibrated = ScanMaskGeometry.matchSideSegments(tops: [left, right], sides: [side], horizontalDim: 100)
    XCTAssertEqual(calibrated.map(\.from), [0, 70])
    XCTAssertEqual(calibrated.map(\.to), [69, 99])
    left.projectedLo = nil; left.projectedHi = nil; left.cameraDepth = nil
    let fallback = ScanMaskGeometry.matchSideSegments(tops: [left, right], sides: [side], horizontalDim: 100)
    XCTAssertEqual(fallback.map(\.from), [0, 51])
    XCTAssertEqual(fallback.map(\.to), [50, 99])
  }

  func testLidarMirrorPreservesLongitudinalProfileAtTranslatedInstance() {
    let k = simd_float3x3(columns: (SIMD3(400, 0, 0), SIMD3(0, 400, 0), SIMD3(200, 200, 1)))
    var baseCamera = matrix_identity_float4x4
    baseCamera.columns.3 = SIMD4(0.1, 0.25, 1.5, 1)
    var yaw = matrix_identity_float4x4
    yaw.columns.0 = SIMD4(0, 0, -1, 0)
    yaw.columns.2 = SIMD4(1, 0, 0, 0)
    var roll = matrix_identity_float4x4
    roll.columns.0 = SIMD4(0, 1, 0, 0)
    roll.columns.1 = SIMD4(-1, 0, 0, 0)
    for pose in 0..<3 {
      let camera = pose == 0 ? baseCamera : yaw * baseCamera * (pose == 2 ? roll : matrix_identity_float4x4)
      var solid: [DepthFusion.VoxelKey] = []
      for x: Int32 in 20...31 {
        for z: Int32 in 40...41 {
          for y: Int32 in (x >= 28 ? [2, 8] : [2]) {
            solid.append(pose == 0 ? DepthFusion.VoxelKey(x: x, y: y, z: z)
              : DepthFusion.VoxelKey(x: z, y: y, z: -x - 1))
          }
        }
      }
      var mask = Array(repeating: Array(repeating: UInt8(0), count: 400), count: 400)
      for key in solid {
        let centre = SIMD3<Float>(Float(key.x) + 0.5, Float(key.y) + 0.5, Float(key.z) + 0.5) * 0.01
        let p = DepthFusion.projectToImage(centre, worldToCamera: camera.inverse,
          fx: 400, fy: 400, cx: 200, cy: 200)!
        for r in (Int(p.v) - 1)...(Int(p.v) + 1) {
          for c in (Int(p.u) - 1)...(Int(p.u) + 1) { mask[r][c] = 1 }
        }
      }
      let fusion = DepthFusion()
      fusion.setSideSilhouette(DepthFusion.SideSilhouette(mask: mask, instanceMasks: [0: mask],
        cropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        roiShape: .roundedRect(longAxisAlongColumns: pose != 2), cameraTransform: camera,
        cameraIntrinsics: k, imageWidth: 400, imageHeight: 400))
      XCTAssertFalse(fusion.carveBySideSilhouette(solid, id: "asymmetric-profile", topIndex: 0).keys.isEmpty)
    }
  }

  func testLidarMirrorAlsoRequiresReflectedPointInsideSideMask() {
    var camera = matrix_identity_float4x4
    camera.columns.3 = SIMD4(0.1, 0.25, 1.5, 1)
    let k = simd_float3x3(columns: (SIMD3(400, 0, 0), SIMD3(0, 400, 0), SIMD3(200, 200, 1)))
    let solid = [DepthFusion.VoxelKey(x: 30, y: 8, z: 10), DepthFusion.VoxelKey(x: 30, y: 8, z: 50)]
    let first = SIMD3<Float>(0.305, 0.085, 0.105)
    let p = DepthFusion.projectToImage(first, worldToCamera: camera.inverse,
      fx: 400, fy: 400, cx: 200, cy: 200)!
    var mask = Array(repeating: Array(repeating: UInt8(0), count: 400), count: 400)
    mask[Int(p.v)][Int(p.u)] = 1
    let fusion = DepthFusion()
    fusion.setSideSilhouette(DepthFusion.SideSilhouette(mask: mask, instanceMasks: [0: mask],
      cropRect: CGRect(x: 0, y: 0, width: 1, height: 1), roiShape: .roundedRect(longAxisAlongColumns: true),
      cameraTransform: camera, cameraIntrinsics: k, imageWidth: 400, imageHeight: 400))
    XCTAssertTrue(fusion.carveBySideSilhouette(solid, id: "mirror-outside", topIndex: 0).keys.isEmpty)
  }

  func testCoLocatedTopsNeverBorrowAnotherFoodsSideProfile() {
    let tops = [
      ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.9, area: 1000, label: "beef", classIndex: 1),
      ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.9, area: 900, label: "beef", classIndex: 1),
    ]
    let side = ScanMaskGeometry.SideMatchSide(lo: 10, hi: 89, area: 1000, label: "beef",
      classIndex: 1, centredness: 1, verticalExtent: Array(repeating: 20, count: 100))
    let matches = ScanMaskGeometry.matchSideSegments(tops: tops, sides: [side], horizontalDim: 100)
    XCTAssertTrue(matches.isEmpty)
  }

  func testCalibratedOcclusionOnlyAssignsVisiblePiece() {
    var near = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.9, area: 900, label: "beef", classIndex: 1)
    near.projectedLo = 0.1; near.projectedHi = 0.9; near.cameraDepth = 0.3
    var far = near
    far.cameraDepth = 0.5
    let side = ScanMaskGeometry.SideMatchSide(lo: 10, hi: 89, area: 1000, label: "beef",
      classIndex: 1, centredness: 1, verticalExtent: Array(repeating: 20, count: 100))
    let matches = ScanMaskGeometry.matchSideSegments(tops: [far, near], sides: [side], horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [1])
    XCTAssertEqual(matches.map(\.isShared), [false])
  }

  func testSmallCalibratedPieceKeepsItsOwnSideMask() {
    var large = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.6, area: 1000, label: "beef", classIndex: 1)
    large.projectedLo = 0.1; large.projectedHi = 0.6; large.cameraDepth = 0.4
    var small = ScanMaskGeometry.SideMatchTop(lo: 0.75, hi: 0.9, area: 50, label: "sausage", classIndex: 2)
    small.projectedLo = 0.75; small.projectedHi = 0.9; small.cameraDepth = 0.4
    let sides = [
      ScanMaskGeometry.SideMatchSide(lo: 10, hi: 59, area: 1000, label: "beef", classIndex: 1,
        centredness: 1, verticalExtent: Array(repeating: 20, count: 100)),
      ScanMaskGeometry.SideMatchSide(lo: 75, hi: 89, area: 50, label: "beef", classIndex: 1,
        centredness: 0.5, verticalExtent: Array(repeating: 5, count: 100)),
    ]
    let matches = ScanMaskGeometry.matchSideSegments(tops: [large, small], sides: sides, horizontalDim: 100)
    XCTAssertEqual(matches.map(\.sideIndex), [0, 1])
    XCTAssertEqual(matches.map(\.topIndex), [0, 1])
  }

  func testMissingSideProducesNoAssignment() {
    let top = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.9, area: 1000, label: "beef", classIndex: 1)
    XCTAssertTrue(ScanMaskGeometry.matchSideSegments(tops: [top], sides: [], horizontalDim: 100).isEmpty)
  }

  private func side(_ lo: Int, _ hi: Int, area: Int = 500, label: String = "apple",
                    centredness: Double = 1) -> ScanMaskGeometry.SideMatchSide {
    ScanMaskGeometry.SideMatchSide(lo: lo, hi: hi, area: area, label: label, classIndex: 1,
      centredness: centredness, verticalExtent: Array(repeating: 20, count: 100))
  }

  func testSingleFoodGetsUnionOfAllSideSegments() {
    let apple = ScanMaskGeometry.SideMatchTop(lo: 0.3, hi: 0.7, area: 1000, label: "apple", classIndex: 1)
    // Body split by a stem highlight into two pieces + a small off-centre
    // shadow piece with a different label: every one belongs to the food.
    let sides = [side(30, 49), side(52, 70), side(80, 90, area: 40, label: "chocolate", centredness: 0.2)]
    let matches = ScanMaskGeometry.matchSideSegments(tops: [apple], sides: sides, horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [0, 0, 0])
    XCTAssertEqual(matches.map(\.sideIndex), [0, 1, 2])
    XCTAssertEqual(matches.map(\.from), [30, 52, 80])
    XCTAssertEqual(matches.map(\.to), [49, 70, 90])
    XCTAssertTrue(matches.allSatisfy { $0.reason == "single_food_union" && !$0.isShared })
  }

  func testSingleFoodSingleSegmentKeepsFullSpan() {
    var apple = ScanMaskGeometry.SideMatchTop(lo: 0.3, hi: 0.7, area: 1000, label: "apple", classIndex: 1)
    apple.projectedLo = 0.0; apple.projectedHi = 0.05; apple.cameraDepth = 0.3
    let matches = ScanMaskGeometry.matchSideSegments(tops: [apple], sides: [side(40, 60)], horizontalDim: 100)
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].from, 40)
    XCTAssertEqual(matches[0].to, 60)
    XCTAssertEqual(matches[0].reason, "single_food")
  }

  func testMultiFoodMatchesSideSegmentsByOverlap() {
    let tops = [
      ScanMaskGeometry.SideMatchTop(lo: 0.6, hi: 0.9, area: 1000, label: "apple", classIndex: 1),
      ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.4, area: 800, label: "banana", classIndex: 2),
    ]
    let sides = [side(10, 39), side(60, 89)]
    let matches = ScanMaskGeometry.matchSideSegments(tops: tops, sides: sides, horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [0, 1])
    XCTAssertEqual(matches.map(\.sideIndex), [1, 0])
    XCTAssertTrue(matches.allSatisfy { $0.reason == "overlap" && !$0.isShared && !$0.isSplit })
  }

  func testMultiFoodFallsBackToHorizontalOrderWhenOverlapFails() {
    // Calibrated projections are off (no overlap with any side piece): pair
    // by left-to-right order instead of dropping either silhouette.
    var left = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.3, area: 1000, label: "apple", classIndex: 1)
    left.projectedLo = 0.0; left.projectedHi = 0.08; left.cameraDepth = 0.3
    var right = ScanMaskGeometry.SideMatchTop(lo: 0.6, hi: 0.8, area: 900, label: "pear", classIndex: 1)
    right.projectedLo = 0.1; right.projectedHi = 0.18; right.cameraDepth = 0.3
    let sides = [side(80, 95), side(55, 70)]
    let matches = ScanMaskGeometry.matchSideSegments(tops: [right, left], sides: sides, horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [0, 1])
    XCTAssertEqual(matches.map(\.sideIndex), [0, 1])
    XCTAssertTrue(matches.allSatisfy { $0.reason == "order" && !$0.isShared })
  }

  func testSplitSidePiecesAreUnionedForOneFoodInMultiFoodScan() {
    let tops = [
      ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.5, area: 1000, label: "apple", classIndex: 1),
      ScanMaskGeometry.SideMatchTop(lo: 0.7, hi: 0.9, area: 600, label: "egg", classIndex: 2),
    ]
    let sides = [side(10, 28), side(31, 50), side(70, 89)]
    let matches = ScanMaskGeometry.matchSideSegments(tops: tops, sides: sides, horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [0, 0, 1])
    XCTAssertEqual(matches.map(\.sideIndex), [0, 1, 2])

    var a = Array(repeating: Array(repeating: UInt8(0), count: 100), count: 10)
    var b = a
    for c in 10...28 { a[5][c] = 1 }
    for c in 31...50 { b[5][c] = 1; b[6][c] = 1 }
    let union = ScanMaskGeometry.sidePieceUnion(
      sideMasks: [a, b], assignments: matches.filter { $0.topIndex == 0 }, horizontalAlongRows: false)
    XCTAssertEqual(union.pixelCount, 19 + 40)
    XCTAssertEqual(union.piecePixels, [19, 40])
    XCTAssertEqual(union.mask[5][10], 1)
    XCTAssertEqual(union.mask[6][50], 1)
    XCTAssertEqual(union.mask[5][29], 0)
  }

  func testUnmatchedTopDoesNotBorrowNearestSidePiece() {
    var a = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.3, area: 1000, label: "apple", classIndex: 1)
    a.projectedLo = 0.1; a.projectedHi = 0.3; a.cameraDepth = 0.3
    var b = ScanMaskGeometry.SideMatchTop(lo: 0.6, hi: 0.8, area: 1000, label: "pear", classIndex: 1)
    b.projectedLo = 0.6; b.projectedHi = 0.8; b.cameraDepth = 0.3
    var c = ScanMaskGeometry.SideMatchTop(lo: 0.85, hi: 0.95, area: 400, label: "plum", classIndex: 1)
    c.projectedLo = 0.85; c.projectedHi = 0.95; c.cameraDepth = 0.6
    let matches = ScanMaskGeometry.matchSideSegments(
      tops: [a, b, c], sides: [side(10, 29), side(60, 79)], horizontalDim: 100)
    XCTAssertEqual(matches.map(\.topIndex), [0, 1])
    XCTAssertEqual(matches.map(\.sideIndex), [0, 1])
    XCTAssertTrue(matches.allSatisfy { !$0.isShared })
  }

  func testMissingSideDiagnosticAndLidarRetakeError() {
    XCTAssertEqual(InferencePipeline.monocularSideViewFailure(sideFrameCaptured: false, sideProfileCount: 0),
      "missing_side_capture")
    XCTAssertEqual(InferencePipeline.monocularSideViewFailure(sideFrameCaptured: true, sideProfileCount: 0),
      "no_side_food_mask")
    XCTAssertNil(InferencePipeline.monocularSideViewFailure(sideFrameCaptured: true, sideProfileCount: 1))
    let top = ScanMaskGeometry.SideMatchTop(lo: 0.1, hi: 0.9, area: 1000, label: "apple", classIndex: 1)
    XCTAssertTrue(ScanMaskGeometry.matchSideSegments(tops: [top], sides: [side(0, -1, area: 0)],
      horizontalDim: 100).isEmpty)

    let error = ScannerPlugin.flutterError(for: InferencePipeline.PipelineError.sideViewRequired("no_side_food_mask"))
    XCTAssertEqual(error.code, "SIDE_VIEW_REQUIRED")
    XCTAssertEqual(error.message, "Side photo did not show the food clearly; retake a level side photo.")
    XCTAssertEqual(error.details as? String, "no_side_food_mask")
    let estimatorError = MonocularVolumeEstimator.EstimateError.sideViewRequired("food#0_no_side_silhouette")
    XCTAssertEqual(estimatorError.errorDescription, InferencePipeline.PipelineError.sideViewRequiredMessage)
    XCTAssertEqual(ScannerPlugin.flutterError(for: InferencePipeline.PipelineError.noFoodDetected("x")).code,
      "NO_FOOD_DETECTED")
  }

  func testCapturedPhotoProjectionHonorsCropAndGravity() {
    var top = matrix_identity_float4x4
    top.columns.0 = SIMD4(1, 0, 0, 0)
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    top.columns.3 = SIMD4(0, 0.5, 0, 1)
    var side = matrix_identity_float4x4
    side.columns.3 = SIMD4(0, 0.2, 0.5, 1)
    let k = simd_float3x3(columns: (SIMD3(100, 0, 0), SIMD3(0, 100, 0), SIMD3(100, 50, 1)))
    let calibration = MonocularVolumeEstimator.PhotoCalibration(
      topTransform: top, topIntrinsics: k, topWidth: 200, topHeight: 100,
      topCrop: CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
      sideTransform: side, sideIntrinsics: k, sideWidth: 200, sideHeight: 100,
      sideCrop: CGRect(x: 0.25, y: 0, width: 0.5, height: 1), tableY: 0)
    let world = calibration.topWorld(row: 0.5, column: 0.7)!
    XCTAssertEqual(world.x, 0.1, accuracy: 0.0001)
    XCTAssertEqual(world.y, 0, accuracy: 0.0001)
    let uv = calibration.sideUV(world: world)!
    XCTAssertEqual(uv.x, 0.7, accuracy: 0.0001)
    XCTAssertEqual(uv.y, 0.9, accuracy: 0.0001)
    let recovered = calibration.sideWorld(uv: uv, through: world)!
    XCTAssertEqual(recovered.x, world.x, accuracy: 0.0001)
    XCTAssertEqual(recovered.y, world.y, accuracy: 0.0001)
  }

  func testThinFullSideProfileIsNotRejectedOrSnappedAcrossImage() {
    let profile = MonocularVolumeEstimator.SideProfile(
      label: "beef", classIndex: 1, topAxis: .columns, reversed: false,
      normalizedHeights: [1, 1], normalizedBottoms: [0, 0], normalizedTops: [1, 1],
      aspectRatio: 0.01, coverage: 0.0001, confidence: 0.9, pixelCount: 30,
      textureHorizontalUsesRows: false, textureHorizontalMin: 0, textureHorizontalMax: 1,
      textureVerticalMin: 0, textureVerticalMax: 0.01, sourceMask: [[1, 1]])
    XCTAssertNotNil(MonocularVolumeEstimator().usableSideProfile(profile, for: "beef"))
    XCTAssertFalse(profile.maskSnappedUV(SIMD2(-0.1, 0.5)).found)
    XCTAssertFalse(profile.maskSnappedUV(SIMD2(1.1, 0.5)).found)
    var borrowed = profile
    borrowed.sideShared = true
    XCTAssertNil(MonocularVolumeEstimator().usableSideProfile(borrowed, for: "beef"))
  }

  func testMonocularMissingSideExportsUnmeasuredTopMaskSheet() throws {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
      kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
      &buffer), kCVReturnSuccess)
    let rgb = try XCTUnwrap(buffer)
    CVPixelBufferLockBaseAddress(rgb, [])
    memset(CVPixelBufferGetBaseAddress(rgb), 100, CVPixelBufferGetBytesPerRow(rgb) * 64)
    CVPixelBufferUnlockBaseAddress(rgb, [])
    var camera = matrix_identity_float4x4
    camera.columns.1 = SIMD4(0, 0, -1, 0)
    camera.columns.2 = SIMD4(0, 1, 0, 0)
    camera.columns.3 = SIMD4(0, 0.5, 0, 1)
    let k = simd_float3x3(columns: (SIMD3(64, 0, 0), SIMD3(0, 64, 0), SIMD3(32, 32, 1)))
    let frame = FrameCaptureService.CapturedFrame(pixelBuffer: rgb, depthBuffer: nil,
      cameraTransform: camera, cameraIntrinsics: k, timestamp: 1)
    var mask = Array(repeating: Array(repeating: UInt8(0), count: 64), count: 64)
    for r in 16..<48 { for c in 16..<48 { mask[r][c] = 1 } }
    let segment = SegmentationService.SegmentedObject(label: "apple", classIndex: 1,
      mask: mask, pixelCount: 1024, centroid: (row: 32, col: 32), confidence: 0.9)
    for side in [nil, frame] as [FrameCaptureService.CapturedFrame?] {
      let result = try MonocularVolumeEstimator().estimate(
        segments: [segment], topFrame: frame, sideFrame: side, maskWidth: 64,
        maskHeight: 64, preprocessedRGB: rgb, tableDistanceCm: 50)
      let object = try XCTUnwrap(result.objects.first)
      XCTAssertEqual(object["scan_mode"] as? String, "monocular_top_only")
      XCTAssertEqual(object["volume_measured"] as? Bool, false)
      XCTAssertEqual(object["side_view_applied"] as? Bool, false)
      XCTAssertEqual(object["height_cm"] as? Double, 0)
      XCTAssertEqual(object["mesh_volume_cm3"] as? Double, 0)
      XCTAssertEqual(object["volume_cm3"] as? Double, 0)
      XCTAssertEqual(object["side_missing_reason"] as? String,
        side == nil ? "missing_capture" : "unmatched_occluded_or_invalid_mask")
      XCTAssertTrue(FileManager.default.fileExists(atPath: result.modelPath))
    }
  }

  /// 4×4×3 cm box at x,z ∈ [0, 4) cm, y ∈ [0, 3) cm on a table at y = 0, seen by
  /// a top camera 50 cm above and a level side camera 50 cm away. With NO
  /// fused depth, its fusion must rebuild the food only from the two masks.
  private func sparseDepthLidarFusion(withSide: Bool, tablePlane: Float?) -> DepthFusion {
    let k = simd_float3x3(columns: (SIMD3(400, 0, 0), SIMD3(0, 400, 0), SIMD3(200, 200, 1)))
    var top = matrix_identity_float4x4
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    top.columns.3 = SIMD4(0, 0.5, 0, 1)
    var side = matrix_identity_float4x4
    side.columns.3 = SIMD4(0.02, 0.015, 0.5, 1)
    func boxMask(_ camera: simd_float4x4) -> [[UInt8]] {
      var minU = Float.greatestFiniteMagnitude, maxU = -minU, minV = minU, maxV = -minU
      for x: Float in [0, 0.04] { for y: Float in [0, 0.03] { for z: Float in [0, 0.04] {
        let p = DepthFusion.projectToImage(SIMD3(x, y, z), worldToCamera: camera.inverse,
          fx: 400, fy: 400, cx: 200, cy: 200)!
        minU = min(minU, p.u); maxU = max(maxU, p.u); minV = min(minV, p.v); maxV = max(maxV, p.v)
      } } }
      var mask = Array(repeating: Array(repeating: UInt8(0), count: 400), count: 400)
      for r in Int(minV.rounded(.down))...Int(maxV.rounded(.down)) {
        for c in Int(minU.rounded(.down))...Int(maxU.rounded(.down)) { mask[r][c] = 1 }
      }
      return mask
    }
    let topMask = boxMask(top)
    let fusion = DepthFusion()
    fusion.assignLabels(
      segments: [SegmentationService.SegmentedObject(label: "apple", classIndex: 1, mask: topMask,
        pixelCount: topMask.reduce(0) { $0 + $1.filter { $0 != 0 }.count },
        centroid: (row: 200, col: 200), confidence: 0.9)],
      plateRect: CGRect(x: 0, y: 0, width: 1, height: 1), topFrameTransform: top,
      topFrameIntrinsics: k, maskWidth: 400, maskHeight: 400, imageWidth: 400, imageHeight: 400)
    fusion.setTablePlaneY(tablePlane)
    if withSide {
      let sideMask = boxMask(side)
      fusion.setSideSilhouette(DepthFusion.SideSilhouette(mask: sideMask, instanceMasks: [0: sideMask],
        cropRect: CGRect(x: 0, y: 0, width: 1, height: 1), roiShape: .roundedRect(longAxisAlongColumns: true),
        cameraTransform: side, cameraIntrinsics: k, imageWidth: 400, imageHeight: 400))
    }
    return fusion
  }

  func testLidarSparseDepthFoodUsesExactSideSilhouetteHull() {
    let fusion = sparseDepthLidarFusion(withSide: true, tablePlane: 0)
    let clusters = fusion.voxelClusters()
    XCTAssertTrue(fusion.lastUnresolvedFoods.isEmpty)
    XCTAssertEqual(clusters.count, 1)
    guard let cluster = clusters.first else { return }
    XCTAssertEqual(cluster.id, "apple_0")
    XCTAssertEqual(cluster.topSegmentIndex, 0)
    XCTAssertEqual(cluster.heightSource, .sideSilhouette)
    // Rasterized silhouette cones include the boundary pixels and perspective,
    // so the measured hull differs from the ideal box used to make the masks.
    XCTAssertEqual(cluster.voxelSizeM, 0.0025, accuracy: 0.000001)
    XCTAssertEqual(Set(cluster.voxelKeys.map(\.y)), Set((0..<13).map(Int32.init)))
    XCTAssertEqual(Set(cluster.voxelKeys.map(\.x)), Set((0..<17).map(Int32.init)))
    XCTAssertEqual(Set(cluster.voxelKeys.map(\.z)), Set((0..<17).map(Int32.init)))
    XCTAssertEqual(cluster.voxelKeys.count, 3593)
    XCTAssertEqual(cluster.volumeCm3, 56.140625, accuracy: 0.001)
  }

  func testLidarSparseDepthWithoutSideSilhouetteRequiresSideView() {
    let fusion = sparseDepthLidarFusion(withSide: false, tablePlane: 0)
    XCTAssertTrue(fusion.voxelClusters().isEmpty)
    XCTAssertEqual(fusion.lastUnresolvedFoods,
      [DepthFusion.UnresolvedFood(topIndex: 0, label: "apple", reason: "no_side_silhouette")])
    let food = fusion.lastUnresolvedFoods[0]
    let missing = InferencePipeline.lidarUnresolvedFailure(food, sideFrameCaptured: false, sideProfileCount: 0)
    let error = ScannerPlugin.flutterError(for: missing)
    XCTAssertEqual(error.code, "SIDE_VIEW_REQUIRED")
    XCTAssertEqual(error.details as? String, "lidar_food#0_insufficient_depth_missing_side_capture")
    let noMask = InferencePipeline.lidarUnresolvedFailure(food, sideFrameCaptured: true, sideProfileCount: 0)
    XCTAssertEqual(ScannerPlugin.flutterError(for: noMask).details as? String,
      "lidar_food#0_insufficient_depth_no_side_food_mask")
    let unmatched = DepthFusion.UnresolvedFood(topIndex: 1, label: "pear", reason: "unmatched_side_silhouette")
    XCTAssertEqual(ScannerPlugin.flutterError(for: InferencePipeline.lidarUnresolvedFailure(
      unmatched, sideFrameCaptured: true, sideProfileCount: 2)).details as? String,
      "lidar_food#1_insufficient_depth_no_side_silhouette")
  }

  func testLidarWithoutMeasuredSupportPlaneNeverInventsHeight() {
    let fusion = sparseDepthLidarFusion(withSide: true, tablePlane: nil)
    XCTAssertTrue(fusion.voxelClusters().isEmpty)
    XCTAssertEqual(fusion.lastUnresolvedFoods.map(\.reason), ["no_measured_support_plane"])
    let failure = InferencePipeline.lidarUnresolvedFailure(
      fusion.lastUnresolvedFoods[0], sideFrameCaptured: true, sideProfileCount: 1)
    guard case .model3DExportFailed(let reason) = failure else {
      return XCTFail("expected model3DExportFailed, got \(failure)")
    }
    XCTAssertEqual(reason, "no_measured_support_plane")
  }

}
