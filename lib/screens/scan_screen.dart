import 'dart:async';
import 'dart:convert';
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
import '../theme/app_theme.dart';
import '../widgets/confidence_badge.dart';
import '../widgets/scan_guidance_overlay.dart';
import '../widgets/scan_tutorial_overlay.dart';
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
  bool _sessionStarted   = false;
  bool _showTutorial     = false;
  bool _isRecording      = false;
  /// True while runVideoInference is in-flight — prevents re-entry.
  bool _isInferenceRunning = false;
  /// Non-null while showing the "no food detected" overlay.
  String? _noFoodMessage;
  Timer? _noFoodResetTimer;
  double _recordProgress = 0.0;  // 0.0 – 1.0 over the recording window
  Timer? _recordTimer;
  Timer? _pitchTimer;            // polls phone orientation at ~15 fps
  double _currentPitch   = 0.0;  // radians: -π/2 = top, 0 = horizontal
  String _detectedDepthMode = 'unknown';
  ScanResult? _savedScanResult;
  int? _sessionGeneration;       // generation counter for safe stop()

  /// Flashlight (torch) state and ambient light (lux) for low-light warning.
  bool _torchOn = false;
  double _ambientLux = -1.0;
  int _pitchTickCounter = 0;

  static const _maxRecordDuration = Duration(seconds: 5);
  static const _timerInterval     = Duration(milliseconds: 80);

  /// Pitch thresholds (radians).
  /// Top-view:  pitch < -80° = -1.396 rad → phone is nearly flat / pointing straight down.
  /// Side-view: pitch > -10° = -0.175 rad → phone is nearly vertical (upright).
  static const double _topViewThreshold  = -1.396;  // -80° — truly horizontal
  static const double _sideViewThreshold = -0.175;  // -10° — nearly vertical

  @override
  void initState() {
    super.initState();
    // Reset any stale state from a previous scan session (the provider is
    // NOT autoDispose so depthFailed / modelFailed from earlier persists).
    // Defer both reset AND session start to post-frame callback so that
    // the previous screen's dispose() (and its fire-and-forget stopSession)
    // has already been sent to the method channel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(scanStateProvider.notifier).reset();
        _startSession();
      }
    });
    _checkTutorial();
  }

  void _checkTutorial() {
    final prefs = ref.read(userPrefsProvider);
    if (!prefs.hasSeenScanTutorial) {
      setState(() => _showTutorial = true);
    }
  }

  void _dismissTutorial() {
    ref.read(userPrefsProvider.notifier).dismissScanTutorial();
    setState(() => _showTutorial = false);
  }

  String? _sessionErrorDetail;       // actual error text for UI

  Future<void> _startSession() async {
    // Stop any previous session, using the generation counter so only
    // the correct session is stopped.
    try { await _bridge.stopSession(generation: _sessionGeneration); } catch (_) {}

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
        _detectedDepthMode = 'plate_fallback';
      }

      // ── 4. Upgrade to depth config in the background ──────────────────
      // The session started with a bare config (no depth/mesh) to maximise
      // startup reliability.  Now that frames are flowing, add depth.
      _bridge.upgradeDepthConfig();

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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Camera Required'),
        content: const Text(
          'Pixels to Macros needs camera access to scan your food. '
          'Please enable it in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pitchTimer?.cancel();
    _noFoodResetTimer?.cancel();
    _isRecording = false;
    _isInferenceRunning = false;
    // Make sure we never leave the torch on after the user leaves the screen.
    if (_torchOn) {
      try { _bridge.setTorch(false); } catch (_) {}
    }
    // Use generation-aware stop so this fire-and-forget call can never
    // accidentally kill a session started by a newer ScanScreen instance.
    try {
      _bridge.stopSession(generation: _sessionGeneration);
    } catch (_) {}
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

  Future<void> _pollPitch() async {
    if (!mounted || !_sessionStarted) return;
    double pitch;
    try {
      pitch = await _bridge.getPhonePitch();
    } catch (e) {
      return;
    }
    if (!mounted) return;
    setState(() => _currentPitch = pitch);

    // Sample ambient light every ~5 ticks (~3 Hz) — cheap.
    _pitchTickCounter++;
    if (_pitchTickCounter % 5 == 0) {
      _bridge.getAmbientIntensity().then((lux) {
        if (mounted && lux != _ambientLux) {
          setState(() => _ambientLux = lux);
        }
      }).catchError((_) {});
    }

    final state = ref.read(scanStateProvider);

    // Auto-start recording when phone points down (top-view).
    if (state == ScanState.waitingForTopView && pitch < _topViewThreshold) {
      ref.read(scanStateProvider.notifier).topViewDetected();
      _startRecording();
      return;
    }

    // Auto-stop recording when phone reaches side-view.
    // Guard: don't trigger if inference is already in-flight.
    if (state == ScanState.recording &&
        pitch > _sideViewThreshold &&
        !_isInferenceRunning) {
      _stopRecording();
    }
  }

  // ── Recording ────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isRecording || !mounted) return;
    _hapticMedium();
    setState(() {
      _isRecording    = true;
      _recordProgress = 0.0;
    });
    ref.read(scanStateProvider.notifier).startedRecording();
    try {
      PerfMonitor.instance.start('record');
      await _bridge.startRecording();
    } catch (e) {
      DebugLog.instance.log('Scan', 'Recording start failed: $e — resetting');
      _hapticError();
      if (!mounted) return;
      setState(() => _isRecording = false);
      ref.read(scanStateProvider.notifier).reset();
      return;
    }

    // Recording stops automatically when the phone reaches vertical (side-view).
    // The max-duration timer is a safety fallback only.
    final totalTicks = _maxRecordDuration.inMilliseconds ~/
        _timerInterval.inMilliseconds;
    var tick = 0;
    _recordTimer = Timer.periodic(_timerInterval, (t) {
      if (!mounted) { t.cancel(); return; }
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
    _recordTimer?.cancel();
    _recordTimer = null;
    if (!mounted) return;
    setState(() {
      _isRecording       = false;
      _isInferenceRunning = true;
      _recordProgress    = 1.0;
    });
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

    if (result == null || result.noFood || (result.foods.isEmpty && result.error == null)) {
      // No food recognised — stay on scan screen with a friendly retry message.
      _hapticError();
      _showNoFoodOverlay();
    } else if (result.error != null) {
      DebugLog.instance.log('Scan', 'Inference error: ${result.error}');
      _hapticError();
      ref.read(scanStateProvider.notifier).modelFailed();
    } else {
      DebugLog.instance.log('Scan',
          'Inference done: ${result.foods.length} items, '
          '${result.totalCaloriesMin.round()}-${result.totalCaloriesMax.round()} kcal');
      _hapticSuccess();
      ref.read(scanStateProvider.notifier).calculationDone();
      DebugLog.instance.log('Perf', PerfMonitor.instance.report());
      if (mounted) await _saveScanResult(result);
    }
  }

  /// Show a friendly "no food" banner and auto-reset to the aim state after 3 s.
  void _showNoFoodOverlay() {
    if (!mounted) return;
    _noFoodResetTimer?.cancel();
    setState(() {
      _noFoodMessage = 'No food detected.\nMake sure the food fills the frame,\nthen scan again.';
    });
    _noFoodResetTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _noFoodMessage = null);
      ref.read(scanStateProvider.notifier).reset();
      ref.read(scanResultProvider.notifier).reset();
    });
  }

  Future<void> _saveScanResult(ScanResultState resultState) async {
    try {
      final scanResult = ScanResult(
        timestamp: DateTime.now(),
        depthMode: _detectedDepthMode,
        foods: resultState.foods,
        topCameraPosition:  null,
        topCameraTransform: null,
        sideCameraPosition:  null,
        sideCameraTransform: null,
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
    } catch (e) {
      DebugLog.instance.log('Scan', 'Save result error: $e');
    }
  }

  void _retry() {
    _hapticLight();
    _recordTimer?.cancel();
    _recordTimer        = null;
    _pitchTimer?.cancel();
    _pitchTimer         = null;
    _noFoodResetTimer?.cancel();
    _noFoodResetTimer   = null;
    _isRecording        = false;
    _isInferenceRunning = false;
    _recordProgress     = 0.0;
    _sessionStarted     = false;
    _sessionErrorDetail = null;
    _noFoodMessage      = null;
    ref.read(scanStateProvider.notifier).reset();
    ref.read(scanResultProvider.notifier).reset();
    _startSession();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanStateProvider);
    final scanResult = ref.watch(scanResultProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Live AR camera preview ───────────────────────────────────
          // Always show the ARKit camera platform view so the background is
          // never a plain black container.  The native ARSCNView handles the
          // "no session yet" case internally (shows black until the session
          // starts, then auto-connects via the arSessionDidStart notification).
          const Positioned.fill(
            child: UiKitView(viewType: 'com.pixelstomacros/ar_camera'),
          ),

          // ── Guidance overlay ─────────────────────────────────────────
          ScanGuidanceOverlay(scanState: scanState, currentPitch: _currentPitch),

          // ── Bottom action panel ─────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
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
              onClose: () => Navigator.of(context).pop(),
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

          // ── Close button (top-left) ─────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // ── Flashlight toggle (top-right) ───────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: Icon(
                _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                color: _torchOn ? AppTheme.amber500 : Colors.white70,
                size: 28,
              ),
              tooltip: _torchOn ? 'Turn off flashlight' : 'Turn on flashlight',
              onPressed: () async {
                final next = !_torchOn;
                final ok = await _bridge.setTorch(next);
                if (!mounted) return;
                if (ok) {
                  setState(() => _torchOn = next);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Flashlight unavailable on this device.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),

          // ── Low-light warning banner ────────────────────────────────
          if (_ambientLux >= 0 && _ambientLux < 200 && !_torchOn)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.amber500),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.nightlight_round,
                        color: AppTheme.amber500, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Low light — turn on the flashlight for better detection.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Tutorial overlay (first scan) ───────────────────────────
          if (_showTutorial)
            ScanTutorialOverlay(onDismiss: _dismissTutorial),

          // ── No-food overlay ──────────────────────────────────────────
          if (_noFoodMessage != null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.amber500, width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_food_outlined,
                            size: 48, color: AppTheme.amber500),
                        const SizedBox(height: 12),
                        Text(
                          _noFoodMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Returning to scan in 3s…',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            _noFoodResetTimer?.cancel();
                            setState(() => _noFoodMessage = null);
                            ref.read(scanStateProvider.notifier).reset();
                            ref.read(scanResultProvider.notifier).reset();
                          },
                          child: const Text('Scan Again Now'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 20, 24, MediaQuery.of(context).padding.bottom + 20,
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
            ),

          // ── Ready to record (manual fallback) ─────────────────────
          if (scanState == ScanState.readyToRecord)
            _RecordButton(
              enabled: sessionStarted,
              isRecording: false,
              progress: 0,
              onPressed: onStartRecord,
            ),

          // ── Recording in progress ─────────────────────────────────
          if (scanState == ScanState.recording)
            _RecordButton(
              enabled: true,
              isRecording: true,
              progress: recordProgress,
              onPressed: onStopRecord,
            ),

          // ── Processing ────────────────────────────────────────────
          if (scanState == ScanState.calculating)
            const _ProcessingIndicator(text: 'Building 3-D model…'),

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
                    label: '${timings.values.fold(Duration.zero, (a, b) => a + b).inMilliseconds}ms total',
                  ),
                _InfoChipDark(
                  icon: Icons.restaurant,
                  label: '${scanResult.foods.length} item${scanResult.foods.length == 1 ? '' : 's'}',
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
                    child: const Text('Scan Again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onViewDetails ?? onClose,
                    child: Text(onViewDetails != null ? 'View Details' : 'Done'),
                  ),
                ),
              ],
            ),
          ],

          // ── Error states → retry + back ───────────────────────────
          if (scanState.isError) ...[
            const Icon(Icons.error_outline, size: 40, color: AppTheme.red500),
            const SizedBox(height: 8),
            Text(
              scanState.label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            // Show the ACTUAL native error so the user/developer can
            // see exactly why the camera failed.
            if (sessionErrorDetail != null) ...[
              const SizedBox(height: 8),
              _ScanErrorBox(error: sessionErrorDetail!),
            ] else if (scanResult.error != null) ...[
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
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
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
    (ScanState.recording,     'Record'),
    (ScanState.calculating,   'Analyse'),
    (ScanState.done,          'Done'),
  ];

  int get _activeIndex {
    return switch (state) {
      ScanState.waitingForTopView => 0,
      ScanState.readyToRecord     => 0,
      ScanState.recording         => 1,
      ScanState.calculating       => 2,
      ScanState.done              => 3,
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
    required this.onPressed,
  });

  final bool enabled;
  final bool isRecording;
  final double progress;   // 0.0 – 1.0
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
                        : (enabled ? context.primary500 : context.primary500.withValues(alpha: 0.3)),
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
              ? '${((1.0 - progress) * 2).ceil()}s remaining'
              : (enabled ? 'Tap to scan' : 'Starting camera…'),
          style: TextStyle(
            fontSize: 12,
            color: isRecording ? AppTheme.amber500 : Colors.white54,
          ),
        ),
      ],
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.color,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.primary500;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
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
  });

  final double pitch;       // radians: -π/2 = top-view, 0 = horizontal
  final bool sessionStarted;

  @override
  Widget build(BuildContext context) {
    if (!sessionStarted) {
      return const _ProcessingIndicator(text: 'Starting camera…');
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
              ? 'Top view detected — starting…'
              : 'Tilt phone down ($angleDeg°)',
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
                    'Error — tap & hold to copy',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade300,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy, size: 14, color: Colors.red.shade300),
                  tooltip: 'Copy error',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error copied'),
                        duration: Duration(seconds: 2),
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
