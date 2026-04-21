/// Performance benchmark record for a single scan (Part 17).
///
/// Stores per-stage timing data alongside the scan so that
/// performance can be analysed historically in the thesis.
class ScanBenchmark {
  final int? id;
  final int scanId;
  final int captureTopMs;
  final int captureSideMs;
  final int inferenceMs;
  final int totalMs;
  final int peakMemoryBytes;
  final String depthMode;
  final DateTime timestamp;

  const ScanBenchmark({
    this.id,
    required this.scanId,
    required this.captureTopMs,
    required this.captureSideMs,
    required this.inferenceMs,
    required this.totalMs,
    this.peakMemoryBytes = 0,
    required this.depthMode,
    required this.timestamp,
  });

  /// Peak memory in MB for display.
  double get peakMemoryMB => peakMemoryBytes / (1024 * 1024);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'scan_id': scanId,
      'capture_top_ms': captureTopMs,
      'capture_side_ms': captureSideMs,
      'inference_ms': inferenceMs,
      'total_ms': totalMs,
      'peak_memory_bytes': peakMemoryBytes,
      'depth_mode': depthMode,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ScanBenchmark.fromMap(Map<String, dynamic> map) {
    return ScanBenchmark(
      id: map['id'] as int?,
      scanId: map['scan_id'] as int,
      captureTopMs: map['capture_top_ms'] as int,
      captureSideMs: map['capture_side_ms'] as int,
      inferenceMs: map['inference_ms'] as int,
      totalMs: map['total_ms'] as int,
      peakMemoryBytes: (map['peak_memory_bytes'] as int?) ?? 0,
      depthMode: map['depth_mode'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
