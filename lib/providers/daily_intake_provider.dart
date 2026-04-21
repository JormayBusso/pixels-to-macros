import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';

/// Today's aggregated calorie intake from all scans.
class DailyIntake {
  final bool loading;
  final double caloriesMin;
  final double caloriesMax;
  final int scanCount;
  final List<DetectedFood> foods;

  const DailyIntake({
    this.loading = false,
    this.caloriesMin = 0,
    this.caloriesMax = 0,
    this.scanCount = 0,
    this.foods = const [],
  });

  double get caloriesAvg => (caloriesMin + caloriesMax) / 2;
}

class DailyIntakeNotifier extends StateNotifier<DailyIntake> {
  DailyIntakeNotifier() : super(const DailyIntake());

  Future<void> load() async {
    state = const DailyIntake(loading: true);

    final allScans = await DatabaseService.instance.getAllScanResults();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final todayScans = allScans.where(
      (s) => s.timestamp.isAfter(todayStart),
    );

    double minSum = 0;
    double maxSum = 0;
    final allFoods = <DetectedFood>[];

    for (final scan in todayScans) {
      minSum += scan.totalCaloriesMin;
      maxSum += scan.totalCaloriesMax;
      allFoods.addAll(scan.foods);
    }

    state = DailyIntake(
      caloriesMin: minSum,
      caloriesMax: maxSum,
      scanCount: todayScans.length,
      foods: allFoods,
    );
  }
}

final dailyIntakeProvider =
    StateNotifierProvider<DailyIntakeNotifier, DailyIntake>(
  (ref) => DailyIntakeNotifier(),
);
