import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_benchmark.dart';
import '../services/database_service.dart';

/// State holding all benchmark data and computed statistics (Part 17).
class BenchmarkState {
  final bool loading;
  final List<ScanBenchmark> benchmarks;

  const BenchmarkState({
    this.loading = false,
    this.benchmarks = const [],
  });

  int get count => benchmarks.length;

  double get avgCaptureTopMs => _avg((b) => b.captureTopMs.toDouble());
  double get avgCaptureSideMs => _avg((b) => b.captureSideMs.toDouble());
  double get avgInferenceMs => _avg((b) => b.inferenceMs.toDouble());
  double get avgTotalMs => _avg((b) => b.totalMs.toDouble());
  double get avgMemoryMB => _avg((b) => b.peakMemoryMB);

  int get maxInferenceMs =>
      benchmarks.isEmpty ? 0 : benchmarks.map((b) => b.inferenceMs).reduce((a, b) => a > b ? a : b);
  int get minInferenceMs =>
      benchmarks.isEmpty ? 0 : benchmarks.map((b) => b.inferenceMs).reduce((a, b) => a < b ? a : b);

  double get maxMemoryMB =>
      benchmarks.isEmpty ? 0 : benchmarks.map((b) => b.peakMemoryMB).reduce((a, b) => a > b ? a : b);

  /// Whether all scans met the <200ms inference target.
  int get scansUnderTarget =>
      benchmarks.where((b) => b.inferenceMs < 200).length;

  double _avg(double Function(ScanBenchmark) selector) {
    if (benchmarks.isEmpty) return 0;
    return benchmarks.map(selector).reduce((a, b) => a + b) / benchmarks.length;
  }
}

class BenchmarkNotifier extends StateNotifier<BenchmarkState> {
  BenchmarkNotifier() : super(const BenchmarkState());

  Future<void> load() async {
    state = const BenchmarkState(loading: true);
    final benchmarks = await DatabaseService.instance.getAllBenchmarks();
    state = BenchmarkState(benchmarks: benchmarks);
  }
}

final benchmarkProvider =
    StateNotifierProvider<BenchmarkNotifier, BenchmarkState>(
  (ref) => BenchmarkNotifier(),
);
