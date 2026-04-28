import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ground_truth.dart';
import '../services/database_service.dart';

/// A single paired observation: predicted vs actual.
class EvalPair {
  final int scanId;
  final String label;
  final double volumeCm3;
  final double predictedCaloriesMin;
  final double predictedCaloriesMax;
  final double actualWeightGrams;
  final double? actualCalories;
  final String depthMode;
  final DateTime timestamp;

  /// Density bounds from the food database (g/cm³).
  final double densityMin;
  final double densityMax;

  const EvalPair({
    required this.scanId,
    required this.label,
    required this.volumeCm3,
    required this.predictedCaloriesMin,
    required this.predictedCaloriesMax,
    required this.actualWeightGrams,
    this.actualCalories,
    required this.depthMode,
    required this.timestamp,
    this.densityMin = 0.8,
    this.densityMax = 1.0,
  });

  double get densityAvg => (densityMin + densityMax) / 2;

  double get predictedCaloriesAvg =>
      (predictedCaloriesMin + predictedCaloriesMax) / 2;

  /// Predicted weight from volume × density (Part 12 model).
  double get predictedWeightMin => volumeCm3 * densityMin;
  double get predictedWeightMax => volumeCm3 * densityMax;
  double get predictedWeightAvg => volumeCm3 * densityAvg;

  /// Estimated actual volume derived from actual weight / density.
  double get actualVolumeCm3 =>
      densityAvg > 0 ? actualWeightGrams / densityAvg : 0;

  /// Absolute error (kcal) — only if actual calories are known.
  double? get absoluteError {
    if (actualCalories == null) return null;
    return (predictedCaloriesAvg - actualCalories!).abs();
  }

  /// Calorie percentage error — only if actual calories are known and > 0.
  double? get percentageError {
    if (actualCalories == null || actualCalories == 0) return null;
    return (absoluteError! / actualCalories!) * 100;
  }

  /// Weight error (%).
  double? get weightPercentageError {
    if (actualWeightGrams <= 0) return null;
    return ((predictedWeightAvg - actualWeightGrams).abs() /
            actualWeightGrams) *
        100;
  }

  /// Volume error (%).
  double? get volumePercentageError {
    if (actualVolumeCm3 <= 0) return null;
    return ((volumeCm3 - actualVolumeCm3).abs() / actualVolumeCm3) * 100;
  }

  /// Whether the actual value falls within the predicted range.
  bool? get withinRange {
    if (actualCalories == null) return null;
    return actualCalories! >= predictedCaloriesMin &&
        actualCalories! <= predictedCaloriesMax;
  }
}

/// Aggregate accuracy metrics across all paired observations.
class EvalMetrics {
  final List<EvalPair> pairs;
  final int totalScans;
  final int scansWithGroundTruth;

  const EvalMetrics({
    this.pairs = const [],
    this.totalScans = 0,
    this.scansWithGroundTruth = 0,
  });

  int get sampleSize => pairs.where((p) => p.actualCalories != null).length;

  /// Mean Absolute Error (kcal).
  double get mae {
    final valid = pairs.where((p) => p.absoluteError != null).toList();
    if (valid.isEmpty) return 0;
    return valid.map((p) => p.absoluteError!).reduce((a, b) => a + b) /
        valid.length;
  }

  /// Mean Absolute Percentage Error (%).
  double get mape {
    final valid = pairs.where((p) => p.percentageError != null).toList();
    if (valid.isEmpty) return 0;
    return valid.map((p) => p.percentageError!).reduce((a, b) => a + b) /
        valid.length;
  }

  /// Root Mean Square Error (kcal).
  double get rmse {
    final valid = pairs.where((p) => p.absoluteError != null).toList();
    if (valid.isEmpty) return 0;
    final sumSq = valid
        .map((p) => p.absoluteError! * p.absoluteError!)
        .reduce((a, b) => a + b);
    return math.sqrt(sumSq / valid.length);
  }

  /// Fraction of predictions where actual falls within predicted range.
  double get rangeAccuracy {
    final valid = pairs.where((p) => p.withinRange != null).toList();
    if (valid.isEmpty) return 0;
    return valid.where((p) => p.withinRange!).length / valid.length;
  }

  /// Mean weight error (%) — Part 16 requirement.
  double get weightMape {
    final valid =
        pairs.where((p) => p.weightPercentageError != null).toList();
    if (valid.isEmpty) return 0;
    return valid.map((p) => p.weightPercentageError!).reduce((a, b) => a + b) /
        valid.length;
  }

  /// Mean volume error (%) — Part 16 requirement.
  double get volumeMape {
    final valid =
        pairs.where((p) => p.volumePercentageError != null).toList();
    if (valid.isEmpty) return 0;
    return valid.map((p) => p.volumePercentageError!).reduce((a, b) => a + b) /
        valid.length;
  }

  /// Pearson correlation coefficient between predicted and actual.
  double get correlation {
    final valid = pairs.where((p) => p.actualCalories != null).toList();
    if (valid.length < 2) return 0;
    final predMean =
        valid.map((p) => p.predictedCaloriesAvg).reduce((a, b) => a + b) /
            valid.length;
    final actMean =
        valid.map((p) => p.actualCalories!).reduce((a, b) => a + b) /
            valid.length;

    double num = 0, denPred = 0, denAct = 0;
    for (final p in valid) {
      final dp = p.predictedCaloriesAvg - predMean;
      final da = p.actualCalories! - actMean;
      num += dp * da;
      denPred += dp * dp;
      denAct += da * da;
    }
    final den = math.sqrt(denPred * denAct);
    if (den == 0) return 0;
    return num / den;
  }

  /// Metrics broken down by depth mode.
  Map<String, EvalMetrics> get byDepthMode {
    final map = <String, List<EvalPair>>{};
    for (final p in pairs) {
      map.putIfAbsent(p.depthMode, () => []).add(p);
    }
    return map.map((k, v) => MapEntry(k, EvalMetrics(pairs: v)));
  }
}

/// State for the evaluation provider.
class EvalState {
  final bool loading;
  final EvalMetrics metrics;

  const EvalState({this.loading = false, this.metrics = const EvalMetrics()});
}

/// Provider that loads all ground truth data and computes accuracy metrics.
class EvalNotifier extends StateNotifier<EvalState> {
  EvalNotifier() : super(const EvalState());

  Future<void> load() async {
    state = const EvalState(loading: true);

    final db = DatabaseService.instance;
    final allScans = await db.getAllScanResults();
    final allGTs = await db.getAllGroundTruths();

    // Index ground truths by detected_food_id
    final gtByFoodId = <int, GroundTruth>{};
    for (final gt in allGTs) {
      gtByFoodId[gt.detectedFoodId] = gt;
    }

    // Build paired observations
    final pairs = <EvalPair>[];
    int scansWithGT = 0;

    for (final scan in allScans) {
      bool hasGT = false;
      for (final food in scan.foods) {
        if (food.id == null) continue;
        final gt = gtByFoodId[food.id!];
        if (gt != null) {
          hasGT = true;
          // Look up density for weight/volume error calculation
          final foodData = await db.getFoodByLabel(food.label);
          pairs.add(EvalPair(
            scanId: scan.id ?? 0,
            label: food.label,
            volumeCm3: food.volumeCm3,
            predictedCaloriesMin: food.caloriesMin,
            predictedCaloriesMax: food.caloriesMax,
            actualWeightGrams: gt.actualWeightGrams,
            actualCalories: gt.actualCalories,
            depthMode: scan.depthMode,
            timestamp: scan.timestamp,
            densityMin: foodData?.densityMin ?? 0.8,
            densityMax: foodData?.densityMax ?? 1.0,
          ));
        }
      }
      if (hasGT) scansWithGT++;
    }

    state = EvalState(
      metrics: EvalMetrics(
        pairs: pairs,
        totalScans: allScans.length,
        scansWithGroundTruth: scansWithGT,
      ),
    );
  }
}

final evalProvider = StateNotifierProvider<EvalNotifier, EvalState>(
  (ref) => EvalNotifier(),
);
