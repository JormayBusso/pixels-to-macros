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
}

/// Holds the results of the most recent scan.
class ScanResultState {
  const ScanResultState({
    this.loading = false,
    this.error,
    this.failureKind,
    this.foods = const [],
    this.unmeasuredFoodLabels = const [],
  });

  final bool loading;
  final String? error;
  final ScanFailureKind? failureKind;
  final List<DetectedFood> foods;
  final List<String> unmeasuredFoodLabels;
  bool get hasUnmeasuredFoods => unmeasuredFoodLabels.isNotEmpty;

  ScanResultState copyWith({
    bool? loading,
    String? error,
    ScanFailureKind? failureKind,
    List<DetectedFood>? foods,
    List<String>? unmeasuredFoodLabels,
  }) {
    return ScanResultState(
      loading: loading ?? this.loading,
      error: error,
      failureKind: failureKind,
      foods: foods ?? this.foods,
      unmeasuredFoodLabels: unmeasuredFoodLabels ?? this.unmeasuredFoodLabels,
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
  })  : _runInference = runInference,
        _lookupFood = lookupFood,
        super(const ScanResultState());

  final Future<List<Map<String, dynamic>>> Function()? _runInference;
  final Future<FoodData?> Function(String)? _lookupFood;

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
  Future<void> runVideoScan() async {
    state = const ScanResultState(loading: true);

    try {
      // Load the user's on-device label corrections so the native pipeline can
      // recognise foods they've already taught it. Local SQLite only.
      final rawVolumes = await (_runInference?.call() ?? _runNativeInference());
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

      final foods = <DetectedFood>[];
      final unmeasuredFoodLabels = <String>[];

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

  Future<List<Map<String, dynamic>>> _runNativeInference() async {
    final userExemplars = await DatabaseService.instance.getFoodExemplars();
    return NativeBridge.instance
        .runVideoInference(userExemplars: userExemplars);
  }

  @visibleForTesting
  static ScanFailureKind classifyFailure(Object error) {
    if (error is PlatformException) {
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
