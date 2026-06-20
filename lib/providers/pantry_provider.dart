import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final pantryProvider = StateNotifierProvider<PantryNotifier, PantryState>(
  (ref) => PantryNotifier(),
);

final pantryModeProvider = StateProvider<bool>((ref) => false);
