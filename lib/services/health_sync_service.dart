import 'package:health/health.dart';

/// Two-way Apple Health sync service.
///
/// Writes: dietary calories, protein, carbs, fat, fiber, water.
/// Reads: active energy burned, steps (for context in analytics).
///
/// Requires HealthKit entitlement + Info.plist keys. iOS only.
class HealthSyncService {
  HealthSyncService._();
  static final instance = HealthSyncService._();

  final _health = Health();
  bool _authorized = false;

  static const _writeTypes = [
    HealthDataType.DIETARY_ENERGY_CONSUMED,
    HealthDataType.DIETARY_PROTEIN_CONSUMED,
    HealthDataType.DIETARY_CARBS_CONSUMED,
    HealthDataType.DIETARY_FATS_CONSUMED,
    HealthDataType.DIETARY_FIBER,
    HealthDataType.WATER,
  ];

  static const _readTypes = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.STEPS,
    HealthDataType.DIETARY_ENERGY_CONSUMED,
    HealthDataType.DIETARY_PROTEIN_CONSUMED,
    HealthDataType.DIETARY_CARBS_CONSUMED,
    HealthDataType.DIETARY_FATS_CONSUMED,
  ];

  /// Request authorization. Returns true if granted.
  Future<bool> requestPermissions() async {
    try {
      final types = [..._readTypes, ..._writeTypes];
      final permissions = [
        ...List.filled(_readTypes.length, HealthDataAccess.READ),
        ...List.filled(_writeTypes.length, HealthDataAccess.READ_WRITE),
      ];
      _authorized = await _health.requestAuthorization(types, permissions: permissions);
      return _authorized;
    } catch (_) {
      return false;
    }
  }

  bool get isAuthorized => _authorized;

  // ── Write to Apple Health ──────────────────────────────────────────────

  /// Write a meal's nutrition data to Apple Health.
  Future<bool> writeMeal({
    required DateTime timestamp,
    required double caloriesKcal,
    required double proteinG,
    required double carbsG,
    required double fatG,
    double fiberG = 0,
  }) async {
    if (!_authorized) return false;
    try {
      final end = timestamp;
      final start = timestamp.subtract(const Duration(minutes: 15));

      final results = await Future.wait([
        _health.writeHealthData(
          value: caloriesKcal,
          type: HealthDataType.DIETARY_ENERGY_CONSUMED,
          startTime: start,
          endTime: end,
          unit: HealthDataUnit.KILOCALORIE,
        ),
        _health.writeHealthData(
          value: proteinG,
          type: HealthDataType.DIETARY_PROTEIN_CONSUMED,
          startTime: start,
          endTime: end,
          unit: HealthDataUnit.GRAM,
        ),
        _health.writeHealthData(
          value: carbsG,
          type: HealthDataType.DIETARY_CARBS_CONSUMED,
          startTime: start,
          endTime: end,
          unit: HealthDataUnit.GRAM,
        ),
        _health.writeHealthData(
          value: fatG,
          type: HealthDataType.DIETARY_FATS_CONSUMED,
          startTime: start,
          endTime: end,
          unit: HealthDataUnit.GRAM,
        ),
        if (fiberG > 0)
          _health.writeHealthData(
            value: fiberG,
            type: HealthDataType.DIETARY_FIBER,
            startTime: start,
            endTime: end,
            unit: HealthDataUnit.GRAM,
          ),
      ]);
      return results.every((r) => r);
    } catch (_) {
      return false;
    }
  }

  /// Write water intake to Apple Health.
  Future<bool> writeWater({
    required DateTime timestamp,
    required double millilitres,
  }) async {
    if (!_authorized) return false;
    try {
      return await _health.writeHealthData(
        value: millilitres / 1000, // Health package uses litres for water
        type: HealthDataType.WATER,
        startTime: timestamp.subtract(const Duration(minutes: 1)),
        endTime: timestamp,
        unit: HealthDataUnit.LITER,
      );
    } catch (_) {
      return false;
    }
  }

  // ── Read from Apple Health ─────────────────────────────────────────────

  /// Read today's active energy burned (kcal).
  Future<double> readTodayActiveEnergy() async {
    if (!_authorized) return 0;
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: start,
        endTime: now,
      );
      double total = 0;
      for (final p in points) {
        if (p.value is NumericHealthValue) {
          total += (p.value as NumericHealthValue).numericValue;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Read today's step count.
  Future<int> readTodaySteps() async {
    if (!_authorized) return 0;
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final steps = await _health.getTotalStepsInInterval(start, now);
      return steps ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
