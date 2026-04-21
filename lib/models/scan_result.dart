/// Result of a single scan stored locally (Part 13 — result history).
class ScanResult {
  final int? id;
  final DateTime timestamp;
  final String depthMode;
  final List<DetectedFood> foods;

  const ScanResult({
    this.id,
    required this.timestamp,
    required this.depthMode,
    required this.foods,
  });

  double get totalCaloriesMin =>
      foods.fold(0.0, (sum, f) => sum + f.caloriesMin);

  double get totalCaloriesMax =>
      foods.fold(0.0, (sum, f) => sum + f.caloriesMax);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'depth_mode': depthMode,
    };
  }

  factory ScanResult.fromMap(Map<String, dynamic> map,
      {List<DetectedFood> foods = const []}) {
    return ScanResult(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      depthMode: map['depth_mode'] as String,
      foods: foods,
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
