import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Thin wrapper around the `health` plugin that reads the two signals the
/// adaptive daily calorie target needs from Apple Health / HealthKit:
///   • body **weight** (keeps the maintenance estimate current), and
///   • **active energy burned** (adapts the day's budget to real activity).
///
/// iOS-only: on any other platform every method is a safe no-op. The class is a
/// pure reader — it never writes to HealthKit — so only read authorization is
/// requested.
class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  final Health _health = Health();
  bool _configured = false;

  static const List<HealthDataType> _types = <HealthDataType>[
    HealthDataType.WEIGHT,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];
  static const List<HealthDataAccess> _permissions = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  /// Apple Health is iPhone-only in this app.
  bool get isSupported => Platform.isIOS;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Prompt for read access. Returns true when the request completes without
  /// error (HealthKit deliberately does not reveal whether READ was granted, so
  /// callers must also tolerate empty reads).
  Future<bool> requestAuthorization() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(_types, permissions: _permissions);
    } catch (e) {
      debugPrint('[Health] requestAuthorization failed: $e');
      return false;
    }
  }

  /// Best-effort check of whether access has already been granted.
  Future<bool> hasPermissions() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      return (await _health.hasPermissions(_types, permissions: _permissions)) ??
          false;
    } catch (e) {
      debugPrint('[Health] hasPermissions failed: $e');
      return false;
    }
  }

  /// Most recent body-mass reading in kilograms, or null if none/​out of range.
  Future<double?> latestWeightKg() async {
    if (!isSupported) return null;
    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final points = await _health.getHealthDataFromTypes(
        types: const <HealthDataType>[HealthDataType.WEIGHT],
        startTime: now.subtract(const Duration(days: 400)),
        endTime: now,
      );
      if (points.isEmpty) return null;
      points.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final value = points.first.value;
      if (value is NumericHealthValue) {
        final kg = value.numericValue.toDouble();
        if (kg > 20 && kg < 400) return kg;
      }
      return null;
    } catch (e) {
      debugPrint('[Health] latestWeightKg failed: $e');
      return null;
    }
  }

  /// Total active energy (kcal) burned between [start] and [end].
  Future<double> activeEnergyKcal(DateTime start, DateTime end) async {
    if (!isSupported || !end.isAfter(start)) return 0;
    try {
      await _ensureConfigured();
      final points = await _health.getHealthDataFromTypes(
        types: const <HealthDataType>[HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: start,
        endTime: end,
      );
      final unique = _health.removeDuplicates(points);
      var sum = 0.0;
      for (final p in unique) {
        final value = p.value;
        if (value is NumericHealthValue) sum += value.numericValue.toDouble();
      }
      return sum < 0 ? 0 : sum;
    } catch (e) {
      debugPrint('[Health] activeEnergyKcal failed: $e');
      return 0;
    }
  }

  /// Active energy (kcal) burned so far today (local midnight → now).
  Future<double> todayActiveEnergyKcal() {
    final now = DateTime.now();
    return activeEnergyKcal(DateTime(now.year, now.month, now.day), now);
  }

  /// Average daily active energy (kcal) over the last [days] COMPLETED days
  /// (today is excluded because it is only partial). This is the user's
  /// habitual activity, already implicitly baked into the maintenance estimate,
  /// so the adaptive target only reacts to activity ABOVE this baseline.
  Future<double> habitualDailyActiveEnergyKcal({int days = 7}) async {
    if (!isSupported || days <= 0) return 0;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final start = todayStart.subtract(Duration(days: days));
    final total = await activeEnergyKcal(start, todayStart);
    if (total <= 0) return 0;
    return total / days;
  }
}
