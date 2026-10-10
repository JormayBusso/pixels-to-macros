//
// DepthFusion+TopViewFiltering.swift
// Enhancement to DepthFusion to validate side-view depth against top-view segmentation
//
// To integrate:
// 1. Add these properties and methods to DepthFusion.swift
// 2. Call setTopViewReference() after top-frame segmentation
// 3. Pass topFrameTransform + topFrameIntrinsics to insertDepth()
//

import simd
import Foundation

// MARK: – Top-View Reference Projection Storage

extension DepthFusion {
    
    /// 2D projection grid of top-view segmentation labels (for background filtering)
    private static var topViewProjection: [Int32]?
    private static var topViewMaskWidth: Int = 0
    private static var topViewMaskHeight: Int = 0
    
    /// Statistics for debugging
    struct DepthFusionStats {
        var totalVoxelsInserted: Int = 0
        var voxelsRejectedByTopView: Int = 0
        var voxelsAcceptedOutsidePlate: Int = 0
    }
    private var stats = DepthFusionStats()
    
    // MARK: – Set Top-View Reference
    
    /// Store the top-view segmentation as a 2D reference projection.
    /// Call this immediately after top-frame segmentation but before side-frame depth fusion.
    ///
    /// - Parameters:
    ///   - segments: Segmented food objects from top frame
    ///   - maskWidth: Model output width (e.g., 513)
    ///   - maskHeight: Model output height (e.g., 513)
    ///   - topFrameTransform: ARFrame.camera.transform for the top frame
    ///   - imageWidth: Full RGB buffer width
    ///   - imageHeight: Full RGB buffer height
    func setTopViewReference(
        segments: [SegmentationService.SegmentedObject],
        maskWidth: Int,
        maskHeight: Int,
        topFrameTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) {
        // Flatten segmentation masks into a single 2D reference grid
        // Any pixel covered by a food region gets the food's label
        var projection = [Int32](repeating: 0, count: maskWidth * maskHeight)
        
        for seg in segments {
            let lIdx = labelMap[seg.label] ?? Int32(labelMap.count + 1)
            
            for r in 0..<maskHeight {
                for c in 0..<maskWidth {
                    if seg.mask[r][c] == 1 && projection[r * maskWidth + c] == 0 {
                        // Mark with label (0 = background, >0 = food)
                        projection[r * maskWidth + c] = lIdx
                    }
                }
            }
        }
        
        DepthFusion.topViewProjection = projection
        DepthFusion.topViewMaskWidth = maskWidth
        DepthFusion.topViewMaskHeight = maskHeight
        
        print("DepthFusion: Top-view reference stored (\(maskWidth)×\(maskHeight))")
    }
    
    // MARK: – Enhanced Depth Insertion with Top-View Filtering
    
    /// Back-project a world-space 3D point onto the top-view frame.
    /// Returns (u, v) image coordinates in the top frame, or nil if behind camera.
    private func projectToTopView(
        worldPoint: simd_float3,
        topFrameTransform: simd_float4x4,
        topFrameIntrinsics: simd_float3x3
    ) -> (u: Int, v: Int)? {
        // Transform from world to top-frame camera space
        let topCamInv = topFrameTransform.inverse
        let homogeneousWorld = simd_float4(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)
        let camPoint = topCamInv * homogeneousWorld
        
        // Reject points behind the camera
        guard camPoint.z > 0.01 else { return nil }
        
        // Project to image plane using camera intrinsics
        let fx = topFrameIntrinsics.columns.0.x
        let fy = topFrameIntrinsics.columns.1.y
        let cx = topFrameIntrinsics.columns.2.x
        let cy = topFrameIntrinsics.columns.2.y
        
        let u = Int((camPoint.x * fx / camPoint.z) + cx)
        let v = Int((camPoint.y * fy / camPoint.z) + cy)
        
        return (u, v)
    }
    
    /// Test if a 3D world point is within the plate boundary detected in the top view.
    /// Used as a secondary filter for robustness.
    private func isWithinPlate(
        worldPoint: simd_float3,
        plateCenter: simd_float2,
        plateRadiusPx: Float,
        topFrameTransform: simd_float4x4,
        topFrameIntrinsics: simd_float3x3,
        marginFactor: Float = 1.3  // Allow 30% margin outside plate edge
    ) -> Bool {
        guard let (u, v) = projectToTopView(
            worldPoint: worldPoint,
            topFrameTransform: topFrameTransform,
            topFrameIntrinsics: topFrameIntrinsics
        ) else { return false }
        
        let dx = Float(u) - plateCenter.x
        let dy = Float(v) - plateCenter.y
        let distFromCenter = sqrt(dx * dx + dy * dy)
        
        let plateRadiusWithMargin = plateRadiusPx * marginFactor
        return distFromCenter <= plateRadiusWithMargin
    }
    
    // MARK: – Enhanced Voxel Insertion
    
    /// Enhanced version of insertDepth that validates voxels against top-view reference.
    ///
    /// Call this for each side frame during video scan.
    /// - Parameters:
    ///   - depthBuffer: Raw depth map from the frame
    ///   - cameraTransform: ARFrame.camera.transform for this frame
    ///   - cameraIntrinsics: Camera intrinsics for this frame
    ///   - imageWidth: Depth buffer width
    ///   - imageHeight: Depth buffer height
    ///   - topFrameTransform: ARFrame.camera.transform for the **top frame** (for reference)
    ///   - topFrameIntrinsics: Camera intrinsics for the top frame
    ///   - plateCenter: Plate center in top frame (pixels)
    ///   - plateRadiusPx: Plate radius in top frame (pixels)
    func insertDepthWithTopViewFiltering(
        depthBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageWidth: Int,
        imageHeight: Int,
        topFrameTransform: simd_float4x4,
        topFrameIntrinsics: simd_float3x3,
        plateCenter: simd_float2,
        plateRadiusPx: Float
    ) {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }
        
        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let depthBase = CVPixelBufferGetBaseAddress(depthBuffer) else { return }
        
        let depthPtr = depthBase.assumingMemoryBound(to: Float32.self)
        let depthFloatsPerRow = depthRowBytes / MemoryLayout<Float32>.stride
        
        let fx = cameraIntrinsics.columns.0.x
        let fy = cameraIntrinsics.columns.1.y
        let cx = cameraIntrinsics.columns.2.x
        let cy = cameraIntrinsics.columns.2.y
        
        let camInv = cameraTransform.inverse
        
        var voxelsInserted = 0
        var voxelsRejected = 0
        
        for row in 0..<depthH {
            for col in 0..<depthW {
                let depthValue = depthPtr[row * depthFloatsPerRow + col]
                
                // ── 1. Depth sanity check
                guard depthValue > 0.01 && depthValue < 8.0 else { continue }
                
                // ── 2. Back-project to camera space
                let x_cam = Float(col - Int(cx)) * depthValue / fx
                let y_cam = Float(row - Int(cy)) * depthValue / fy
                let z_cam = depthValue
                
                // ── 3. Transform to world coordinates
                let camPoint = simd_float4(x_cam, y_cam, z_cam, 1.0)
                let worldPoint = cameraTransform * camPoint
                let worldPos = simd_float3(worldPoint.x, worldPoint.y, worldPoint.z)
                
                // ── 4. Filter #1: Check if point projects into food region on top view
                if let projection = DepthFusion.topViewProjection {
                    if let (projU, projV) = projectToTopView(
                        worldPoint: worldPos,
                        topFrameTransform: topFrameTransform,
                        topFrameIntrinsics: topFrameIntrinsics
                    ) {
                        // Map to projection grid coordinates
                        let projIdx = projV * DepthFusion.topViewMaskWidth + projU
                        
                        if projIdx >= 0 && projIdx < projection.count {
                            let label = projection[projIdx]
                            
                            if label == 0 {
                                // Projection is in background → REJECT voxel
                                voxelsRejected += 1
                                stats.voxelsRejectedByTopView += 1
                                continue
                            }
                        }
                    }
                }
                
                // ── 5. Filter #2: Optional — reject if far outside plate boundary
                let withinPlate = isWithinPlate(
                    worldPoint: worldPos,
                    plateCenter: plateCenter,
                    plateRadiusPx: plateRadiusPx,
                    topFrameTransform: topFrameTransform,
                    topFrameIntrinsics: topFrameIntrinsics,
                    marginFactor: 1.3
                )
                
                if !withinPlate {
                    // Outside plate → could be background/reflections
                    // Log but don't strictly reject (might clip food)
                    stats.voxelsAcceptedOutsidePlate += 1
                }
                
                // ── 6. Accept voxel — add to grid
                let vx = Int32(worldPos.x / voxelSizeM)
                let vy = Int32(worldPos.y / voxelSizeM)
                let vz = Int32(worldPos.z / voxelSizeM)
                
                let key = VoxelKey(x: vx, y: vy, z: vz)
                if grid[key] == nil {
                    grid[key] = 0  // occupied, pending label
                    voxelsInserted += 1
                    stats.totalVoxelsInserted += 1
                }
            }
        }
        
        print("DepthFusion: Inserted \(voxelsInserted) voxels, rejected \(voxelsRejected) background voxels")
    }
    
    /// Retrieve fusion statistics for debugging/metrics reporting
    func getStats() -> DepthFusionStats {
        return stats
    }
    
    /// Clear statistics (call at start of new scan)
    func resetStats() {
        stats = DepthFusionStats()
    }
}

// MARK: – Integration Example (InferencePipeline.runVideoScan)

/*
 
 Replace the existing depth fusion code in InferencePipeline.runVideoScan() with:
 
 ─────────────────────────────────────────────────────────────────────────
 
 // Create fusion
 let fusion = DepthFusion()
 fusion.resetStats()
 
 // ── Top frame segmentation
 let segments = try segmentationService.segment(pixelBuffer: preprocessedRGB)
 
 // ── NEW: Set top-view reference for background filtering
 fusion.setTopViewReference(
     segments: segments,
     maskWidth: preprocessor.modelInputWidth,
     maskHeight: preprocessor.modelInputHeight,
     topFrameTransform: topFrameTransform,
     imageWidth: topFrameWidth,
     imageHeight: topFrameHeight
 )
 
 // ── Plate detection (needed for boundary checking)
 let plate = plateDetector.detect(in: topFrame.pixelBuffer)
 let plateCenter = simd_float2(
     Float(plate.rect.midX * Float(topFrameWidth)),
     Float(plate.rect.midY * Float(topFrameHeight))
 )
 let plateRadiusPx = Float(plate.diameterPx / 2)
 
 // ── Fuse depth from all recorded frames
 for frame in recorder.frames {
     // NEW: Use enhanced insertion with top-view filtering
     fusion.insertDepthWithTopViewFiltering(
         depthBuffer: frame.depthBuffer,
         cameraTransform: frame.transform,
         cameraIntrinsics: frame.intrinsics,
         imageWidth: depthFrameWidth,
         imageHeight: depthFrameHeight,
         topFrameTransform: topFrameTransform,
         topFrameIntrinsics: topFrameIntrinsics,
         plateCenter: plateCenter,
         plateRadiusPx: plateRadiusPx
     )
 }
 
 // ── Assign labels and calculate volumes
 fusion.assignLabels(
     segments: segments,
     plateRect: plate.rect,
     topFrameTransform: topFrameTransform,
     topFrameIntrinsics: topFrameIntrinsics,
     maskWidth: preprocessor.modelInputWidth,
     maskHeight: preprocessor.modelInputHeight,
     imageWidth: topFrameWidth,
     imageHeight: topFrameHeight
 )
 
 let volumes = fusion.allVolumes()
 
 // ── NEW: Include fusion statistics in result
 let stats = fusion.getStats()
 let debugInfo = [
     "total_voxels": stats.totalVoxelsInserted,
     "voxels_rejected_by_topview": stats.voxelsRejectedByTopView,
     "voxels_outside_plate": stats.voxelsAcceptedOutsidePlate,
     "background_rejection_rate": stats.voxelsRejectedByTopView > 0
         ? Double(stats.voxelsRejectedByTopView) / Double(stats.totalVoxelsInserted + stats.voxelsRejectedByTopView) * 100
         : 0
 ]
 
 // Build result with statistics
 var result: [String: Any] = [:]
 // ... existing fields ...
 result["fusion_stats"] = debugInfo
 
 ─────────────────────────────────────────────────────────────────────────
 
*/
