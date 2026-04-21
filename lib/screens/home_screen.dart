import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/scan_state.dart';
import '../providers/scan_state_provider.dart';
import '../services/database_service.dart';
import '../services/debug_log.dart';
import '../services/native_bridge.dart';
import '../models/food_data.dart';
import '../theme/app_theme.dart';
import 'debug_screen.dart';
import 'scan_screen.dart';

/// Temporary home screen that verifies the Step 1 foundation:
///   • ScanState enum + state machine
///   • SQLite database + seed data
///   • MethodChannel bridge (display only — native side not built yet)
///   • Theme matching original NutriLens design
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<FoodData> _foods = [];
  bool _loading = true;
  String? _depthMode;

  @override
  void initState() {
    super.initState();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    final foods = await DatabaseService.instance.getAllFoods();
    setState(() {
      _foods = foods;
      _loading = false;
    });
  }

  Future<void> _queryDepthMode() async {
    try {
      final mode = await NativeBridge.instance.getDepthMode();
      setState(() => _depthMode = mode);
    } catch (e) {
      setState(() => _depthMode = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanStateProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.green600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.eco, color: Colors.white, size: 20),
          ),
        ),
        title: const Text('Pixels to Macros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Start scan button ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Start Scan'),
                onPressed: () {
                  ref.read(scanStateProvider.notifier).reset();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Scan state card ──────────────────────────────────────────
            _SectionCard(
              title: 'Scan State Machine',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: 'Current state',
                    value: scanState.name,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    label: 'Instruction',
                    value: scanState.label,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SmallButton(
                        label: 'Next →',
                        onPressed: () => _advanceState(ref),
                      ),
                      _SmallButton(
                        label: 'Reset',
                        outline: true,
                        onPressed: () =>
                            ref.read(scanStateProvider.notifier).reset(),
                      ),
                      _SmallButton(
                        label: 'Depth fail',
                        danger: true,
                        onPressed: () =>
                            ref.read(scanStateProvider.notifier).depthFailed(),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Database seed card ───────────────────────────────────────
            _SectionCard(
              title: 'SQLite Seed Data',
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: _foods
                          .map((f) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    _badge(f.category),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        f.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${f.kcalPer100g.round()} kcal',
                                      style: TextStyle(
                                        color: AppTheme.gray700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${f.densityMin}–${f.densityMax} g/cm³',
                                      style: TextStyle(
                                        color: AppTheme.gray400,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
            ),

            const SizedBox(height: 16),

            // ── Native Bridge status ──────────────────────────────────────
            _SectionCard(
              title: 'Native Bridge',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: 'Channel',
                    value: AppConstants.methodChannelName,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(
                    label: 'Depth mode',
                    value: _depthMode ?? 'not queried',
                  ),
                  const SizedBox(height: 12),
                  _SmallButton(
                    label: 'Query depth mode',
                    onPressed: _queryDepthMode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _advanceState(WidgetRef ref) {
    final notifier = ref.read(scanStateProvider.notifier);
    final current = ref.read(scanStateProvider);
    switch (current) {
      case ScanState.alignTop:
        notifier.topAligned();
      case ScanState.captureTop:
        notifier.topCaptured();
      case ScanState.moveSide:
        notifier.sideReady();
      case ScanState.captureSide:
        notifier.sideCaptured();
      case ScanState.calculating:
        notifier.calculationDone();
      default:
        notifier.reset();
    }
  }

  Widget _badge(String category) {
    final (Color bg, Color fg) = switch (category) {
      'fruit' => (AppTheme.green100, AppTheme.green700),
      'grain' => (AppTheme.amber100, AppTheme.amber700),
      'protein' => (AppTheme.red100, AppTheme.red700),
      'vegetable' => (AppTheme.green100, AppTheme.green600),
      'dairy' => (AppTheme.amber100, AppTheme.amber500),
      'mixed' => (AppTheme.gray100, AppTheme.gray700),
      _ => (AppTheme.gray100, AppTheme.gray700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        category,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gray700,
                )),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: AppTheme.gray400)),
        ),
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onPressed,
    this.outline = false,
    this.danger = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool outline;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    if (outline) {
      return OutlinedButton(
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: danger
          ? ElevatedButton.styleFrom(backgroundColor: AppTheme.red500)
          : null,
      child: Text(label),
    );
  }
}
