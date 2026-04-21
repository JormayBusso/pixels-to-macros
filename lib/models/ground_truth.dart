/// Ground truth measurement for a detected food item.
///
/// Used for scientific evaluation — the user enters the actual
/// weighed mass (grams) after scanning so we can compute accuracy.
class GroundTruth {
  final int? id;
  final int detectedFoodId;
  final int scanId;
  final double actualWeightGrams;
  final double? actualCalories;
  final String? notes;
  final DateTime timestamp;

  const GroundTruth({
    this.id,
    required this.detectedFoodId,
    required this.scanId,
    required this.actualWeightGrams,
    this.actualCalories,
    this.notes,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'detected_food_id': detectedFoodId,
      'scan_id': scanId,
      'actual_weight_grams': actualWeightGrams,
      'actual_calories': actualCalories,
      'notes': notes,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GroundTruth.fromMap(Map<String, dynamic> map) {
    return GroundTruth(
      id: map['id'] as int?,
      detectedFoodId: map['detected_food_id'] as int,
      scanId: map['scan_id'] as int,
      actualWeightGrams: (map['actual_weight_grams'] as num).toDouble(),
      actualCalories: (map['actual_calories'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
