import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';

/// Daily calorie summary for analytics.
class DaySummary {
  final DateTime date;
  final double caloriesAvg;
  final int scanCount;

  const DaySummary({
    required this.date,
    required this.caloriesAvg,
    required this.scanCount,
  });
}

/// Analytics state for the past N days.
class AnalyticsState {
  final bool loading;
  final List<DaySummary> days;
  final int rangeDays;

  const AnalyticsState({
    this.loading = false,
    this.days = const [],
    this.rangeDays = 7,
  });

  double get averageDaily {
    if (days.isEmpty) return 0;
    final total = days.fold(0.0, (sum, d) => sum + d.caloriesAvg);
    return total / days.length;
  }

  double get peakDay {
    if (days.isEmpty) return 0;
    return days.map((d) => d.caloriesAvg).reduce((a, b) => a > b ? a : b);
  }

  int get totalScans => days.fold(0, (sum, d) => sum + d.scanCount);
}

class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  AnalyticsNotifier() : super(const AnalyticsState());

  Future<void> load({int rangeDays = 7}) async {
    state = AnalyticsState(loading: true, rangeDays: rangeDays);

    final allScans = await DatabaseService.instance.getAllScanResults();
    final now = DateTime.now();
    final days = <DaySummary>[];

    for (int i = 0; i < rangeDays; i++) {
      final date = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final nextDate = date.add(const Duration(days: 1));

      final dayScans = allScans.where(
        (s) => s.timestamp.isAfter(date) && s.timestamp.isBefore(nextDate),
      );

      double totalAvg = 0;
      for (final scan in dayScans) {
        totalAvg += (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;
      }

      days.add(DaySummary(
        date: date,
        caloriesAvg: totalAvg,
        scanCount: dayScans.length,
      ));
    }

    state = AnalyticsState(
      days: days.reversed.toList(), // oldest first
      rangeDays: rangeDays,
    );
  }
}

final analyticsProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>(
  (ref) => AnalyticsNotifier(),
);
