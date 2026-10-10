# Implementation Guide: Volume Estimator Improvements

## Quick Start

### 1. **Copy the Enhancement Files**

```bash
# Swift extension for depth fusion
cp DepthFusion+TopViewFiltering.swift ios/Runner/Scanner/

# Flutter 3D viewer screen
cp scan_3d_viewer_screen.dart lib/screens/
```

### 2. **Update `InferencePipeline.runVideoScan()`**

In `ios/Runner/Scanner/InferencePipeline.swift`, replace the depth fusion section:

**Before:**
```swift
// Fuse depth from all frames
for frame in recorder.frames {
    try fusion.insertDepth(...)
}
```

**After:**
```swift
// Store top-view reference for background filtering
fusion.setTopViewReference(
    segments: segments,
    maskWidth: preprocessor.modelInputWidth,
    maskHeight: preprocessor.modelInputHeight,
    topFrameTransform: topFrameTransform,
    imageWidth: CVPixelBufferGetWidth(topFrame.pixelBuffer),
    imageHeight: CVPixelBufferGetHeight(topFrame.pixelBuffer)
)

// Get plate boundary info
let plate = plateDetector.detect(in: topFrame.pixelBuffer)
let plateCenter = simd_float2(
    Float(plate.rect.midX * Float(CVPixelBufferGetWidth(topFrame.pixelBuffer))),
    Float(plate.rect.midY * Float(CVPixelBufferGetHeight(topFrame.pixelBuffer)))
)
let plateRadiusPx = Float(plate.diameterPx / 2)

// Fuse with top-view filtering
for frame in recorder.frames {
    fusion.insertDepthWithTopViewFiltering(
        depthBuffer: frame.depthBuffer,
        cameraTransform: frame.transform,
        cameraIntrinsics: frame.intrinsics,
        imageWidth: depthW,
        imageHeight: depthH,
        topFrameTransform: topFrameTransform,
        topFrameIntrinsics: topFrameIntrinsics,
        plateCenter: plateCenter,
        plateRadiusPx: plateRadiusPx
    )
}

// Get statistics
let stats = fusion.getStats()
```

### 3. **Update JSON Result to Include Stats**

In the same file, add to the result JSON:

```swift
// Build result JSON
var result: [[String: Any]] = []
for vol in volumes {
    var d = [String: Any]()
    d["label"] = vol.label
    d["volume_cm3"] = round(vol.volumeCm3 * 10) / 10
    d["pixel_count"] = vol.pixelCount
    result.append(d)
}

// NEW: Add fusion statistics
var response = [String: Any]()
response["foods"] = result
response["fusion_stats"] = [
    "total_voxels_inserted": stats.totalVoxelsInserted,
    "voxels_rejected_by_topview": stats.voxelsRejectedByTopView,
    "voxels_outside_plate": stats.voxelsAcceptedOutsidePlate,
    "background_rejection_rate": stats.voxelsRejectedByTopView > 0
        ? Double(stats.voxelsRejectedByTopView) / 
          Double(stats.totalVoxelsInserted + stats.voxelsRejectedByTopView) * 100
        : 0
]

return try JSONSerialization.data(withJSONObject: response).base64EncodedString()
```

### 4. **Update Dart Scan Result Provider**

In `lib/providers/scan_result_provider.dart`, update to parse fusion stats:

```dart
// After parsing volumes...
final fusionStats = rawResult['fusion_stats'] as Map<String, dynamic>? ?? {};

state = ScanResultState(
    foods: foods,
    fusionStats: fusionStats,  // NEW
);
```

### 5. **Add Button to Scan Detail Screen**

In `lib/screens/scan_detail_screen.dart`, add a button to view 3D:

```dart
// Add this to the action bar or a new section:
FilledButton.icon(
    onPressed: () {
        // Get the PLY path from your native bridge
        final plyPath = ref.read(scanResultProvider).plyPath;
        final scanResult = ref.read(scanResultProvider);
        final stats = ref.read(scanResultProvider).fusionStats;
        
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scan3DViewerScreen(
                plyPath: plyPath,
                scanResult: scanResult,
                fusionStats: stats,
            ),
        ));
    },
    icon: const Icon(Icons.view_in_ar),
    label: const Text('View 3D'),
)
```

### 6. **Export PLY Point Clouds**

Add to `InferencePipeline.runVideoScan()` after volume calculation:

```swift
// Export point cloud for testing
let exporter = PointCloudExporter()
if let plyContent = exporter.generatePLY(
    depthBuffer: <reconstructed_depth>,  // from fusion
    rgbBuffer: topFrame.pixelBuffer,
    intrinsics: topFrameIntrinsics.toArray(),
    mask: fusion.getLabelGrid()  // NEW method to export voxel labels
) {
    let timestamp = Date().timeIntervalSince1970
    let plyPath = NSTemporaryDirectory() + "scan_\(Int(timestamp)).ply"
    try? plyContent.write(toFile: plyPath, atomically: true, encoding: .utf8)
    
    response["ply_path"] = plyPath
}
```

---

## Key Metrics to Monitor

### 1. **Background Rejection Rate**
- **Good**: > 60% (many side-view depth pixels rejected because outside top-view)
- **OK**: 30-60% (moderate filtering)
- **Poor**: < 10% (little to no background filtering happening)

### 2. **Voxel Volume Consistency**
- **Before**: Same food scanned 5x: volumes vary ±15%
- **After Target**: Same food scanned 5x: volumes vary ±8%

### 3. **Visual Inspection**
- Export PLY and open in **MeshLab** (free) or **CloudCompare**
- **Good**: Clean food shape with no background
- **Poor**: Blurred background or platform visible around food

---

## Testing Protocol

### Test 1: Simple Food Item
```
Setup:
  - Place single rice bowl on white plate
  - Clean background (no clutter)
  - Good lighting
  
Scan & Evaluate:
  1. Record top view (phone pointed down)
  2. Tilt to side 2-3 times
  3. Check fusion stats: rejection rate should be high (80%+)
  4. Export PLY and inspect: should show only rice, no background
```

### Test 2: Multiple Items
```
Setup:
  - Place 3 items (e.g., chicken, rice, salad) on one plate
  - Position some items near plate edge
  
Scan & Evaluate:
  1. Record sweeping motion around plate
  2. Check: Each food detected and volume reasonable
  3. Fusion stats: rejection rate 60-80%
  4. PLY: All 3 foods visible, no background blur
```

### Test 3: Challenging Background
```
Setup:
  - Place plate on busy surface (patterned tablecloth, objects nearby)
  
Scan & Evaluate:
  1. Make sure to capture clean top view
  2. Tilt to show background
  3. Check fusion stats: should reject background pixels
  4. PLY inspection: background should NOT appear in point cloud
```

---

## Debugging Outputs

### Enable Logging

In `DepthFusion.swift`:
```swift
print("DepthFusion: Inserted \(voxelsInserted) voxels, rejected \(voxelsRejected) background voxels")
```

### Check Console Output

After scan completes:
```
DepthFusion: Top-view reference stored (513×513)
DepthFusion: Inserted 12450 voxels, rejected 3210 background voxels
```

### Interpret Results

```
Example 1 (Good):
  Total: 15660 voxels (12450 inserted + 3210 rejected)
  Rejection rate: 20.4%
  → Moderate background filtering, mostly accepted food voxels

Example 2 (Excellent):
  Total: 2840 voxels (600 inserted + 2240 rejected)
  Rejection rate: 78.9%
  → Strong filtering, side-view mostly captured background

Example 3 (Poor):
  Total: 8500 voxels (8450 inserted + 50 rejected)
  Rejection rate: 0.6%
  → Little filtering, mostly accepted pixels (possible background contamination)
```

---

## Common Issues & Fixes

### Issue 1: Rejection Rate Very Low (< 5%)
**Cause**: Top-view reference not being set correctly
**Fix**:
1. Check `setTopViewReference()` is called before side frame fusion
2. Verify segmentation output is valid (not empty)
3. Increase `topViewMaskWidth/Height` if using cropped model output

### Issue 2: Volumes Decrease After Update
**Cause**: More aggressive filtering is correctly removing background voxels
**Fix**:
1. This is expected! Volumes may be more accurate now
2. Compare against known ground truth (weigh food)
3. Check PLY visualization — is shape correct?

### Issue 3: Plate Boundary Cutoff (Food at Edge Gets Rejected)
**Cause**: Plate boundary validation too strict
**Fix**:
1. Increase `marginFactor` from 1.3 to 1.5 in `isWithinPlate()`
2. Or comment out plate boundary check entirely if not needed
3. Rely solely on top-view projection filtering

### Issue 4: PLY File Not Exported
**Cause**: Point cloud exporter called but no output generated
**Fix**:
1. Ensure fusion has valid voxels
2. Check that `PointCloudExporter.generatePLY()` receives valid depth/RGB
3. Verify write permissions to temp directory

---

## Performance Considerations

### Memory
- Top-view projection: ~261 KB (513×513 Int32)
- Voxel grid: ~50-200 MB depending on scan duration
- No significant change to existing memory usage

### CPU Time
- Back-projection per voxel: ~0.5 µs
- For 100k voxels: ~50 ms additional
- Negligible impact on overall pipeline (already multi-second)

### Optimization Tips
- Use `autoreleasepool` blocks for large loops
- Early-exit on invalid coordinates
- Pre-compute camera matrices outside loops

---

## Next Steps

1. **Phase 1 (This Sprint)**:
   - [ ] Implement top-view reference masking
   - [ ] Test with simple food items
   - [ ] Monitor rejection rates

2. **Phase 2 (Optional)**:
   - [ ] Add plate boundary validation
   - [ ] Fine-tune threshold parameters
   - [ ] Compare volumes before/after

3. **Phase 3 (Field Testing)**:
   - [ ] Deploy to beta testers
   - [ ] Collect PLY files for manual inspection
   - [ ] Gather feedback on volume accuracy

4. **Phase 4 (Production)**:
   - [ ] Remove debug logging
   - [ ] Hide fusion stats from UI (or make optional)
   - [ ] Monitor for any edge cases

---

## References

- **ARKit Coordinate Systems**: https://developer.apple.com/documentation/arkit/camera
- **Back-Projection Formula**: x = (u - cx) * z / fx
- **PLY Format**: http://paulbourke.net/dataformats/ply/
- **MeshLab**: https://www.meshlab.net/
- **CloudCompare**: https://www.cloudcompare.org/
