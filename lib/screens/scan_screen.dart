import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/scan_state.dart';
import '../models/scan_benchmark.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/scan_state_provider.dart';
import '../providers/scan_result_provider.dart';
import '../providers/streak_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/database_service.dart';
import '../services/debug_log.dart';
import '../services/native_bridge.dart';
import '../services/perf_monitor.dart';
import '../core/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/confidence_badge.dart';
import '../widgets/generated_food_preview.dart';
import '../widgets/scan_guidance_overlay.dart';
import '../widgets/scan_tutorial_overlay.dart';
import 'scan_3d_viewer_screen.dart';
import '../widgets/scan_3d_viewer.dart' show Scan3DObject;
import 'scan_detail_screen.dart';

/// Full-screen scan flow with camera guidance, haptic feedback,
/// confidence scoring, and first-scan tutorial (Part 4 + Step 9).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _bridge = NativeBridge.instance;
  bool _sessionStarted = false;
  bool _showTutorial = false;
  bool _isRecording = false;

  /// True while runVideoInference is in-flight — prevents re-entry.
  bool _isInferenceRunning = false;

  double _recordProgress = 0.0; // 0.0 – 1.0 over the recording window
  Timer? _recordTimer;
  DateTime? _recordStartedAt;
  Timer? _pitchTimer; // polls phone orientation at ~15 fps
  double _currentPitch = 0.0; // radians: -π/2 = top, 0 = horizontal
  double _currentRoll = 0.0; // radians: 0 = portrait, ±π/2 = landscape
  int _quarterTurns = 0; // overlay counter-rotation (0..3) to stay world-upright
  String _detectedDepthMode = 'unknown';
  ScanResult? _savedScanResult;
  List<DetectedFood> _buildPreviewFoods = const [];
  bool _launched3DViewer = false;
  int? _sessionGeneration; // generation counter for safe stop()

  /// Flashlight (torch) state and ambient light (lux) for low-light warning.
  bool _torchOn = false;
  double _ambientLux = -1.0;
  int _pitchTickCounter = 0;

  /// The native recorder keeps up to 40 frames at ~10 fps (a 4-second HARD
  /// cap). The sweep normally finishes earlier: recording auto-stops the moment
  /// the phone completes the top-to-side arc (pitch > side-view threshold) once
  /// [_minRecordDuration] has elapsed, so a steady user is done in ~1.6–2.5 s
  /// and only a slow sweep uses the full 4 s.
  static const _maxRecordDuration = Duration(seconds: 4);
  static const _minRecordDuration = Duration(milliseconds: 1600);
  static const _timerInterval = Duration(milliseconds: 80);

  /// Pitch thresholds (radians).
  /// Top-view:  pitch < -80° = -1.396 rad → phone is nearly flat / pointing straight down.
  /// Side-view: pitch > -10° = -0.175 rad → phone is nearly vertical (upright).
  static const double _topViewThreshold = -1.396; // -80° — truly horizontal
  static const double _sideViewThreshold = -0.175; // -10° — nearly vertical

  @override
  void initState() {
    super.initState();
    // Lock the scan flow to portrait. The ARKit preview applies a hardcoded
    // portrait transform, and the landscape side-view UX depends on the UI
    // staying portrait while the user physically rotates the phone to
    // landscape (the on-screen instruction is pre-rotated to compensate).
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    // Reset any stale state from a previous scan session (the provider is
    // NOT autoDispose so depthFailed / modelFailed from earlier persists).
    // Defer both reset AND session start to post-frame callback so that
    // the previous screen's dispose() (and its fire-and-forget stopSession)
    // has already been sent to the method channel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(scanStateProvider.notifier).reset();
        // Only start session immediately if no tutorial is shown.
        // If tutorial is shown, _startSession is called from _dismissTutorial.
        if (!_showTutorial) _startSession();
      }
    });
    _checkTutorial();
  }

  void _checkTutorial() {
    final prefs = ref.read(userPrefsProvider);
    // Assign directly — no setState needed, widget hasn't built yet.
    _showTutorial = !prefs.hasSeenScanTutorial;
  }

  void _dismissTutorial() {
    // Guard: do nothing if the widget is already gone.
    if (!mounted) return;
    try {
      ref.read(userPrefsProvider.notifier).dismissScanTutorial();
      setState(() => _showTutorial = false);
      _startSession();
    } catch (e, st) {
      DebugLog.instance.log('ScanTutorial', 'Dismiss error: $e\n$st');
      // Never crash — just return the user to the home screen.
      _safePopToHome();
    }
  }

  /// Pops all routes back to the first (home) route without throwing.
  void _safePopToHome() {
    if (!mounted) return;
    try {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {}
  }

  String? _sessionErrorDetail; // actual error text for UI

  Future<void> _startSession() async {
    // Stop any previous session, using the generation counter so only
    // the correct session is stopped.
    try {
      await _bridge.stopSession(generation: _sessionGeneration);
    } catch (_) {}

    try {
      // ── 1. Dart-side camera permission (belt) ─────────────────────────
      // The native side ALSO checks AVCaptureDevice.authorizationStatus
      // (suspenders), but calling permission_handler first ensures the
      // Flutter permission dialogue shows if needed.
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        DebugLog.instance.log('Scan', 'Camera permission denied: $status');
        if (mounted) _showCameraPermissionDialog();
        return;
      }

      DebugLog.instance.log('Scan', 'Starting AR session');

      // ── 2. Start session (single call — native handles retries) ───────
      // The native side:
      //   a) verifies camera auth natively (AVCaptureDevice)
      //   b) starts a bare ARWorldTrackingConfiguration (no depth)
      //   c) waits up to 5 s for the first frame
      //   d) retries once automatically if it fails
      // NO Dart-side retry loop — that was causing 30 s waits.
      _sessionGeneration = await _bridge.startSession();

      // ── 3. Detect depth mode ──────────────────────────────────────────
      try {
        _detectedDepthMode = await _bridge.getDepthMode();
        DebugLog.instance.log('Scan', 'Depth mode: $_detectedDepthMode');
      } catch (_) {
        _detectedDepthMode = 'monocular_scale';
      }

      // ── 4. Upgrade to depth config in the background ──────────────────
      // The session started with a bare config (no depth/mesh) to maximise
      // startup reliability.  Now that frames are flowing, add depth.
      unawaited(_bridge.upgradeDepthConfig());

      if (mounted) {
        setState(() {
          _sessionStarted = true;
          _sessionErrorDetail = null;
        });
        ref.read(scanStateProvider.notifier).sessionReady();
        _startPitchPolling();
      }
      DebugLog.instance.log('Scan', 'AR session started');
    } catch (e) {
      final msg = e.toString();
      DebugLog.instance.log('Scan', 'AR session failed: $msg');
      // ignore: avoid_print
      print('[ScanScreen] startSession error: $msg');

      // Get the real error from the native side.
      final nativeError = await _bridge.getSessionError();
      if (nativeError != null) {
        DebugLog.instance.log('Scan', 'Native error: $nativeError');
      }

      if (mounted) {
        setState(() {
          _sessionStarted = true;
          // Show the ACTUAL error so the user (and developer) can diagnose.
          _sessionErrorDetail = nativeError ?? msg;
        });
        ref.read(scanStateProvider.notifier).depthFailed();
      }
    }
  }

  void _showCameraPermissionDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cameraRequired),
        content: Text(
          '${l10n.appName} ${l10n.openSettings.toLowerCase()}.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: Text(l10n.openSettings),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pitchTimer?.cancel();
    _isRecording = false;
    _isInferenceRunning = false;
    // Make sure we never leave the torch on after the user leaves the screen.
    if (_torchOn) {
      try {
        _bridge.setTorch(false);
      } catch (_) {}
    }
    // Use generation-aware stop so this fire-and-forget call can never
    // accidentally kill a session started by a newer ScanScreen instance.
    try {
      _bridge.stopSession(generation: _sessionGeneration);
    } catch (_) {}
    // Restore free orientation for the rest of the app.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── Haptic helpers ──────────────────────────────────────────────────────

  void _hapticLight() => HapticFeedback.lightImpact();
  void _hapticMedium() => HapticFeedback.mediumImpact();
  void _hapticHeavy() => HapticFeedback.heavyImpact();
  void _hapticSuccess() => HapticFeedback.mediumImpact();
  void _hapticError() => HapticFeedback.heavyImpact();

  // ── Orientation tracking ──────────────────────────────────────────────────

  void _startPitchPolling() {
    _pitchTimer = Timer.periodic(
      const Duration(milliseconds: 66), // ~15 fps
      (_) => _pollPitch(),
    );
  }

  /// Snap a continuous device [roll] (radians) to one of four quarter-turn
  /// orientations (0..3) for the overlay, with hysteresis so it does not flicker
  /// at the 45° boundaries. The overlay is counter-rotated clockwise by the
  /// returned number of quarter turns to stay upright relative to the world.
  int _snapQuarterTurns(double roll, int current) {
    // Roll at the centre of the current quadrant (q maps to roll ≈ q·π/2).
    final double currentCentre = current * (math.pi / 2);
    double delta = roll - currentCentre;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    // Stay in the current quadrant until clearly past 45° (+10° hysteresis).
    if (delta.abs() < (math.pi / 4) + 0.18) return current;
    return ((roll / (math.pi / 2)).round() % 4 + 4) % 4;
  }

  Future<void> _pollPitch() async {
    if (!mounted || !_sessionStarted) return;
    double pitch;
    try {
      pitch = await _bridge.getPhonePitch();
    } catch (e) {
      return;
    }
    if (!mounted) return;

    // Track device roll so the guidance overlay can rotate to stay upright when
    // the phone is physically held in landscape — independent of scan state.
    double roll = 999.0;
    try {
      roll = await _bridge.getPhoneRoll();
    } catch (_) {
      roll = 999.0;
    }
    if (!mounted) return;
    final int quarterTurns =
        roll > 100 ? _quarterTurns : _snapQuarterTurns(roll, _quarterTurns);

    setState(() {
      _currentPitch = pitch;
      if (roll <= 100) _currentRoll = roll;
      _quarterTurns = quarterTurns;
    });

    // Sample ambient light every ~5 ticks (~3 Hz) — cheap.
    _pitchTickCounter++;
    if (_pitchTickCounter % 5 == 0) {
      unawaited(_bridge.getAmbientIntensity().then((lux) {
        if (mounted && lux != _ambientLux) {
          setState(() => _ambientLux = lux);
        }
      }).catchError((_) {}));
    }

    final state = ref.read(scanStateProvider);

    // Auto-start recording when phone points down (top-view).
    if (state == ScanState.waitingForTopView && pitch < _topViewThreshold) {
      ref.read(scanStateProvider.notifier).topViewDetected();
      unawaited(_startRecording());
      return;
    }

    // Auto-stop recording when phone reaches side-view.
    // Guard: don't trigger if inference is already in-flight.
    final hasEnoughSweep = _recordStartedAt == null ||
        DateTime.now().difference(_recordStartedAt!) >= _minRecordDuration;

    if (state == ScanState.recording &&
        pitch > _sideViewThreshold &&
        hasEnoughSweep &&
        !_isInferenceRunning) {
      unawaited(_stopRecording());
    }
  }

  // ── Recording ────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isRecording || !mounted) return;
    _hapticMedium();
    setState(() {
      _isRecording = true;
      _recordProgress = 0.0;
      _buildPreviewFoods = const [];
    });
    _recordStartedAt = DateTime.now();
    ref.read(scanStateProvider.notifier).startedRecording();
    try {
      PerfMonitor.instance.start('record');
      await _bridge.startRecording();
    } catch (e) {
      DebugLog.instance.log('Scan', 'Recording start failed: $e — resetting');
      _hapticError();
      if (!mounted) return;
      setState(() => _isRecording = false);
      _recordStartedAt = null;
      ref.read(scanStateProvider.notifier).reset();
      return;
    }

    // Recording stops automatically when the phone reaches vertical (side-view)
    // or at the 4-second native frame budget. The user should move in one
    // smooth line from top view to side view during this window.
    final totalTicks =
        _maxRecordDuration.inMilliseconds ~/ _timerInterval.inMilliseconds;
    var tick = 0;
    _recordTimer = Timer.periodic(_timerInterval, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      tick++;
      if (mounted) setState(() => _recordProgress = tick / totalTicks);
      if (tick >= totalTicks) {
        t.cancel();
        if (mounted) _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _isInferenceRunning) return;
    if (_recordStartedAt != null &&
        DateTime.now().difference(_recordStartedAt!) < _minRecordDuration) {
      return;
    }
    _recordTimer?.cancel();
    _recordTimer = null;
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isInferenceRunning = true;
      _recordProgress = 1.0;
    });
    _recordStartedAt = null;
    _hapticHeavy();
    PerfMonitor.instance.end();
    try {
      await _bridge.stopRecording();
    } catch (e) {
      DebugLog.instance.log('Scan', 'stopRecording error: $e');
    }
    if (!mounted) {
      _isInferenceRunning = false;
      return;
    }
    try {
      await _runVideoInference();
    } catch (e, st) {
      final msg = 'Unhandled inference error: $e';
      DebugLog.instance.log('Scan', '$msg\n$st');
      if (mounted) {
        setState(() => _sessionErrorDetail = msg);
        ref.read(scanStateProvider.notifier).modelFailed();
      }
    } finally {
      if (mounted) setState(() => _isInferenceRunning = false);
    }
  }

  Future<void> _runVideoInference() async {
    if (!mounted) return;
    DebugLog.instance.log('Scan', 'Running video inference pipeline');
    ref.read(scanStateProvider.notifier).recordingStopped();
    PerfMonitor.instance.start('inference');

    ScanResultState? result;
    try {
      await ref.read(scanResultProvider.notifier).runVideoScan();
      if (!mounted) return;
      result = ref.read(scanResultProvider);
    } catch (e) {
      final msg = 'Inference failed: $e';
      DebugLog.instance.log('Scan', msg);
      if (!mounted) return;
      setState(() => _sessionErrorDetail = msg);
      _hapticError();
      ref.read(scanStateProvider.notifier).modelFailed();
      return;
    }

    if (!mounted) return;
    PerfMonitor.instance.end();

    if (result == null || (result.foods.isEmpty && result.error == null)) {
      _hapticError();
      setState(() => _sessionErrorDetail = null);
      ref.read(scanStateProvider.notifier).plateNotDetected();
    } else if (result.error != null) {
      final failedResult = result;
      DebugLog.instance.log('Scan', 'Inference error: ${failedResult.error}');
      _hapticError();
      if (failedResult.failureKind == ScanFailureKind.noFood) {
        setState(() => _sessionErrorDetail = null);
        ref.read(scanStateProvider.notifier).plateNotDetected();
      } else {
        setState(() => _sessionErrorDetail = failedResult.error);
        ref.read(scanStateProvider.notifier).modelFailed();
      }
    } else {
      final successfulResult = result;
      if (mounted) {
        setState(() {
          _buildPreviewFoods = List<DetectedFood>.from(successfulResult.foods);
        });
      }
      if (!mounted) return;
      DebugLog.instance.log(
          'Scan',
          'Inference done: ${successfulResult.foods.length} items, '
              '${successfulResult.totalCaloriesMin.round()}-${successfulResult.totalCaloriesMax.round()} kcal');
      DebugLog.instance.log('Perf', PerfMonitor.instance.report());
      try {
        await _saveScanResult(successfulResult);
      } catch (e, st) {
        if (!mounted) return;
        DebugLog.instance.log('Scan3D', 'Save failed: $e\n$st');
        setState(() =>
            _sessionErrorDetail = AppLocalizations.of(context).scan3dFailed);
        _hapticError();
        ref.read(scanStateProvider.notifier).modelFailed();
        return;
      }
      if (!mounted) return;
      _hapticSuccess();
      ref.read(scanStateProvider.notifier).calculationDone();
    }
  }

  Future<void> _saveScanResult(ScanResultState resultState) async {
    try {
      // Hard contract: a successful scan must have a real 3-D model file.
      final model3dPath = await _bridge.getModel3DPath();
      final model3dRaw = await _bridge.getModel3DObjects();
      final model3dObjects = model3dRaw
          .map(Scan3DObject.fromMap)
          .where((o) => o.id.isNotEmpty)
          .toList(growable: false);
      final modelExists = model3dPath != null &&
          model3dPath.isNotEmpty &&
          File(model3dPath).existsSync();

      debugPrint('[SCAN] model3dPath received: $model3dPath');
      DebugLog.instance.log(
        'Scan3D',
        'model3dPath=$model3dPath exists=$modelExists '
            'objects=${model3dObjects.length}',
      );

      if (!modelExists) {
        debugPrint('[SCAN] ERROR: missing 3D model');
        throw StateError('missing_3d_model');
      }

      final scanResult = ScanResult(
        timestamp: DateTime.now(),
        depthMode: _detectedDepthMode,
        foods: resultState.foods,
        topCameraPosition: null,
        topCameraTransform: null,
        sideCameraPosition: null,
        sideCameraTransform: null,
        imagePath: null,
      );
      await ref.read(historyProvider.notifier).addScan(scanResult);
      if (!mounted) return;
      await ref.read(dailyIntakeProvider.notifier).load();
      if (!mounted) return;
      await ref.read(streakProvider.notifier).load();
      if (!mounted) return;
      final history = ref.read(historyProvider);
      if (history.scans.isNotEmpty) {
        _savedScanResult = history.scans.first;
        final scanId = _savedScanResult?.id;
        if (scanId != null) {
          final timings = PerfMonitor.instance.allTimings;
          int memoryBytes = 0;
          try {
            memoryBytes = await _bridge.getMemoryUsage();
          } catch (_) {}
          if (!mounted) return;
          final benchmark = ScanBenchmark(
            scanId: scanId,
            captureTopMs: timings['record']?.inMilliseconds ?? 0,
            captureSideMs: 0,
            inferenceMs: timings['inference']?.inMilliseconds ?? 0,
            totalMs: PerfMonitor.instance.total.inMilliseconds,
            peakMemoryBytes: memoryBytes,
            depthMode: _detectedDepthMode,
            timestamp: DateTime.now(),
          );
          await DatabaseService.instance.insertBenchmark(benchmark);
        }
      }
      DebugLog.instance.log('Scan', 'Result saved to history');
      _launch3DViewer(model3dPath, model3dObjects);
    } catch (e) {
      DebugLog.instance.log('Scan', 'Save result error: $e');
      rethrow;
    }
  }

  void _launch3DViewer(String path, List<Scan3DObject> objects) {
    if (_launched3DViewer || !mounted) return;
    _launched3DViewer = true;
    debugPrint('[SCAN] launching Scan3DViewer');
    DebugLog.instance.log('Scan3D', 'launching Scan3DViewer: $path');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => Scan3DViewerScreen(
          modelPath: path,
          objects: objects,
          scanId: _savedScanResult?.id,
        ),
      ),
    );
  }

  void _retry() {
    _hapticLight();
    _recordTimer?.cancel();
    _recordTimer = null;
    _recordStartedAt = null;
    _pitchTimer?.cancel();
    _pitchTimer = null;
    _isRecording = false;
    _isInferenceRunning = false;
    _recordProgress = 0.0;
    _sessionStarted = false;
    _sessionErrorDetail = null;
    _launched3DViewer = false;
    _buildPreviewFoods = const [];
    ref.read(scanStateProvider.notifier).reset();
    ref.read(scanResultProvider.notifier).reset();
    _startSession();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanStateProvider);
    final scanResult = ref.watch(scanResultProvider);
    final l10n = AppLocalizations.of(context);
    final isProcessing =
        scanState == ScanState.calculating || scanState == ScanState.done;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Live AR camera preview ───────────────────────────────────
          // Hide the platform view during inference/done so Flutter widgets
          // (close button, cancel) can receive touches unobstructed.
          // ARKit inference runs on a background Swift thread independently.
          if (!isProcessing)
            const Positioned.fill(
              child: UiKitView(viewType: 'com.pixelstomacros/ar_camera'),
            )
          else
            const Positioned.fill(child: ColoredBox(color: Colors.black)),

          // ── Guidance overlay ─────────────────────────────────────────
          ScanGuidanceOverlay(
              scanState: scanState,
              currentPitch: _currentPitch,
              quarterTurns: _quarterTurns,
              scanMode: _detectedDepthMode),

          if (scanState == ScanState.calculating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 104,
              left: 16,
              right: 16,
              child: GeneratedFoodPreview(
                foods: _buildPreviewFoods,
                isBuilding: true,
                height: 250,
                title: _buildPreviewFoods.isEmpty
                    ? l10n.building3dPreview
                    : l10n.refining3dFoodModel,
              ),
            ),

          // ── Bottom action panel ─────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: _BottomPanel(
                scanState: scanState,
                scanResult: scanResult,
                sessionStarted: _sessionStarted,
                sessionErrorDetail: _sessionErrorDetail,
                depthMode: _detectedDepthMode,
                timings: PerfMonitor.instance.allTimings,
                isRecording: _isRecording,
                recordProgress: _recordProgress,
                currentPitch: _currentPitch,
                onStartRecord: _startRecording,
                onStopRecord: _stopRecording,
                onRetry: _retry,
                onClose: () {
                  _isInferenceRunning = false;
                  Navigator.of(context).pop();
                },
                onViewDetails: _savedScanResult != null
                    ? () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                ScanDetailScreen(scan: _savedScanResult!),
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ),

          // ── Close button (top-left) ─────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                onPressed: () {
                  _isInferenceRunning = false;
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),

          // ── Flashlight toggle (top-right) ───────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: Icon(
                  _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                  color: _torchOn ? AppTheme.amber500 : Colors.white70,
                  size: 28,
                ),
                tooltip:
                    _torchOn ? l10n.turnOffFlashlight : l10n.turnOnFlashlight,
                onPressed: () async {
                  final next = !_torchOn;
                  final ok = await _bridge.setTorch(next);
                  if (!context.mounted) return;
                  if (ok) {
                    setState(() => _torchOn = next);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            AppLocalizations.of(context).flashlightUnavailable),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
          ),

          // ── Low-light warning banner ────────────────────────────────
          if (_ambientLux >= 0 && _ambientLux < 200 && !_torchOn)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.amber500),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.nightlight_round,
                        color: AppTheme.amber500, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.lowLightScanWarning,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Tutorial overlay (first scan) ───────────────────────────
          if (_showTutorial) ScanTutorialOverlay(onDismiss: _dismissTutorial),
        ],
      ),
    );
  }
}
// ── Bottom action panel ───────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.scanState,
    required this.scanResult,
    required this.sessionStarted,
    this.sessionErrorDetail,
    required this.depthMode,
    required this.timings,
    required this.isRecording,
    required this.recordProgress,
    required this.currentPitch,
    required this.onStartRecord,
    required this.onStopRecord,
    required this.onRetry,
    required this.onClose,
    this.onViewDetails,
  });

  final ScanState scanState;
  final ScanResultState scanResult;
  final bool sessionStarted;
  final String? sessionErrorDetail;
  final String depthMode;
  final Map<String, Duration> timings;
  final bool isRecording;
  final double recordProgress;
  final double currentPitch;
  final VoidCallback onStartRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback? onViewDetails;

  String _scanErrorTitle(AppLocalizations l10n) {
    if (scanState == ScanState.depthFailed) {
      return l10n.cameraSessionFailedTitle;
    }
    return scanResult.failureKind == ScanFailureKind.reconstructionFailed
        ? l10n.scan3dFailed
        : l10n.scanAnalysisFailed;
  }

  String _scanErrorBody(AppLocalizations l10n) {
    switch (scanState) {
      case ScanState.depthFailed:
        return l10n.cameraSessionFailedBody;
      case ScanState.modelFailed:
        return l10n.scanModelErrorBody;
      default:
        return scanState.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isNoFood = scanResult.failureKind == ScanFailureKind.noFood ||
        scanState == ScanState.plateNotDetected;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Step indicator ────────────────────────────────────────
          _StateProgressRow(state: scanState),
          const SizedBox(height: 16),

          // ── Waiting for top-view orientation ──────────────────────
          if (scanState == ScanState.waitingForTopView)
            _OrientationIndicator(
              pitch: currentPitch,
              sessionStarted: sessionStarted,
              l10n: l10n,
            ),

          // ── Ready to record (manual start) ─────────────────────
          if (scanState == ScanState.readyToRecord)
            _RecordButton(
              enabled: sessionStarted,
              isRecording: false,
              progress: 0,
              l10n: l10n,
              onPressed: onStartRecord,
            ),

          // ── Recording in progress ─────────────────────────────────
          if (scanState == ScanState.recording)
            _RecordButton(
              enabled: true,
              isRecording: true,
              progress: recordProgress,
              l10n: l10n,
              onPressed: onStopRecord,
            ),

          // ── Processing ────────────────────────────────────────────
          if (scanState == ScanState.calculating) ...[
            _ProcessingIndicator(
              text: depthMode == 'monocular_scale'
                  ? l10n.generatingEstimated3dModel
                  : l10n.buildingLidar3dModel,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onClose,
              child: Text(l10n.cancel,
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ),
          ],

          // ── Done → results + confidence ───────────────────────────
          if (scanState == ScanState.done) ...[
            ConfidenceBadge(
              caloriesMin: scanResult.totalCaloriesMin,
              caloriesMax: scanResult.totalCaloriesMax,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                _InfoChipDark(
                  icon: Icons.visibility,
                  label: depthMode.replaceAll('_', ' '),
                ),
                if (timings.isNotEmpty)
                  _InfoChipDark(
                    icon: Icons.timer,
                    label:
                        '${timings.values.fold(Duration.zero, (a, b) => a + b).inMilliseconds}ms total',
                  ),
                _InfoChipDark(
                  icon: Icons.restaurant,
                  label:
                      '${scanResult.foods.length} item${scanResult.foods.length == 1 ? '' : 's'}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...scanResult.foods.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant,
                          size: 14, color: context.primary400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        f.displayCalories,
                        style: TextStyle(
                          color: context.primary400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Text(
              'Total: ${scanResult.totalCaloriesMin.round()}–'
              '${scanResult.totalCaloriesMax.round()} kcal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.primary400,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: Text(AppLocalizations.of(context).scanAgain),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onViewDetails ?? onClose,
                    child: Text(onViewDetails != null
                        ? AppLocalizations.of(context).scanDetails
                        : AppLocalizations.of(context).done),
                  ),
                ),
              ],
            ),
          ],

          // ── Error states → retry + back ───────────────────────────
          if (scanState.isError) ...[
            Icon(
              isNoFood ? Icons.no_food_outlined : Icons.error_outline,
              size: 40,
              color: isNoFood ? AppTheme.amber500 : AppTheme.red500,
            ),
            const SizedBox(height: 8),
            Text(
              isNoFood ? l10n.noFoodDetectedTitle : _scanErrorTitle(l10n),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isNoFood ? l10n.noFoodDetectedBody : _scanErrorBody(l10n),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (!isNoFood && sessionErrorDetail != null) ...[
              const SizedBox(height: 8),
              _ScanErrorBox(error: sessionErrorDetail!),
            ] else if (!isNoFood && scanResult.error != null) ...[
              const SizedBox(height: 8),
              _ScanErrorBox(error: scanResult.error!),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: Text(AppLocalizations.of(context).back),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onRetry,
                    child: Text(AppLocalizations.of(context).retry),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
// ── State progress row ──────────────────────────────────────────────────────

class _StateProgressRow extends StatelessWidget {
  const _StateProgressRow({required this.state});
  final ScanState state;

  static const _steps = [
    (ScanState.waitingForTopView, 'Aim'),
    (ScanState.recording, 'Record'),
    (ScanState.calculating, 'Analyse'),
    (ScanState.done, 'Done'),
  ];

  int get _activeIndex {
    return switch (state) {
      ScanState.waitingForTopView => 0,
      ScanState.readyToRecord => 0,
      ScanState.recording => 1,
      ScanState.calculating => 2,
      ScanState.done => 3,
      _ => -1, // error
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= active ? context.primary400 : Colors.white12,
              ),
            ),
          _StepDot(
            label: _steps[i].$2,
            isActive: i == active,
            isCompleted: i < active,
            isError: state.isError && i == active,
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.isActive,
    required this.isCompleted,
    this.isError = false,
  });

  final String label;
  final bool isActive;
  final bool isCompleted;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (isError) {
      color = AppTheme.red500;
    } else if (isCompleted) {
      color = context.primary400;
    } else if (isActive) {
      color = context.primary500;
    } else {
      color = Colors.white24;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isCompleted ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: isCompleted
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

/// Circular record button that shows a countdown arc while recording.
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.enabled,
    required this.isRecording,
    required this.progress,
    required this.l10n,
    required this.onPressed,
  });

  final bool enabled;
  final bool isRecording;
  final double progress; // 0.0 – 1.0
  final AppLocalizations l10n;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress arc
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: isRecording ? progress : 0,
                    strokeWidth: 5,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.amber500,
                    ),
                  ),
                ),
                // Inner circle button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: isRecording
                        ? AppTheme.red500
                        : (enabled
                            ? context.primary500
                            : context.primary500.withValues(alpha: 0.3)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRecording ? Icons.stop : Icons.videocam,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isRecording
              ? l10n.secondsRemaining(
                  ((1.0 - progress) *
                          _ScanScreenState._maxRecordDuration.inSeconds)
                      .ceil(),
                )
              : (enabled ? l10n.tapToScan : l10n.startingCamera),
          style: TextStyle(
            fontSize: 12,
            color: isRecording ? AppTheme.amber500 : Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(context.primary400),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}

class _InfoChipDark extends StatelessWidget {
  const _InfoChipDark({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

/// Visual indicator showing the phone's tilt angle.
/// Guides the user to point the phone straight down at the food.
class _OrientationIndicator extends StatelessWidget {
  const _OrientationIndicator({
    required this.pitch,
    required this.sessionStarted,
    required this.l10n,
  });

  final double pitch; // radians: -π/2 = top-view, 0 = horizontal
  final bool sessionStarted;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (!sessionStarted) {
      return _ProcessingIndicator(text: l10n.startingCamera);
    }

    // Map pitch to 0..1 progress: -π/2 → 1.0 (top-view), 0 → 0.0 (horizontal).
    final progress = (pitch / (-math.pi / 2)).clamp(0.0, 1.0);
    final isTopView = pitch < -1.047; // < -60°
    final angleDeg = (pitch * 180 / math.pi).round().abs();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 5,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTopView ? context.primary400 : AppTheme.amber500,
                  ),
                ),
              ),
              Icon(
                isTopView ? Icons.check : Icons.phone_android,
                color: isTopView ? context.primary400 : Colors.white70,
                size: 36,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isTopView
              ? l10n.topViewDetectedStarting
              : l10n.tiltPhoneDown(angleDeg),
          style: TextStyle(
            fontSize: 12,
            color: isTopView ? context.primary400 : AppTheme.amber500,
          ),
        ),
      ],
    );
  }
}

/// Dark-themed error box for the scan screen (black background).
/// Selectable text + copy button so the developer can grab the exact error.
class _ScanErrorBox extends StatelessWidget {
  const _ScanErrorBox({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 0),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red.shade300),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.scanErrorCopyTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade300,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy, size: 14, color: Colors.red.shade300),
                  tooltip: l10n.copyError,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.errorCopied),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const Divider(height: 8, color: Colors.white12),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SelectableText(
                error,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade200,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
