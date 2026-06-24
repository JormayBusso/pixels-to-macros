import '../services/perf_monitor.dart';

/// Structured per-food diagnostics captured from the native scanner pipeline.
///
/// The native `getModel3DObjects()` call already returns a rich telemetry map
/// per food (volume, scale source, guardrails, side-view usage, etc.). This
/// model captures that data so it can be inspected, validated, and exported
/// from the Flutter side instead of only living in `print` logs.
class FoodDiagnostic {
  const FoodDiagnostic({
    required this.label,
    required this.scanMode,
    required this.volumeCm3,
    this.scaleSource,
    this.rawVolumeCm3,
    this.footprintAreaCm2,
    this.heightCm,
    this.weightG,
    this.densityGCm3,
    this.pixelsPerCm,
    this.confidence,
    this.voxelCount,
    this.pixelCount,
    this.framesUsed,
    this.guardrailApplied,
    this.guardrailUpperCm3,
    this.sideViewApplied,
    this.fallbackUsed,
    this.estimated,
    this.debug,
  });

  final String label;
  final String scanMode;
  final double volumeCm3;
  final String? scaleSource;
  final double? rawVolumeCm3;
  final double? footprintAreaCm2;
  final double? heightCm;
  final double? weightG;
  final double? densityGCm3;
  final double? pixelsPerCm;
  final double? confidence;
  final int? voxelCount;
  final int? pixelCount;
  final int? framesUsed;
  final bool? guardrailApplied;
  final double? guardrailUpperCm3;
  final bool? sideViewApplied;
  final bool? fallbackUsed;
  final bool? estimated;
  final String? debug;

  static double? _d(Object? v) => (v is num) ? v.toDouble() : null;
  static int? _i(Object? v) => (v is num) ? v.toInt() : null;
  static bool? _b(Object? v) => (v is bool) ? v : null;

  factory FoodDiagnostic.fromMap(Map<String, dynamic> m) {
    return FoodDiagnostic(
      label: (m['label'] as String?) ?? 'unknown',
      scanMode: (m['scan_mode'] as String?) ?? 'unknown',
      volumeCm3: _d(m['volume_cm3']) ?? 0,
      scaleSource: m['scale_source'] as String?,
      rawVolumeCm3: _d(m['raw_volume_cm3']),
      footprintAreaCm2: _d(m['footprint_area_cm2']),
      heightCm: _d(m['height_cm']),
      weightG: _d(m['weight_g']),
      densityGCm3: _d(m['density_g_cm3']),
      pixelsPerCm: _d(m['pixels_per_cm']),
      confidence: _d(m['confidence']),
      voxelCount: _i(m['voxel_count']),
      pixelCount: _i(m['pixel_count']),
      framesUsed: _i(m['frames_used']),
      guardrailApplied: _b(m['volume_guardrail_applied']),
      guardrailUpperCm3: _d(m['guardrail_upper_cm3']),
      sideViewApplied: _b(m['side_view_applied']),
      fallbackUsed: _b(m['fallback_used']),
      estimated: _b(m['estimated']),
      debug: m['debug'] as String?,
    );
  }

  /// Whether both silhouettes (top + side) contributed to this reconstruction.
  bool get usedBothViews =>
      (sideViewApplied ?? false) && !(fallbackUsed ?? true);
}

/// One scan's full diagnostics snapshot: device capability, timings, and the
/// per-food reconstruction telemetry.
class ScanDiagnostics {
  ScanDiagnostics({
    required this.capturedAt,
    required this.depthMode,
    required this.recordMs,
    required this.inferenceMs,
    required this.totalMs,
    required this.foods,
    this.peakMemoryBytes = 0,
    this.ambientLux,
    this.stability,
  });

  final DateTime capturedAt;
  final String depthMode;
  final int recordMs;
  final int inferenceMs;
  final int totalMs;
  final List<FoodDiagnostic> foods;
  final int peakMemoryBytes;
  final double? ambientLux;
  final double? stability;

  factory ScanDiagnostics.fromCapture({
    required String depthMode,
    required List<Map<String, dynamic>> nativeObjects,
    required Map<String, Duration> timings,
    int peakMemoryBytes = 0,
    double? ambientLux,
    double? stability,
  }) {
    return ScanDiagnostics(
      capturedAt: DateTime.now(),
      depthMode: depthMode,
      recordMs: timings['record']?.inMilliseconds ?? 0,
      inferenceMs: timings['inference']?.inMilliseconds ?? 0,
      totalMs: PerfMonitor.instance.total.inMilliseconds,
      peakMemoryBytes: peakMemoryBytes,
      ambientLux: ambientLux,
      stability: stability,
      foods: nativeObjects.map(FoodDiagnostic.fromMap).toList(growable: false),
    );
  }

  /// Plain-text report suitable for copy/share during scanner validation.
  String toReport() {
    final b = StringBuffer();
    b.writeln('── Scan diagnostics ──');
    b.writeln('time:        ${capturedAt.toIso8601String()}');
    b.writeln('depth mode:  $depthMode');
    b.writeln('timings:     record=${recordMs}ms inference=${inferenceMs}ms '
        'total=${totalMs}ms');
    if (peakMemoryBytes > 0) {
      b.writeln(
          'peak memory: ${(peakMemoryBytes / 1048576).toStringAsFixed(1)} MB');
    }
    if (ambientLux != null) {
      b.writeln('ambient lux: ${ambientLux!.toStringAsFixed(0)}');
    }
    if (stability != null) {
      b.writeln('stability:   ${(stability! * 100).toStringAsFixed(0)}%');
    }
    b.writeln('foods:       ${foods.length}');
    for (final f in foods) {
      b.writeln('');
      b.writeln('  • ${f.label}  (${f.scanMode})');
      b.writeln('    volume:    ${f.volumeCm3.toStringAsFixed(1)} cm³'
          '${f.rawVolumeCm3 != null ? ' (raw ${f.rawVolumeCm3!.toStringAsFixed(1)})' : ''}');
      if (f.weightG != null) {
        b.writeln('    weight:    ${f.weightG!.toStringAsFixed(0)} g'
            '${f.densityGCm3 != null ? ' @ ${f.densityGCm3} g/cm³' : ''}');
      }
      if (f.footprintAreaCm2 != null || f.heightCm != null) {
        b.writeln(
            '    geometry:  footprint=${f.footprintAreaCm2?.toStringAsFixed(1) ?? '-'} cm² '
            'height=${f.heightCm?.toStringAsFixed(1) ?? '-'} cm');
      }
      b.writeln('    scale:     ${f.scaleSource ?? '-'}'
          '${f.pixelsPerCm != null ? ' (${f.pixelsPerCm} px/cm)' : ''}');
      b.writeln('    views:     side=${f.sideViewApplied ?? false} '
          'fallback=${f.fallbackUsed ?? false} bothViews=${f.usedBothViews}');
      if (f.guardrailApplied == true) {
        b.writeln(
            '    guardrail: softened (≤ ${f.guardrailUpperCm3 ?? '-'} cm³)');
      }
      if (f.debug != null) b.writeln('    debug:     ${f.debug}');
    }
    return b.toString();
  }
}
