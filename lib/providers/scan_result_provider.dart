import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../services/database_service.dart';
import '../services/native_bridge.dart';

/// Holds the results of the most recent scan.
class ScanResultState {
  final bool loading;
  final String? error;
  final List<DetectedFood> foods;

  const ScanResultState({
    this.loading = false,
    this.error,
    this.foods = const [],
  });

  ScanResultState copyWith({
    bool? loading,
    String? error,
    List<DetectedFood>? foods,
  }) {
    return ScanResultState(
      loading: loading ?? this.loading,
      error: error,
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

  /// Run inference and compute calories.
  Future<void> runScan() async {
    state = const ScanResultState(loading: true);

    try {
      // 1. Call native pipeline (plate detect → segment → volume)
      final rawVolumes = await NativeBridge.instance.runInference();

      if (rawVolumes.isEmpty) {
        state = const ScanResultState(
          error: 'No food detected — try again with a clearer view.',
        );
        return;
      }

      // 2. Look up each food in the local DB and compute calorie range
      final db = DatabaseService.instance;
      final foods = <DetectedFood>[];

      for (final vol in rawVolumes) {
        final label = vol['label'] as String? ?? 'unknown';
        final volumeCm3 = (vol['volume_cm3'] as num?)?.toDouble() ?? 0;

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
      }

      state = ScanResultState(foods: foods);
    } catch (e) {
      state = ScanResultState(error: e.toString());
    }
  }

  void reset() => state = const ScanResultState();
}

/// Global provider.
final scanResultProvider =
    StateNotifierProvider<ScanResultNotifier, ScanResultState>(
  (ref) => ScanResultNotifier(),
);
