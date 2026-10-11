import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
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
import '../widgets/ai_scan_processing_view.dart';
import '../widgets/dual_photo_capture_overlay.dart';
import '../widgets/ai_scan_edge_glow.dart';
import '../models/scan_diagnostics.dart';
import '../providers/scan_diagnostics_provider.dart';
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

  /// True while runVideoInference is in-flight — prevents re-entry.
  bool _isInferenceRunning = false;

  /// True while a top/side photo is being committed — prevents double capture.
  bool _capturing = false;
  bool? _captureExtraAccuracy;
  bool get _extraAccuracy =>
      _captureExtraAccuracy ?? ref.read(userPrefsProvider).extraAccuracy;

  Timer? _pitchTimer; // polls orientation + stability at ~12 fps
  double _stability = 0.0; // 0..1 from CoreMotion (1 = perfectly still)
  double _alignmentScore = 0.0; // 0..1 target-orientation score
  bool _aligned = false; // current orientation matches the active capture step
  double _tiltError = 0.0; // signed pitch error vs. the active step's target
  int _stableHoldTicks =
      0; // consecutive aligned+stable polls before auto-shutter
  String _detectedDepthMode = 'unknown';
  ScanResult? _savedScanResult;
  bool _launched3DViewer = false;
  bool _orientationReady = false;
  int? _sessionGeneration; // generation counter for safe stop()

  /// Flashlight (torch) state and ambient light (lux) for low-light warning.
  bool _torchOn = false;
  double _ambientLux = -1.0;
  int _pitchTickCounter = 0;

  /// Live food detection on the camera preview (native "AI glow").
  bool _foodDetected = false;
  bool _liveDetectionAvailable = false;
  bool _liveGlowRunning = false;
  String? _liveGlowStyleKey;
  bool? _liveGlowSideView;

  /// Camera frame aspect (long / short side) reported by the native preview;
  /// the guide sits on the frame's centred square like the native ROI.
  double _videoAspect = ScanGuideGeometry.defaultVideoAspect;

  /// The guided capture takes two deliberate, orientation- and stability-gated
  /// photos: a top-down view, then a side profile. The auto-shutter fires only
  /// after the phone has held the correct orientation AND been still for
  /// [_requiredHoldTicks] consecutive polls — eliminating motion blur. The two
  /// frames feed the SAME 3-D reconstruction pipeline the video sweep used.
  static const Duration _pollInterval = Duration(milliseconds: 80);

  /// Stability (0..1) at/above which the phone is considered "still enough" to
  /// capture, and the number of consecutive aligned+stable polls required
  /// before the shutter fires.
  static const double _stableThreshold = 0.45;
  static const double _softStableThreshold = 0.30;
  static const int _requiredHoldTicks = 4;

  static const double _topViewTargetRad =
      -1.5707963267948966; // -90° straight down
  static const double _sideViewTargetRad = 0.0; // 0° perfectly horizontal

  @override
  void initState() {
    super.initState();
    // The scan is performed in LANDSCAPE: the moment the scan screen opens we
    // force the app to landscape so it is obvious the phone must be held
    // sideways for the guided top→side photo capture. Portrait is restored the
    // instant the second (side) photo is taken (see [_captureSide]) and on
    // leaving the screen. The landscape lock itself is applied in
    // [_startSession] so it also re-applies after a retry. The ARKit preview
    // transform is orientation-aware.
    // Reset any stale state from a previous scan session (the provider is
    // NOT autoDispose so depthFailed / modelFailed from earlier persists).
    // Defer both reset AND session start to post-frame callback so that
    // the previous screen's dispose() (and its fire-and-forget stopSession)
    // has already been sent to the method channel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(scanStateProvider.notifier).reset();
        ref.read(scanResultProvider.notifier).reset();
        // Only start session immediately if no tutorial is shown.
        // If tutorial is shown, _startSession is called from _dismissTutorial.
        if (!_showTutorial) _startSession();
      }
    });
    _checkTutorial();
    _bridge.setLiveDetectionListener(
      _onLiveDetection,
      onVideoSize: _onPreviewVideoSize,
    );
  }

  void _onPreviewVideoSize(double width, double height) {
    final aspect = math.max(width, height) / math.min(width, height);
    if (!mounted || (aspect - _videoAspect).abs() < 1e-4) return;
    setState(() => _videoAspect = aspect);
  }

  void _onLiveDetection(LiveFoodDetection d) {
    if (!mounted) return;
    final detected = d.detected && _liveGlowRunning;
    if (detected == _foodDetected && d.available == _liveDetectionAvailable) {
      return;
    }
    setState(() {
      _foodDetected = detected;
      _liveDetectionAvailable = d.available;
    });
  }

  /// Starts, restyles, re-targets or stops the native live food glow so it
  /// only runs while the user is framing a shot (never while capturing or
  /// processing). Called from build; only talks to the platform channel when
  /// something actually changed.
  void _syncLiveGlow({
    required bool want,
    required ScanChromePalette palette,
    required bool reduceMotion,
    required bool sideView,
  }) {
    if (!want) {
      if (_liveGlowRunning) {
        _liveGlowRunning = false;
        _liveGlowStyleKey = null;
        _liveGlowSideView = null;
        unawaited(_bridge.stopLiveGlow());
        if (_foodDetected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_liveGlowRunning) {
              setState(() => _foodDetected = false);
            }
          });
        }
      }
      return;
    }
    final styleKey = '${palette.hashCode}|$reduceMotion';
    if (!_liveGlowRunning || styleKey != _liveGlowStyleKey) {
      _liveGlowRunning = true;
      _liveGlowStyleKey = styleKey;
      _liveGlowSideView = sideView;
      unawaited(_bridge.startLiveGlow(
        colors: palette.nativeColors,
        premium: palette.premium,
        reduceMotion: reduceMotion,
        sideView: sideView,
      ));
    } else if (sideView != _liveGlowSideView) {
      _liveGlowSideView = sideView;
      unawaited(_bridge.updateLiveGlowRoi(sideView: sideView));
    }
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

  Future<void> _closeScan() async {
    _isInferenceRunning = false;
    await _restorePortrait();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String? _sessionErrorDetail; // actual error text for UI

  /// Force the app into landscape for the duration of the scan sweep so the
  /// user clearly knows to hold the phone sideways.
  ///
  /// We lock to a SINGLE landscape orientation (not both) so the rear camera
  /// sits on the LOWER end of the phone rather than the upper end. ARKit's
  /// native sensor orientation is `landscapeRight`, which places the rear
  /// camera on the far/upper end while scanning; forcing `landscapeLeft`
  /// (the opposite side) puts the camera on the lower end so the user doesn't
  /// have to drop the phone as far down to frame food on the table. The native
  /// preview layer rotates 180° for `landscapeLeft`, so the feed stays upright.
  Future<void> _lockLandscape() async {
    if (mounted && _orientationReady) {
      setState(() => _orientationReady = false);
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
    ]);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      setState(() => _orientationReady = true);
    }
  }

  /// Restore portrait the moment the sweep finishes / the screen is left.
  Future<void> _restorePortrait() async {
    if (mounted && _orientationReady) {
      setState(() => _orientationReady = false);
    }
    await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp]);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _startSession() async {
    // The scan runs in landscape — (re)apply the lock on every session start
    // (initial open and retry).
    await _lockLandscape();
    if (!mounted) return;
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
        // Reset the native recorder for a fresh top→side capture.
        unawaited(_bridge.beginScan());
        _startSensorPolling();
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
    _pitchTimer?.cancel();
    _bridge.setLiveDetectionListener(null);
    if (_liveGlowRunning) {
      _liveGlowRunning = false;
      unawaited(_bridge.stopLiveGlow());
    }
    _isInferenceRunning = false;
    _capturing = false;
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
    // Restore portrait for the rest of the app after leaving the scan flow.
    unawaited(SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    ));
    super.dispose();
  }

  // ── Haptic helpers ──────────────────────────────────────────────────────

  void _hapticLight() => HapticFeedback.lightImpact();
  void _hapticMedium() => HapticFeedback.mediumImpact();
  void _hapticHeavy() => HapticFeedback.heavyImpact();
  void _hapticSuccess() => HapticFeedback.mediumImpact();
  void _hapticError() => HapticFeedback.heavyImpact();

  // ── Orientation + stability tracking ──────────────────────────────────────

  void _startSensorPolling() {
    _pitchTimer = Timer.periodic(_pollInterval, (_) => _pollSensors());
  }

  Future<void> _pollSensors() async {
    if (!mounted || !_sessionStarted) return;

    double pitch;
    double stability;
    try {
      pitch = await _bridge.getPhonePitch();
      stability = await _bridge.getMotionStability();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final state = ref.read(scanStateProvider);

    // Which orientation does the active capture step require?
    bool aligned;
    double alignmentScore;
    double tiltError;
    if (state == ScanState.waitingForTopView || state == ScanState.captureTop) {
      tiltError = pitch - _topViewTargetRad;
      final error = tiltError.abs();
      aligned = ScanCaptureAlignment.isAligned(error);
      alignmentScore = _alignmentScoreFor(error);
    } else if (state == ScanState.moveSide || state == ScanState.captureSide) {
      tiltError = pitch - _sideViewTargetRad;
      final error = tiltError.abs();
      aligned = ScanCaptureAlignment.isAligned(error);
      alignmentScore = _alignmentScoreFor(error);
    } else {
      aligned = false;
      alignmentScore = 0.0;
      tiltError = 0.0;
    }

    final bool stable = stability >= _stableThreshold ||
        (_stableHoldTicks > 0 && stability >= _softStableThreshold);
    if (!aligned || _capturing) {
      _stableHoldTicks = 0;
    } else if (stable) {
      _stableHoldTicks++;
    } else {
      _stableHoldTicks = (_stableHoldTicks - 1).clamp(0, _requiredHoldTicks);
    }

    setState(() {
      _stability = stability;
      _alignmentScore = alignmentScore;
      _aligned = aligned;
      _tiltError = tiltError;
    });

    // Sample ambient light every ~5 ticks — cheap; drives the low-light banner.
    _pitchTickCounter++;
    if (_pitchTickCounter % 5 == 0) {
      unawaited(_bridge.getAmbientIntensity().then((lux) {
        if (mounted && lux != _ambientLux) {
          setState(() => _ambientLux = lux);
        }
      }).catchError((_) {}));
    }

    // Auto-shutter: fire only once the phone has held the correct orientation
    // AND been still for [_requiredHoldTicks] consecutive polls.
    if (!_capturing && _stableHoldTicks >= _requiredHoldTicks) {
      if (state == ScanState.waitingForTopView) {
        unawaited(_captureTop());
      } else if (state == ScanState.moveSide) {
        unawaited(_captureSide());
      }
    }
  }

  /// Progress (0..1) of the "hold steady" gate, for the UI stability meter.
  double get _holdProgress =>
      (_stableHoldTicks / _requiredHoldTicks).clamp(0.0, 1.0);

  double _alignmentScoreFor(double error) => ScanCaptureAlignment.score(error);

  // ── Guided dual-photo capture ──────────────────────────────────────────────

  /// Commit the top-down photo, then advance to the side-view step.
  Future<void> _captureTop() async {
    if (_capturing || !mounted) return;
    setState(() {
      _captureExtraAccuracy ??= ref.read(userPrefsProvider).extraAccuracy;
      _capturing = true;
    });
    _stableHoldTicks = 0;
    _hapticMedium();
    ref.read(scanStateProvider.notifier).topAligned(); // → captureTop (flash)

    bool ok = false;
    try {
      PerfMonitor.instance.start('record');
      await _bridge.stopLiveGlow();
      ok = await _bridge.captureTopFrame();
      PerfMonitor.instance.end();
    } catch (e) {
      DebugLog.instance.log('Scan', 'captureTopFrame error: $e');
    }
    if (!mounted) return;

    if (!ok) {
      _hapticError();
      ref.read(scanStateProvider.notifier).sessionReady(); // retry top
      setState(() => _capturing = false);
      return;
    }

    _hapticSuccess();
    // Brief confirmation flash so the user sees the top shot landed.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (!_extraAccuracy) {
      await _restorePortrait();
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _isInferenceRunning = true;
      });
      try {
        await _runVideoInference();
      } finally {
        if (mounted) setState(() => _isInferenceRunning = false);
      }
      return;
    }
    ref.read(scanStateProvider.notifier).topCaptured(); // → moveSide
    setState(() => _capturing = false);
  }

  /// Commit the side-profile photo, then run reconstruction + inference on the
  /// two captured frames via the SAME pipeline the video sweep used.
  Future<void> _captureSide() async {
    if (_capturing || _isInferenceRunning || !mounted) return;
    setState(() => _capturing = true);
    _stableHoldTicks = 0;
    _hapticMedium();
    ref.read(scanStateProvider.notifier).sideReady(); // → captureSide (flash)

    bool ok = false;
    try {
      await _bridge.stopLiveGlow();
      ok = await _bridge.captureSideFrame();
    } catch (e) {
      DebugLog.instance.log('Scan', 'captureSideFrame error: $e');
    }
    if (!mounted) return;

    if (!ok) {
      _hapticError();
      ref.read(scanStateProvider.notifier).topCaptured(); // back to moveSide
      setState(() => _capturing = false);
      return;
    }

    _hapticHeavy();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    // Both photos captured → snap back to portrait while the (hidden-preview)
    // reconstruction runs, per the scan UX contract.
    await _restorePortrait();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      _isInferenceRunning = true;
    });
    ref.read(scanStateProvider.notifier).sideCaptured(); // → calculating

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
      await _bridge.stopLiveGlow();
      await ref
          .read(scanResultProvider.notifier)
          .runVideoScan(extraAccuracy: _extraAccuracy);
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

    if (result == null ||
        (result.foods.isEmpty &&
            !result.needsPortionReview &&
            !result.hasUnmeasuredFoods &&
            result.error == null)) {
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
      var successfulResult = result;
      if (successfulResult.needsPortionReview) {
        final accepted = await _reviewApproximatePortions(successfulResult);
        if (!mounted) return;
        if (!accepted) {
          await _closeScan();
          return;
        }
        successfulResult = ref.read(scanResultProvider);
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

  Future<bool> _reviewApproximatePortions(ScanResultState result) async {
    final l10n = AppLocalizations.of(context);
    final labels = [
      for (final portion in result.portions)
        TextEditingController(text: portion.label),
    ];
    final amounts = [
      for (final portion in result.portions)
        TextEditingController(text: portion.grams?.toStringAsFixed(0) ?? ''),
    ];
    var confirming = false;
    var invalid = false;
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => StatefulBuilder(
              builder: (context, updateDialog) => PopScope(
                canPop: !confirming,
                child: AlertDialog(
                  title: Text(l10n.reviewScanPortions),
                  content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.approximatePortionHelp),
                          for (var i = 0; i < labels.length; i++) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: labels[i],
                              enabled: !confirming,
                              decoration: InputDecoration(
                                  labelText: l10n.scanFoodLabel),
                            ),
                            TextField(
                              controller: amounts[i],
                              enabled: !confirming,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: l10n.scanPortionAmount),
                            ),
                          ],
                          if (invalid)
                            Text(l10n.scanPortionReviewInvalid,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: confirming
                          ? null
                          : () => Navigator.pop(context, false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: confirming
                          ? null
                          : () async {
                              updateDialog(() => confirming = true);
                              var accepted = false;
                              try {
                                accepted = await ref
                                    .read(scanResultProvider.notifier)
                                    .confirmApproximatePortions([
                                  for (var i = 0; i < labels.length; i++)
                                    ApproximatePortion(
                                      label: labels[i].text.trim(),
                                      grams: double.tryParse(
                                          amounts[i].text.replaceAll(',', '.')),
                                    ),
                                ]);
                              } catch (e) {
                                DebugLog.instance
                                    .log('ApproximateReview', '$e');
                              }
                              if (!context.mounted) return;
                              if (accepted) {
                                Navigator.pop(context, true);
                              } else {
                                updateDialog(() {
                                  confirming = false;
                                  invalid = true;
                                });
                              }
                            },
                      child: Text(l10n.save),
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          false;
    } finally {
      for (final controller in [...labels, ...amounts]) {
        controller.dispose();
      }
    }
  }

  Future<void> _saveScanResult(ScanResultState resultState) async {
    try {
      if (resultState.approximate) {
        if (resultState.needsPortionReview || resultState.foods.isEmpty) {
          throw StateError('portion_review_required');
        }
        final paths = await _bridge.getScanCapturePaths();
        final scan = ScanResult(
          timestamp: DateTime.now(),
          depthMode: 'approximate',
          foods: resultState.foods,
          imagePath: paths['topImagePath'] as String?,
          topImagePath: paths['topImagePath'] as String?,
          modelObjectsJson: jsonEncode(resultState.metadata),
        );
        final diagnostics = ScanDiagnostics.fromCapture(
          depthMode: 'approximate',
          nativeObjects: resultState.metadata,
          timings: PerfMonitor.instance.allTimings,
        );
        ref.read(scanDiagnosticsProvider.notifier).add(diagnostics);
        DebugLog.instance.log('ScanDiag', diagnostics.toReport());
        await ref.read(historyProvider.notifier).addScan(scan);
        if (!mounted) return;
        await ref.read(dailyIntakeProvider.notifier).load();
        await ref.read(streakProvider.notifier).load();
        if (!mounted) return;
        _savedScanResult = ref.read(historyProvider).scans.firstOrNull;
        return;
      }
      // Hard contract: a successful scan must have a real 3-D model file.
      final model3dPath = await _bridge.getModel3DPath();
      final capturePaths = await _bridge.getScanCapturePaths();
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

      // Capture structured scanner diagnostics for inspection/validation.
      try {
        var diagMemory = 0;
        try {
          diagMemory = await _bridge.getMemoryUsage();
        } catch (_) {}
        final diagnostics = ScanDiagnostics.fromCapture(
          depthMode: _detectedDepthMode,
          nativeObjects: model3dRaw,
          timings: PerfMonitor.instance.allTimings,
          peakMemoryBytes: diagMemory,
          ambientLux: _ambientLux,
          stability: _stability,
        );
        if (mounted) {
          ref.read(scanDiagnosticsProvider.notifier).add(diagnostics);
        }
        DebugLog.instance.log('ScanDiag', diagnostics.toReport());
      } catch (e) {
        DebugLog.instance.log('ScanDiag', 'capture failed: $e');
      }

      final scanResult = ScanResult(
        timestamp: DateTime.now(),
        depthMode: _detectedDepthMode,
        foods: resultState.foods,
        topCameraPosition: null,
        topCameraTransform: null,
        sideCameraPosition: null,
        sideCameraTransform: null,
        imagePath: capturePaths['topImagePath'] as String?,
        topImagePath: capturePaths['topImagePath'] as String?,
        sideImagePath: capturePaths['sideImagePath'] as String?,
        modelPath: model3dPath,
        modelObjectsJson: model3dObjects.isEmpty
            ? null
            : jsonEncode(model3dObjects.map((o) => o.toMap()).toList()),
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
      await _launch3DViewer(model3dPath, model3dObjects);
    } catch (e) {
      DebugLog.instance.log('Scan', 'Save result error: $e');
      rethrow;
    }
  }

  Future<void> _launch3DViewer(String path, List<Scan3DObject> objects) async {
    if (_launched3DViewer || !mounted) return;
    _launched3DViewer = true;
    await _restorePortrait();
    if (!mounted) return;
    debugPrint('[SCAN] launching Scan3DViewer');
    DebugLog.instance.log('Scan3D', 'launching Scan3DViewer: $path');
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => Scan3DViewerScreen(
            modelPath: path,
            objects: objects,
            scanId: _savedScanResult?.id,
          ),
        ),
      ),
    );
  }

  void _retry() {
    _hapticLight();
    _pitchTimer?.cancel();
    _pitchTimer = null;
    _capturing = false;
    _isInferenceRunning = false;
    _stableHoldTicks = 0;
    _sessionStarted = false;
    _sessionErrorDetail = null;
    _launched3DViewer = false;
    _captureExtraAccuracy = null;
    _savedScanResult = null;
    ref.read(scanStateProvider.notifier).reset();
    ref.read(scanResultProvider.notifier).reset();
    _startSession();
  }

  /// Whether the given state belongs to the guided dual-photo capture phase
  /// (top/side framing + capture), as opposed to processing/done/error.
  bool _isCaptureState(ScanState s) =>
      s == ScanState.waitingForTopView ||
      s == ScanState.captureTop ||
      s == ScanState.moveSide ||
      s == ScanState.captureSide;

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanStateProvider);
    final scanResult = ref.watch(scanResultProvider);
    final l10n = AppLocalizations.of(context);
    final isProcessing =
        scanState == ScanState.calculating || scanState == ScanState.done;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final landscape = screen.width > screen.height;
    final palette = ScanChromePalette.of(context);
    final cameraVisible = _orientationReady && _sessionStarted && !isProcessing;
    final captureChrome =
        _orientationReady && _sessionStarted && _isCaptureState(scanState);

    // Live "AI glow" on the food: only while framing a shot in landscape.
    final framing = scanState == ScanState.waitingForTopView ||
        scanState == ScanState.moveSide;
    _syncLiveGlow(
      want: cameraVisible &&
          landscape &&
          framing &&
          !_capturing &&
          !_showTutorial,
      palette: palette,
      reduceMotion: mq.disableAnimations || mq.accessibleNavigation,
      sideView: scanState == ScanState.moveSide,
    );

    final railX = landscape
        ? ScanGuideGeometry.rightRailCenterX(screen, mq.padding, _videoAspect)
        : screen.width - mq.padding.right - 14 - 22;
    final lowLight = _ambientLux >= 0 && _ambientLux < 200 && !_torchOn;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Live AR camera preview ───────────────────────────────────
          // Hide the platform view during inference/done so Flutter widgets
          // (close button, cancel) can receive touches unobstructed.
          // ARKit inference runs on a background Swift thread independently.
          // The native view also draws the live "AI glow" on detected food.
          if (cameraVisible)
            const Positioned.fill(
              child: UiKitView(viewType: 'com.pixelstomacros/ar_camera'),
            )
          else
            const Positioned.fill(child: ColoredBox(color: Colors.black)),

          // ── Guided dual-photo capture overlay ────────────────────────
          if (captureChrome)
            Positioned.fill(
              child: DualPhotoCaptureOverlay(
                scanState: scanState,
                aligned: _aligned,
                alignmentScore: _alignmentScore,
                stability: _stability,
                holdProgress: _holdProgress,
                capturing: _capturing,
                scanMode: _detectedDepthMode,
                tiltError: _tiltError,
                foodDetected: _foodDetected,
                liveDetectionAvailable: _liveDetectionAvailable,
                videoAspect: _videoAspect,
                lowLight: lowLight,
                extraAccuracy: _captureExtraAccuracy ??
                    ref.watch(userPrefsProvider
                        .select((prefs) => prefs.extraAccuracy)),
                onExtraAccuracyChanged:
                    scanState == ScanState.waitingForTopView &&
                            !_capturing &&
                            _captureExtraAccuracy == null
                        ? (value) {
                            _stableHoldTicks = 0;
                            unawaited(ref
                                .read(userPrefsProvider.notifier)
                                .update(ref
                                    .read(userPrefsProvider)
                                    .copyWith(extraAccuracy: value)));
                          }
                        : null,
              ),
            ),

          if (scanState == ScanState.calculating)
            Positioned(
              top: mq.padding.top + 104,
              left: 16,
              right: 16,
              child: AiScanProcessingView(
                height: 250,
                label: _extraAccuracy
                    ? l10n.building3dPreview
                    : l10n.approximateEstimate,
              ),
            ),

          // ── Premium AI edge effect (signals on-device intelligence) ──
          // Theme-aware glow that hugs the screen edges while a scan is in
          // progress. IgnorePointer + premium-gated internally.
          if (_orientationReady && _sessionStarted)
            Positioned.fill(
              child: AiScanEdgeGlow(
                active: _isCaptureState(scanState) ||
                    scanState == ScanState.calculating,
                intensity: scanState == ScanState.calculating ? 1.0 : 0.7,
              ),
            ),

          // ── Bottom action panel (processing / done / error only) ─────
          if (!_isCaptureState(scanState))
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
                  depthMode:
                      _extraAccuracy ? _detectedDepthMode : 'approximate',
                  timings: PerfMonitor.instance.allTimings,
                  onRetry: _retry,
                  onClose: () => unawaited(_closeScan()),
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

          // ── Close button (top-left) — translucent glass circle ──────
          Positioned(
            top: mq.padding.top + 12,
            left: (landscape ? mq.padding.left : 0) + 12,
            child: _GlassCircleButton(
              size: 40,
              semanticsLabel: l10n.close,
              onTap: () => unawaited(_closeScan()),
              child: const Icon(
                CupertinoIcons.xmark,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),

          // ── Flash toggle — iPhone Camera style ──────────────────────
          // Off = translucent glass circle with a slashed bolt
          // (bolt.slash.fill); On = solid Camera-app yellow with a black bolt
          // (bolt.fill). Sits at the top of the right control rail.
          Positioned(
            top: mq.padding.top + 12,
            left: railX - 22,
            child: _GlassCircleButton(
              size: 44,
              semanticsLabel:
                  _torchOn ? l10n.turnOffFlashlight : l10n.turnOnFlashlight,
              fill: _torchOn ? _cameraYellow : null,
              onTap: () async {
                final next = !_torchOn;
                final ok = await _bridge.setTorch(next);
                if (!context.mounted) return;
                if (ok) {
                  unawaited(HapticFeedback.selectionClick());
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _torchOn
                      ? CupertinoIcons.bolt_fill
                      : CupertinoIcons.bolt_slash_fill,
                  key: ValueKey(_torchOn),
                  color: _torchOn ? Colors.black : Colors.white,
                  size: 20,
                ),
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
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final VoidCallback? onViewDetails;

  String _scanErrorTitle(AppLocalizations l10n) {
    if (scanResult.failureKind ==
        ScanFailureKind.containerPortionReviewRequired) {
      return l10n.containerPortionReviewTitle;
    }
    if (scanState == ScanState.depthFailed) {
      return l10n.cameraSessionFailedTitle;
    }
    if (scanResult.failureKind == ScanFailureKind.sideViewRequired) {
      return l10n.sideViewRequiredTitle;
    }
    if (scanResult.failureKind == ScanFailureKind.dualSilhouetteFailed) {
      return "Couldn't build a 3D scan";
    }
    return scanResult.failureKind == ScanFailureKind.reconstructionFailed
        ? l10n.scan3dFailed
        : l10n.scanAnalysisFailed;
  }

  String _scanErrorBody(AppLocalizations l10n) {
    if (scanResult.failureKind ==
        ScanFailureKind.containerPortionReviewRequired) {
      return l10n.containerPortionReviewBody;
    }
    if (scanResult.failureKind == ScanFailureKind.sideViewRequired) {
      return l10n.sideViewRequiredBody;
    }
    if (scanResult.failureKind == ScanFailureKind.dualSilhouetteFailed) {
      return 'We need a clear top AND side view of the food to build the '
          'model. Please scan again:';
    }
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
          if (!scanResult.approximate && depthMode != 'approximate')
            _StateProgressRow(state: scanState),
          const SizedBox(height: 16),

          // ── Processing ────────────────────────────────────────────
          if (scanState == ScanState.calculating) ...[
            Text(
              depthMode == 'approximate'
                  ? l10n.approximateEstimate
                  : depthMode == 'monocular_scale'
                      ? l10n.generatingEstimated3dModel
                      : l10n.buildingLidar3dModel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClose,
              child: Text(l10n.cancel,
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ),
          ],

          // ── Done → results + confidence ───────────────────────────
          if (scanState == ScanState.done) ...[
            if (scanResult.approximate)
              Text(
                '${l10n.approximateEstimate} • ${scanResult.totalCaloriesMin.round()} kcal',
                style: const TextStyle(color: Colors.white),
              ),
            if (!scanResult.hasUnmeasuredFoods && !scanResult.approximate)
              ConfidenceBadge(
                caloriesMin: scanResult.totalCaloriesMin,
                caloriesMax: scanResult.totalCaloriesMax,
              ),
            if (scanResult.hasUnmeasuredFoods)
              Text(
                '${l10n.scanUnmeasuredFoods(scanResult.unmeasuredFoodLabels.join(', '))}\n'
                '${l10n.scanSideRecaptureGuidance}',
                style: const TextStyle(color: Colors.white),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                _InfoChipDark(
                  icon: Icons.visibility,
                  label: scanResult.approximate
                      ? l10n.approximateScanMode
                      : depthMode.replaceAll('_', ' '),
                ),
                if (timings.isNotEmpty)
                  _InfoChipDark(
                    icon: Icons.timer,
                    label:
                        '${timings.values.fold(Duration.zero, (a, b) => a + b).inMilliseconds}ms total',
                  ),
                _InfoChipDark(
                  icon: Icons.restaurant,
                  label: l10n.scanItemCount(scanResult.foods.length +
                      scanResult.unmeasuredFoodLabels.length),
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
            // Primary action: the scan is already saved to the diary on
            // completion. This opens the logged meal's details — which, for
            // diabetes users, includes the glucose-spike + insulin-timing
            // insight — or just confirms and returns home.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onViewDetails ?? onClose,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(AppLocalizations.of(context).logFood),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primary500,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
                  child: OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: Text(AppLocalizations.of(context).done),
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
            if (scanResult.failureKind ==
                ScanFailureKind.dualSilhouetteFailed) ...[
              const SizedBox(height: 12),
              const _DualSilhouetteTips(),
            ] else if (!isNoFood && sessionErrorDetail != null) ...[
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
                    child: Text(scanResult.failureKind ==
                            ScanFailureKind.sideViewRequired
                        ? l10n.sideViewRequiredRetake
                        : l10n.retry),
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

  int get _activeIndex {
    return switch (state) {
      ScanState.waitingForTopView => 0,
      ScanState.readyToRecord => 0,
      ScanState.captureTop => 0,
      ScanState.recording => 1,
      ScanState.moveSide => 1,
      ScanState.captureSide => 1,
      ScanState.calculating => 2,
      ScanState.done => 3,
      _ => -1, // error
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = _activeIndex;
    final steps = [
      l10n.scanTopView,
      l10n.scanSideView,
      l10n.scanStepAnalyse,
      l10n.done,
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= active ? context.primary400 : Colors.white12,
              ),
            ),
          _StepDot(
            label: steps[i],
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

/// Actionable failure card shown when dual-silhouette reconstruction fails.
/// Plain-language tips only (no technical jargon), per the scan UX spec.
class _DualSilhouetteTips extends StatelessWidget {
  const _DualSilhouetteTips();

  static const List<(IconData, String)> _tips = [
    (
      Icons.wb_sunny_outlined,
      'Use even lighting — avoid glare and deep shadows'
    ),
    (
      Icons.center_focus_strong,
      'Keep the whole food centred and fully in frame'
    ),
    (
      Icons.pan_tool_outlined,
      "Hold steady — don't move the food between shots"
    ),
    (Icons.lens_blur, 'Wipe the lens and use a plain, uncluttered background'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in _tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(tip.$1, size: 16, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip.$2,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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

/// iPhone Camera flash-on yellow.
const Color _cameraYellow = Color(0xFFFFD60A);

/// Circular translucent "glass" control used by the camera chrome (close and
/// flash), modelled on the round controls of the iPhone Camera app.
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.size,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    this.fill,
  });

  final double size;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  /// Solid fill (e.g. flash on); null = translucent glass.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill ?? Colors.black.withValues(alpha: 0.42),
                  border: Border.all(
                    color: fill != null
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
