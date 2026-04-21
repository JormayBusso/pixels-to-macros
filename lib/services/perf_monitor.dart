import '../services/debug_log.dart';

/// Lightweight performance stopwatch for pipeline stages (Part 17).
class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  final _timings = <String, Duration>{};
  DateTime? _stageStart;
  String? _currentStage;

  /// Start timing a named stage.
  void start(String stage) {
    _currentStage = stage;
    _stageStart = DateTime.now();
  }

  /// End the current stage and record its duration.
  Duration? end() {
    if (_stageStart == null || _currentStage == null) return null;
    final elapsed = DateTime.now().difference(_stageStart!);
    _timings[_currentStage!] = elapsed;
    DebugLog.instance.log(
      'Perf',
      '$_currentStage: ${elapsed.inMilliseconds}ms',
    );
    _stageStart = null;
    _currentStage = null;
    return elapsed;
  }

  /// Get timing for a specific stage.
  Duration? getStage(String stage) => _timings[stage];

  /// All recorded timings.
  Map<String, Duration> get allTimings => Map.unmodifiable(_timings);

  /// Total time across all recorded stages.
  Duration get total =>
      _timings.values.fold(Duration.zero, (sum, d) => sum + d);

  /// Export as a formatted report string.
  String report() {
    final buf = StringBuffer();
    buf.writeln('=== Performance Report ===');
    for (final entry in _timings.entries) {
      buf.writeln('  ${entry.key}: ${entry.value.inMilliseconds}ms');
    }
    buf.writeln('  TOTAL: ${total.inMilliseconds}ms');
    return buf.toString();
  }

  /// Reset all timings.
  void reset() {
    _timings.clear();
    _stageStart = null;
    _currentStage = null;
  }
}
