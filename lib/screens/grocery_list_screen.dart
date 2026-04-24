import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grocery_item.dart';
import '../providers/grocery_provider.dart';
import '../theme/app_theme.dart';

/// Screen for managing a personal grocery shopping list.
class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key});

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  final _nameCtrl = TextEditingController();
  String? _selectedCategory;
  bool _loaded = false;

  static const _categories = [
    'Fruits',
    'Vegetables',
    'Protein',
    'Dairy',
    'Grains',
    'Snacks',
    'Drinks',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(groceryProvider.notifier).load();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    ref.read(groceryProvider.notifier).addItem(
          name,
          category: _selectedCategory,
        );
    _nameCtrl.clear();
    _selectedCategory = null;
  }

  void _showAddDialog() {
    _nameCtrl.clear();
    _selectedCategory = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Grocery Item',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Item name',
                  prefixIcon: Icon(Icons.shopping_basket_outlined),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  _addItem();
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((cat) {
                  final selected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (sel) {
                      setSheetState(() {
                        _selectedCategory = sel ? cat : null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _addItem();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grocery = ref.watch(groceryProvider);
    final unchecked = grocery.items.where((i) => !i.checked).toList();
    final checked = grocery.items.where((i) => i.checked).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery List'),
        actions: [
          if (checked.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear purchased items',
              onPressed: () => ref.read(groceryProvider.notifier).clearChecked(),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : grocery.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          size: 64, color: AppTheme.gray300),
                      const SizedBox(height: 16),
                      const Text(
                        'Your grocery list is empty',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.gray400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap + to add items',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.gray400,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    if (unchecked.isNotEmpty) ...[
                      _SectionLabel(
                        'To Buy (${unchecked.length})',
                        color: AppTheme.green700,
                      ),
                      ...unchecked.map((item) => _GroceryTile(
                            item: item,
                            onToggle: () => ref
                                .read(groceryProvider.notifier)
                                .toggleChecked(item),
                            onDelete: () => ref
                                .read(groceryProvider.notifier)
                                .deleteItem(item),
                          )),
                    ],
                    if (checked.isNotEmpty) ...[
                      _SectionLabel(
                        'Purchased (${checked.length})',
                        color: AppTheme.gray400,
                      ),
                      ...checked.map((item) => _GroceryTile(
                            item: item,
                            onToggle: () => ref
                                .read(groceryProvider.notifier)
                                .toggleChecked(item),
                            onDelete: () => ref
                                .read(groceryProvider.notifier)
                                .deleteItem(item),
                          )),
                    ],
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _GroceryTile extends StatelessWidget {
  const _GroceryTile({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });
  final GroceryItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.red500,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: Checkbox(
          value: item.checked,
          onChanged: (_) => onToggle(),
          activeColor: AppTheme.green500,
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            decoration:
                item.checked ? TextDecoration.lineThrough : null,
            color: item.checked ? AppTheme.gray400 : AppTheme.gray900,
          ),
        ),
        subtitle: item.category != null
            ? Text(
                item.category!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.gray400,
                ),
              )
            : null,
        trailing: item.quantity > 1
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.green100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'x${item.quantity}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.green700,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
