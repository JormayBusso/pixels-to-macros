class WeightEntry {
  const WeightEntry({
    this.id,
    required this.recordedAt,
    required this.weightKg,
  });

  factory WeightEntry.fromMap(Map<String, dynamic> map) => WeightEntry(
        id: map['id'] as int?,
        recordedAt: DateTime.tryParse(map['recorded_at'] as String? ?? '') ??
            DateTime.now(),
        weightKg: (map['weight_kg'] as num?)?.toDouble() ?? 70.0,
      );

  final int? id;
  final DateTime recordedAt;
  final double weightKg;

  String get monthKey =>
      '${recordedAt.year.toString().padLeft(4, '0')}-${recordedAt.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'recorded_at': recordedAt.toIso8601String(),
        'weight_kg': weightKg,
      };
}

class CalorieCalibrationResult {
  const CalorieCalibrationResult({
    required this.recommendedCalories,
    required this.deltaCalories,
    required this.messageKey,
  });

  final int recommendedCalories;
  final int deltaCalories;
  final String messageKey;

  bool get changed => deltaCalories != 0;
}
