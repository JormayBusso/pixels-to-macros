import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/scan_result.dart';
import '../models/food_data.dart';
import '../services/database_service.dart';
import '../services/debug_log.dart';
import '../services/native_bridge.dart';

enum ScanFailureKind {
  noFood,
  analysisFailed,
  reconstructionFailed,
  dualSilhouetteFailed,
  sideViewRequired,
  containerPortionReviewRequired,
}

class ApproximatePortion {
  const ApproximatePortion({
    required this.label,
    this.grams,
    this.foodData,
  });
  final String label;
  final double? grams;
  final FoodData? foodData;
}

/// Holds the results of the most recent scan.
class ScanResultState {
  const ScanResultState({
    this.loading = false,
    this.error,
    this.failureKind,
    this.foods = const [],
    this.unmeasuredFoodLabels = const [],
    this.approximate = false,
    this.portions = const [],
    this.metadata = const [],
  });

  final bool loading;
  final String? error;
  final ScanFailureKind? failureKind;
  final List<DetectedFood> foods;
  final List<String> unmeasuredFoodLabels;
  final bool approximate;
  final List<ApproximatePortion> portions;
  final List<Map<String, dynamic>> metadata;
  bool get needsPortionReview => approximate && portions.isNotEmpty;
  bool get hasUnmeasuredFoods => unmeasuredFoodLabels.isNotEmpty;

  ScanResultState copyWith({
    bool? loading,
    String? error,
    ScanFailureKind? failureKind,
    List<DetectedFood>? foods,
    List<String>? unmeasuredFoodLabels,
    List<ApproximatePortion>? portions,
    List<Map<String, dynamic>>? metadata,
  }) {
    return ScanResultState(
      loading: loading ?? this.loading,
      error: error,
      failureKind: failureKind,
      foods: foods ?? this.foods,
      unmeasuredFoodLabels: unmeasuredFoodLabels ?? this.unmeasuredFoodLabels,
      approximate: approximate,
      portions: portions ?? this.portions,
      metadata: metadata ?? this.metadata,
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
  ScanResultNotifier({
    Future<List<Map<String, dynamic>>> Function()? runInference,
    Future<FoodData?> Function(String)? lookupFood,
    Future<double?> Function(String)? lookupPortion,
  })  : _runInference = runInference,
        _lookupFood = lookupFood,
        _lookupPortion = lookupPortion,
        super(const ScanResultState());

  final Future<List<Map<String, dynamic>>> Function()? _runInference;
  final Future<FoodData?> Function(String)? _lookupFood;
  final Future<double?> Function(String)? _lookupPortion;

  /// Maps model output labels to user-friendly DB labels where they differ.
  static const _labelAliases = {
    'chicken duck': 'chicken',
    'white rice': 'rice',
    'fried rice': 'fried rice',
    'rice with vegetables': 'vegetable rice',
    'rice with peas': 'vegetable rice',
    'rice with carrots': 'vegetable rice',
    'rice with peas and carrots': 'vegetable rice',
    'steamed rice': 'rice',
    'french fries': 'french fries',
    'fries': 'french fries',
    'potato fries': 'french fries',
    'chips': 'french fries',
    'roast chicken': 'chicken',
    'beef steak': 'steak',
    'grilled salmon': 'salmon',
    'salmon fillet': 'salmon',
    'grilled fish': 'fish',
    'fried fish': 'fish',
    'orange juice': 'orange juice',
    'apple juice': 'apple juice',
    'hard boiled egg': 'egg',
    'scrambled egg': 'scrambled eggs',
    'fried egg': 'egg',
    'boiled egg': 'egg',
    'whole wheat bread': 'bread',
    'white bread': 'bread',
    'toast': 'bread',
    'yoghurt': 'yogurt',
    'red pepper': 'pepper',
    'green pepper': 'pepper',
    'carrots': 'carrot',
    'baby carrots': 'carrot',
    'peas': 'green peas',
    'pea': 'green peas',
    'green pea': 'green peas',
    // Classifier vocabulary spelling variants that share a nutrition profile.
    'lox': 'smoked salmon',
    'canned tuna': 'tuna',
    'omelet': 'omelette',
    'macaroni': 'pasta',
    'baked potato': 'potato',
    'barbecue sauce': 'bbq sauce',
    'dressing': 'salad dressing',
    'sweet chilli sauce': 'sweet chili sauce',
  };

  // Labels that are NOT foods — model noise, non-food objects, or sentence fragments.
  // These are rejected before any further processing.
  static const _nonFoodLabels = {
    'background', 'others', 'other', 'unknown', 'food', 'dish', 'meal',
    'plate', 'bowl', 'cup', 'glass', 'table', 'surface', 'object',
    'person', 'hand', 'finger', 'spoon', 'fork', 'knife', 'utensil',
    // Common sentence fragment fragments the FoodSeg model sometimes emits:
    'and', 'the', 'with', 'of', 'a', 'an', 'in', 'on', 'for', 'to',
    'is', 'are', 'it', 'this', 'that',
    // Non-food items that occasionally score high:
    'paper', 'napkin', 'cloth', 'wrapper', 'box', 'bag', 'container',
    'packaging', 'label', 'text', 'logo',
  };

  /// Returns true if a label looks like a plausible food name.
  /// Rejects: very short tokens, all-numeric strings, labels with 4+ words
  /// (likely a sentence fragment), and entries in [_nonFoodLabels].
  static bool _isFoodLabel(String label) {
    final lower = label.toLowerCase().trim();
    if (lower.isEmpty || lower.length < 2) return false;
    if (_nonFoodLabels.contains(lower)) return false;
    // Reject pure numbers
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(lower)) return false;
    // Reject if it contains sentence-like punctuation
    if (lower.contains(RegExp(r'[.,!?;:()\[\]]'))) return false;
    // Reject 5+ word strings — model is concatenating descriptions
    final wordCount = lower.split(RegExp(r'\s+')).length;
    if (wordCount >= 5) return false;
    return true;
  }

  /// Normalise a model label: reject non-food and apply aliases.
  static String? _normaliseLabel(String raw) {
    final trimmed = raw.trim();
    if (!_isFoodLabel(trimmed)) return null;
    final lower = trimmed.toLowerCase();
    return _labelAliases[lower] ?? trimmed;
  }

  /// Run the multi-frame video inference pipeline.
  Future<void> runVideoScan({bool extraAccuracy = true}) async {
    state = ScanResultState(loading: true, approximate: !extraAccuracy);

    try {
      // Load the user's on-device label corrections so the native pipeline can
      // recognise foods they've already taught it. Local SQLite only.
      final rawVolumes = await (_runInference?.call() ??
          _runNativeInference(extraAccuracy: extraAccuracy));
      debugPrint(
          '[SCAN] Flutter received ${rawVolumes.length} raw items from native');
      for (final vol in rawVolumes) {
        debugPrint('[SCAN] Flutter item: $vol');
      }

      if (rawVolumes.isEmpty) {
        DebugLog.instance.log(
          'VideoScan',
          'Native video inference returned empty; treating as no-food scan.',
        );
        state = const ScanResultState(
          error: 'No food detected.',
          failureKind: ScanFailureKind.noFood,
        );
        return;
      }

      if (!extraAccuracy) {
        final portions = <ApproximatePortion>[];
        for (final item in rawVolumes) {
          final label = _normaliseLabel(item['label'] as String? ?? '');
          if (label == null) continue;
          final food = await _foodFor(label);
          final grams = food == null ? null : await _previousPortion(label);
          portions.add(
              ApproximatePortion(label: label, grams: grams, foodData: food));
        }
        state = portions.isEmpty
            ? const ScanResultState(
                error: 'No food detected.', failureKind: ScanFailureKind.noFood)
            : ScanResultState(approximate: true, portions: portions);
        return;
      }

      final foods = <DetectedFood>[];
      final unmeasuredFoodLabels = <String>[];

      // A strict monocular plate is atomic: one unsupported food requires a
      // retake before nutrition lookup or the screen's successful-save branch.
      // Legacy history and the separate LiDAR status contract stay readable.
      for (final vol in rawVolumes) {
        final mode = vol['scan_mode'] as String? ?? '';
        final label = _normaliseLabel(vol['label'] as String? ?? 'unknown');
        if (label != null &&
            mode.startsWith('monocular_') &&
            !ScanVolumeStatus.hasUsableVolume(
              ScanVolumeStatus.fromMap(vol),
              (vol['volume_cm3'] as num?)?.toDouble() ?? 0,
            )) {
          throw PlatformException(
            code: 'SIDE_VIEW_REQUIRED',
            details: vol['side_missing_reason'] ??
                'missing_or_invalid_monocular_measurement',
          );
        }
      }

      for (final vol in rawVolumes) {
        final rawLabel = vol['label'] as String? ?? 'unknown';
        final label = _normaliseLabel(rawLabel);
        if (label == null) {
          DebugLog.instance
              .log('VideoScan', 'Rejected non-food label: $rawLabel');
          continue;
        }
        final volumeCm3 = (vol['volume_cm3'] as num?)?.toDouble() ?? 0;
        final pixelCount = (vol['pixel_count'] as num?)?.toInt() ?? 0;
        final confidence = (vol['confidence'] as num?)?.toDouble();
        final framesUsed = (vol['frames_used'] as num?)?.toInt() ?? 0;

        if (!ScanVolumeStatus.hasUsableVolume(
          ScanVolumeStatus.fromMap(vol),
          volumeCm3,
        )) {
          // Native has exported an outline, not a nutritional measurement.
          // Do not let the volume-size gate erase it or invent nutrition.
          unmeasuredFoodLabels.add(label);
          DebugLog.instance.log(
            'VideoScan',
            '$label: volume unmeasured, side=${vol['side_missing_reason']}',
          );
          continue;
        }

        if (!_passesDetectionGate(
          label: label,
          volumeCm3: volumeCm3,
          pixelCount: pixelCount,
          confidence: confidence,
        )) {
          DebugLog.instance.log(
            'VideoScan',
            'Rejected $label as low-confidence/no-food candidate '
                '($volumeCm3 cm³, $pixelCount px, conf $confidence)',
          );
          continue;
        }

        final foodData = await (_lookupFood?.call(label) ??
            DatabaseService.instance.getFoodByLabelFuzzy(label));
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

        DebugLog.instance.log(
          'NutritionMeasurement',
          'nativeId=${vol['id']} rawLabel=$rawLabel normalizedLabel=$label '
              'volumeSource=${vol['volume_source']} volumeCm3=$volumeCm3 '
              'lookup=${foodData?.label ?? "none"} '
              'densitySource=${foodData != null ? "food_database_range" : "unknown_food_fallback"} '
              'densityMin=${foodData?.densityMin} densityMax=${foodData?.densityMax} '
              'kcalPer100g=${foodData?.kcalPer100g} calories=$calMin...$calMax',
        );

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
                '${confidence != null ? ", conf ${confidence.toStringAsFixed(2)}" : ""}');
      }

      if (foods.isEmpty && unmeasuredFoodLabels.isEmpty) {
        state = const ScanResultState(
          error: 'No food detected.',
          failureKind: ScanFailureKind.noFood,
        );
      } else {
        state = ScanResultState(
          foods: foods,
          unmeasuredFoodLabels: unmeasuredFoodLabels,
        );
      }
    } catch (e) {
      final failureKind = classifyFailure(e);
      DebugLog.instance.log(
        'VideoScan',
        'Native video inference failed: $e ($failureKind)',
      );
      state = ScanResultState(
        error: failureKind == ScanFailureKind.noFood
            ? 'No food detected.'
            : e.toString(),
        failureKind: failureKind,
      );
    }
  }

  Future<FoodData?> _foodFor(String label) async => _lookupFood != null
      ? _lookupFood(label)
      : DatabaseService.instance.getFoodByLabelFuzzy(label);

  Future<double?> _previousPortion(String label) async {
    if (_lookupPortion != null) return _lookupPortion(label);
    final scans = await DatabaseService.instance.getAllScanResults();
    for (final scan in scans) {
      for (final food in scan.foods) {
        if (food.label.toLowerCase() != label.toLowerCase()) continue;
        final grams = scan.reviewedPortionFor(food);
        if (grams != null) return grams;
      }
    }
    return null;
  }

  Future<bool> confirmApproximatePortions(
      List<ApproximatePortion> reviewed) async {
    if (!state.needsPortionReview || reviewed.length != state.portions.length) {
      return false;
    }
    final foods = <DetectedFood>[];
    final metadata = <Map<String, dynamic>>[];
    for (final portion in reviewed) {
      final label = _normaliseLabel(portion.label);
      final grams = portion.grams;
      if (label == null || grams == null || !grams.isFinite || grams <= 0) {
        return false;
      }
      final data = await _foodFor(label);
      if (data == null || !data.kcalPer100g.isFinite || data.kcalPer100g < 0) {
        return false;
      }
      // Store weight separately: it is user-reviewed, never a measured volume.
      final calories = grams / 100 * data.kcalPer100g;
      if (!calories.isFinite) return false;
      foods.add(DetectedFood(
          label: data.label,
          volumeCm3: 0,
          caloriesMin: calories,
          caloriesMax: calories));
      metadata.add({
        'food_index': foods.length - 1,
        'label': data.label,
        'scan_mode': 'approximate',
        'volume_status': 'unavailable',
        'volume_measured': false,
        'volume_cm3': 0,
        'portion_status': 'estimated',
        'portion_reviewed': true,
        'estimated': true,
        'portion_amount': grams,
        'portion_unit': data.perMl ? 'ml' : 'g',
        if (!data.perMl) 'weight_g': grams,
        'measurement_provenance': 'user_reviewed_local_food_portion',
      });
    }
    state =
        ScanResultState(approximate: true, foods: foods, metadata: metadata);
    return true;
  }

  Future<List<Map<String, dynamic>>> _runNativeInference({
    required bool extraAccuracy,
  }) async {
    final userExemplars = await DatabaseService.instance.getFoodExemplars();
    return NativeBridge.instance.runVideoInference(
        userExemplars: userExemplars, extraAccuracy: extraAccuracy);
  }

  @visibleForTesting
  static ScanFailureKind classifyFailure(Object error) {
    if (error is PlatformException) {
      if (error.code == 'CONTAINER_PORTION_REVIEW_REQUIRED') {
        return ScanFailureKind.containerPortionReviewRequired;
      }
      if (error.code == 'SIDE_VIEW_REQUIRED') {
        return ScanFailureKind.sideViewRequired;
      }
      if (error.code == 'NO_FOOD_DETECTED') return ScanFailureKind.noFood;
      if (error.code == 'DUAL_SILHOUETTE_FAILED') {
        return ScanFailureKind.dualSilhouetteFailed;
      }
      final message =
          '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
      if (_looksLikeNoFoodFailure(message)) return ScanFailureKind.noFood;
      if (message.contains('3d') || message.contains('export')) {
        return ScanFailureKind.reconstructionFailed;
      }
    }
    final text = error.toString().toLowerCase();
    if (_looksLikeNoFoodFailure(text)) return ScanFailureKind.noFood;
    if (text.contains('3d') || text.contains('export')) {
      return ScanFailureKind.reconstructionFailed;
    }
    return ScanFailureKind.analysisFailed;
  }

  static bool _looksLikeNoFoodFailure(String text) {
    return text.contains('no_food') ||
        text.contains('no food') ||
        text.contains('food_gate_rejected') ||
        text.contains('food_presence_gate_failed') ||
        text.contains('segmentation_empty');
  }

  bool _passesDetectionGate({
    required String label,
    required double volumeCm3,
    required int pixelCount,
    required double? confidence,
  }) {
    // Non-food labels are already filtered by _normaliseLabel; this gate
    // only applies physical size thresholds. Native confidence is retained for
    // diagnostics and low-confidence UI, but a valid exported 3-D object must
    // not be erased solely because the fallback path was cautious.
    if (volumeCm3 < 6.0) return false;
    if (pixelCount < 650) return false;
    return true;
  }

  void reset() => state = const ScanResultState();
}

/// Global provider.
final scanResultProvider =
    StateNotifierProvider<ScanResultNotifier, ScanResultState>(
  (ref) => ScanResultNotifier(),
);
