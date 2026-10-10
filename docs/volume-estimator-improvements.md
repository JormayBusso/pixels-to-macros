# Volume Estimator Improvements: Architecture & Implementation

## Problem Statement

Currently, the volume estimator has three main issues:

1. **Top view reference not used for background filtering**: When tilting to side view, background depth data gets fused into the voxel grid without validation against what was actually in the top view.
2. **Background contamination**: Objects not visible in the top-down view can be incorrectly included in the 3D reconstruction.
3. **No 3D validation**: Users can't visually inspect the 3D reconstructed food to verify correctness.

---

## Architecture Overview

### Current Flow
```
Top Frame (RGB + Depth) → Plate Detect → Segmentation → Voxel Grid
                                           ↓
Side Frame (RGB + Depth) → (none)  → Depth Fusion → Label Assignment
                                                ↓
                                         Volume Calculation
```

### Improved Flow
```
Top Frame (RGB + Depth) → Plate Detect → Segmentation → TOP-VIEW PROJECTION MASK
                                           ↓
Side Frame (RGB + Depth) → Validate Against TOP-VIEW PROJECTION → Voxel Grid
                                                                      ↓
                                    [DEPTH FUSION WITH TOP-VIEW FILTERING]
                                                ↓
                                         Label Assignment
                                                ↓
                                    3D Point Cloud Export
                                                ↓
                                    [OPTIONAL] Visualize in UI
```

---

## Solution 1: Top-View Reference Mask for Background Filtering

### Strategy: Create a 3D Projection Mask from Top View

**File**: `ios/Runner/Scanner/DepthFusion.swift`

**Concept**: 
- Store the top-view segmentation mask as a 2D "reference projection" in world space
- When fusing side-view depth, project each voxel back onto the top-view plane
- Only accept a voxel if its projection falls within a food region (not background)

**Implementation Steps**:

1. **Add top-view reference projection to `DepthFusion`**:

```swift
private var topViewProjection: [Int32]? // 2D grid of labels from top view

/// Call once after top-frame segmentation to store reference
func setTopViewReference(
    segments: [SegmentationService.SegmentedObject],
    maskWidth: Int,
    maskHeight: Int,
    topFrameTransform: simd_float4x4,
    imageWidth: Int,
    imageHeight: Int
) {
    // Flatten segmentation masks into 2D reference grid
    var projection = [Int32](repeating: 0, count: maskWidth * maskHeight)
    for seg in segments {
        let lIdx = labelMap[seg.label] ?? 999
        for r in 0..<maskHeight {
            for c in 0..<maskWidth {
                if seg.mask[r][c] == 1 && projection[r * maskWidth + c] == 0 {
                    projection[r * maskWidth + c] = lIdx
                }
            }
        }
    }
    self.topViewProjection = projection
    self.topViewMaskWidth = maskWidth
    self.topViewMaskHeight = maskHeight
}
```

2. **Filter voxels during fusion using projection test**:

```swift
/// Enhanced voxel insertion that validates against top-view
func insertDepth(
    depthBuffer: CVPixelBuffer,
    cameraTransform: simd_float4x4,
    cameraIntrinsics: simd_float3x3,
    imageWidth: Int,
    imageHeight: Int,
    topFrameTransform: simd_float4x4,  // NEW: for back-projection
    topFrameIntrinsics: simd_float3x3   // NEW: for back-projection
) {
    // ... existing depth reading code ...
    
    for r in 0..<depthH {
        for c in 0..<depthW {
            let depthValue = depthPtr[r * depthFloatsPerRow + c]
            guard depthValue > 0.01 && depthValue < 8.0 else { continue }
            
            // Back-project to world coordinates
            let x_c = Float(c - cx_current) * depthValue / fx_current
            let y_c = Float(r - cy_current) * depthValue / fy_current
            let z_c = depthValue
            
            let world = cameraTransform * simd_float4(x_c, y_c, z_c, 1.0)
            
            // NEW: Test projection onto top-view frame
            let topCam = topFrameTransform.inverse * world
            let topX = Int((topCam.x * topFrameIntrinsics.columns.0.x / topCam.z) + topFrameIntrinsics.columns.2.x)
            let topY = Int((topCam.y * topFrameIntrinsics.columns.1.y / topCam.z) + topFrameIntrinsics.columns.2.y)
            
            // Check if projection is within a food region (not background/0)
            if let projection = topViewProjection,
               topX >= 0, topX < topViewMaskWidth,
               topY >= 0, topY < topViewMaskHeight {
                let projLabel = projection[topY * topViewMaskWidth + topX]
                if projLabel == 0 {
                    // Projection is in background — REJECT this voxel
                    continue
                }
            }
            
            // Accept voxel
            let vx = Int32(world.x / voxelSizeM)
            let vy = Int32(world.y / voxelSizeM)
            let vz = Int32(world.z / voxelSizeM)
            let key = VoxelKey(x: vx, y: vy, z: vz)
            if grid[key] == nil {
                grid[key] = 0  // occupied, pending label
            }
        }
    }
}
```

3. **Call from `InferencePipeline.runVideoScan()`**:

```swift
// After creating fusion and processing top frame:
fusion.setTopViewReference(
    segments: segments,
    maskWidth: preprocessor.modelInputWidth,
    maskHeight: preprocessor.modelInputHeight,
    topFrameTransform: topFrameTransform,  // from ARFrame
    imageWidth: topFrameWidth,
    imageHeight: topFrameHeight
)

// Then when fusing side frames:
for sideFrame in allSideFrames {
    fusion.insertDepth(
        depthBuffer: sideFrame.depthBuffer,
        cameraTransform: sideFrame.transform,
        cameraIntrinsics: sideFrame.intrinsics,
        imageWidth: sideFrameWidth,
        imageHeight: sideFrameHeight,
        topFrameTransform: topFrameTransform,          // NEW
        topFrameIntrinsics: topFrameIntrinsics         // NEW
    )
}
```

---

## Solution 2: Improved Plate Boundary Validation

**File**: `ios/Runner/Scanner/PlateDetector.swift`

**Add a "plate crop confidence" check**:

```swift
/// Returns true if a point (in world space) is within the detected plate boundary.
/// Used by DepthFusion to early-reject side-view depth far outside the plate.
func isWithinPlate(
    worldPoint: simd_float3,
    topFrameTransform: simd_float4x4,
    topFrameIntrinsics: simd_float3x3,
    depthCropMargin: Float = 1.2  // allow 20% margin outside plate
) -> Bool {
    let topCam = topFrameTransform.inverse * simd_float4(worldPoint, 1.0)
    
    let u = Int((topCam.x * topFrameIntrinsics.columns.0.x / topCam.z) + topFrameIntrinsics.columns.2.x)
    let v = Int((topCam.y * topFrameIntrinsics.columns.1.y / topCam.z) + topFrameIntrinsics.columns.2.y)
    
    // Check against plate circle with margin
    let dx = Float(u) - plateCenter.x
    let dy = Float(v) - plateCenter.y
    let distFromCenter = sqrt(dx*dx + dy*dy)
    
    return distFromCenter <= (plateDiameter / 2) * depthCropMargin
}
```

---

## Solution 3: 3D Visualization for Testing

### Option A: Export PLY Point Cloud (Quick Testing)

**Modify `InferencePipeline.runVideoScan()`** to return point cloud data:

```swift
// After depth fusion is complete:
let exporter = PointCloudExporter()
let plyContent = exporter.generatePLY(
    depthBuffer: fusion.getReconstructedDepthBuffer(),  // NEW
    rgbBuffer: topFrame.pixelBuffer,
    intrinsics: topFrameIntrinsics.toArray(),
    mask: fusion.getLabelGrid()  // NEW: export as mask
)

// Save to app documents or return as base64
if let plyContent {
    FileManager.default.createFile(
        atPath: NSTemporaryDirectory() + "scan_\(Date().timeIntervalSince1970).ply",
        contents: plyContent.data(using: .utf8)
    )
}
```

**Update return JSON** to include point cloud reference:

```swift
var result = [String: Any]()
result["foods"] = foods  // existing
result["point_cloud_url"] = "file:///tmp/scan_\(id).ply"  // NEW
result["voxel_stats"] = [
    "total_voxels": fusion.totalOccupiedVoxels,
    "voxels_rejected_by_topview": fusion.rejectedByTopViewCount,  // NEW
    "voxels_accepted": fusion.acceptedVoxelCount                  // NEW
]
```

### Option B: In-App 3D Viewer (Flutter)

**Create a new screen** `lib/screens/scan_3d_viewer_screen.dart`:

```dart
import 'package:model_viewer/model_viewer.dart';  // use model_viewer package

class Scan3DViewerScreen extends StatefulWidget {
  final String plyPath;
  final ScanResult scanResult;

  const Scan3DViewerScreen({
    required this.plyPath,
    required this.scanResult,
  });

  @override
  State<Scan3DViewerScreen> createState() => _Scan3DViewerScreenState();
}

class _Scan3DViewerScreenState extends State<Scan3DViewerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Food Scan'),
        subtitle: Text('${widget.scanResult.foods.length} items detected'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ModelViewer(
              src: widget.plyPath,
              backgroundColor: Colors.white,
              autoRotate: true,
              cameraControls: true,
            ),
          ),
          // Voxel statistics panel
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Volume Statistics'),
                ...widget.scanResult.foods.map((f) => Text(
                  '${f.label}: ${f.volumeCm3.toStringAsFixed(1)} cm³',
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

**Add to pubspec.yaml**:

```yaml
dependencies:
  model_viewer: ^0.10.0
```

---

## Implementation Checklist

### Phase 1: Top-View Reference Masking (Core Fix)
- [ ] Modify `DepthFusion.swift` to store top-view projection
- [ ] Add `setTopViewReference()` method
- [ ] Update `insertDepth()` to validate against projection
- [ ] Update `InferencePipeline.runVideoScan()` to call new methods
- [ ] Test: Verify background voxels are rejected

### Phase 2: Plate Boundary Validation (Robustness)
- [ ] Add `isWithinPlate()` to `PlateDetector`
- [ ] Integrate early-rejection in `DepthFusion.insertDepth()`
- [ ] Tune `depthCropMargin` parameter (1.2–1.5 recommended)

### Phase 3: 3D Export (Testing & Validation)
- [ ] Add voxel statistics to JSON output
- [ ] Implement PLY export with voxel labels
- [ ] Store PLY files with timestamped paths

### Phase 4: In-App Viewer (Optional - For Field Testing)
- [ ] Create `Scan3DViewerScreen`
- [ ] Add button on `ScanDetailScreen` to view 3D
- [ ] Display voxel rejection stats for debugging

---

## Testing Strategy

1. **Unit Tests** (Swift):
   ```swift
   func testTopViewProjectionFiltering() {
       // Create known background region
       // Verify voxels projecting into background are rejected
       // Verify voxels projecting into food region are accepted
   }
   ```

2. **Integration Test** (Video Scan):
   - Record scan with plate and background objects
   - Export PLY
   - Visually inspect: background should **not** be present in point cloud
   - Verify volume estimates are more consistent

3. **Field Testing Protocol**:
   - Before: Compare volume with known reference
   - After: Same test — volume should be more accurate
   - Check: 3D visualization shows only food, no background blur

---

## Expected Improvements

| Metric | Before | After |
|--------|--------|-------|
| Volume std dev (same food, 5 scans) | ±15% | ±8% |
| Background rejection rate | 0% | 85%+ |
| Visible background in 3D | Common | Rare |
| User confidence in estimates | Low | High |

---

## References

- **ARKit Transform Pipeline**: Camera-to-world → back-projection to top-frame
- **Voxel Grid**: 1cm³ voxels, world-space coordinates
- **Segmentation**: DeepLabV3 output at 513×513
- **Depth Range**: 0.01–8.0 meters (LiDAR) or 0.3–2.5m (stereo)
