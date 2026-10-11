import Flutter
import UIKit
import XCTest
import simd
@testable import Runner

class RunnerTests: XCTestCase {

  func testPantryUIKitDecoderNormalizesRotatedImageAndRejectsMissingFile() throws {
    XCTAssertNil(ScannerPlugin.pantryImageBuffer(path: "/nonexistent/pantry_fixture.png"))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let source = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 2), format: format).image { ctx in
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
      UIColor.blue.setFill()
      ctx.fill(CGRect(x: 2, y: 0, width: 2, height: 2))
    }
    let upright = try XCTUnwrap(ScannerPlugin.pantryImageBuffer(image: source))
    let rotated = UIImage(cgImage: source.cgImage!, scale: 1, orientation: .right)
    let buffer = try XCTUnwrap(ScannerPlugin.pantryImageBuffer(image: rotated))
    XCTAssertEqual(CVPixelBufferGetWidth(upright), 4)
    XCTAssertEqual(CVPixelBufferGetHeight(upright), 2)
    XCTAssertEqual(CVPixelBufferGetWidth(buffer), 2)
    XCTAssertEqual(CVPixelBufferGetHeight(buffer), 4)
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let p = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    // Rotation preserves both observed colors, rather than stretching a crop.
    let first = [p[2], p[1], p[0]]
    let last = [p[3 * stride + 2], p[3 * stride + 1], p[3 * stride]]
    XCTAssertTrue(first == [255, 0, 0] || first == [0, 0, 255])
    XCTAssertTrue(last == [255, 0, 0] || last == [0, 0, 255])
    XCTAssertFalse(first == last)
  }

  func testStrictLidarUsesAssignedSourceHullAndMaskColorsIndependently() throws {
    func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> CVPixelBuffer {
      var buffer: CVPixelBuffer?
      XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
        kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
      CVPixelBufferLockBaseAddress(buffer!, [])
      let p = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
      let stride = CVPixelBufferGetBytesPerRow(buffer!)
      for r in 0..<64 { for c in 0..<64 {
        let i = r * stride + c * 4
        p[i] = blue; p[i + 1] = green; p[i + 2] = red; p[i + 3] = 255
      } }
      CVPixelBufferUnlockBaseAddress(buffer!, [])
      return buffer!
    }
    let topRGB = rgb(240, 30, 20), sideRGB = rgb(250, 250, 250)
    var topPose = matrix_identity_float4x4
    topPose.columns.1 = SIMD4(0, 0, -1, 0)
    topPose.columns.2 = SIMD4(0, 1, 0, 0)
    topPose.columns.3 = SIMD4(0, 0.5, 0, 1)
    var sidePose = matrix_identity_float4x4
    sidePose.columns.3 = SIMD4(0, 0.08, 0.5, 1)
    let k = simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(32, 32, 1)))
    let topFrame = FrameCaptureService.CapturedFrame(pixelBuffer: topRGB, depthBuffer: nil,
      cameraTransform: topPose, cameraIntrinsics: k, timestamp: 1)
    let sideFrame = FrameCaptureService.CapturedFrame(pixelBuffer: sideRGB, depthBuffer: nil,
      cameraTransform: sidePose, cameraIntrinsics: k, timestamp: 2)
    let top: [[UInt8]] = [[1, 1, 1, 1], [1, 0, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1]]
    let side = [[UInt8]](repeating: [1, 1, 1, 1], count: 4)
    let segment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1, mask: top,
      pixelCount: 15, centroid: (row: 1, col: 1), confidence: 0.9)
    var profile = hullProfile(side)
    profile.calibrationFailure = "monocular_fit_failed"
    let fusion = DepthFusion()
    fusion.assignLabels(segments: [segment], plateRect: CGRect(x: 0, y: 0, width: 1, height: 1),
      topFrameTransform: topPose, topFrameIntrinsics: k, maskWidth: 4, maskHeight: 4,
      imageWidth: 64, imageHeight: 64)
    fusion.setTablePlaneY(0)
    let result = try fusion.strictFoodObjects(segments: [segment], topFrame: topFrame,
      sideFrame: sideFrame, profiles: [profile], topColor: topRGB, sideColor: sideRGB)
    let object = try XCTUnwrap(result.objects.first)
    XCTAssertEqual(result.clusters.count, 1)
    XCTAssertTrue(result.clusters[0].sideCarved)
    XCTAssertEqual(object.volumeCm3, 3840, accuracy: 0.01)
    XCTAssertEqual(object.colors.count, object.vertices.count * 3)
    XCTAssertTrue(object.colors.contains(250)) // White side FOOD is retained.
    XCTAssertTrue(object.colors.contains(30)) // Top photo remains food-local.
    XCTAssertTrue(Food3DExporter.validDisplayObject(object))
    XCTAssertEqual(object.volumeCm3,
      DepthFusion.signedDisplayVolume(vertices: object.vertices, faces: object.faces), accuracy: 0.00001)
    let exported = try XCTUnwrap(Food3DExporter().export(objects: [object],
      baseName: "strict_lidar_\(Int(Date().timeIntervalSince1970 * 1000))", textureSource: nil,
      sideTextureSource: nil, topCoverage: nil, sideCoverage: nil))
    let sidecar = exported.deletingPathExtension().appendingPathExtension("p2mesh")
    let data = try Data(contentsOf: sidecar)
    var offset = 0
    func u32() -> Int {
      let n = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
      offset += 4
      return Int(UInt32(littleEndian: n))
    }
    XCTAssertEqual(u32(), 0x324D3250)
    XCTAssertEqual(u32(), 1)
    let nameLength = u32()
    offset += nameLength + 12
    let vertexCount = u32()
    XCTAssertEqual(vertexCount, object.vertices.count)
    offset += vertexCount * 12
    let storedColor = Array(data[offset..<offset + vertexCount * 4])
    for v in 0..<vertexCount {
      XCTAssertEqual(Array(storedColor[v * 4..<v * 4 + 3]), Array(object.colors[v * 3..<v * 3 + 3]))
      XCTAssertEqual(storedColor[v * 4 + 3], 255)
    }
    var depth: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4,
      kCVPixelFormatType_DepthFloat32, nil, &depth), kCVReturnSuccess)
    CVPixelBufferLockBaseAddress(depth!, [])
    let floats = CVPixelBufferGetBaseAddress(depth!)!.assumingMemoryBound(to: Float.self)
    let rowStride = CVPixelBufferGetBytesPerRow(depth!) / MemoryLayout<Float>.stride
    for r in 0..<4 { for c in 0..<4 { floats[r * rowStride + c] = 0.42 } }
    CVPixelBufferUnlockBaseAddress(depth!, [])
    fusion.integrate(depthBuffer: depth!, cameraTransform: topPose, cameraIntrinsics: k,
      imageWidth: 64, imageHeight: 64, stride: 1)
    fusion.assignLabels(segments: [segment], plateRect: CGRect(x: 0, y: 0, width: 1, height: 1),
      topFrameTransform: topPose, topFrameIntrinsics: k, maskWidth: 4, maskHeight: 4,
      imageWidth: 64, imageHeight: 64)
    XCTAssertTrue(fusion.totalOccupiedVoxels > 0)
    let depthCarved = try fusion.strictFoodObjects(segments: [segment], topFrame: topFrame,
      sideFrame: sideFrame, profiles: [profile], topColor: topRGB, sideColor: sideRGB)
    XCTAssertTrue(depthCarved.objects[0].volumeCm3 > 0)
    XCTAssertTrue(depthCarved.objects[0].volumeCm3 < object.volumeCm3)
    for profiles in [[], [profile, profile]] {
      do {
        _ = try fusion.strictFoodObjects(segments: [segment], topFrame: topFrame, sideFrame: sideFrame,
          profiles: profiles, topColor: topRGB, sideColor: sideRGB)
        XCTFail("unassigned or ambiguous side must fail")
      } catch InferencePipeline.PipelineError.sideViewRequired { }
    }
    profile.sideShared = true
    do {
      _ = try fusion.strictFoodObjects(segments: [segment], topFrame: topFrame, sideFrame: sideFrame,
        profiles: [profile], topColor: topRGB, sideColor: sideRGB)
      XCTFail("borrowed side must fail even on LiDAR")
    } catch InferencePipeline.PipelineError.sideViewRequired { }
    do {
      _ = try fusion.strictFoodObjects(segments: [segment], topFrame: topFrame, sideFrame: nil,
        profiles: [profile], topColor: topRGB, sideColor: sideRGB)
      XCTFail("missing side must fail even on LiDAR")
    } catch InferencePipeline.PipelineError.sideViewRequired { }
    let broken = DepthFusion.Food3DObject(id: object.id, label: object.label, instanceIndex: 0,
      vertices: object.vertices, faces: object.faces, colors: [], uvs: object.uvs,
      voxelCount: 0, volumeCm3: object.volumeCm3, preserveCreases: true)
    XCTAssertFalse(Food3DExporter.validDisplayObject(broken))
  }

  func testMeasuredDepthCeilingOnlyCarvesStrictVisibleFoodHull() throws {
    let top: [[UInt8]] = [[1, 1], [1, 1]]
    let side: [[UInt8]] = [[1, 1], [1, 1], [1, 1], [1, 1]]
    let profile = hullProfile(side)
    let estimator = MonocularVolumeEstimator()
    let baseline = try estimator.silhouetteHull(mask: top, profile: profile,
      widthCm: 2, depthCm: 2, heightCm: 4)
    let carved = try estimator.silhouetteHull(mask: top, profile: profile,
      widthCm: 2, depthCm: 2, heightCm: 4, measuredCeilingCm: { r, c in r == 0 && c == 0 ? 1 : nil })
    assertClosedHull(carved)
    XCTAssertEqual(carved.cellVolumeCm3, baseline.cellVolumeCm3 - 3, accuracy: 0.00001)
    XCTAssertFalse(hullContains(SIMD3(-0.005, 0.035, -0.005), carved))
    do {
      _ = try estimator.silhouetteHull(mask: top, profile: profile,
        widthCm: 2, depthCm: 2, heightCm: 4, measuredCeilingCm: { _, _ in 0 })
      XCTFail("empty measured intersection must retake")
    } catch MonocularVolumeEstimator.EstimateError.sideViewRequired { }
  }

  func testSourceMaskColorProjectionKeepsWhiteFoodAndRejectsHoleBackground() throws {
    let mask: [[UInt8]] = [[1, 1, 1, 1], [1, 0, 0, 1], [1, 0, 1, 1], [1, 1, 1, 1]]
    func image(_ color: [UInt8]) -> CVPixelBuffer {
      var buffer: CVPixelBuffer?
      XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
        kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
      CVPixelBufferLockBaseAddress(buffer!, [])
      let p = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
      let bytes = CVPixelBufferGetBytesPerRow(buffer!)
      for r in 0..<64 { for c in 0..<64 {
        let rgb: [UInt8] = mask[r / 16][c / 16] == 1 ? color : [255, 0, 0]
        let off = r * bytes + c * 4
        p[off] = rgb[2]; p[off + 1] = rgb[1]; p[off + 2] = rgb[0]; p[off + 3] = 255
      } }
      CVPixelBufferUnlockBaseAddress(buffer!, [])
      return buffer!
    }
    let top = image([250, 250, 250]), side = image([20, 40, 220])
    let frame = FrameCaptureService.CapturedFrame(pixelBuffer: top, depthBuffer: nil,
      cameraTransform: matrix_identity_float4x4, cameraIntrinsics: matrix_identity_float3x3, timestamp: 1)
    let object = try MonocularVolumeEstimator().sourceSilhouetteObject(
      id: "white_food", label: "fixture", instanceIndex: 0, mask: mask,
      widthCm: 4, depthCm: 4, heightCm: 4, topFrame: frame, colorFrame: top,
      sideColorFrame: side, profile: hullProfile(mask))
    XCTAssertEqual(object.colors.count, object.vertices.count * 3)
    var white = 0, blue = 0
    for i in stride(from: 0, to: object.colors.count, by: 3) {
      let rgb = Array(object.colors[i..<i + 3])
      XCTAssertTrue(rgb == [250, 250, 250] || rgb == [20, 40, 220])
      if rgb == [250, 250, 250] { white += 1 }
      if rgb == [20, 40, 220] { blue += 1 }
    }
    XCTAssertTrue(white > 0)
    XCTAssertTrue(blue > 0)
    XCTAssertTrue(Food3DExporter.validDisplayObject(object))
  }

  func testApproximateRecognitionNeverClaimsVolumeHeightOrModel() {
    let payload = InferencePipeline.approximateRecognitionPayload([
      ["label": "rice", "confidence": 0.8],
      ["label": "apple", "confidence": 0.7]
    ])
    XCTAssertEqual(payload.count, 2)
    for item in payload {
      XCTAssertEqual(item["scan_mode"] as? String, "approximate")
      XCTAssertEqual(item["volume_status"] as? String, "unavailable")
      XCTAssertEqual(item["volume_cm3"] as? Int, 0)
      XCTAssertEqual(item["volume_measured"] as? Bool, false)
      XCTAssertEqual(item["portion_status"] as? String, "unavailable")
      XCTAssertNil(item["height_cm"])
      XCTAssertNil(item["density_g_cm3"])
      XCTAssertNil(item["model_path"])
    }
    XCTAssertTrue(InferencePipeline.approximateRecognitionPayload([]).isEmpty)
  }

  func testContainerReviewIsExplicitAndPantryNeverCountsExteriorOrGenericLabels() {
    XCTAssertNotNil(InferencePipeline.containerReviewReason(labels: [("bowl", 0.9), ("rice", 0.9)]))
    XCTAssertNotNil(InferencePipeline.containerReviewReason(labels: [("coffee cup", 0.8)]))
    XCTAssertNil(InferencePipeline.containerReviewReason(labels: [("rice", 0.9), ("bowl", 0.3)]))
    XCTAssertNil(InferencePipeline.containerReviewReason(labels: [("white rice", 0.95)]))
    let error = ScannerPlugin.flutterError(for:
      InferencePipeline.PipelineError.containerPortionReviewRequired("unobserved_fill"))
    XCTAssertEqual(error.code, "CONTAINER_PORTION_REVIEW_REQUIRED")
    let segments = ["food", "bowl", "apple", "apple", "banana"].map {
      SegmentationService.SegmentedObject(label: $0, classIndex: 1, mask: [[1]],
        pixelCount: 1, centroid: (row: 0, col: 0), confidence: 0.9)
    }
    let payload = InferencePipeline.pantryRecognitionPayload(segments)
    XCTAssertEqual(payload.compactMap { $0["label"] as? String }, ["apple", "banana"])
    XCTAssertTrue(payload.allSatisfy { $0["count"] == nil && $0["volume_cm3"] == nil })
  }

  func testCapturedSupportingPlaneRejectsStaleFarVerticalAndOffFootprint() {
    var camera = matrix_identity_float4x4
    camera.columns.1 = SIMD4(0, 0, -1, 0)
    camera.columns.2 = SIMD4(0, 1, 0, 0)
    camera.columns.3 = SIMD4(0.3, 0.5, -0.2, 1)
    var plane = matrix_identity_float4x4
    plane.columns.3 = SIMD4(0.3, 0, -0.2, 1)
    let boundary: [SIMD3<Float>] = [
      SIMD3(-0.2, 0, -0.2), SIMD3(0.2, 0, -0.2),
      SIMD3(0.2, 0, 0.2), SIMD3(-0.2, 0, 0.2)]
    func measurement(_ pose: simd_float4x4, _ anchor: simd_float4x4,
                     age: Double = 0, horizontal: Bool = true) -> (meters: Float?, reason: String) {
      FrameCaptureService.SupportingPlane(transform: anchor, boundary: boundary)
        .distance(camera: pose, timestamp: 10, currentTimestamp: 10 + age, horizontal: horizontal)
    }
    XCTAssertEqual(measurement(camera, plane).meters!, 0.5, accuracy: 0.00001)
    XCTAssertEqual(measurement(camera, plane, age: 0.3).reason, "stale_capture_frame")
    XCTAssertEqual(measurement(camera, plane, age: -0.01).reason, "stale_capture_frame")
    XCTAssertEqual(measurement(camera, plane, horizontal: false).reason, "nonhorizontal_plane")
    var far = plane
    far.columns.3.y = -1
    XCTAssertEqual(measurement(camera, far).reason, "plane_distance_out_of_range")
    var outside = plane
    outside.columns.3.x += 0.5
    XCTAssertEqual(measurement(camera, outside).reason, "capture_ray_outside_plane_footprint")
    var level = matrix_identity_float4x4
    level.columns.3 = camera.columns.3
    XCTAssertEqual(measurement(level, plane).reason, "plane_ray_parallel_or_away")
    var invalid = camera
    invalid.columns.3.y = .nan
    XCTAssertEqual(measurement(invalid, plane).reason, "invalid_plane_or_camera_pose")
    XCTAssertEqual(FrameCaptureService.SupportingPlane(transform: plane, boundary: [])
      .distance(camera: camera, timestamp: 10, currentTimestamp: 10, horizontal: true).reason,
      "invalid_plane_boundary")
    XCTAssertEqual(FrameCaptureService.SupportingPlane(transform: plane, boundary: boundary)
      .distance(camera: camera, timestamp: 10, currentTimestamp: 10,
        horizontal: true, supportsFood: false).reason, "nonfood_support_classification")
  }

  func testScaleUsesPreprocessingCropAndDoesNotGateMeasuredReferencesByGuidedDistance() {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 1000, 500,
      kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    var pose = matrix_identity_float4x4
    pose.columns.1 = SIMD4(0, 0, -1, 0)
    pose.columns.2 = SIMD4(0, 1, 0, 0)
    pose.columns.3 = SIMD4(0, 0.1, 0, 1)
    let k = simd_float3x3(columns: (
      SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(500, 250, 1)))
    let frame = FrameCaptureService.CapturedFrame(pixelBuffer: buffer!, depthBuffer: nil,
      cameraTransform: pose, cameraIntrinsics: k, timestamp: 10)
    let estimator = MonocularVolumeEstimator()
    for crop in [CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
                 CGRect(x: 0.35, y: 0.2, width: 0.3, height: 0.6)] {
      let plate = PlateDetector.PlateResult(rect: crop, diameterPx: 0, detected: false)
      let scale = estimator.estimateScale(topFrame: frame, maskWidth: 640, maskHeight: 640,
        tableDistanceCm: 10, preprocessingPlate: plate)
      XCTAssertEqual(scale.source, "arkit_plane")
      XCTAssertEqual(640 / scale.columnPixelsPerCm, Double(crop.width) * 10, accuracy: 0.001)
      XCTAssertEqual(640 / scale.rowPixelsPerCm, Double(crop.height) * 5, accuracy: 0.001)
      XCTAssertTrue(scale.provenance.contains("cropSource=preprocessing"))
      let fallback = estimator.estimateScale(topFrame: frame, maskWidth: 640, maskHeight: 640,
        preprocessingPlate: plate)
      XCTAssertEqual(fallback.source, "intrinsic_guided")
      XCTAssertTrue(fallback.provenance.contains("guidedDistanceIsAssumption=true"))
      let invalid = estimator.estimateScale(topFrame: frame, maskWidth: 640, maskHeight: 640,
        tableDistanceCm: .nan, preprocessingPlate: plate)
      XCTAssertEqual(invalid.fallbackReason, "invalid_arkit_plane_distance")
    }
    let plate = PlateDetector.PlateResult(rect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1),
      diameterPx: 220, detected: true)
    let scale = estimator.estimateScale(topFrame: frame, maskWidth: 640, maskHeight: 640,
      tableDistanceCm: 10, preprocessingPlate: plate)
    // This valid plate was formerly discarded for disagreeing with assumed 22 cm.
    XCTAssertEqual(scale.source, "plate_diameter")
    XCTAssertEqual(scale.columnPixelsPerCm, 220 * 640 / (500 * 26), accuracy: 0.0001)
    let invalidCrop = PlateDetector.PlateResult(rect: .zero, diameterPx: 0, detected: false)
    XCTAssertEqual(estimator.estimateScale(topFrame: frame, maskWidth: 640, maskHeight: 640,
      preprocessingPlate: invalidCrop).fallbackReason, "invalid_preprocessing_crop")
  }

  func testOccupiedSideEndpointsDoNotMeasureEmptyBoundingBoxCorners() {
    let k = simd_float3x3(columns: (
      SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
    var top = matrix_identity_float4x4
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    top.columns.3 = SIMD4(0, 0.5, 0, 1)
    for angle in [Float(0), Float.pi / 2, Float.pi, Float.pi / 4] {
      var side = matrix_identity_float4x4
      side.columns.0 = SIMD4(cos(angle), sin(angle), 0, 0)
      side.columns.1 = SIMD4(-sin(angle), cos(angle), 0, 0)
      side.columns.3 = SIMD4(0, 0.04, 0.5, 1)
      for crop in [CGRect(x: 0, y: 0, width: 1, height: 1),
                   CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)] {
        let calibration = MonocularVolumeEstimator.PhotoCalibration(
          topTransform: top, topIntrinsics: k, topWidth: 200, topHeight: 100, topCrop: crop,
          sideTransform: side, sideIntrinsics: k, sideWidth: 200, sideHeight: 100,
          sideCrop: crop, tableY: 0)
        var mask = Array(repeating: Array(repeating: UInt8(0), count: 400), count: 400)
        // Two separated thin silhouette pieces, leaving a genuinely empty centre.
        for x in [Float(-0.025), Float(0.025)] {
          for step in 0...60 {
            let uv = calibration.sideUV(world: SIMD3(x, Float(step) / 1000, 0))!
            let r = Int(uv.y * 400), c = Int(uv.x * 400)
            if r >= 0, r < 400, c >= 0, c < 400 { mask[r][c] = 1 }
          }
        }
        let measurement = calibration.silhouetteHeight(mask: mask, through: SIMD3(0, 0, 0),
          verticalUsesColumns: abs(sin(angle)) >= abs(cos(angle)))
        XCTAssertEqual(measurement.reason, "side_pose_ray")
        // Maximum error: one mask pixel per endpoint after crop rasterization.
        XCTAssertEqual(measurement.heightCm!, 6, accuracy: 0.15)
      }
    }
  }

  func testTiltedTopPlaneScaleUsesRayProjectionNotVerticalDistanceOverFocalLength() {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 200, 100,
      kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    let angle = Float.pi / 6
    var pose = matrix_identity_float4x4
    pose.columns.1 = SIMD4(0, sin(angle), -cos(angle), 0)
    pose.columns.2 = SIMD4(0, cos(angle), sin(angle), 0)
    pose.columns.3 = SIMD4(0, 0.5, 0, 1)
    let k = simd_float3x3(columns: (
      SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
    let frame = FrameCaptureService.CapturedFrame(pixelBuffer: buffer!, depthBuffer: nil,
      cameraTransform: pose, cameraIntrinsics: k, timestamp: 10)
    let scale = MonocularVolumeEstimator().estimateScale(topFrame: frame,
      maskWidth: 200, maskHeight: 100, tableDistanceCm: 50,
      preprocessingPlate: PlateDetector.PlateResult(
        rect: CGRect(x: 0, y: 0, width: 1, height: 1), diameterPx: 0, detected: false))
    XCTAssertEqual(scale.source, "arkit_plane")
    XCTAssertEqual(scale.columnPixelsPerCm, Double(4 * cos(angle)), accuracy: 0.001)
    XCTAssertEqual(scale.rowPixelsPerCm, Double(4 * cos(angle) * cos(angle)), accuracy: 0.001)
  }

  func testLevelRayHeightAndAspectAgreeWithinOneSourcePixel() {
    var top = matrix_identity_float4x4
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    top.columns.3 = SIMD4(0, 0.5, 0, 1)
    let k = simd_float3x3(columns: (
      SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
    var side = matrix_identity_float4x4
    side.columns.3 = SIMD4(0, 0.04, 0.5, 1)
    let crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    let calibration = MonocularVolumeEstimator.PhotoCalibration(
      topTransform: top, topIntrinsics: k, topWidth: 200, topHeight: 100, topCrop: crop,
      sideTransform: side, sideIntrinsics: k, sideWidth: 200, sideHeight: 100,
      sideCrop: crop, tableY: 0)
    var mask = Array(repeating: Array(repeating: UInt8(0), count: 200), count: 100)
    for r in 42..<66 { for c in 88..<112 { mask[r][c] = 1 } }
    let segment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
      mask: mask, pixelCount: 576, centroid: (row: 54, col: 100), confidence: 1)
    var profile = InferencePipeline().makeSideProfile(segment: segment,
      axes: (false, .columns, false, false), imageWidth: 200, imageHeight: 100)!
    let measured = calibration.silhouetteHeight(mask: mask,
      through: SIMD3(0, 0, 0), verticalUsesColumns: false)
    XCTAssertEqual(measured.heightCm!, 6, accuracy: 0.0001)
    // A source pixel spans 0.25 cm at this focal length and measured depth.
    XCTAssertEqual(measured.heightCm!, profile.aspectRatio * 6, accuracy: 0.25)
    profile.calibrationFailure = "side_endpoint_ray_invalid"
    XCTAssertNil(MonocularVolumeEstimator().usableSideProfile(profile, for: "fixture", mode: .monocular))
  }

  func testCalibratedTiltedSideHeightStaysWithinProjectedEndpointPixelBounds() {
    var topPose = matrix_identity_float4x4
    topPose.columns.1 = SIMD4(0, 0, -1, 0)
    topPose.columns.2 = SIMD4(0, 1, 0, 0)
    topPose.columns.3 = SIMD4(0, 0.5, 0, 1)
    let k = simd_float3x3(columns: (
      SIMD3(300, 0, 0), SIMD3(0, 300, 0), SIMD3(400, 200, 1)))
    for pitch: Float in [-0.35, 0.35] {
      for roll: Float in [0, .pi / 2, .pi / 4] {
        for cropped in [false, true] {
          var pitchPose = matrix_identity_float4x4
          pitchPose.columns.1 = SIMD4(0, cos(pitch), sin(pitch), 0)
          pitchPose.columns.2 = SIMD4(0, -sin(pitch), cos(pitch), 0)
          var rollPose = matrix_identity_float4x4
          rollPose.columns.0 = SIMD4(cos(roll), sin(roll), 0, 0)
          rollPose.columns.1 = SIMD4(-sin(roll), cos(roll), 0, 0)
          var sidePose = pitchPose * rollPose
          sidePose.columns.3 = SIMD4(cropped ? 0.02 : 0, 0.03, 0.6, 1)
          let crop = cropped ? CGRect(x: 0.15, y: 0.05, width: 0.7, height: 0.9)
                             : CGRect(x: 0, y: 0, width: 1, height: 1)
          let calibration = MonocularVolumeEstimator.PhotoCalibration(
            topTransform: topPose, topIntrinsics: k, topWidth: 800, topHeight: 400,
            topCrop: CGRect(x: 0, y: 0, width: 1, height: 1),
            sideTransform: sidePose, sideIntrinsics: k, sideWidth: 800, sideHeight: 400,
            sideCrop: crop, tableY: 0)
          let maskWidth = 1600, maskHeight = 800
          var mask = Array(repeating: Array(repeating: UInt8(0), count: maskWidth), count: maskHeight)
          for x in 0...120 { for y in 0...120 {
            let world = SIMD3<Float>(Float(x) / 2000 - 0.03, Float(y) / 2000, 0)
            let uv = calibration.sideUV(world: world)!
            XCTAssertTrue(uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1)
            mask[Int(uv.y * Float(maskHeight))][Int(uv.x * Float(maskWidth))] = 1
          } }
          var pixelSpanM: Float = 0
          for r in mask.indices { for c in mask[r].indices where mask[r][c] != 0 {
            var low = Float.infinity, high = -Float.infinity
            for dr: Float in [0, 1] { for dc: Float in [0, 1] {
              let uv = SIMD2<Float>((Float(c) + dc) / Float(maskWidth), (Float(r) + dr) / Float(maskHeight))
              let world = calibration.sideWorld(uv: uv, through: SIMD3(0, 0, 0))!
              low = min(low, world.y); high = max(high, world.y)
            } }
            pixelSpanM = max(pixelSpanM, high - low)
          } }
          let height = calibration.silhouetteHeight(mask: mask, through: SIMD3(0, 0, 0),
            verticalUsesColumns: abs(sin(roll)) > abs(cos(roll)))
          XCTAssertEqual(height.reason, "side_pose_ray")
          let endpointRasterBoundCm = Double(pixelSpanM) * 200 + 0.0001
          XCTAssertEqual(height.heightCm!, 6, accuracy: endpointRasterBoundCm)
          print("PASS tiltedSide pitch=\(pitch) roll=\(roll) cropped=\(cropped) height=\(height.heightCm!) endpointRasterBoundCm=\(endpointRasterBoundCm)")
        }
      }
    }
  }

  func testFailedMonocularHeightPreservesExactLidarMatchedMaskAndDepthCarve() {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 400, 400,
      kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    var topPose = matrix_identity_float4x4
    topPose.columns.1 = SIMD4(0, 0, -1, 0)
    topPose.columns.2 = SIMD4(0, 1, 0, 0)
    topPose.columns.3 = SIMD4(0, 0.5, 0, 1)
    var sidePose = matrix_identity_float4x4
    sidePose.columns.3 = SIMD4(0, 0.03, 2.1, 1)
    let k = simd_float3x3(columns: (
      SIMD3(800, 0, 0), SIMD3(0, 800, 0), SIMD3(200, 200, 1)))
    let crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    let calibration = MonocularVolumeEstimator.PhotoCalibration(
      topTransform: topPose, topIntrinsics: k, topWidth: 400, topHeight: 400, topCrop: crop,
      sideTransform: sidePose, sideIntrinsics: k, sideWidth: 400, sideHeight: 400,
      sideCrop: crop, tableY: 0)
    var mask = Array(repeating: Array(repeating: UInt8(0), count: 400), count: 400)
    for r in 188..<212 { for c in 188..<212 { mask[r][c] = 1 } }
    mask[190][190] = 0
    let segment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
      mask: mask, pixelCount: 575, centroid: (row: 200, col: 200), confidence: 1)
    let pipeline = InferencePipeline()
    var profile = pipeline.makeSideProfile(segment: segment,
      axes: (false, .columns, false, false), imageWidth: 400, imageHeight: 400)!
    profile.topSegmentIndex = 0
    profile.sourceMask = mask
    profile.calibration = calibration
    let height = calibration.silhouetteHeight(mask: mask, through: SIMD3(0, 0, 0),
      verticalUsesColumns: false)
    XCTAssertNil(height.heightCm)
    XCTAssertEqual(height.reason, "side_endpoint_ray_invalid")
    profile.calibrationFailure = height.reason
    let estimator = MonocularVolumeEstimator()
    XCTAssertNil(estimator.usableSideProfile(profile, for: "fixture", mode: .monocular))
    XCTAssertEqual(estimator.usableSideProfile(profile, for: "fixture", mode: .lidar)?.sourceMask, mask)
    let failure = ScannerPlugin.flutterError(
      for: InferencePipeline.PipelineError.sideViewRequired(height.reason))
    XCTAssertEqual(failure.code, "SIDE_VIEW_REQUIRED")
    let topFrame = FrameCaptureService.CapturedFrame(pixelBuffer: buffer!, depthBuffer: nil,
      cameraTransform: topPose, cameraIntrinsics: k, timestamp: 10)
    let sideFrame = FrameCaptureService.CapturedFrame(pixelBuffer: buffer!, depthBuffer: nil,
      cameraTransform: sidePose, cameraIntrinsics: k, timestamp: 11)
    let side = pipeline.lidarSideSilhouette(sideFrame: sideFrame, topFrame: topFrame,
      profiles: [profile])!
    XCTAssertEqual(side.instanceMasks[0], mask)
    XCTAssertEqual(side.mask, mask)
    let world = SIMD3<Float>(0, 0.03, 0)
    let uv = calibration.sideUV(world: world)!
    XCTAssertEqual(mask[Int(uv.y * 400)][Int(uv.x * 400)], 1)
    let fusion = DepthFusion()
    fusion.setSideSilhouette(side)
    var observed = [DepthFusion.VoxelKey]()
    for x: Int32 in -2..<2 { for y: Int32 in 0..<10 { for z: Int32 in -2..<2 {
      observed.append(DepthFusion.VoxelKey(x: x, y: y, z: z))
    } } }
    let carved = fusion.carveBySideSilhouette(observed, id: "fixture", topIndex: 0)
    XCTAssertFalse(carved.keys.isEmpty)
    XCTAssertTrue(carved.voxelSizeM < 0.01)
    XCTAssertTrue(carved.keys.allSatisfy { Float($0.y + 1) * carved.voxelSizeM <= 0.065 })
    XCTAssertNil(pipeline.lidarSideSilhouette(sideFrame: sideFrame, topFrame: topFrame, profiles: []))
    var borrowed = profile
    borrowed.sideShared = true
    XCTAssertNil(pipeline.lidarSideSilhouette(sideFrame: sideFrame, topFrame: topFrame, profiles: [borrowed]))
    var empty = profile
    empty.sourceMask = [[0]]
    XCTAssertNil(pipeline.lidarSideSilhouette(sideFrame: sideFrame, topFrame: topFrame, profiles: [empty]))
    XCTAssertNil(estimator.usableSideProfile(nil, for: "fixture", mode: .monocular))
    XCTAssertNil(estimator.usableSideProfile(nil, for: "fixture", mode: .lidar))
    fusion.setSideSilhouette(nil)
    let missingSide = fusion.carveBySideSilhouette(observed, id: "fixture", topIndex: 0)
    XCTAssertEqual(missingSide.keys, observed)
    XCTAssertEqual(missingSide.voxelSizeM, 0.01, accuracy: 0.000001)
  }

  func testUncalibratedAspectOnlyAcceptsItsLevelAlignedGeometry() {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4,
      kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    func frame(_ pose: simd_float4x4) -> FrameCaptureService.CapturedFrame {
      FrameCaptureService.CapturedFrame(pixelBuffer: buffer!, depthBuffer: nil,
        cameraTransform: pose, cameraIntrinsics: matrix_identity_float3x3, timestamp: 10)
    }
    var top = matrix_identity_float4x4
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    let pipeline = InferencePipeline()
    XCTAssertNil(pipeline.uncalibratedAspectFailure(top: frame(top), side: frame(matrix_identity_float4x4)))
    var tilted = matrix_identity_float4x4
    tilted.columns.1 = SIMD4(0, cos(0.4), sin(0.4), 0)
    tilted.columns.2 = SIMD4(0, -sin(0.4), cos(0.4), 0)
    XCTAssertEqual(pipeline.uncalibratedAspectFailure(top: frame(top), side: frame(tilted)),
      "aspect_requires_level_side_and_top")
    var rolled = matrix_identity_float4x4
    rolled.columns.0 = SIMD4(0, 1, 0, 0)
    rolled.columns.1 = SIMD4(-1, 0, 0, 0)
    XCTAssertNil(pipeline.uncalibratedAspectFailure(top: frame(top), side: frame(rolled)))
  }

  func testPreprocessingCropRetainsRawTopLeftPixelOrientation() {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 8, 4,
      kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    CVPixelBufferLockBaseAddress(buffer!, [])
    let bytes = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer!)
    for r in 0..<4 { for c in 0..<8 {
      let offset = r * stride + c * 4
      bytes[offset] = r < 2 ? 20 : 220
      bytes[offset + 1] = c < 4 ? 30 : 230
      bytes[offset + 2] = 80
      bytes[offset + 3] = 255
    } }
    CVPixelBufferUnlockBaseAddress(buffer!, [])
    let output = FramePreprocessor().preprocess(pixelBuffer: buffer!,
      plateRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1))!
    CVPixelBufferLockBaseAddress(output, .readOnly)
    let actual = CVPixelBufferGetBaseAddress(output)!.assumingMemoryBound(to: UInt8.self)
    let outStride = CVPixelBufferGetBytesPerRow(output)
    XCTAssertEqual(actual[64 * outStride + 64 * 4], UInt8(20))
    XCTAssertEqual(actual[448 * outStride + 64 * 4], UInt8(220))
    XCTAssertEqual(actual[64 * outStride + 64 * 4 + 1], UInt8(30))
    XCTAssertEqual(actual[64 * outStride + 448 * 4 + 1], UInt8(230))
    CVPixelBufferUnlockBaseAddress(output, .readOnly)
  }

  func testSideRayRejectsDegenerateCropInsteadOfReturningZeroHeight() {
    var top = matrix_identity_float4x4
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    top.columns.3 = SIMD4(0, 0.5, 0, 1)
    var side = matrix_identity_float4x4
    side.columns.3 = SIMD4(0, 0.04, 0.5, 1)
    let k = simd_float3x3(columns: (
        SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
    let calibration = MonocularVolumeEstimator.PhotoCalibration(
        topTransform: top, topIntrinsics: k, topWidth: 200, topHeight: 100,
        topCrop: CGRect(x: 0, y: 0, width: 1, height: 1),
        sideTransform: side, sideIntrinsics: k, sideWidth: 200, sideHeight: 100,
        sideCrop: CGRect(x: 0, y: 0, width: 1, height: 0), tableY: 0)
    XCTAssertNil(calibration.sideWorld(uv: SIMD2(0.5, 0.2), through: SIMD3(0, 0, 0)))
  }

  func testCaptureCropPoseReplayPreservesMeasuredHeightAndExposesWrongCrop() {
    let k = simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(100, 50, 1)))
    for translated in [false, true] {
      let offset = translated ? SIMD3<Float>(0.2, 0.1, -0.3) : SIMD3<Float>(repeating: 0)
      var top = matrix_identity_float4x4
      top.columns.1 = SIMD4(0, 0, -1, 0)
      top.columns.2 = SIMD4(0, 1, 0, 0)
      top.columns.3 = SIMD4(offset.x, offset.y + 0.5, offset.z, 1)
      for rolled in [false, true] {
        var side = matrix_identity_float4x4
        if rolled {
          side.columns.0 = SIMD4(0, 1, 0, 0)
          side.columns.1 = SIMD4(-1, 0, 0, 0)
        }
        side.columns.3 = SIMD4(offset.x, offset.y + 0.04, offset.z + 0.5, 1)
        for cropped in [false, true] {
          let crop = cropped ? CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
            : CGRect(x: 0, y: 0, width: 1, height: 1)
          let calibration = MonocularVolumeEstimator.PhotoCalibration(
            topTransform: top, topIntrinsics: k, topWidth: 200, topHeight: 100, topCrop: crop,
            sideTransform: side, sideIntrinsics: k, sideWidth: 200, sideHeight: 100,
            sideCrop: crop, tableY: offset.y)
          let centre = calibration.topWorld(
            row: (0.58 - Double(crop.minY)) / Double(crop.height),
            column: (0.64 - Double(crop.minX)) / Double(crop.width))!
          XCTAssertEqual(centre.x, offset.x + 0.07, accuracy: 0.00001)
          XCTAssertEqual(centre.z, offset.z + 0.02, accuracy: 0.00001)
          let upper = centre + SIMD3<Float>(0, 0.06, 0)
          let bottomUV = calibration.sideUV(world: centre)!
          let upperUV = calibration.sideUV(world: upper)!
          let bottom = calibration.sideWorld(uv: bottomUV, through: centre)!
          let recovered = calibration.sideWorld(uv: upperUV, through: centre)!
          XCTAssertEqual(Double(abs(recovered.y - bottom.y)) * 100, 6, accuracy: 0.0001)
          let wrong = MonocularVolumeEstimator.PhotoCalibration(
            topTransform: top, topIntrinsics: k, topWidth: 200, topHeight: 100, topCrop: crop,
            sideTransform: side, sideIntrinsics: k, sideWidth: 200, sideHeight: 100,
            sideCrop: cropped
                ? CGRect(x: crop.minX, y: crop.minY + 0.1, width: crop.width, height: crop.height)
                : CGRect(x: 0, y: 0, width: 0.6, height: 0.6),
            tableY: offset.y)
          let misplaced = wrong.sideWorld(uv: upperUV, through: centre)!
          XCTAssertTrue(simd_length(misplaced - upper) > 0.02)
        }
      }
    }
  }

  func testRolledAsymmetricSideMaskReplayPreservesAxisAndProfile() {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA,
      nil, &buffer), kCVReturnSuccess)
    var top = matrix_identity_float4x4
    top.columns.1 = SIMD4(0, 0, -1, 0)
    top.columns.2 = SIMD4(0, 1, 0, 0)
    func frame(_ pose: simd_float4x4) -> FrameCaptureService.CapturedFrame {
      FrameCaptureService.CapturedFrame(pixelBuffer: buffer!, depthBuffer: nil,
        cameraTransform: pose, cameraIntrinsics: matrix_identity_float3x3, timestamp: 1)
    }
    var mask = Array(repeating: Array(repeating: UInt8(0), count: 7), count: 5)
    for c in 1...5 { mask[3][c] = 1 }
    for c in 3...5 { mask[2][c] = 1 }
    mask[1][5] = 1
    var rolledMask = Array(repeating: Array(repeating: UInt8(0), count: 5), count: 7)
    for r in 0..<5 { for c in 0..<7 { rolledMask[c][4 - r] = mask[r][c] } }
    var side = matrix_identity_float4x4
    let pipeline = InferencePipeline()
    let axes = pipeline.sideProfileAxes(sideFrame: frame(side), topFrame: frame(top))
    side.columns.0 = SIMD4(0, 1, 0, 0)
    side.columns.1 = SIMD4(-1, 0, 0, 0)
    let rolledAxes = pipeline.sideProfileAxes(sideFrame: frame(side), topFrame: frame(top))
    XCTAssertFalse(axes.verticalUsesColumns)
    XCTAssertTrue(rolledAxes.verticalUsesColumns)
    XCTAssertTrue(rolledAxes.verticalIndexIncreasesUp)
    XCTAssertEqual(axes.topAxis, rolledAxes.topAxis)
    XCTAssertEqual(axes.reversed, rolledAxes.reversed)
    let segment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
      mask: mask, pixelCount: 9, centroid: (row: 2, col: 3), confidence: 1)
    let rolledSegment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
      mask: rolledMask, pixelCount: 9, centroid: (row: 3, col: 2), confidence: 1)
    let profile = pipeline.makeSideProfile(segment: segment, axes: axes, imageWidth: 7, imageHeight: 5)!
    let rolledProfile = pipeline.makeSideProfile(segment: rolledSegment, axes: rolledAxes, imageWidth: 5, imageHeight: 7)!
    XCTAssertEqual(profile.normalizedHeights, rolledProfile.normalizedHeights)
    XCTAssertEqual(profile.normalizedBottoms, rolledProfile.normalizedBottoms)
    XCTAssertEqual(profile.normalizedTops, rolledProfile.normalizedTops)
    XCTAssertEqual(profile.aspectRatio, rolledProfile.aspectRatio, accuracy: 0.00001)
    XCTAssertTrue(profile.normalizedHeights.first! < profile.normalizedHeights.last!)
  }

  func testMaskProvenanceExposesIntervalGapAndEmptyCentre() {
    var mask = Array(repeating: Array(repeating: UInt8(0), count: 5), count: 5)
    mask[1][2] = 1; mask[3][2] = 1; mask[3][1] = 1; mask[3][3] = 1
    let summary = ScanMaskGeometry.maskProvenance(mask)
    XCTAssertTrue(summary.contains("gapColumns=1"))
    XCTAssertTrue(summary.contains("centrePixels=2"))
    let segment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
      mask: mask, pixelCount: 4, centroid: (row: 3, col: 2), confidence: 1)
    let profile = InferencePipeline().makeSideProfile(segment: segment,
      axes: (false, .columns, false, false), imageWidth: 5, imageHeight: 5)!
    // The existing interval representation spans an unobserved interior pixel.
    XCTAssertEqual(profile.normalizedHeights[1], 1)
    XCTAssertEqual(mask[2][2], 0)
    mask[1][2] = 0; mask[3][2] = 0
    let emptyCentre = ScanMaskGeometry.maskProvenance(mask)
    XCTAssertTrue(emptyCentre.contains("emptyColumns=1"))
    XCTAssertTrue(emptyCentre.contains("centrePixels=0"))
    XCTAssertFalse(summary == emptyCentre)
    mask[0][0] = 1
    XCTAssertTrue(ScanMaskGeometry.maskProvenance(mask).contains("edgePixels=1"))
    XCTAssertEqual(ScanMaskGeometry.maskProvenance([]), "mask=empty")
  }

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
    XCTAssertNotNil(MonocularVolumeEstimator().usableSideProfile(profile, for: "beef", mode: .monocular))
    XCTAssertFalse(profile.maskSnappedUV(SIMD2(-0.1, 0.5)).found)
    XCTAssertFalse(profile.maskSnappedUV(SIMD2(1.1, 0.5)).found)
    var borrowed = profile
    borrowed.sideShared = true
    XCTAssertNil(MonocularVolumeEstimator().usableSideProfile(borrowed, for: "beef", mode: .monocular))
  }

  func testMonocularMissingSideRequiresRetakeBeforeExport() throws {
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
    #if os(macOS)
    let docs = URL(fileURLWithPath: ".dart_tool/native-repeatability-exports", isDirectory: true)
    #else
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    #endif
    let before = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
    let profile = hullProfile([[1, 1], [1, 1]])
    var borrowed = profile
    borrowed.sideShared = true
    var wrongFood = profile
    wrongFood.topSegmentIndex = 1
    var empty = profile
    empty.sourceMask = [[0, 0], [0, 0]]
    var legacy = profile
    legacy.topSegmentIndex = nil
    let cases: [(FrameCaptureService.CapturedFrame?, [MonocularVolumeEstimator.SideProfile])] = [
      (nil, [profile]), (frame, []), (frame, [borrowed]), (frame, [wrongFood]),
      (frame, [empty]), (frame, [legacy]),
    ]
    for (side, profiles) in cases {
      do {
        _ = try MonocularVolumeEstimator().estimate(
          segments: [segment], topFrame: frame, sideFrame: side, sideProfiles: profiles,
          maskWidth: 64, maskHeight: 64, preprocessedRGB: rgb, tableDistanceCm: 50)
        XCTFail("strict missing/borrowed/empty/unassigned side must fail")
      } catch MonocularVolumeEstimator.EstimateError.sideViewRequired(let reason) {
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(ScannerPlugin.flutterError(
          for: InferencePipeline.PipelineError.sideViewRequired(reason)).code, "SIDE_VIEW_REQUIRED")
      }
    }
    let after = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
    XCTAssertEqual(Set(before), Set(after))
  }

  private func hullProfile(_ mask: [[UInt8]], reversed: Bool = false,
                           rows: Bool = false, up: Bool = false) -> MonocularVolumeEstimator.SideProfile {
    let count = mask.reduce(0) { $0 + $1.filter { $0 != 0 }.count }
    let segment = SegmentationService.SegmentedObject(label: "fixture", classIndex: 1,
      mask: mask, pixelCount: count, centroid: (row: 0, col: 0), confidence: 0.9)
    var profile = InferencePipeline().makeSideProfile(segment: segment,
      axes: (verticalUsesColumns: rows, topAxis: rows ? .rows : .columns,
             reversed: reversed, verticalIndexIncreasesUp: up),
      imageWidth: mask[0].count, imageHeight: mask.count)!
    profile.sourceMask = mask
    profile.topSegmentIndex = 0
    profile.verticalIndexIncreasesUp = up
    return profile
  }

  private func signedHullVolume(_ vertices: [SIMD3<Float>], _ faces: [Int]) -> Double {
    var volume = 0.0
    for i in stride(from: 0, to: faces.count, by: 3) {
      func vector(_ j: Int) -> SIMD3<Double> {
        let p = vertices[faces[i + j]]
        return SIMD3(Double(p.x), Double(p.y), Double(p.z))
      }
      volume += simd_dot(vector(0), simd_cross(vector(1), vector(2))) / 6
    }
    return volume * 1_000_000
  }

  private func assertClosedHull(_ hull: MonocularVolumeEstimator.SilhouetteHull) {
    XCTAssertFalse(hull.vertices.isEmpty)
    XCTAssertTrue(hull.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    var edges: [String: [Int]] = [:]
    var links = [[Int: Set<Int>]](repeating: [:], count: hull.vertices.count)
    for i in stride(from: 0, to: hull.faces.count, by: 3) {
      let face = Array(hull.faces[i..<i + 3])
      XCTAssertTrue(face.allSatisfy { $0 >= 0 && $0 < hull.vertices.count })
      let a = hull.vertices[face[0]], b = hull.vertices[face[1]], c = hull.vertices[face[2]]
      XCTAssertTrue(simd_length(simd_cross(b - a, c - a)) > 0)
      for j in 0..<3 {
        let a = face[j], b = face[(j + 1) % 3], c = face[(j + 2) % 3]
        edges["\(min(a, b)):\(max(a, b))", default: []].append(a < b ? 1 : -1)
        links[a][b, default: []].insert(c)
        links[a][c, default: []].insert(b)
      }
    }
    XCTAssertTrue(edges.values.allSatisfy { $0.count == 2 && $0.reduce(0, +) == 0 })
    for link in links {
      XCTAssertTrue(link.values.allSatisfy { $0.count == 2 })
      var seen: Set<Int> = [], queue = [link.keys.first!]
      while let p = queue.popLast() {
        if seen.insert(p).inserted { queue.append(contentsOf: link[p]!) }
      }
      XCTAssertEqual(seen.count, link.count)
    }
    let volume = signedHullVolume(hull.vertices, hull.faces)
    XCTAssertTrue(volume > 0)
    XCTAssertEqual(volume, hull.cellVolumeCm3, accuracy: max(1e-9, hull.cellVolumeCm3 * 0.00001))
  }

  private func hullContains(_ p: SIMD3<Float>, _ hull: MonocularVolumeEstimator.SilhouetteHull) -> Bool {
    // Solid-angle winding is independent of the production occupancy/mesher.
    var angle = 0.0
    for i in stride(from: 0, to: hull.faces.count, by: 3) {
      func v(_ j: Int) -> SIMD3<Double> {
        let a = hull.vertices[hull.faces[i + j]] - p
        return SIMD3(Double(a.x), Double(a.y), Double(a.z))
      }
      let a = v(0), b = v(1), c = v(2)
      let la = simd_length(a), lb = simd_length(b), lc = simd_length(c)
      angle += 2 * atan2(simd_dot(a, simd_cross(b, c)),
        la * lb * lc + simd_dot(a, b) * lc + simd_dot(b, c) * la + simd_dot(c, a) * lb)
    }
    return abs(angle) > 2 * Double.pi
  }

  func testMonocularSourcePixelHullPreservesHolesGapsAndAsymmetry() throws {
    let top: [[UInt8]] = [
      [1, 1, 1, 1], [1, 0, 0, 1], [1, 0, 1, 1], [1, 1, 1, 1],
    ]
    let side: [[UInt8]] = [
      [1, 0, 0, 0], [1, 1, 1, 0], [0, 1, 0, 0],
      [1, 1, 1, 1], [1, 0, 1, 1],
    ]
    for reversed in [false, true] {
      let hull = try MonocularVolumeEstimator().silhouetteHull(mask: top,
        profile: hullProfile(side, reversed: reversed), widthCm: 4, depthCm: 4, heightCm: 5)
      assertClosedHull(hull)
      var expectedCells = 0
      for z in 0..<4 { for x in 0..<4 { for y in 0..<5 {
        let sx = reversed ? 3 - x : x, sz = reversed ? 3 - z : z
        let expected = top[z][x] != 0 && side[4 - y][sx] != 0 && side[4 - y][sz] != 0
        if expected { expectedCells += 1 }
        let p = SIMD3<Float>((Float(x) + 0.43 - 2) / 100,
          (Float(y) + 0.37) / 100, (Float(z) + 0.41 - 2) / 100)
        XCTAssertEqual(hullContains(p, hull), expected)
      } } }
      XCTAssertEqual(hull.cellCount, expectedCells)
      XCTAssertEqual(hull.cellVolumeCm3, Double(expectedCells), accuracy: 1e-9)
      // Rolled side mask uses rows horizontally; gravity and matching reversal
      // are applied once and both transverse/matched silhouettes are unchanged.
      let rolled = (0..<4).map { c in (0..<5).map { r in side[r][c] } }
      let rolledHull = try MonocularVolumeEstimator().silhouetteHull(mask: top,
        profile: hullProfile(rolled, reversed: reversed, rows: true),
        widthCm: 4, depthCm: 4, heightCm: 5)
      assertClosedHull(rolledHull)
      XCTAssertEqual(rolledHull.cellVolumeCm3, hull.cellVolumeCm3, accuracy: 1e-9)
      XCTAssertEqual(rolledHull.vertices, hull.vertices)
      XCTAssertEqual(rolledHull.faces, hull.faces)
      let flipped = try MonocularVolumeEstimator().silhouetteHull(mask: top,
        profile: hullProfile(Array(side.reversed()), reversed: reversed, up: true),
        widthCm: 4, depthCm: 4, heightCm: 5)
      XCTAssertEqual(flipped.vertices, hull.vertices)
      XCTAssertEqual(flipped.faces, hull.faces)
    }
  }

  func testMonocularPixelBoundarySurfaceFansRemainManifold() throws {
    var masks: [[[UInt8]]] = []
    for bits in 1..<16 {
      let mask = (0..<2).map { r in (0..<2).map { c in UInt8((bits >> (r * 2 + c)) & 1) } }
      if mask[0].contains(1), mask[1].contains(1),
         mask[0][0] != 0 || mask[1][0] != 0,
         mask[0][1] != 0 || mask[1][1] != 0 { masks.append(mask) }
    }
    for top in masks { for side in masks {
      var cells = 0
      for z in 0..<2 { for x in 0..<2 { for y in 0..<2 {
        if top[z][x] != 0 && side[1 - y][x] != 0 && side[1 - y][z] != 0 { cells += 1 }
      } } }
      do {
        let hull = try MonocularVolumeEstimator().silhouetteHull(mask: top, profile: hullProfile(side),
          widthCm: 2, depthCm: 2, heightCm: 2)
        XCTAssertTrue(cells > 0)
        assertClosedHull(hull)
        XCTAssertEqual(hull.cellCount, cells)
        XCTAssertEqual(hull.cellVolumeCm3, Double(cells), accuracy: 1e-9)
      } catch MonocularVolumeEstimator.EstimateError.sideViewRequired {
        XCTAssertEqual(cells, 0)
      }
    } }
  }

  func testMonocularSourcePixelHullRetainsThinDisconnectedAndSubpixelIntervals() throws {
    let estimator = MonocularVolumeEstimator()
    for top: [[UInt8]] in [[[1, 0], [0, 1]], [[1, 0, 1]], [[1]]] {
      let hull = try estimator.silhouetteHull(mask: top, profile: hullProfile([[1, 1]]),
        widthCm: Double(top[0].count), depthCm: Double(top.count), heightCm: 0.00001)
      assertClosedHull(hull)
      XCTAssertEqual(Double(hull.vertices.map(\.y).max()!), 0.0000001, accuracy: 1e-14)
    }
    let fineSide: [[UInt8]] = [[1, 0, 1], [1, 1, 1]]
    let fine = try estimator.silhouetteHull(mask: [[1]], profile: hullProfile(fineSide),
      widthCm: 1, depthCm: 1, heightCm: 2)
    assertClosedHull(fine)
    XCTAssertEqual(fine.cellVolumeCm3, 1 + 4.0 / 9, accuracy: 1e-9)
    XCTAssertFalse(hullContains(SIMD3(0, 0.015, 0), fine))
    // >100 source columns exposed the old touched-cell acceleration expansion.
    var narrow = [[UInt8]](repeating: [UInt8](repeating: 1, count: 101), count: 2)
    narrow[0][50] = 0
    let large = try estimator.silhouetteHull(mask: narrow, profile: hullProfile([[1, 1]]),
      widthCm: 101, depthCm: 2, heightCm: 0.01)
    assertClosedHull(large)
    XCTAssertEqual(large.cellVolumeCm3, 201 * 0.01, accuracy: 1e-9)
    XCTAssertFalse(hullContains(SIMD3(0, 0.00005, -0.005), large))
  }

  func testMonocularEmptyIntersectionNeverInventsGeometry() throws {
    let top: [[UInt8]] = [[0, 1], [1, 0]]
    let profile = hullProfile([[1, 0], [0, 1]])
    // Side columns have mutually disjoint height support on occupied top cells.
    for mask in [top, [[0, 0], [0, 0]], [[1], []]] {
      do {
        _ = try MonocularVolumeEstimator().silhouetteHull(mask: mask, profile: profile,
          widthCm: 2, depthCm: 2, heightCm: 2)
        XCTFail("empty/invalid support must require retake")
      } catch MonocularVolumeEstimator.EstimateError.sideViewRequired(let reason) {
        XCTAssertFalse(reason.isEmpty)
      }
    }
  }

  func testMonocularFullEstimatorExportsDisplayedMeshVolume() throws {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 8, 8,
      kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    let rgb = try XCTUnwrap(buffer)
    CVPixelBufferLockBaseAddress(rgb, [])
    memset(CVPixelBufferGetBaseAddress(rgb), 100, CVPixelBufferGetBytesPerRow(rgb) * 8)
    CVPixelBufferUnlockBaseAddress(rgb, [])
    var camera = matrix_identity_float4x4
    camera.columns.1 = SIMD4(0, 0, -1, 0)
    camera.columns.2 = SIMD4(0, 1, 0, 0)
    camera.columns.3 = SIMD4(0, 0.5, 0, 1)
    let k = simd_float3x3(columns: (SIMD3(8, 0, 0), SIMD3(0, 8, 0), SIMD3(4, 4, 1)))
    let frame = FrameCaptureService.CapturedFrame(pixelBuffer: rgb, depthBuffer: nil,
      cameraTransform: camera, cameraIntrinsics: k, timestamp: 1)
    let mask: [[UInt8]] = [
      [1, 1, 1, 1, 1, 1, 1, 1], [1, 1, 0, 0, 0, 0, 1, 1],
      [1, 1, 0, 0, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1, 1, 1],
      [1, 1, 1, 1, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1, 1, 1],
      [1, 1, 1, 1, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1, 1, 1],
    ]
    let segment = SegmentationService.SegmentedObject(label: "apple", classIndex: 1,
      mask: mask, pixelCount: 58, centroid: (row: 3, col: 3), confidence: 0.9)
    var profile = hullProfile([[1, 0, 1, 1], [1, 1, 1, 1], [1, 1, 0, 1]])
    profile.measuredHeightCm = 0.003
    for sideRGB in [nil, rgb] as [CVPixelBuffer?] {
      let result = try MonocularVolumeEstimator().estimate(segments: [segment],
        topFrame: frame, sideFrame: frame, sideProfiles: [profile], maskWidth: 8, maskHeight: 8,
        preprocessedRGB: rgb, sidePreprocessedRGB: sideRGB, tableDistanceCm: 50,
        preprocessingPlate: PlateDetector.PlateResult(rect: CGRect(x: 0, y: 0, width: 1, height: 1),
          diameterPx: 0, detected: false))
      let row = try XCTUnwrap(result.objects.first)
      XCTAssertEqual(row["volume_source"] as? String, "display_mesh")
      XCTAssertEqual(row["volume_measured"] as? Bool, true)
      XCTAssertEqual(row["fallback_used"] as? Bool, false)
      XCTAssertTrue(FileManager.default.fileExists(atPath: result.modelPath))
      let url = URL(fileURLWithPath: result.modelPath).deletingPathExtension().appendingPathExtension("p2mesh")
      let data = try Data(contentsOf: url)
      var offset = 0
      func u32() -> Int {
        let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        return Int(UInt32(littleEndian: v))
      }
      func float() -> Float { Float(bitPattern: UInt32(u32())) }
      XCTAssertEqual(u32(), 0x324D3250)
      XCTAssertEqual(u32(), 1)
      let idLength = u32()
      offset += idLength
      offset += 12
      let count = u32()
      var vertices: [SIMD3<Float>] = []
      for _ in 0..<count { vertices.append(SIMD3(float(), float(), float())) }
      offset += count * 4
      let uvCount = u32()
      XCTAssertEqual(uvCount, count)
      offset += uvCount * 8
      let faceCount = u32()
      let faces = (0..<faceCount).map { _ in u32() }
      let meshVolume = signedHullVolume(vertices, faces)
      XCTAssertTrue(meshVolume > 0)
      XCTAssertEqual(meshVolume, row["volume_cm3"] as! Double, accuracy: 1e-9)
      XCTAssertEqual(meshVolume, row["mesh_volume_cm3"] as! Double, accuracy: 1e-9)
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
