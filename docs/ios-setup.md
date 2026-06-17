# iOS Setup Guide — Pixels to Macros

## Prerequisites
- macOS 14+ with Xcode 16+
- Flutter SDK ≥ 3.22
- CocoaPods (`sudo gem install cocoapods`)
- iPhone 15 or newer connected via USB

## One-time setup

### 1. Generate the iOS project
```bash
cd /path/to/pixels-to-macros
flutter create . --org com.pixelstomacros --platforms ios
```

### 2. Replace AppDelegate.swift
The generated `ios/Runner/AppDelegate.swift` should be **replaced** with
the one in this repo (it registers `ScannerPlugin`).

### 3. Add Scanner source files + CoreML model
The `ios/Runner/Scanner/` folder already contains the native Swift files.
The fastest way to wire them (and the model) into the Xcode target is the
automated script:

```bash
gem install xcodeproj          # one-time
ruby scripts/add_scanner_files.rb
```

This adds every `Scanner/*.swift` file to the **Runner** target, links the
required frameworks (ARKit, RealityKit, SceneKit, Metal, CoreML, Vision,
CoreVideo, AVFoundation), sets the deployment target to iOS 17.0, and bundles
`FoodSegmentation.mlmodelc` as an app resource.

To do it manually instead:
1. Open `ios/Runner.xcworkspace` in Xcode.
2. Right-click the **Runner** group → **Add Files to "Runner"…**
3. Select the `Scanner/` folder. Ensure **"Create groups"** is checked.
4. Verify all Swift files are added to the **Runner** target.
5. Drag `ios/Runner/FoodSegmentation.mlmodelc` into the target's
   **Copy Bundle Resources** phase.

### 3a. Train & export the CoreML model (required)
The scanner needs a compiled segmentation model in the bundle. Train it, then
export and compile:

```bash
# Train (run enough epochs for a usable mIoU — the sample checkpoint is only a smoke test)
python training/train.py

# Export PyTorch → CoreML (.mlpackage)
python training/export_coreml.py --checkpoint training/output/best.pth

# Compile .mlpackage → .mlmodelc and place it in the bundle (macOS only)
xcrun coremlcompiler compile training/output/FoodSegmentation.mlpackage ios/Runner/
```

Without `FoodSegmentation.mlmodelc` in the bundle every scan fails with
"FoodSegmentation.mlmodelc not found in bundle".

### 4. Merge Info.plist entries
Open `ios/Runner/Info.plist` in Xcode and add these keys from
`Info-additions.plist`:

| Key | Value |
|-----|-------|
| `NSCameraUsageDescription` | Pixels to Macros uses the camera to scan your plate and estimate food calories. |
| `UIRequiredDeviceCapabilities` | `arkit`, `arm64` |

### 5. Set deployment target
In Xcode → Runner target → General → **Minimum Deployments** → set to **iOS 17.0**.

Also update `ios/Podfile` line 1:
```ruby
platform :ios, '17.0'
```

### 6. Build & run
```bash
flutter pub get
cd ios && pod install && cd ..
flutter run
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "ARKit is not supported" | You need a physical device, not Simulator |
| "No depth data" | Only Pro models have LiDAR (the `lidar` tier); non-Pro models (15/15 Plus/16/16 Plus) use the `camera` tier with 30 cm + reference-object scale |
| Pod install fails | Run `cd ios && pod deintegrate && pod install` |
