import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/grocery_item.dart';
import '../providers/grocery_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';

/// Screen for managing a personal grocery shopping list.
///
/// Features:
///   • Manual add via bottom sheet
///   • Smart suggestions derived from meal-scan history (last 30 days)
///   • Up to 3 reference photos (fridge / basket / freezer) — stored locally,
///     never uploaded
class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key});

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  final _nameCtrl = TextEditingController();
  final _picker   = ImagePicker();

  String? _selectedCategory;
  bool    _loaded = false;

  /// Three reference-photo slots for the smart-suggestion sheet.
  final List<XFile?> _photos = [null, null, null];

  static const _categories = [
    'Fruits', 'Vegetables', 'Protein', 'Dairy',
    'Grains', 'Snacks',     'Drinks',  'Other',
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

  // ── Manual add ────────────────────────────────────────────────────────────

  void _addItem() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    ref.read(groceryProvider.notifier).addItem(name, category: _selectedCategory);
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
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Grocery Item',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                  final sel = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: sel,
                    onSelected: (v) =>
                        setSheetState(() => _selectedCategory = v ? cat : null),
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

  // ── Smart suggestions ─────────────────────────────────────────────────────

  /// Compute suggestion items from scan history.
  /// Foods eaten more recently are weighted higher (×2 in last 30 days).
  List<_SuggestionItem> _buildSuggestions() {
    final history = ref.read(historyProvider);
    if (history.scans.isEmpty) return [];

    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final freq   = <String, int>{};

    for (final scan in history.scans) {
      final recent = scan.timestamp.isAfter(cutoff);
      for (final food in scan.foods) {
        final label = food.label.trim().toLowerCase();
        if (label.isEmpty) continue;
        freq[label] = (freq[label] ?? 0) + (recent ? 2 : 1);
      }
    }

    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(12).map((e) {
      return _SuggestionItem(
        name:     _capitalize(e.key),
        category: _guessCategory(e.key),
      );
    }).toList();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _guessCategory(String label) {
    final l = label.toLowerCase();
    const fruits   = ['apple','banana','berry','orange','grape','mango','peach','pear','plum','melon','kiwi','pine','lemon','cherry','avocado'];
    const vegs     = ['broc','carrot','pepper','tomato','onion','lettuce','spinach','cucumber','zucchini','kale','celery','potato','pea','bean','asparagus','corn'];
    const proteins = ['chicken','beef','pork','salmon','tuna','shrimp','egg','tofu','steak','fish','lamb','turkey','tempeh'];
    const dairy    = ['milk','cheese','yogurt','cream','butter','whey'];
    const grains   = ['rice','pasta','bread','oat','cereal','quinoa','wheat','flour','noodle','tortilla'];
    const drinks   = ['juice','coffee','tea','water','soda','smoothie','kombucha'];
    if (fruits.any(l.contains))   return 'Fruits';
    if (vegs.any(l.contains))     return 'Vegetables';
    if (proteins.any(l.contains)) return 'Protein';
    if (dairy.any(l.contains))    return 'Dairy';
    if (grains.any(l.contains))   return 'Grains';
    if (drinks.any(l.contains))   return 'Drinks';
    return 'Other';
  }

  Future<void> _takePhoto(int slot, StateSetter setSheetState) async {
    final file = await _picker.pickImage(
      source:       ImageSource.camera,
      maxWidth:     1200,
      maxHeight:    1200,
      imageQuality: 75,
    );
    if (file != null && mounted) {
      setState(() => _photos[slot] = file);
      setSheetState(() {});
    }
  }

  void _showSmartSuggestSheet() {
    // Ensure history is fresh before computing suggestions.
    ref.read(historyProvider.notifier).load().then((_) {
      if (!mounted) return;
      final suggestions = _buildSuggestions();
      final selected    = <int>{};

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand:            false,
              initialChildSize:  0.75,
              maxChildSize:      0.95,
              minChildSize:      0.40,
              builder: (_, scrollCtrl) => Column(
                children: [
                  // ── Handle bar ──────────────────────────────────────
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // ── Header ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppTheme.green600),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Smart Grocery Suggestions',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              Text('Based on your meal history',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.gray400)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // ── Scrollable body ──────────────────────────────────
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      children: [
                        // Photo slots
                        const Text(
                          'Snap your fridge, pantry or basket (optional)',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.gray700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Photos stay on your device and are never uploaded.',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.gray400),
                        ),
                        const SizedBox(height: 12),

                        // Three photo tiles
                        Row(
                          children: List.generate(3, (i) {
                            final photo  = _photos[i];
                            final labels = ['Fridge', 'Basket', 'Freezer'];
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _takePhoto(i, setSheetState),
                                child: Container(
                                  height: 90,
                                  margin: EdgeInsets.only(
                                      right: i < 2 ? 8.0 : 0.0),
                                  decoration: BoxDecoration(
                                    color: AppTheme.green50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: photo != null
                                          ? AppTheme.green400
                                          : AppTheme.gray200,
                                    ),
                                  ),
                                  child: photo != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(11),
                                          child: Image.file(
                                            File(photo.path),
                                            fit:   BoxFit.cover,
                                            width: double.infinity,
                                          ),
                                        )
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.add_a_photo_outlined,
                                              color: AppTheme.green500,
                                              size: 24,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(labels[i],
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppTheme.gray400)),
                                          ],
                                        ),
                                ),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        // Suggestions list
                        if (suggestions.isEmpty) ...[
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Column(
                                children: [
                                  Icon(Icons.history_outlined,
                                      size: 40, color: AppTheme.gray300),
                                  SizedBox(height: 8),
                                  Text('No meal history yet',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.gray400)),
                                  SizedBox(height: 4),
                                  Text(
                                    'Scan a meal first to get personalised suggestions.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.gray400),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          const Row(
                            children: [
                              Icon(Icons.recommend_outlined,
                                  size: 16, color: AppTheme.green600),
                              SizedBox(width: 6),
                              Text('You often eat these — stock up!',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.gray700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...suggestions.asMap().entries.map((e) {
                            final idx  = e.key;
                            final item = e.value;
                            return CheckboxListTile(
                              value:           selected.contains(idx),
                              dense:           true,
                              activeColor:     AppTheme.green600,
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.name,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(item.category,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.gray400)),
                              onChanged: (v) => setSheetState(() {
                                if (v == true) selected.add(idx);
                                else           selected.remove(idx);
                              }),
                            );
                          }),
                        ],
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),

                  // ── Add button (shown only when items are selected) ──
                  if (selected.isNotEmpty)
                    SafeArea(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon:  const Icon(Icons.add_shopping_cart),
                            label: Text(
                              'Add ${selected.length} '
                              'item${selected.length > 1 ? "s" : ""} to list',
                            ),
                            onPressed: () {
                              for (final idx in selected) {
                                final item = suggestions[idx];
                                ref
                                    .read(groceryProvider.notifier)
                                    .addItem(item.name,
                                        category: item.category);
                              }
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final grocery   = ref.watch(groceryProvider);
    final unchecked = grocery.items.where((i) => !i.checked).toList();
    final checked   = grocery.items.where((i) =>  i.checked).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery List'),
        actions: [
          // Smart suggestion — always visible
          IconButton(
            icon:    const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Smart suggestions from history',
            onPressed: _showSmartSuggestSheet,
          ),
          // Manual add — always visible
          IconButton(
            icon:    const Icon(Icons.add),
            tooltip: 'Add item',
            onPressed: _showAddDialog,
          ),
          if (checked.isNotEmpty)
            IconButton(
              icon:    const Icon(Icons.delete_sweep),
              tooltip: 'Clear purchased items',
              onPressed: () =>
                  ref.read(groceryProvider.notifier).clearChecked(),
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
                      const Text('Your grocery list is empty',
                          style: TextStyle(
                              fontSize: 16, color: AppTheme.gray400)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            icon:     const Icon(Icons.add, size: 18),
                            label:    const Text('Add item'),
                            onPressed: _showAddDialog,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon:     const Icon(Icons.auto_awesome, size: 18),
                            label:    const Text('Suggest'),
                            onPressed: _showSmartSuggestSheet,
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (unchecked.isNotEmpty) ...[
                      _SectionLabel('To Buy (${unchecked.length})',
                          color: AppTheme.green700),
                      ...unchecked.map((item) => _GroceryTile(
                            item:     item,
                            onToggle: () => ref
                                .read(groceryProvider.notifier)
                                .toggleChecked(item),
                            onDelete: () => ref
                                .read(groceryProvider.notifier)
                                .deleteItem(item),
                          )),
                    ],
                    if (checked.isNotEmpty) ...[
                      _SectionLabel('Purchased (${checked.length})',
                          color: AppTheme.gray400),
                      ...checked.map((item) => _GroceryTile(
                            item:     item,
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
    );
  }
}

// ── Internal data model ────────────────────────────────────────────────────────

class _SuggestionItem {
  final String name;
  final String category;
  const _SuggestionItem({required this.name, required this.category});
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});
  final String text;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Grocery tile ───────────────────────────────────────────────────────────────

class _GroceryTile extends StatelessWidget {
  const _GroceryTile({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  final GroceryItem    item;
  final VoidCallback   onToggle;
  final VoidCallback   onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key:       ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 20),
        color:     AppTheme.red500,
        child:     const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: Checkbox(
          value:       item.checked,
          onChanged:   (_) => onToggle(),
          activeColor: AppTheme.green500,
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize:   15,
            fontWeight: FontWeight.w500,
            decoration: item.checked ? TextDecoration.lineThrough : null,
            color:      item.checked ? AppTheme.gray400 : AppTheme.gray900,
          ),
        ),
        subtitle: item.category != null
            ? Text(item.category!,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.gray400))
            : null,
        trailing: item.quantity > 1
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:        AppTheme.green100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('x${item.quantity}',
                    style: const TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                        color:      AppTheme.green700)),
              )
            : null,
      ),
    );
  }
}
