import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pantry_item.dart';
import '../services/database_service.dart';

class PantryState {
  const PantryState({this.items = const [], this.loading = false});

  final List<PantryItem> items;
  final bool loading;

  List<PantryItem> get availableItems =>
      items.where((item) => item.available).toList(growable: false);

  Set<String> get availableNames => availableItems
      .map((item) => item.name.toLowerCase().trim())
      .where((name) => name.isNotEmpty)
      .toSet();
}

class PantryNotifier extends StateNotifier<PantryState> {
  PantryNotifier() : super(const PantryState());

  Future<void> load() async {
    state = const PantryState(loading: true);
    final items = await DatabaseService.instance.getPantryItems();
    state = PantryState(items: items);
  }

  Future<void> addItem(String name, {String? category}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    await DatabaseService.instance.insertPantryItem(
      PantryItem(
        name: trimmed,
        category: category,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await load();
  }

  Future<void> toggleAvailable(PantryItem item) async {
    await DatabaseService.instance.updatePantryItem(
      item.copyWith(available: !item.available, updatedAt: DateTime.now()),
    );
    await load();
  }

  Future<void> deleteItem(PantryItem item) async {
    if (item.id == null) return;
    await DatabaseService.instance.deletePantryItem(item.id!);
    await load();
  }

  /// Add [name] to the pantry, merging into an existing item (by normalized
  /// name) by increasing its quantity and marking it available again.
  Future<void> addOrIncrement(
    String name, {
    String? category,
    double quantity = 1,
    String? unit,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final key = PantryItem.normalizeKey(trimmed);
    final now = DateTime.now();
    PantryItem? existing;
    for (final it in state.items) {
      if (PantryItem.normalizeKey(it.name) == key) {
        existing = it;
        break;
      }
    }
    if (existing != null) {
      await DatabaseService.instance.updatePantryItem(
        existing.copyWith(
          quantity: (existing.available ? existing.quantity : 0) + quantity,
          available: true,
          category: existing.category ?? category,
          unit: existing.unit ?? unit,
          updatedAt: now,
        ),
      );
    } else {
      await DatabaseService.instance.insertPantryItem(
        PantryItem(
          name: trimmed,
          category: category,
          quantity: quantity,
          unit: unit,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await load();
  }

  /// Consume one matching available item (by normalized name) when the user
  /// logs/scans food. Reduces quantity; marks the item unavailable when it
  /// runs out (kept as a row so it can be re-stocked). Returns true if a
  /// matching item was found and decremented.
  Future<bool> consume(String label, {double amount = 1}) async {
    final key = PantryItem.normalizeKey(label);
    PantryItem? match;
    for (final it in state.items) {
      if (it.available && PantryItem.normalizeKey(it.name) == key) {
        match = it;
        break;
      }
    }
    if (match == null) return false;
    final remaining = match.quantity - amount;
    await DatabaseService.instance.updatePantryItem(
      match.copyWith(
        quantity: remaining > 0 ? remaining : 0,
        available: remaining > 0,
        updatedAt: DateTime.now(),
      ),
    );
    await load();
    return true;
  }

  /// Set an exact quantity; quantity <= 0 marks the item unavailable.
  Future<void> setQuantity(PantryItem item, double quantity) async {
    final q = quantity < 0 ? 0.0 : quantity;
    await DatabaseService.instance.updatePantryItem(
      item.copyWith(
        quantity: q,
        available: q > 0,
        updatedAt: DateTime.now(),
      ),
    );
    await load();
  }

  /// Remove every pantry item.
  Future<void> clearAll() async {
    for (final it in state.items) {
      if (it.id != null) {
        await DatabaseService.instance.deletePantryItem(it.id!);
      }
    }
    await load();
  }
}

final pantryProvider = StateNotifierProvider<PantryNotifier, PantryState>(
  (ref) => PantryNotifier(),
);

final pantryModeProvider = StateProvider<bool>((ref) => false);

/// Master on/off switch for the smart grocery + pantry system (persisted).
/// When off, grocery items no longer feed the pantry and logging food no
/// longer decrements it. Defaults to on.
class SmartGroceryNotifier extends StateNotifier<bool> {
  SmartGroceryNotifier() : super(true) {
    _load();
  }

  static const _key = 'smart_grocery_enabled';

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    state = sp.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_key, value);
    state = value;
  }
}

final smartGroceryEnabledProvider =
    StateNotifierProvider<SmartGroceryNotifier, bool>(
  (ref) => SmartGroceryNotifier(),
);
