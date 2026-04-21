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

### 3. Add Scanner source files
The `ios/Runner/Scanner/` folder already contains the native Swift files.
Make sure they appear in Xcode's project navigator:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Right-click the **Runner** group → **Add Files to "Runner"…**
3. Select the `Scanner/` folder. Ensure **"Create groups"** is checked.
4. Verify all 4 Swift files are added to the **Runner** target.

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
| "No depth data" | Only Pro models have LiDAR; non-Pro falls back to camera depth or plate mode |
| Pod install fails | Run `cd ios && pod deintegrate && pod install` |
