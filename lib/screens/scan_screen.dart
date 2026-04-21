import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/scan_state.dart';
import '../providers/scan_state_provider.dart';
import '../providers/scan_result_provider.dart';
import '../services/native_bridge.dart';
import '../theme/app_theme.dart';

/// Full-screen scan flow that follows the state machine from Part 4:
///
///   align_top → capture_top → move_side → capture_side → calculating → done
///
/// On errors: shows retry button that resets to align_top.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _bridge = NativeBridge.instance;
  bool _sessionStarted = false;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    try {
      await _bridge.startSession();
      setState(() => _sessionStarted = true);
    } catch (e) {
      ref.read(scanStateProvider.notifier).depthFailed();
    }
  }

  @override
  void dispose() {
    _bridge.stopSession();
    super.dispose();
  }

  // ── State-driven actions ────────────────────────────────────────────────

  Future<void> _captureTop() async {
    ref.read(scanStateProvider.notifier).topAligned();
    try {
      await _bridge.captureFrame('top');
      ref.read(scanStateProvider.notifier).topCaptured();
    } catch (_) {
      ref.read(scanStateProvider.notifier).depthFailed();
    }
  }

  Future<void> _captureSide() async {
    ref.read(scanStateProvider.notifier).sideReady();
    try {
      await _bridge.captureFrame('side');
      ref.read(scanStateProvider.notifier).sideCaptured();
      await _runInference();
    } catch (_) {
      ref.read(scanStateProvider.notifier).depthFailed();
    }
  }

  Future<void> _runInference() async {
    await ref.read(scanResultProvider.notifier).runScan();
    final result = ref.read(scanResultProvider);
    if (result.error != null) {
      ref.read(scanStateProvider.notifier).modelFailed();
    } else {
      ref.read(scanStateProvider.notifier).calculationDone();
    }
  }

  void _retry() {
    ref.read(scanStateProvider.notifier).reset();
    ref.read(scanResultProvider.notifier).reset();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanStateProvider);
    final scanResult = ref.watch(scanResultProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Food')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Instruction text
              Text(
                scanState.label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scanState.isError ? AppTheme.red500 : AppTheme.gray900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // State-specific UI
              if (scanState == ScanState.alignTop) ...[
                const _Illustration(icon: Icons.phone_android, label: 'Point camera at plate'),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _sessionStarted ? _captureTop : null,
                  child: const Text('Capture Top View'),
                ),
              ],

              if (scanState == ScanState.captureTop)
                const _Illustration(icon: Icons.camera, label: 'Capturing…'),

              if (scanState == ScanState.moveSide) ...[
                const _Illustration(icon: Icons.arrow_forward, label: 'Move to the side'),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _captureSide,
                  child: const Text('Capture Side View'),
                ),
              ],

              if (scanState == ScanState.captureSide || scanState == ScanState.calculating)
                Column(
                  children: [
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      scanResult.loading ? 'Running ML inference…' : 'Processing…',
                      style: const TextStyle(color: AppTheme.gray400),
                    ),
                  ],
                ),

              if (scanState == ScanState.done) ...[
                const Icon(Icons.check_circle, size: 48, color: AppTheme.green500),
                const SizedBox(height: 16),
                ...scanResult.foods.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    f.displayCalories,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                )),
                const SizedBox(height: 8),
                Text(
                  'Total: ${scanResult.totalCaloriesMin.round()}–'
                  '${scanResult.totalCaloriesMax.round()} kcal',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.green700,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _retry,
                  child: const Text('Scan Again'),
                ),
              ],

              // Error states
              if (scanState.isError) ...[
                const SizedBox(height: 16),
                const Icon(Icons.error_outline, size: 48, color: AppTheme.red500),
                if (scanResult.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    scanResult.error!,
                    style: const TextStyle(fontSize: 13, color: AppTheme.gray400),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _retry,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple icon + label placeholder for scan instructions.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.green50,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.green200, width: 2),
          ),
          child: Icon(icon, size: 48, color: AppTheme.green600),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: AppTheme.gray400)),
      ],
    );
  }
}
