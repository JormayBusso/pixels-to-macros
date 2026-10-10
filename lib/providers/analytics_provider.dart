import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';

/// Daily summary row for analytics: average calories + macro grams + scan count.
class DaySummary {
  final DateTime date;
  final double caloriesAvg;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final int scanCount;

  const DaySummary({
    required this.date,
    required this.caloriesAvg,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.scanCount,
  });

  bool get isEmpty => scanCount == 0;
}

/// Aggregate analytics state for the past N days.
class AnalyticsState {
  final bool loading;
  final List<DaySummary> days;
  final int rangeDays;

  const AnalyticsState({
    this.loading = false,
    this.days = const [],
    this.rangeDays = 7,
  });

  Iterable<DaySummary> get _logged => days.where((d) => !d.isEmpty);

  double get averageDaily {
    final logged = _logged.toList();
    if (logged.isEmpty) return 0;
    final total = logged.fold(0.0, (s, d) => s + d.caloriesAvg);
    return total / logged.length;
  }

  double get peakDay {
    if (days.isEmpty) return 0;
    return days.map((d) => d.caloriesAvg).fold(0.0, (a, b) => a > b ? a : b);
  }

  double get lowestLoggedDay {
    final logged = _logged.toList();
    if (logged.isEmpty) return 0;
    return logged
        .map((d) => d.caloriesAvg)
        .reduce((a, b) => a < b ? a : b);
  }

  int get totalScans => days.fold(0, (s, d) => s + d.scanCount);

  int get loggedDays => _logged.length;

  double get consistency =>
      days.isEmpty ? 0 : loggedDays / days.length;

  /// Average daily macro grams across logged days.
  ({double protein, double carbs, double fat}) get avgMacros {
    final logged = _logged.toList();
    if (logged.isEmpty) return (protein: 0, carbs: 0, fat: 0);
    final p = logged.fold(0.0, (s, d) => s + d.proteinG) / logged.length;
    final c = logged.fold(0.0, (s, d) => s + d.carbsG) / logged.length;
    final f = logged.fold(0.0, (s, d) => s + d.fatG) / logged.length;
    return (protein: p, carbs: c, fat: f);
  }

  /// Trend: % change between latest half and earlier half of logged days.
  /// Returns null when there is not enough data to compare.
  double? get weeklyTrendPct {
    final logged = _logged.toList();
    if (logged.length < 4) return null;
    final mid = logged.length ~/ 2;
    final earlier = logged.sublist(0, mid);
    final later = logged.sublist(mid);
    final eAvg = earlier.fold(0.0, (s, d) => s + d.caloriesAvg) / earlier.length;
    final lAvg = later.fold(0.0, (s, d) => s + d.caloriesAvg) / later.length;
    if (eAvg <= 0) return null;
    return ((lAvg - eAvg) / eAvg) * 100.0;
  }

  /// Average calories per weekday (Monday=1 … Sunday=7). Returns 0 for
  /// weekdays with no logged data.
  Map<int, double> get weekdayAverages {
    final buckets = <int, List<double>>{};
    for (final d in _logged) {
      buckets.putIfAbsent(d.date.weekday, () => []).add(d.caloriesAvg);
    }
    return {
      for (int wd = 1; wd <= 7; wd++)
        wd: buckets[wd] == null
            ? 0.0
            : buckets[wd]!.reduce((a, b) => a + b) / buckets[wd]!.length,
    };
  }
}

class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  AnalyticsNotifier() : super(const AnalyticsState());

  Future<void> load({int rangeDays = 7}) async {
    state = AnalyticsState(loading: true, rangeDays: rangeDays);

    final allScans = await DatabaseService.instance.getAllScanResults();
    final now = DateTime.now();
    final days = <DaySummary>[];

    // Pre-fetch food DB rows we need (one per distinct label across scans).
    final labels = <String>{
      for (final s in allScans)
        for (final f in s.foods) f.label.toLowerCase(),
    };
    final foodCache = <String, dynamic>{};
    for (final label in labels) {
      foodCache[label] =
          await DatabaseService.instance.getFoodByLabel(label);
    }

    for (int i = 0; i < rangeDays; i++) {
      final date = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final nextDate = date.add(const Duration(days: 1));

      final dayScans = allScans
          .where((s) =>
              !s.timestamp.isBefore(date) && s.timestamp.isBefore(nextDate))
          .toList();

      double calSum = 0;
      double pSum = 0;
      double cSum = 0;
      double fSum = 0;
      for (final scan in dayScans) {
        calSum += (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;
        for (final food in scan.foods) {
          final fd = foodCache[food.label.toLowerCase()];
          if (fd != null && fd.kcalPer100g > 0) {
            final avgCal = (food.caloriesMin + food.caloriesMax) / 2;
            final weightG = avgCal / (fd.kcalPer100g / 100);
            pSum += weightG * fd.proteinPer100g / 100;
            cSum += weightG * fd.carbsPer100g / 100;
            fSum += weightG * fd.fatPer100g / 100;
          }
        }
      }

      days.add(DaySummary(
        date: date,
        caloriesAvg: calSum,
        proteinG: pSum,
        carbsG: cSum,
        fatG: fSum,
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
