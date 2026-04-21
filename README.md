# Pixels to Macros

**Offline Multi-Food Calorie Scanner** — Academic thesis project.

Uses on-device AR (ARKit) and ML (CoreML DeepLabV3) to estimate food volume
and calculate calories with uncertainty ranges. 100% offline, iOS only.

---

## Architecture

| Layer | Tech | Responsibility |
|-------|------|----------------|
| **UI** | Flutter (Dart) + Riverpod | Screens, state machine, history, analytics |
| **Bridge** | MethodChannel | JSON messages between Dart and Swift |
| **Native** | Swift / ARKit / CoreML | AR session, depth, segmentation, volume |
| **Storage** | SQLite v4 (sqflite) | Food DB (42+ items), scan history, user preferences |
| **Training** | PyTorch → ONNX → CoreML | DeepLabV3-MobileNetV3 on FoodSeg103 |

---

## Features

- **Two-angle scan flow** — top-down + 45° side capture with AR guidance
- **Camera guidance overlay** — reticle, distance hints, step progress bar
- **First-scan tutorial** — 3-page walkthrough (shown once)
- **Haptic feedback** — light/medium/heavy on capture, success, and error
- **ML food segmentation** — CoreML DeepLabV3 with <200ms inference target
- **Volume → calorie estimation** — density-based model with min/max uncertainty
- **Confidence scoring** — aggregate uncertainty metric (colour-coded badge + ring)
- **Dashboard** — calorie ring, streak tracker, today's foods, recent scans
- **Analytics** — 7/14/30-day bar charts, daily averages, peak-day stats
- **Scan history** — searchable, swipe-to-delete, tap for full detail
- **Edit scans** — correct food labels and calorie values after scanning
- **Manual food entry** — searchable DB picker with portion input
- **Food database browser** — view all 42+ foods, add custom entries
- **CSV export** — detailed per-food rows and daily summary exports
- **Streak tracking** — consecutive scanning day counter
- **Performance monitoring** — pipeline timing (capture, inference, total)
- **Debug logging** — 500-entry ring buffer with clipboard export
- **Onboarding** — 3-page flow (welcome → name → calorie goal)

---

## Project Structure

```
lib/
├── main.dart                         Entry point
├── app.dart                          MaterialApp + routing
├── core/
│   ├── constants.dart                App-wide constants, DepthMode enum
│   └── scan_state.dart               ScanState enum (6 happy + 3 error)
├── models/
│   ├── food_data.dart                FoodData + calorie range math
│   ├── scan_result.dart              ScanResult + DetectedFood
│   └── user_preferences.dart         User prefs (name, goal, tutorial flag)
├── providers/
│   ├── analytics_provider.dart       7/14/30-day analytics aggregation
│   ├── daily_intake_provider.dart    Today's calorie totals
│   ├── history_provider.dart         Scan history CRUD
│   ├── scan_result_provider.dart     ML inference + calorie computation
│   ├── scan_state_provider.dart      Scan state machine
│   ├── streak_provider.dart          Consecutive-day streak counter
│   └── user_prefs_provider.dart      User preferences + tutorial flag
├── screens/
│   ├── analytics_screen.dart         Bar charts + stat cards
│   ├── debug_screen.dart             Monospace log viewer
│   ├── edit_food_screen.dart         Edit detected food labels/calories
│   ├── food_database_screen.dart     Browse + add custom foods
│   ├── history_screen.dart           Searchable scan history
│   ├── home_screen_v2.dart           Dashboard with ring + streak + foods
│   ├── main_shell.dart               4-tab navigation + scan FABs
│   ├── manual_entry_screen.dart      Manual food + portion input
│   ├── onboarding_screen.dart        3-page onboarding
│   ├── scan_detail_screen.dart       Full scan detail + confidence ring
│   ├── scan_screen.dart              Camera guidance + state machine scan
│   └── settings_screen.dart          Profile, goal, DB info, exports
├── services/
│   ├── data_export_service.dart      CSV export (detailed + daily)
│   ├── database_service.dart         SQLite v4 singleton + migrations
│   ├── debug_log.dart                500-entry ring buffer
│   ├── native_bridge.dart            MethodChannel to Swift
│   └── perf_monitor.dart             Pipeline timing
├── theme/
│   └── app_theme.dart                Green design system (Inter font)
└── widgets/
    ├── confidence_badge.dart         Confidence score badge + ring card
    ├── scan_guidance_overlay.dart    Camera reticle + instruction banners
    └── scan_tutorial_overlay.dart    First-scan 3-page tutorial

ios/Runner/
├── AppDelegate.swift                 Registers ScannerPlugin
└── Scanner/
    ├── ScannerPlugin.swift           MethodChannel handler
    ├── DepthModeDetector.swift       LiDAR / camera / fallback detection
    ├── ARSessionManager.swift        ARKit world tracking session
    ├── FrameCaptureService.swift     Frame capture (top + side)
    ├── FramePreprocessor.swift       640×480 resize + normalisation
    ├── PlateDetector.swift           Ellipse fitting for plate boundary
    ├── SegmentationService.swift     CoreML DeepLabV3 inference
    ├── VolumeCalculator.swift        Depth → volume (cm³)
    └── InferencePipeline.swift       Orchestrates full pipeline

training/
├── requirements.txt                  PyTorch, coremltools, etc.
├── dataset.py                        FoodSeg103 data loader
├── train.py                          DeepLabV3-MobileNetV3 training
└── export_coreml.py                  ONNX → CoreML FP16 conversion
```

---

## Build Status

| Step | Description | Status |
|------|-------------|--------|
| 1 | Flutter foundation | Done |
| 2 | Native Swift bridge + ARKit | Done |
| 3 | CoreML segmentation pipeline | Done |
| 4 | Training pipeline, food DB, history, debug logging | Done |
| 5 | Dashboard, daily tracking, settings, onboarding | Done |
| 6 | Analytics, manual entry, delete scans, 4-tab nav | Done |
| 7 | Scan detail, CSV export, streaks, perf monitoring | Done |
| 8 | Edit foods, food DB browser, history search, uncertainty | Done |
| 9 | Scan UX polish — guidance, haptics, confidence, tutorial | Done |

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | >= 3.22 | `flutter --version` |
| Xcode | >= 16 | Required for iOS build |
| macOS | >= 14 | Xcode requirement |
| CocoaPods | >= 1.15 | `sudo gem install cocoapods` |

> **Windows note**: Dart code can be written on any OS, but iOS builds
> require macOS with Xcode.

---

## Getting Started (macOS)

```bash
flutter create . --org com.pixelstomacros --platforms ios
flutter pub get
flutter run
```
