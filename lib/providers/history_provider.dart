import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';
import 'pantry_provider.dart';

/// Holds the list of past scan results loaded from SQLite.
class HistoryState {
  final bool loading;
  final List<ScanResult> scans;

  const HistoryState({this.loading = false, this.scans = const []});

  HistoryState copyWith({bool? loading, List<ScanResult>? scans}) {
    return HistoryState(
      loading: loading ?? this.loading,
      scans: scans ?? this.scans,
    );
  }
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier(this._ref) : super(const HistoryState());

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(loading: true);
    await DatabaseService.instance.purgeExpiredScanMedia();
    final scans = await DatabaseService.instance.getAllScanResults();
    state = HistoryState(scans: scans);
  }

  Future<void> addScan(ScanResult result) async {
    await DatabaseService.instance.insertScanResult(result);
    await load(); // refresh
    await _consumeFromPantry(result);
  }

  /// When the smart grocery/pantry system is on, logging real food marks any
  /// matching pantry items as used up (best-effort match by name). Hydration
  /// (water) entries never touch the pantry.
  Future<void> _consumeFromPantry(ScanResult result) async {
    if (result.depthMode == 'hydration') return;
    if (result.foods.isEmpty) return;
    if (!_ref.read(smartGroceryEnabledProvider)) return;
    final notifier = _ref.read(pantryProvider.notifier);
    if (_ref.read(pantryProvider).items.isEmpty) {
      await notifier.load();
    }
    for (final food in result.foods) {
      await notifier.consume(food.label);
    }
  }

  Future<void> deleteScan(int scanId) async {
    await DatabaseService.instance.deleteScanResult(scanId);
    await load();
  }

  /// Delete several scans at once, then refresh.
  Future<void> deleteScans(List<int> scanIds) async {
    if (scanIds.isEmpty) return;
    await DatabaseService.instance.deleteScanResults(scanIds);
    await load();
  }

  /// Delete a single detected food from a scan and refresh.
  Future<void> deleteDetectedFood(int detectedFoodId) async {
    await DatabaseService.instance.deleteDetectedFood(detectedFoodId);
    await load();
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, HistoryState>(
  (ref) => HistoryNotifier(ref),
);
