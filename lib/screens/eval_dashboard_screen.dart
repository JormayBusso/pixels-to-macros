import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/benchmark_provider.dart';
import '../providers/eval_provider.dart';
import '../services/data_export_service.dart';
import '../theme/app_theme.dart';

/// Scientific evaluation dashboard showing accuracy metrics
/// for the thesis — MAE, MAPE, RMSE, correlation, range accuracy,
/// and performance benchmarks (Part 17).
class EvalDashboardScreen extends ConsumerStatefulWidget {
  const EvalDashboardScreen({super.key});

  @override
  ConsumerState<EvalDashboardScreen> createState() =>
      _EvalDashboardScreenState();
}

class _EvalDashboardScreenState extends ConsumerState<EvalDashboardScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(evalProvider.notifier).load();
    ref.read(benchmarkProvider.notifier).load();
  }

  Future<void> _exportEval() async {
    final csv = await DataExportService.instance.exportEvaluationCsv();
    await DataExportService.instance.copyToClipboard(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evaluation CSV copied to clipboard')),
      );
    }
  }

  Future<void> _exportEvalToFile() async {
    final csv = await DataExportService.instance.exportEvaluationCsv();
    final path = await DataExportService.instance
        .saveToFile(csv, 'evaluation_${DateTime.now().millisecondsSinceEpoch}.csv');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $path')),
      );
    }
  }

  Future<void> _exportBenchmarks() async {
    final csv = await DataExportService.instance.exportBenchmarkCsv();
    await DataExportService.instance.copyToClipboard(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Benchmarks CSV copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final evalState = ref.watch(evalProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(evalProvider.notifier).load(),
          ),
        ],
      ),
      body: evalState.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Coverage ────────────────────────────────────────────
                _SectionTitle('Data Coverage'),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _MetricRow(
                          label: 'Total scans',
                          value: '${evalState.metrics.totalScans}',
                        ),
                        _MetricRow(
                          label: 'Scans with ground truth',
                          value: '${evalState.metrics.scansWithGroundTruth}',
                        ),
                        _MetricRow(
                          label: 'Paired food items',
                          value: '${evalState.metrics.sampleSize}',
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: evalState.metrics.totalScans > 0
                                ? evalState.metrics.scansWithGroundTruth /
                                    evalState.metrics.totalScans
                                : 0,
                            backgroundColor: AppTheme.gray100,
                            valueColor: const AlwaysStoppedAnimation(
                                AppTheme.green500),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          evalState.metrics.totalScans > 0
                              ? '${(evalState.metrics.scansWithGroundTruth / evalState.metrics.totalScans * 100).round()}% coverage'
                              : 'No scans yet',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.gray400),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Accuracy metrics ────────────────────────────────────
                if (evalState.metrics.sampleSize > 0) ...[
                  _SectionTitle('Accuracy Metrics'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'MAE',
                          value:
                              '${evalState.metrics.mae.toStringAsFixed(1)}',
                          unit: 'kcal',
                          subtitle: 'Mean Abs. Error',
                          color: _maeColor(evalState.metrics.mae),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'MAPE',
                          value:
                              '${evalState.metrics.mape.toStringAsFixed(1)}',
                          unit: '%',
                          subtitle: 'Mean Abs. % Error',
                          color: _mapeColor(evalState.metrics.mape),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'RMSE',
                          value:
                              '${evalState.metrics.rmse.toStringAsFixed(1)}',
                          unit: 'kcal',
                          subtitle: 'Root Mean Sq. Error',
                          color: _maeColor(evalState.metrics.rmse),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'r',
                          value: evalState.metrics.correlation
                              .toStringAsFixed(3),
                          unit: '',
                          subtitle: 'Correlation',
                          color: _corrColor(evalState.metrics.correlation),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Weight',
                          value:
                              '${evalState.metrics.weightMape.toStringAsFixed(1)}',
                          unit: '%',
                          subtitle: 'Weight Error',
                          color: _mapeColor(evalState.metrics.weightMape),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Volume',
                          value:
                              '${evalState.metrics.volumeMape.toStringAsFixed(1)}',
                          unit: '%',
                          subtitle: 'Volume Error',
                          color: _mapeColor(evalState.metrics.volumeMape),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _MetricRow(
                            label: 'Range accuracy',
                            value:
                                '${(evalState.metrics.rangeAccuracy * 100).toStringAsFixed(1)}%',
                            valueColor: _rangeColor(
                                evalState.metrics.rangeAccuracy),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fraction of actual values within predicted min–max',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.gray400),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Per depth-mode breakdown ──────────────────────────
                  if (evalState.metrics.byDepthMode.length > 1) ...[
                    _SectionTitle('By Depth Mode'),
                    const SizedBox(height: 8),
                    ...evalState.metrics.byDepthMode.entries.map((entry) {
                      final mode = entry.key;
                      final m = entry.value;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mode.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.gray700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _MetricRow(
                                label: 'Samples',
                                value: '${m.sampleSize}',
                              ),
                              _MetricRow(
                                label: 'MAE',
                                value:
                                    '${m.mae.toStringAsFixed(1)} kcal',
                              ),
                              _MetricRow(
                                label: 'MAPE',
                                value:
                                    '${m.mape.toStringAsFixed(1)}%',
                              ),
                              _MetricRow(
                                label: 'Range accuracy',
                                value:
                                    '${(m.rangeAccuracy * 100).toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],

                  // ── Recent pairs ──────────────────────────────────────
                  _SectionTitle('Recent Observations'),
                  const SizedBox(height: 8),
                  ...evalState.metrics.pairs
                      .take(10)
                      .map((p) => _PairTile(pair: p)),
                  const SizedBox(height: 20),
                ],

                // ── No data message ─────────────────────────────────────
                if (evalState.metrics.sampleSize == 0)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.science_outlined,
                              size: 48, color: AppTheme.gray200),
                          const SizedBox(height: 12),
                          const Text(
                            'No ground truth data yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.gray400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Open a scan detail and tap a food item, then use '
                            'the scale icon to enter actual measurements.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 13, color: AppTheme.gray400),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Performance Benchmarks (Part 17) ────────────────────
                Builder(builder: (context) {
                  final bench = ref.watch(benchmarkProvider);
                  if (bench.count == 0) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _SectionTitle('Performance Benchmarks'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              title: 'Inference',
                              value: bench.avgInferenceMs.toStringAsFixed(0),
                              unit: 'ms',
                              subtitle: 'Avg (target <200)',
                              color: bench.avgInferenceMs < 200
                                  ? AppTheme.green600
                                  : AppTheme.red500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              title: 'Total',
                              value: bench.avgTotalMs.toStringAsFixed(0),
                              unit: 'ms',
                              subtitle: 'Avg scan time',
                              color: bench.avgTotalMs < 3000
                                  ? AppTheme.green600
                                  : AppTheme.amber600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _MetricRow(
                                label: 'Scans benchmarked',
                                value: '${bench.count}',
                              ),
                              _MetricRow(
                                label: 'Avg capture (top)',
                                value: '${bench.avgCaptureTopMs.toStringAsFixed(0)} ms',
                              ),
                              _MetricRow(
                                label: 'Avg capture (side)',
                                value: '${bench.avgCaptureSideMs.toStringAsFixed(0)} ms',
                              ),
                              _MetricRow(
                                label: 'Inference range',
                                value: '${bench.minInferenceMs}–${bench.maxInferenceMs} ms',
                              ),
                              _MetricRow(
                                label: 'Under 200ms target',
                                value: '${bench.scansUnderTarget}/${bench.count}'
                                    ' (${bench.count > 0 ? (bench.scansUnderTarget / bench.count * 100).round() : 0}%)',
                                valueColor: bench.scansUnderTarget == bench.count
                                    ? AppTheme.green600
                                    : AppTheme.amber600,
                              ),
                              _MetricRow(
                                label: 'Avg memory',
                                value: '${bench.avgMemoryMB.toStringAsFixed(1)} MB',
                              ),
                              _MetricRow(
                                label: 'Peak memory',
                                value: '${bench.maxMemoryMB.toStringAsFixed(1)} MB',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),

                // ── Export ───────────────────────────────────────────────
                const SizedBox(height: 20),
                _SectionTitle('Export'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy CSV'),
                        onPressed: _exportEval,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save File'),
                        onPressed: _exportEvalToFile,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.timer),
                    label: const Text('Export Benchmarks CSV'),
                    onPressed: _exportBenchmarks,
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Color _maeColor(double mae) {
    if (mae < 30) return AppTheme.green600;
    if (mae < 60) return AppTheme.amber600;
    return AppTheme.red500;
  }

  Color _mapeColor(double mape) {
    if (mape < 15) return AppTheme.green600;
    if (mape < 30) return AppTheme.amber600;
    return AppTheme.red500;
  }

  Color _corrColor(double r) {
    if (r > 0.8) return AppTheme.green600;
    if (r > 0.5) return AppTheme.amber600;
    return AppTheme.red500;
  }

  Color _rangeColor(double acc) {
    if (acc > 0.7) return AppTheme.green600;
    if (acc > 0.4) return AppTheme.amber600;
    return AppTheme.red500;
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.gray700,
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: AppTheme.gray400)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppTheme.gray700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.subtitle,
    required this.color,
  });
  final String title;
  final String value;
  final String unit;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    ' $unit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppTheme.gray400),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({required this.pair});
  final EvalPair pair;

  @override
  Widget build(BuildContext context) {
    final predicted = pair.predictedCaloriesAvg.round();
    final actual = pair.actualCalories?.round();
    final error = pair.percentageError;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: pair.withinRange == true
                    ? AppTheme.green100
                    : AppTheme.red100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                pair.withinRange == true
                    ? Icons.check
                    : Icons.close,
                size: 18,
                color: pair.withinRange == true
                    ? AppTheme.green600
                    : AppTheme.red500,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pair.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Predicted: $predicted kcal  •  '
                    'Actual: ${actual ?? "—"} kcal',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.gray400),
                  ),
                ],
              ),
            ),
            if (error != null)
              Text(
                '${error.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: error < 15
                      ? AppTheme.green600
                      : error < 30
                          ? AppTheme.amber600
                          : AppTheme.red500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
