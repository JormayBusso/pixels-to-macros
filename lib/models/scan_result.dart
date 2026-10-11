import 'dart:convert';

/// Null means a legacy record did not declare whether volume was measured.
enum ScanVolumeStatus {
  measured,
  estimated,
  unmeasured;

  static ScanVolumeStatus? fromMap(Map<String, dynamic> map) {
    if (map['volume_status'] == 'estimated') return ScanVolumeStatus.estimated;
    if (map['volume_status'] == 'unavailable' ||
        map['scan_mode'] == 'approximate') {
      return ScanVolumeStatus.unmeasured;
    }
    final measured = map['volume_measured'];
    if (measured is bool) {
      return measured ? ScanVolumeStatus.measured : ScanVolumeStatus.unmeasured;
    }
    if (map['scan_mode'] == 'monocular_top_only') {
      return ScanVolumeStatus.unmeasured;
    }
    return null;
  }

  static bool hasUsableVolume(ScanVolumeStatus? status, double volumeCm3) =>
      status != ScanVolumeStatus.unmeasured &&
      volumeCm3.isFinite &&
      volumeCm3 > 0;
}

/// Result of a single scan stored locally (Part 13 — result history).
class ScanResult {
  final int? id;
  final DateTime timestamp;
  final String depthMode;
  final List<DetectedFood> foods;

  /// Camera pose data (Part 9) — stored as JSON strings.
  final String? topCameraPosition;
  final String? topCameraTransform;
  final String? sideCameraPosition;
  final String? sideCameraTransform;

  /// File path of the rendered scan overlay image (camera + segmentation mask).
  final String? imagePath;

  /// Real capture images and exported 3-D model from the scan.
  final String? topImagePath;
  final String? sideImagePath;
  final String? modelPath;
  final String? modelObjectsJson;

  const ScanResult({
    this.id,
    required this.timestamp,
    required this.depthMode,
    required this.foods,
    this.topCameraPosition,
    this.topCameraTransform,
    this.sideCameraPosition,
    this.sideCameraTransform,
    this.imagePath,
    this.topImagePath,
    this.sideImagePath,
    this.modelPath,
    this.modelObjectsJson,
  });

  double get totalCaloriesMin =>
      foods.fold(0.0, (sum, f) => sum + f.caloriesMin);

  double get totalCaloriesMax =>
      foods.fold(0.0, (sum, f) => sum + f.caloriesMax);

  bool get isApproximate => depthMode == 'approximate';

  double? reviewedPortionFor(DetectedFood food) {
    if (!isApproximate || modelObjectsJson == null) return null;
    try {
      final objects = jsonDecode(modelObjectsJson!) as List;
      final index = foods.indexOf(food);
      for (final object in objects.whereType<Map>()) {
        if ((object['food_index'] == index ||
                (object['food_index'] == null &&
                    object['label'] == food.label)) &&
            object['portion_reviewed'] == true) {
          final grams =
              ((object['portion_amount'] ?? object['weight_g']) as num?)
                  ?.toDouble();
          if (grams != null && grams.isFinite && grams > 0) return grams;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Unmeasured objects live in model metadata, never in nutrition rows.
  List<String> get unmeasuredFoodLabels {
    final raw = modelObjectsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final objects = jsonDecode(raw) as List<dynamic>;
      return [
        for (final object in objects.whereType<Map>())
          if (object['portion_reviewed'] != true &&
              !ScanVolumeStatus.hasUsableVolume(
                ScanVolumeStatus.fromMap(Map<String, dynamic>.from(object)),
                (object['volume_cm3'] as num?)?.toDouble() ?? 0,
              ))
            object['label'] as String? ?? '',
      ].where((label) => label.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'depth_mode': depthMode,
      if (topCameraPosition != null) 'top_camera_position': topCameraPosition,
      if (topCameraTransform != null)
        'top_camera_transform': topCameraTransform,
      if (sideCameraPosition != null)
        'side_camera_position': sideCameraPosition,
      if (sideCameraTransform != null)
        'side_camera_transform': sideCameraTransform,
      if (imagePath != null) 'image_path': imagePath,
      if (topImagePath != null) 'top_image_path': topImagePath,
      if (sideImagePath != null) 'side_image_path': sideImagePath,
      if (modelPath != null) 'model_path': modelPath,
      if (modelObjectsJson != null) 'model_objects_json': modelObjectsJson,
    };
  }

  factory ScanResult.fromMap(Map<String, dynamic> map,
      {List<DetectedFood> foods = const []}) {
    return ScanResult(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      depthMode: map['depth_mode'] as String,
      foods: foods,
      topCameraPosition: map['top_camera_position'] as String?,
      topCameraTransform: map['top_camera_transform'] as String?,
      sideCameraPosition: map['side_camera_position'] as String?,
      sideCameraTransform: map['side_camera_transform'] as String?,
      imagePath: map['image_path'] as String?,
      topImagePath: map['top_image_path'] as String?,
      sideImagePath: map['side_image_path'] as String?,
      modelPath: map['model_path'] as String?,
      modelObjectsJson: map['model_objects_json'] as String?,
    );
  }
}

/// One food item detected in a scan.
class DetectedFood {
  final int? id;
  final int? scanId;
  final String label;
  final double volumeCm3;
  final double caloriesMin;
  final double caloriesMax;

  const DetectedFood({
    this.id,
    this.scanId,
    required this.label,
    required this.volumeCm3,
    required this.caloriesMin,
    required this.caloriesMax,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (scanId != null) 'scan_id': scanId,
      'label': label,
      'volume_cm3': volumeCm3,
      'calories_min': caloriesMin,
      'calories_max': caloriesMax,
    };
  }

  factory DetectedFood.fromMap(Map<String, dynamic> map) {
    return DetectedFood(
      id: map['id'] as int?,
      scanId: map['scan_id'] as int?,
      label: map['label'] as String,
      volumeCm3: (map['volume_cm3'] as num).toDouble(),
      caloriesMin: (map['calories_min'] as num).toDouble(),
      caloriesMax: (map['calories_max'] as num).toDouble(),
    );
  }

  /// Display string: "Rice: 240 kcal ± 30 kcal"
  String get displayCalories {
    final avg = (caloriesMin + caloriesMax) / 2;
    final margin = (caloriesMax - caloriesMin) / 2;
    return '$label: ${avg.round()} kcal ± ${margin.round()} kcal';
  }
}
