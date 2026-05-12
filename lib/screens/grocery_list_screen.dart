import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models/grocery_item.dart';
import '../providers/grocery_provider.dart';
import '../providers/history_provider.dart';
import '../services/database_service.dart';
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

  /// How many times per week the user does groceries (default 2).
  int _groceryFrequency = 2;

  static const _categories = [
    'Fruits', 'Vegetables', 'Protein', 'Dairy',
    'Grains', 'Snacks',     'Drinks',  'Other',
  ];

  @override
  void initState() {
    super.initState();
    // Defer load to post-frame to avoid modifying Riverpod state during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
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
                  // Stay in the dialog — just clear the text field
                  setSheetState(() {});
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
                    // Stay in the dialog — clear selection so user can add another
                    setSheetState(() {
                      _selectedCategory = null;
                    });
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

  /// Normalise a detected food label to a specific grocery product.
  /// E.g. "plain yogurt" → "Yogurt (plain)", "banana" stays "Banana".
  static String _normalizeProduct(String raw) {
    final l = raw.toLowerCase().trim();
    // Specific product mapping for common scan labels
    const _productMap = {
      'greek yogurt': 'Greek yogurt',
      'plain yogurt': 'Plain yogurt',
      'yogurt': 'Yogurt',
      'yoghurt': 'Yogurt',
      'banana': 'Bananas',
      'apple': 'Apples',
      'orange': 'Oranges',
      'tomato': 'Tomatoes',
      'onion': 'Onions',
      'pepper': 'Bell peppers',
      'bell pepper': 'Bell peppers',
      'carrot': 'Carrots',
      'potato': 'Potatoes',
      'sweet potato': 'Sweet potatoes',
      'broccoli': 'Broccoli',
      'spinach': 'Spinach',
      'lettuce': 'Lettuce',
      'cucumber': 'Cucumbers',
      'avocado': 'Avocados',
      'egg': 'Eggs (dozen)',
      'eggs': 'Eggs (dozen)',
      'chicken breast': 'Chicken breast',
      'chicken': 'Chicken',
      'ground beef': 'Ground beef',
      'beef': 'Beef',
      'salmon': 'Salmon fillet',
      'tuna': 'Canned tuna',
      'shrimp': 'Shrimp',
      'rice': 'Rice',
      'brown rice': 'Brown rice',
      'white rice': 'White rice',
      'pasta': 'Pasta',
      'bread': 'Bread',
      'whole wheat bread': 'Whole wheat bread',
      'oats': 'Oats',
      'oatmeal': 'Oats',
      'milk': 'Milk (1L)',
      'whole milk': 'Whole milk (1L)',
      'almond milk': 'Almond milk (1L)',
      'cheese': 'Cheese',
      'butter': 'Butter',
      'olive oil': 'Olive oil',
      'peanut butter': 'Peanut butter',
      'almond': 'Almonds',
      'almonds': 'Almonds',
      'mixed nuts': 'Mixed nuts',
      'blueberry': 'Blueberries',
      'blueberries': 'Blueberries',
      'strawberry': 'Strawberries',
      'strawberries': 'Strawberries',
      'tofu': 'Tofu',
      'lemon': 'Lemons',
      'garlic': 'Garlic',
      'ginger': 'Ginger',
    };
    // Check exact match first
    if (_productMap.containsKey(l)) return _productMap[l]!;
    // Check partial match
    for (final entry in _productMap.entries) {
      if (l.contains(entry.key)) return entry.value;
    }
    // Capitalise as-is
    return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
  }

  /// Compute suggestion items from scan history.
  /// Foods eaten more recently are weighted higher (×2 in last 30 days).
  /// Products are normalised to specific grocery items with accurate quantities.
  List<_SuggestionItem> _buildSuggestions() {
    final history = ref.read(historyProvider);
    if (history.scans.isEmpty) return [];

    final cutoff = DateTime.now().subtract(const Duration(days: 30));

    // Count occurrences of each normalised product
    final freq = <String, int>{};
    final categories = <String, String>{};

    for (final scan in history.scans) {
      final recent = scan.timestamp.isAfter(cutoff);
      for (final food in scan.foods) {
        final label = food.label.trim();
        if (label.isEmpty) continue;
        final product = _normalizeProduct(label);
        final rawLower = label.toLowerCase();
        freq[product] = (freq[product] ?? 0) + (recent ? 2 : 1);
        categories[product] ??= _guessCategory(rawLower);
      }
    }

    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Days between grocery trips
    final daysBetween = (7 / _groceryFrequency).ceil();

    // Already on the list? Skip those.
    final existingNames = ref.read(groceryProvider)
        .map((g) => g.name.toLowerCase())
        .toSet();

    return sorted
        .where((e) => !existingNames.contains(e.key.toLowerCase()))
        .take(15)
        .map((e) {
      // Estimate quantity: frequency per week × days until next trip
      final rawFreq = e.value;
      final timesPerWeek = rawFreq / 4; // rough 30-day avg → weekly
      int qty;

      // For items sold in units (fruits, eggs), calculate pieces needed
      final product = e.key.toLowerCase();
      if (product.contains('egg')) {
        // Eggs come in dozens — estimate packs
        qty = (timesPerWeek * daysBetween / 7 / 6).ceil().clamp(1, 4);
      } else if (['bananas', 'apples', 'oranges', 'avocados', 'lemons',
                   'tomatoes', 'onions', 'bell peppers', 'cucumbers',
                   'carrots', 'potatoes', 'sweet potatoes']
          .any(product.contains)) {
        // Count-based produce: estimate pieces per trip
        qty = (timesPerWeek * daysBetween / 7).ceil().clamp(1, 12);
      } else if (['milk', 'juice', 'almond milk'].any(product.contains)) {
        // Liquid containers
        qty = (timesPerWeek * daysBetween / 7).ceil().clamp(1, 4);
      } else {
        // Default: packs/portions
        qty = (timesPerWeek * daysBetween / 7).ceil().clamp(1, 5);
      }

      return _SuggestionItem(
        name: e.key,
        category: categories[e.key] ?? 'Other',
        suggestedQty: qty,
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

      // Analyze photo with ML Kit to detect food items.
      unawaited(_analyzePhotoForFoods(file));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Analyzing food, text and quantities…'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Runs ML Kit Image Labeling on the photo and adds detected food labels
  /// to the grocery list automatically.
  Future<void> _analyzePhotoForFoods(XFile photo) async {
    try {
      final inputImage = InputImage.fromFilePath(photo.path);

      // 1) Visual labels from the image
      final labeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.5),
      );
      final labels = await labeler.processImage(inputImage);
      await labeler.close();

      // 2) OCR text extraction (package text like "2x milk", "eggs 12")
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      // Filter to food-related labels only.
      const foodKeywords = {
        'food', 'fruit', 'vegetable', 'meat', 'dairy', 'bread', 'egg',
        'cheese', 'milk', 'apple', 'banana', 'tomato', 'lettuce', 'carrot',
        'pepper', 'onion', 'potato', 'chicken', 'beef', 'fish', 'rice',
        'pasta', 'cereal', 'juice', 'yogurt', 'butter', 'cream', 'sauce',
        'berry', 'grape', 'orange', 'lemon', 'avocado', 'broccoli',
        'mushroom', 'cucumber', 'spinach', 'produce', 'grocery',
      };
      final detected = <String>[];
      for (final label in labels) {
        final name = label.label.toLowerCase();
        if (foodKeywords.any((k) => name.contains(k))) {
          detected.add(label.label);
        }
      }

      // 3) Parse OCR lines for explicit quantity and unit patterns.
      final quantityAndUnitHints = _extractQuantityAndUnitHints(
        recognizedText.text,
        allowedKeywords: foodKeywords,
      );

      // 4) Build candidate foods from labels + OCR keyword matches.
      final candidates = <String, _PhotoCandidate>{};
      for (final label in detected) {
        final normalized = _normalizeFoodName(label);
        if (normalized.isEmpty) continue;
        final prev = candidates[normalized];
        final hint = quantityAndUnitHints[normalized.toLowerCase()];
        candidates[normalized] = _PhotoCandidate(
          name: normalized,
          sourceCount: (prev?.sourceCount ?? 0) + 1,
          quantity: hint?['quantity'] ?? (prev?.quantity ?? 1),
          unit: hint?['unit'] ?? prev?.unit,
        );
      }

      for (final line in recognizedText.text.split(RegExp(r'\n+'))) {
        final lower = line.toLowerCase();
        for (final keyword in foodKeywords) {
          if (lower.contains(keyword)) {
            final normalized = _normalizeFoodName(keyword);
            if (normalized.isEmpty) continue;
            final prev = candidates[normalized];
            final hint = quantityAndUnitHints[normalized.toLowerCase()];
            candidates[normalized] = _PhotoCandidate(
              name: normalized,
              sourceCount: (prev?.sourceCount ?? 0) + 1,
              quantity: hint?['quantity'] ?? (prev?.quantity ?? 1),
              unit: hint?['unit'] ?? prev?.unit,
            );
          }
        }
      }

      if (candidates.isEmpty || !mounted) return;

      // 5) Upsert into grocery list with quantity and unit awareness.
      final groceryNotifier = ref.read(groceryProvider.notifier);
      final existingItems = ref.read(groceryProvider).items;
      final existingByName = {
        for (final i in existingItems) i.name.toLowerCase().trim(): i,
      };

      int added = 0;
      int updated = 0;
      for (final entry in candidates.values) {
        final hint = quantityAndUnitHints[entry.name.toLowerCase()];
        final explicitQty = hint?['quantity'] ?? 0;
        final explicitUnit = hint?['unit'];
        final inferredQty = explicitQty > 0 ? explicitQty : entry.sourceCount.clamp(1, 3);

        final key = entry.name.toLowerCase();
        final existing = existingByName[key];
        if (existing != null) {
          // Update with new quantity and preserve or add unit
          final newUnit = explicitUnit ?? existing.unit;
          await DatabaseService.instance.updateGroceryItem(
            existing.copyWith(
              quantity: ((existing.quantity + inferredQty).clamp(1, 99)) as int,
              unit: newUnit,
            ),
          );
          updated++;
        } else {
          await groceryNotifier.addItem(
            entry.name,
            category: _guessCategory(entry.name),
            quantity: inferredQty,
            unit: explicitUnit,
          );
          added++;
        }
      }

      if (!mounted) return;
      if (added > 0 || updated > 0) {
        final sample = candidates.values.take(3).map((c) => c.name).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo scan complete: +$added new, $updated updated. Found: $sample${candidates.length > 3 ? '…' : ''}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // ML Kit not available (e.g. simulator) — silently skip.
    }
  }

  /// Parses quantity and unit from text like "500g chicken", "2L milk", "3 pack".
  /// Returns map with 'quantity' (int) and 'unit' (String? null).
  static Map<String, dynamic> _parseQuantityAndUnit(String text) {
    text = text.trim().toLowerCase();

    // Common unit patterns with their regex
    final unitPatterns = {
      'g': r'(\d+(?:\.\d+)?)\s*g\b',
      'kg': r'(\d+(?:\.\d+)?)\s*kg\b',
      'mg': r'(\d+(?:\.\d+)?)\s*mg\b',
      'ml': r'(\d+(?:\.\d+)?)\s*ml\b',
      'L': r'(\d+(?:\.\d+)?)\s*L\b',
      'l': r'(\d+(?:\.\d+)?)\s*l\b',
      'pack': r'(\d+(?:\.\d+)?)\s*pack',
      'box': r'(\d+(?:\.\d+)?)\s*box',
      'bunch': r'(\d+(?:\.\d+)?)\s*bunch',
      'count': r'(\d+(?:\.\d+)?)\s*ct\b',
    };

    for (final unit in unitPatterns.keys) {
      final regex = RegExp(unitPatterns[unit]!);
      final match = regex.firstMatch(text);
      if (match != null) {
        final qty = double.tryParse(match.group(1) ?? '1') ?? 1.0;
        return {'quantity': qty.toInt(), 'unit': unit};
      }
    }

    // Try simple "Nx" or "x N" pattern
    final simpleMatch = RegExp(r'(\d+)\s*x\s*\w+|\w+\s*x\s*(\d+)').firstMatch(text);
    if (simpleMatch != null) {
      final num = simpleMatch.group(1) ?? simpleMatch.group(2);
      if (num != null) {
        return {'quantity': int.parse(num), 'unit': null};
      }
    }

    return {'quantity': 1, 'unit': null};
  }

  /// Extracts quantity hints AND units from OCR text.
  /// Returns a map of food name -> {quantity (int), unit (String?)}
  Map<String, Map<String, dynamic>> _extractQuantityAndUnitHints(
    String rawText, {
    required Set<String> allowedKeywords,
  }) {
    final hints = <String, Map<String, dynamic>>{};
    final lines = rawText
        .split(RegExp(r'\n+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final countPatternA = RegExp(
      r'(\d{1,2})\s*(x|pcs?|pieces?|packs?|bottles?|cans?|g|kg|ml|L|l)\s+([a-zA-Z][a-zA-Z ]{1,30})',
      caseSensitive: false,
    );
    final countPatternB = RegExp(
      r'([a-zA-Z][a-zA-Z ]{1,30})\s*(x|×)\s*(\d{1,2})',
      caseSensitive: false,
    );
    final countPatternC = RegExp(
      r'(\d{1,2})\s+([a-zA-Z][a-zA-Z ]{1,30})',
      caseSensitive: false,
    );

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (!allowedKeywords.any(lower.contains)) continue;

      final mA = countPatternA.firstMatch(line);
      if (mA != null) {
        final qty = int.tryParse(mA.group(1) ?? '') ?? 0;
        final unitStr = mA.group(2) ?? '';
        final food = _normalizeFoodName(mA.group(3) ?? '');
        if (qty > 0 && food.isNotEmpty) {
          hints[food.toLowerCase()] = {
            'quantity': qty.clamp(1, 99),
            'unit': unitStr,
          };
          continue;
        }
      }

      final mB = countPatternB.firstMatch(line);
      if (mB != null) {
        final qty = int.tryParse(mB.group(3) ?? '') ?? 0;
        final food = _normalizeFoodName(mB.group(1) ?? '');
        if (qty > 0 && food.isNotEmpty) {
          hints[food.toLowerCase()] = {
            'quantity': qty.clamp(1, 99),
            'unit': null,
          };
          continue;
        }
      }

      final mC = countPatternC.firstMatch(line);
      if (mC != null) {
        final qty = int.tryParse(mC.group(1) ?? '') ?? 0;
        final food = _normalizeFoodName(mC.group(2) ?? '');
        if (qty > 0 && food.isNotEmpty) {
          hints[food.toLowerCase()] = {
            'quantity': qty.clamp(1, 99),
            'unit': null,
          };
        }
      }
    }

    return hints;
  }

  String _normalizeFoodName(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    final clean = s.replaceAll(RegExp(r'[^a-z\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    return clean.split(' ').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
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
                        Icon(Icons.auto_awesome, color: ctx.primary600),
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
                                    color: ctx.primary50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: photo != null
                                          ? ctx.primary400
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
                                            Icon(
                                              Icons.add_a_photo_outlined,
                                              color: ctx.primary500,
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

                        // Grocery frequency picker
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppTheme.gray600),
                            const SizedBox(width: 8),
                            const Text('How often do you shop?',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.gray700)),
                            const Spacer(),
                            DropdownButton<int>(
                              value: _groceryFrequency,
                              underline: const SizedBox.shrink(),
                              items: [1, 2, 3, 4, 5, 7].map((n) {
                                return DropdownMenuItem(value: n, child: Text('${n}x/week'));
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _groceryFrequency = v);
                                  setSheetState(() {});
                                }
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
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
                          Row(
                            children: [
                              Icon(Icons.recommend_outlined,
                                  size: 16, color: ctx.primary600),
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
                              activeColor:     ctx.primary600,
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.name,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(
                                  '${item.category} • suggested qty: ${item.suggestedQty}',
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
                        color: context.primary700),
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
  final int suggestedQty;
  const _SuggestionItem({required this.name, required this.category, this.suggestedQty = 1});
}

class _PhotoCandidate {
  final String name;
  final int sourceCount;
  final int quantity;
  final String? unit;
  const _PhotoCandidate({
    required this.name,
    this.sourceCount = 1,
    this.quantity = 1,
    this.unit,
  });
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
          activeColor: context.primary500,
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
        trailing: item.quantity > 0 || item.unit != null
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:        context.primary100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                    item.unit != null
                        ? '${item.quantity} ${item.unit}'
                        : 'x${item.quantity}',
                    style: TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                        color:      context.primary700)),
              )
            : null,
      ),
    );
  }
}
