import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grocery_item.dart';
import '../services/database_service.dart';

class GroceryState {
  final List<GroceryItem> items;
  final bool loading;

  const GroceryState({this.items = const [], this.loading = false});

  GroceryState copyWith({List<GroceryItem>? items, bool? loading}) {
    return GroceryState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
    );
  }

  int get uncheckedCount => items.where((i) => !i.checked).length;
  int get checkedCount => items.where((i) => i.checked).length;
}

class GroceryNotifier extends StateNotifier<GroceryState> {
  GroceryNotifier() : super(const GroceryState());

  Future<void> load() async {
    state = state.copyWith(loading: true);
    final items = await DatabaseService.instance.getGroceryItems();
    state = GroceryState(items: items);
  }

  Future<void> addItem(String name, {String? category, int quantity = 1}) async {
    final item = GroceryItem(
      name: name,
      category: category,
      quantity: quantity,
      createdAt: DateTime.now(),
    );
    await DatabaseService.instance.insertGroceryItem(item);
    await load();
  }

  Future<void> toggleChecked(GroceryItem item) async {
    final updated = item.copyWith(checked: !item.checked);
    await DatabaseService.instance.updateGroceryItem(updated);
    await load();
  }

  Future<void> updateQuantity(GroceryItem item, int quantity) async {
    final updated = item.copyWith(quantity: quantity);
    await DatabaseService.instance.updateGroceryItem(updated);
    await load();
  }

  Future<void> deleteItem(GroceryItem item) async {
    if (item.id != null) {
      await DatabaseService.instance.deleteGroceryItem(item.id!);
      await load();
    }
  }

  Future<void> clearChecked() async {
    await DatabaseService.instance.clearCheckedGroceryItems();
    await load();
  }
}

final groceryProvider =
    StateNotifierProvider<GroceryNotifier, GroceryState>(
  (ref) => GroceryNotifier(),
);
