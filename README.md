# Pixels to Macros

**Offline Multi-Food Calorie Scanner** — Academic thesis project.

Uses on-device AR (ARKit + LiDAR) and ML (CoreML) to estimate food volume
and calculate calories with uncertainty ranges. 100%% offline, iOS only.

---

## Architecture

| Layer | Tech | Responsibility |
|-------|------|----------------|
| **UI** | Flutter (Dart) + Riverpod | Screens, state machine, history |
| **Bridge** | MethodChannel | JSON messages between Dart and Swift |
| **Native** | Swift / ARKit / CoreML | AR session, depth, segmentation, volume |
| **Storage** | SQLite (sqflite) | Food reference data, scan history |

---

## Current Status — Step 1 (Foundation)

- [x] Flutter project scaffold (`pubspec.yaml`, `analysis_options.yaml`)
- [x] `ScanState` enum with happy-path + failure states
- [x] `ScanStateNotifier` (Riverpod) state machine
- [x] `DatabaseService` — SQLite with seed data (Apple, Rice, Chicken)
- [x] `FoodData` model with uncertainty calorie math
- [x] `ScanResult` / `DetectedFood` models for history
- [x] `NativeBridge` — MethodChannel stub (Swift side comes in Step 2)
- [x] `AppTheme` — green design language matching original NutriLens UI
- [x] `HomeScreen` — verification dashboard for Step 1

**Next**: Step 2 — Native Swift bridge + ARKit session (requires macOS + Xcode).

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | >= 3.22 | `flutter --version` |
| Xcode | >= 16 | Required for iOS build |
| macOS | >= 14 | Xcode requirement |
| CocoaPods | >= 1.15 | `sudo gem install cocoapods` |

> **Windows note**: Dart code can be written on any OS, but iOS builds
> require macOS with Xcode. Use a Mac for `flutter run` and device testing.

---

## Getting Started (macOS)

```bash
# 1. Generate platform files (first time only)
flutter create . --org com.pixelstomacros --platforms ios

# 2. Install dependencies
flutter pub get

# 3. Run on iOS simulator or connected device
flutter run
```

---

## Project Structure

```
lib/
├── main.dart                     Entry point
├── app.dart                      MaterialApp + routing
├── core/
│   ├── constants.dart            App-wide constants, DepthMode enum
│   └── scan_state.dart           ScanState enum + labels
├── models/
│   ├── food_data.dart            FoodData model + calorie math
│   └── scan_result.dart          ScanResult + DetectedFood
├── providers/
│   └── scan_state_provider.dart  Riverpod state notifier
├── services/
│   ├── database_service.dart     SQLite singleton + seed
│   └── native_bridge.dart        MethodChannel to Swift
├── screens/
│   └── home_screen.dart          Step 1 verification UI
└── theme/
    └── app_theme.dart            Green design system
```
