import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';
import '../services/debug_log.dart';
import '../services/native_bridge.dart';

/// Holds the results of the most recent scan.
class ScanResultState {
  const ScanResultState({
    this.loading = false,
    this.error,
    this.noFood = false,
    this.foods = const [],
  });

  final bool loading;
  final String? error;
  final bool noFood; // true when inference ran but found no food items
  final List<DetectedFood> foods;

  ScanResultState copyWith({
    bool? loading,
    String? error,
    bool? noFood,
    List<DetectedFood>? foods,
  }) {
    return ScanResultState(
      loading: loading ?? this.loading,
      error: error,
      noFood: noFood ?? this.noFood,
      foods: foods ?? this.foods,
    );
  }

  double get totalCaloriesMin =>
      foods.fold(0.0, (sum, f) => sum + f.caloriesMin);
  double get totalCaloriesMax =>
      foods.fold(0.0, (sum, f) => sum + f.caloriesMax);
}

/// Notifier that runs the full scan pipeline via the native bridge
/// and converts volume results into calorie estimates using the
/// local food database.
class ScanResultNotifier extends StateNotifier<ScanResultState> {
  ScanResultNotifier() : super(const ScanResultState());

  /// Maps model output labels to user-friendly DB labels where they differ.
  static const _labelAliases = {
    'chicken duck': 'chicken',
  };

  /// Normalise a model label: apply alias mapping, then title-case fallback.
  static String _normaliseLabel(String raw) {
    final lower = raw.toLowerCase();
    return _labelAliases[lower] ?? raw;
  }

  /// Run inference and compute calories.
  Future<void> runScan() async {
    state = const ScanResultState(loading: true);

    try {
      // 1. Call native pipeline (plate detect → segment → volume)
      final rawVolumes = await NativeBridge.instance.runInference();

      if (rawVolumes.isEmpty) {
        state = const ScanResultState(
          noFood: true,
        );
        return;
      }

      // 2. Look up each food in the local DB and compute calorie range
      final db = DatabaseService.instance;
      final foods = <DetectedFood>[];

      for (final vol in rawVolumes) {
        final rawLabel = vol['label'] as String? ?? 'unknown';
        final label = _normaliseLabel(rawLabel);
        final volumeCm3 = (vol['volume_cm3'] as num?)?.toDouble() ?? 0;
        final pixelCount = (vol['pixel_count'] as num?)?.toInt() ?? 0;
        final confidence = (vol['confidence'] as num?)?.toDouble();
        final depthMinM = (vol['depth_min_m'] as num?)?.toDouble();
        final depthMaxM = (vol['depth_max_m'] as num?)?.toDouble();
        final depthAvgM = (vol['depth_avg_m'] as num?)?.toDouble();

        final foodData = await db.getFoodByLabel(label);
        final double calMin;
        final double calMax;

        if (foodData != null) {
          final range = foodData.calorieRange(volumeCm3);
          calMin = range.min;
          calMax = range.max;
        } else {
          // Unknown food — use rough average density 0.8 g/cm³, 100 kcal/100g
          calMin = volumeCm3 * 0.7 / 100 * 80;
          calMax = volumeCm3 * 1.0 / 100 * 120;
        }

        foods.add(DetectedFood(
          label: label,
          volumeCm3: volumeCm3,
          caloriesMin: calMin,
          caloriesMax: calMax,
        ));

        // Part 14 — detailed per-food debug log
        DebugLog.instance.log(
            'Detection',
            '$label: ${volumeCm3.toStringAsFixed(1)} cm³, '
                '$pixelCount px, '
                '${calMin.round()}-${calMax.round()} kcal'
                '${confidence != null ? ", conf ${confidence.toStringAsFixed(2)}" : ""}');

        // Log depth statistics (once, from first food item)
        if (depthMinM != null && foods.length == 1) {
          DebugLog.instance.log(
              'Depth',
              'min=${depthMinM.toStringAsFixed(3)}m, '
                  'max=${depthMaxM?.toStringAsFixed(3)}m, '
                  'avg=${depthAvgM?.toStringAsFixed(3)}m');
        }
      }

      state = ScanResultState(foods: foods);
    } catch (e) {
      state = ScanResultState(error: e.toString());
    }
  }

  /// Run the multi-frame video inference pipeline.
  /// Same processing as [runScan] but uses [NativeBridge.runVideoInference].
  Future<void> runVideoScan() async {
    state = const ScanResultState(loading: true);

    try {
      final rawVolumes = await NativeBridge.instance.runVideoInference();

      if (rawVolumes.isEmpty) {
        DebugLog.instance.log(
          'VideoScan',
          'Native video inference returned empty; treating scan as no food.',
        );
        state = const ScanResultState(noFood: true);
        return;
      }

      final db = DatabaseService.instance;
      final foods = <DetectedFood>[];

      for (final vol in rawVolumes) {
        final rawLabel = vol['label'] as String? ?? 'unknown';
        final label = _normaliseLabel(rawLabel);
        final volumeCm3 = (vol['volume_cm3'] as num?)?.toDouble() ?? 0;
        final pixelCount = (vol['pixel_count'] as num?)?.toInt() ?? 0;
        final confidence = (vol['confidence'] as num?)?.toDouble();
        final framesUsed = (vol['frames_used'] as num?)?.toInt() ?? 0;
        final fallbackReason = vol['fallback_reason'] as String?;

        if (!_passesDetectionGate(
          label: label,
          volumeCm3: volumeCm3,
          pixelCount: pixelCount,
          confidence: confidence,
          fallbackReason: fallbackReason,
        )) {
          DebugLog.instance.log(
            'VideoScan',
            'Rejected $label as low-confidence/no-food candidate '
                '($volumeCm3 cm³, $pixelCount px, conf $confidence)',
          );
          continue;
        }

        final foodData = await db.getFoodByLabel(label);
        final double calMin;
        final double calMax;

        if (foodData != null) {
          final range = foodData.calorieRange(volumeCm3);
          calMin = range.min;
          calMax = range.max;
        } else {
          calMin = volumeCm3 * 0.7 / 100 * 80;
          calMax = volumeCm3 * 1.0 / 100 * 120;
        }

        foods.add(DetectedFood(
          label: label,
          volumeCm3: volumeCm3,
          caloriesMin: calMin,
          caloriesMax: calMax,
        ));

        DebugLog.instance.log(
            'VideoScan',
            '$label: ${volumeCm3.toStringAsFixed(1)} cm³ '
                '($framesUsed frames), '
                '$pixelCount px, '
                '${calMin.round()}-${calMax.round()} kcal'
                '${confidence != null ? ", conf ${confidence.toStringAsFixed(2)}" : ""}'
                '${fallbackReason != null ? ", fallback $fallbackReason" : ""}');
      }

      if (foods.isEmpty) {
        state = const ScanResultState(noFood: true);
      } else {
        state = ScanResultState(foods: foods);
      }
    } catch (e) {
      DebugLog.instance.log(
        'VideoScan',
        'Native video inference failed: $e',
      );
      state = ScanResultState(error: e.toString());
    }
  }

  bool _passesDetectionGate({
    required String label,
    required double volumeCm3,
    required int pixelCount,
    required double? confidence,
    required String? fallbackReason,
  }) {
    if (fallbackReason != null) return false;
    if (label.toLowerCase() == 'background') return false;
    if (volumeCm3 < 3.0) return false;
    if (pixelCount < 450) return false;
    if (confidence != null && confidence < 0.55) return false;
    if (label.toLowerCase() == 'others' && (confidence ?? 0) < 0.72) {
      return false;
    }
    return true;
  }

  void reset() => state = const ScanResultState();
}

/// Global provider.
final scanResultProvider =
    StateNotifierProvider<ScanResultNotifier, ScanResultState>(
  (ref) => ScanResultNotifier(),
);
