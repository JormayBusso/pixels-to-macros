import 'dart:convert';
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
  bool _sessionStarted = false;
  bool _showTutorial = false;
  String _detectedDepthMode = 'unknown';
  ScanResult? _savedScanResult;

  // Camera pose metadata from capture (Part 9)
  Map<String, dynamic> _topFrameMeta = {};
  Map<String, dynamic> _sideFrameMeta = {};

  @override
  void initState() {
    super.initState();
    _checkTutorial();
    _startSession();
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

  Future<void> _startSession() async {
    try {
      // Request camera permission before starting ARKit
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        DebugLog.instance.log('Scan', 'Camera permission denied: $status');
        if (mounted) {
          _showCameraPermissionDialog();
        }
        return;
      }

      DebugLog.instance.log('Scan', 'Starting AR session');
      await _bridge.startSession();
      // Detect depth mode for this device
      try {
        _detectedDepthMode = await _bridge.getDepthMode();
        DebugLog.instance.log('Scan', 'Depth mode: $_detectedDepthMode');
      } catch (_) {
        _detectedDepthMode = 'plate_fallback';
      }
      setState(() => _sessionStarted = true);
      DebugLog.instance.log('Scan', 'AR session started');
    } catch (e) {
      DebugLog.instance.log('Scan', 'AR session failed: $e');
      ref.read(scanStateProvider.notifier).depthFailed();
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
    _bridge.stopSession();
    super.dispose();
  }

  // ── Haptic helpers ──────────────────────────────────────────────────────

  void _hapticLight() => HapticFeedback.lightImpact();
  void _hapticMedium() => HapticFeedback.mediumImpact();
  void _hapticHeavy() => HapticFeedback.heavyImpact();
  void _hapticSuccess() => HapticFeedback.mediumImpact();
  void _hapticError() => HapticFeedback.heavyImpact();

  // ── State-driven actions ────────────────────────────────────────────────

  Future<void> _captureTop() async {
    _hapticLight();
    ref.read(scanStateProvider.notifier).topAligned();
    try {
      PerfMonitor.instance.start('capture_top');
      _topFrameMeta = await _bridge.captureFrame('top');
      PerfMonitor.instance.end();
      _hapticMedium();
      ref.read(scanStateProvider.notifier).topCaptured();
    } catch (_) {
      _hapticError();
      ref.read(scanStateProvider.notifier).depthFailed();
    }
  }

  Future<void> _captureSide() async {
    _hapticLight();
    ref.read(scanStateProvider.notifier).sideReady();
    try {
      PerfMonitor.instance.start('capture_side');
      _sideFrameMeta = await _bridge.captureFrame('side');
      PerfMonitor.instance.end();
      _hapticMedium();
      ref.read(scanStateProvider.notifier).sideCaptured();
      await _runInference();
    } catch (_) {
      _hapticError();
      ref.read(scanStateProvider.notifier).depthFailed();
    }
  }

  Future<void> _runInference() async {
    DebugLog.instance.log('Scan', 'Running inference pipeline');
    PerfMonitor.instance.reset();
    PerfMonitor.instance.start('inference');
    await ref.read(scanResultProvider.notifier).runScan();
    PerfMonitor.instance.end();
    final result = ref.read(scanResultProvider);
    if (result.error != null) {
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
      await _saveScanResult(result);
    }
  }

  Future<void> _saveScanResult(ScanResultState resultState) async {
    // Encode pose data as JSON strings (Part 9)
    String? _encodeList(dynamic val) {
      if (val is List) return jsonEncode(val);
      return null;
    }

    final scanResult = ScanResult(
      timestamp: DateTime.now(),
      depthMode: _detectedDepthMode,
      foods: resultState.foods,
      topCameraPosition: _encodeList(_topFrameMeta['camera_position']),
      topCameraTransform: _encodeList(_topFrameMeta['camera_transform']),
      sideCameraPosition: _encodeList(_sideFrameMeta['camera_position']),
      sideCameraTransform: _encodeList(_sideFrameMeta['camera_transform']),
    );
    await ref.read(historyProvider.notifier).addScan(scanResult);
    await ref.read(dailyIntakeProvider.notifier).load();
    await ref.read(streakProvider.notifier).load();
    // Store for potential detail navigation
    final history = ref.read(historyProvider);
    if (history.scans.isNotEmpty) {
      _savedScanResult = history.scans.first;

      // Persist benchmark (Part 17)
      final timings = PerfMonitor.instance.allTimings;
      final memoryBytes = await _bridge.getMemoryUsage();
      final benchmark = ScanBenchmark(
        scanId: _savedScanResult!.id!,
        captureTopMs: timings['capture_top']?.inMilliseconds ?? 0,
        captureSideMs: timings['capture_side']?.inMilliseconds ?? 0,
        inferenceMs: timings['inference']?.inMilliseconds ?? 0,
        totalMs: PerfMonitor.instance.total.inMilliseconds,
        peakMemoryBytes: memoryBytes,
        depthMode: _detectedDepthMode,
        timestamp: DateTime.now(),
      );
      await DatabaseService.instance.insertBenchmark(benchmark);
    }
    DebugLog.instance.log('Scan', 'Result saved to history');
  }

  void _retry() {
    _hapticLight();
    ref.read(scanStateProvider.notifier).reset();
    ref.read(scanResultProvider.notifier).reset();
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
          // ── Camera placeholder / dark background ─────────────────────
          Container(color: Colors.black),

          // ── Guidance overlay ─────────────────────────────────────────
          ScanGuidanceOverlay(scanState: scanState),

          // ── Bottom action panel ─────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomPanel(
              scanState: scanState,
              scanResult: scanResult,
              sessionStarted: _sessionStarted,
              depthMode: _detectedDepthMode,
              timings: PerfMonitor.instance.allTimings,
              onCaptureTop: _captureTop,
              onCaptureSide: _captureSide,
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

          // ── Tutorial overlay (first scan) ───────────────────────────
          if (_showTutorial)
            ScanTutorialOverlay(onDismiss: _dismissTutorial),
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
    required this.depthMode,
    required this.timings,
    required this.onCaptureTop,
    required this.onCaptureSide,
    required this.onRetry,
    required this.onClose,
    this.onViewDetails,
  });

  final ScanState scanState;
  final ScanResultState scanResult;
  final bool sessionStarted;
  final String depthMode;
  final Map<String, Duration> timings;
  final VoidCallback onCaptureTop;
  final VoidCallback onCaptureSide;
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
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── State indicator ────────────────────────────────────────
          _StateProgressRow(state: scanState),
          const SizedBox(height: 16),

          // ── Align top → capture button ────────────────────────────
          if (scanState == ScanState.alignTop)
            _ScanButton(
              label: 'Capture Top View',
              icon: Icons.camera_alt,
              enabled: sessionStarted,
              onPressed: onCaptureTop,
            ),

          // ── Capturing top ─────────────────────────────────────────
          if (scanState == ScanState.captureTop)
            const _ProcessingIndicator(text: 'Capturing…'),

          // ── Move to side → capture button ─────────────────────────
          if (scanState == ScanState.moveSide)
            _ScanButton(
              label: 'Capture Side View',
              icon: Icons.camera_alt,
              enabled: true,
              onPressed: onCaptureSide,
              color: AppTheme.amber500,
            ),

          // ── Capture side / calculating ────────────────────────────
          if (scanState == ScanState.captureSide ||
              scanState == ScanState.calculating)
            _ProcessingIndicator(
              text: scanResult.loading
                  ? 'Running ML inference…'
                  : 'Processing depth data…',
            ),

          // ── Done → results + confidence ───────────────────────────
          if (scanState == ScanState.done) ...[
            ConfidenceBadge(
              caloriesMin: scanResult.totalCaloriesMin,
              caloriesMax: scanResult.totalCaloriesMax,
            ),
            const SizedBox(height: 8),

            // Timing + depth mode chips
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
                      const Icon(Icons.restaurant,
                          size: 14, color: AppTheme.green400),
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
                        style: const TextStyle(
                          color: AppTheme.green400,
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.green400,
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
            if (scanResult.error != null) ...[
              const SizedBox(height: 4),
              Text(
                scanResult.error!,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
                textAlign: TextAlign.center,
              ),
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
    (ScanState.alignTop, 'Top'),
    (ScanState.moveSide, 'Side'),
    (ScanState.calculating, 'Analyse'),
    (ScanState.done, 'Done'),
  ];

  int get _activeIndex {
    return switch (state) {
      ScanState.alignTop || ScanState.captureTop => 0,
      ScanState.moveSide || ScanState.captureSide => 1,
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
                color: i <= active ? AppTheme.green400 : Colors.white12,
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
      color = AppTheme.green400;
    } else if (isActive) {
      color = AppTheme.green500;
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
    final c = color ?? AppTheme.green500;
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
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(AppTheme.green400),
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
