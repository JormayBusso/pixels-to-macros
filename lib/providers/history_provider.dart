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
      // Subtract the grams actually eaten so a partly-used stock stays correct
      // (e.g. 200 g tomatoes − a 50 g portion = 150 g left). Weight ≈ scanned
      // volume × a typical food density (0.9 g/cm³ fallback, matching the rest
      // of the app); the pantry decrement is unit-aware so piece-counted items
      // still drop by one.
      final grams = food.volumeCm3 > 0 ? food.volumeCm3 * 0.9 : null;
      await notifier.consume(food.label, grams: grams);
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
