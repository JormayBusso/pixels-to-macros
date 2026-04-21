import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/scan_result.dart';
import '../models/ground_truth.dart';
import '../services/database_service.dart';

/// Exports scan history to CSV format (Part 16 — evaluation support).
class DataExportService {
  DataExportService._();
  static final DataExportService instance = DataExportService._();

  /// Generate CSV string from all scan results.
  Future<String> exportToCsv() async {
    final scans = await DatabaseService.instance.getAllScanResults();

    final buf = StringBuffer();
    // Header
    buf.writeln(
      'scan_id,timestamp,depth_mode,food_label,volume_cm3,'
      'calories_min,calories_max,calories_avg',
    );

    for (final scan in scans) {
      for (final food in scan.foods) {
        final avg = (food.caloriesMin + food.caloriesMax) / 2;
        buf.writeln(
          '${scan.id},'
          '${scan.timestamp.toIso8601String()},'
          '${_escapeCsv(scan.depthMode)},'
          '${_escapeCsv(food.label)},'
          '${food.volumeCm3.toStringAsFixed(2)},'
          '${food.caloriesMin.toStringAsFixed(1)},'
          '${food.caloriesMax.toStringAsFixed(1)},'
          '${avg.toStringAsFixed(1)}',
        );
      }
    }

    return buf.toString();
  }

  /// Generate a daily summary CSV.
  Future<String> exportDailySummary() async {
    final scans = await DatabaseService.instance.getAllScanResults();

    // Group by date
    final byDate = <String, List<ScanResult>>{};
    for (final scan in scans) {
      final key =
          '${scan.timestamp.year}-${scan.timestamp.month.toString().padLeft(2, '0')}-${scan.timestamp.day.toString().padLeft(2, '0')}';
      byDate.putIfAbsent(key, () => []).add(scan);
    }

    final buf = StringBuffer();
    buf.writeln('date,scan_count,total_calories_min,total_calories_max,total_calories_avg');

    final sortedDates = byDate.keys.toList()..sort();
    for (final date in sortedDates) {
      final dayScans = byDate[date]!;
      double minSum = 0, maxSum = 0;
      for (final s in dayScans) {
        minSum += s.totalCaloriesMin;
        maxSum += s.totalCaloriesMax;
      }
      final avg = (minSum + maxSum) / 2;
      buf.writeln(
        '$date,${dayScans.length},'
        '${minSum.toStringAsFixed(1)},${maxSum.toStringAsFixed(1)},'
        '${avg.toStringAsFixed(1)}',
      );
    }

    return buf.toString();
  }

  /// Save CSV to documents directory and return the file path.
  Future<String> saveToFile(String csv, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);
    return file.path;
  }

  /// Copy CSV to clipboard.
  Future<void> copyToClipboard(String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
  }

  /// Generate evaluation CSV pairing predicted vs actual values.
  ///
  /// Includes all food items that have ground truth entries, with
  /// columns for predicted min/max/avg, actual weight/calories,
  /// absolute error, percentage error, and whether actual is in range.
  Future<String> exportEvaluationCsv() async {
    final db = DatabaseService.instance;
    final scans = await db.getAllScanResults();
    final allGTs = await db.getAllGroundTruths();

    // Index by detected food ID
    final gtByFoodId = <int, GroundTruth>{};
    for (final gt in allGTs) {
      gtByFoodId[gt.detectedFoodId] = gt;
    }

    final buf = StringBuffer();
    buf.writeln(
      'scan_id,timestamp,depth_mode,food_label,volume_cm3,'
      'predicted_min,predicted_max,predicted_avg,'
      'actual_weight_g,actual_kcal,'
      'abs_error,pct_error,within_range,notes',
    );

    for (final scan in scans) {
      for (final food in scan.foods) {
        if (food.id == null) continue;
        final gt = gtByFoodId[food.id!];
        if (gt == null) continue;

        final predAvg = (food.caloriesMin + food.caloriesMax) / 2;
        final absErr = gt.actualCalories != null
            ? (predAvg - gt.actualCalories!).abs()
            : null;
        final pctErr = gt.actualCalories != null && gt.actualCalories! > 0
            ? (absErr! / gt.actualCalories!) * 100
            : null;
        final inRange = gt.actualCalories != null
            ? (gt.actualCalories! >= food.caloriesMin &&
                gt.actualCalories! <= food.caloriesMax)
            : null;

        buf.writeln(
          '${scan.id},'
          '${scan.timestamp.toIso8601String()},'
          '${_escapeCsv(scan.depthMode)},'
          '${_escapeCsv(food.label)},'
          '${food.volumeCm3.toStringAsFixed(2)},'
          '${food.caloriesMin.toStringAsFixed(1)},'
          '${food.caloriesMax.toStringAsFixed(1)},'
          '${predAvg.toStringAsFixed(1)},'
          '${gt.actualWeightGrams.toStringAsFixed(1)},'
          '${gt.actualCalories?.toStringAsFixed(1) ?? ""},'
          '${absErr?.toStringAsFixed(1) ?? ""},'
          '${pctErr?.toStringAsFixed(1) ?? ""},'
          '${inRange ?? ""},'
          '${_escapeCsv(gt.notes ?? "")}',
        );
      }
    }

    return buf.toString();
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
