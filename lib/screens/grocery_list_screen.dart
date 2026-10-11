import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_localizations.dart';
import '../models/grocery_item.dart';
import '../models/pantry_item.dart';
import '../providers/grocery_provider.dart';
import '../providers/history_provider.dart';
import '../providers/pantry_provider.dart';
import '../services/barcode_lookup_service.dart';
import '../services/pantry_photo_service.dart';
import '../services/ingredient_localizer.dart';
import '../theme/app_theme.dart';

/// Screen for managing a personal grocery shopping list.
///
/// Features:
///   • Manual add via bottom sheet
///   • Smart suggestions derived from meal-scan history (last 30 days)
///   • Up to 3 reference photos (fridge / basket / freezer) — stored locally,
///     never uploaded
class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key, this.photoService});

  final PantryPhotoService? photoService;

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  final _nameCtrl = TextEditingController();
  final _picker = ImagePicker();

  String? _selectedCategory;
  bool _loaded = false;
  bool _atHome = false;
  bool _photoBusy = false;
  late final _photoService =
      widget.photoService ?? PantryPhotoService(aliases: _pantryAliases);

  static final _pantryAliases = <String, String>{
    for (final entry in _productMap.entries)
      entry.key: entry.value.replaceAll(RegExp(r' \([^)]*\)'), ''),
    'bananas': 'Bananas',
    'apples': 'Apples',
    'banaan': 'Bananas',
    'bananen': 'Bananas',
    'banane': 'Bananas',
    'banan': 'Bananas',
    'banany': 'Bananas',
    'plátano': 'Bananas',
    'plátanos': 'Bananas',
    'appel': 'Apples',
    'appels': 'Apples',
    'apfel': 'Apples',
    'äpfel': 'Apples',
    'jabłko': 'Apples',
    'jabłka': 'Apples',
    'manzana': 'Apples',
    'manzanas': 'Apples',
  };

  /// Selected food-group filter for the grocery list (null = show all groups).
  String? _selectedFoodGroup;

  /// Three reference-photo slots for the smart-suggestion sheet.
  final List<XFile?> _photos = [null, null, null];

  /// How many times per week the user does groceries (default 2).
  int _groceryFrequency = 2;

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
    // Defer load to post-frame to avoid modifying Riverpod state during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    await ref.read(groceryProvider.notifier).load();
    await ref.read(pantryProvider.notifier).load();
    if (mounted) setState(() => _loaded = true);
  }

  /// Left action: the user took/bought this item — move it into the pantry
  /// (what they have at home) and off the buy list. Revertible via the snackbar.
  Future<void> _markBought(GroceryItem item) async {
    final l10n = AppLocalizations.of(context);
    final qty = item.quantity <= 0 ? 1.0 : item.quantity.toDouble();
    await ref.read(pantryProvider.notifier).addOrIncrement(
          item.name,
          category: item.category,
          quantity: qty,
          unit: item.unit,
        );
    await ref.read(groceryProvider.notifier).deleteItem(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.addedToPantrySnack(item.name)),
        action: SnackBarAction(
          label: l10n.undoAction,
          onPressed: () async {
            await ref
                .read(pantryProvider.notifier)
                .consume(item.name, amount: qty);
            await ref.read(groceryProvider.notifier).addItem(
                  item.name,
                  category: item.category,
                  quantity: item.quantity,
                  unit: item.unit,
                );
          },
        ),
      ),
    );
  }

  /// Right action: don't buy this anymore — remove it from the list.
  /// Revertible via the snackbar.
  Future<void> _dontBuy(GroceryItem item) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(groceryProvider.notifier).deleteItem(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.removedFromListSnack(item.name)),
        action: SnackBarAction(
          label: l10n.undoAction,
          onPressed: () => ref.read(groceryProvider.notifier).addItem(
                item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
              ),
        ),
      ),
    );
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
    if (_atHome && ref.read(smartGroceryEnabledProvider)) {
      unawaited(ref
          .read(pantryProvider.notifier)
          .addOrIncrement(name, category: _selectedCategory));
    } else {
      unawaited(ref
          .read(groceryProvider.notifier)
          .addItem(name, category: _selectedCategory));
    }
    _nameCtrl.clear();
    _selectedCategory = null;
  }

  void _showAddDialog() {
    final l10n = AppLocalizations.of(context);
    _nameCtrl.clear();
    _selectedCategory = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appSurfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_atHome ? l10n.pantryAddItem : l10n.addGroceryItem,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.itemName,
                  prefixIcon: const Icon(Icons.shopping_basket_outlined),
                  border: const OutlineInputBorder(),
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
                    label: Text(l10n.groceryCategoryLabel(cat)),
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
                  child: Text(l10n.add),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editPantryItem(PantryItem item) async {
    final l10n = AppLocalizations.of(context);
    final quantityCtrl = TextEditingController(text: item.quantity.toString());
    ModalRoute<void>? quantityRoute;
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.appSurfaceColor,
      builder: (ctx) {
        quantityRoute ??= ModalRoute.of<void>(ctx);
        return StatefulBuilder(
            builder: (ctx, setSheet) => Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(IngredientLocalizer.localize(item.name,
                        targetLang: l10n.locale.languageCode,
                        sourceLang: 'en')),
                    TextField(
                      controller: quantityCtrl,
                      enabled: !saving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: l10n.quantityLabel, suffixText: item.unit),
                    ),
                    Row(children: [
                      TextButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: Text(l10n.cancel)),
                      const Spacer(),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final quantity = double.tryParse(
                                    quantityCtrl.text.replaceAll(',', '.'));
                                if (quantity == null ||
                                    !quantity.isFinite ||
                                    quantity < 0) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text(l10n.pantryInvalidItems)));
                                  return;
                                }
                                setSheet(() => saving = true);
                                try {
                                  await ref
                                      .read(pantryProvider.notifier)
                                      .setQuantity(item, quantity);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setSheet(() => saving = false);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                            content:
                                                Text(l10n.pantrySaveFailed)));
                                  }
                                }
                              },
                        child: Text(l10n.save),
                      ),
                    ]),
                  ]),
                ));
      },
    );
    await quantityRoute?.completed;
    quantityCtrl.dispose();
  }

  void _editItem(GroceryItem item) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: item.name);
    final qtyCtrl = TextEditingController(
        text: item.quantity > 0 ? item.quantity.toString() : '');
    final unitCtrl = TextEditingController(text: item.unit ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appSurfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.editGroceryItem,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.itemName,
                prefixIcon: const Icon(Icons.shopping_basket_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.quantityLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: unitCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.unitOptional,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final newName = nameCtrl.text.trim();
                  if (newName.isEmpty) return;
                  final qty =
                      int.tryParse(qtyCtrl.text.trim()) ?? item.quantity;
                  ref.read(groceryProvider.notifier).updateItem(
                        item,
                        name: newName,
                        quantity: qty,
                        unit: unitCtrl.text.trim(),
                      );
                  Navigator.of(ctx).pop();
                },
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Smart suggestions ─────────────────────────────────────────────────────

  /// Scan a packaged product's barcode and add the exact product (by name from
  /// Open Food Facts) to the grocery list — the accurate path for packaged
  /// foods. When the smart pantry is on, the product is also stocked at home.
  Future<void> _scanBarcode() async {
    final l10n = AppLocalizations.of(context);
    BarcodeFood? food;
    try {
      food = await BarcodeLookupService.instance.scanAndLookup(
        themeColor: context.isPremiumTheme
            ? context.visualTheme.primaryAccent
            : context.primary500,
        l10n: l10n,
      );
    } catch (e) {
      debugPrint('GroceryList: barcode scan failed: $e');
    }
    if (!mounted) return;
    if (food == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.barcodeProductNotFound)),
      );
      return;
    }
    final name = food.name.trim();
    if (name.isEmpty) return;
    if (_atHome && ref.read(smartGroceryEnabledProvider)) {
      await ref.read(pantryProvider.notifier).addOrIncrement(name);
    } else {
      await ref.read(groceryProvider.notifier).addItem(name);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.groceryBarcodeAddedSnack(name)),
        backgroundColor: AppTheme.green600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Take a photo of the fridge / fruit bowl / products, recognise the items,
  /// then show an EDITABLE list the user confirms before anything is added.
  Future<void> _scanWhatIHave() async {
    if (_photoBusy) return;
    final l10n = AppLocalizations.of(context);
    final photos = <XFile>[];
    var busy = false;
    setState(() => _photoBusy = true);
    final candidates = await showModalBottomSheet<List<PantryPhotoCandidate>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.appSurfaceColor,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> pick(ImageSource source) async {
          setSheet(() => busy = true);
          try {
            final selected = await _photoService.pick(source);
            if (!ctx.mounted) return;
            setSheet(() {
              final paths = photos.map((p) => p.path).toSet();
              photos.addAll(selected.where((p) => paths.add(p.path)));
            });
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(l10n.couldNotAnalyzePhoto)));
            }
          } finally {
            if (ctx.mounted) setSheet(() => busy = false);
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l10n.groceryScanWhatYouHave,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: ctx.appTextColor)),
              const SizedBox(height: 8),
              Text(l10n.pantryPhotoReviewHint,
                  style: TextStyle(color: ctx.appMutedTextColor)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: photos.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: Image.file(File(photos[i].path),
                        width: 48, height: 48, fit: BoxFit.cover),
                    title: Text(l10n.pantryPhotoNumber(i + 1)),
                    trailing: IconButton(
                      tooltip: l10n.removePhoto,
                      icon: const Icon(Icons.close),
                      onPressed: busy
                          ? null
                          : () => setSheet(() => photos.removeAt(i)),
                    ),
                  ),
                ),
              ),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: busy ? null : () => pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(l10n.takePhoto)),
                TextButton.icon(
                    onPressed: busy ? null : () => pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.chooseFromGallery)),
              ]),
              if (busy) const LinearProgressIndicator(),
              Row(children: [
                TextButton(
                    onPressed: busy ? null : () => Navigator.pop(ctx),
                    child: Text(l10n.cancel)),
                const Spacer(),
                FilledButton(
                  onPressed: busy || photos.isEmpty
                      ? null
                      : () async {
                          setSheet(() => busy = true);
                          try {
                            final results =
                                await _photoService.analyzeAll(photos);
                            if (ctx.mounted) Navigator.pop(ctx, results);
                          } catch (e) {
                            debugPrint(
                                'GroceryList: photo analysis failed: $e');
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content: Text(l10n.couldNotAnalyzePhoto)));
                            }
                          } finally {
                            if (ctx.mounted) setSheet(() => busy = false);
                          }
                        },
                  child: Text(l10n.pantryReviewPhotos),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
    if (!mounted) return;
    setState(() => _photoBusy = false);
    if (candidates == null) return;
    await _showRecognizedItemsSheet(candidates.map((c) => c.name).toList(),
        toPantry: true, candidates: candidates);
  }

  /// Take a photo of a shopping receipt, OCR its line items, and stock the
  /// recognised foods into the home-ingredients database (pantry). Prices,
  /// totals and store lines are ignored; the user reviews/edits before adding.
  Future<void> _scanReceipt() async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).couldNotReadReceipt)));
      }
      return;
    }
    if (file == null || !mounted) return;
    final l10n = AppLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.readingReceipt),
        duration: const Duration(seconds: 2),
      ),
    );

    final recognized = <String>{};
    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final recognizedText = await textRecognizer.processImage(inputImage);
        for (final product in _parseReceiptProducts(recognizedText.text)) {
          recognized.add(product);
        }
      } finally {
        await textRecognizer.close();
      }
    } catch (e) {
      debugPrint('GroceryList: receipt scan failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.couldNotReadReceipt)),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    await _showRecognizedItemsSheet(recognized.toList(),
        toPantry: true, observations: false);
  }

  /// Parse receipt OCR text into clean food product names. Receipt lines mix
  /// product names with prices, quantities and store metadata; this keeps only
  /// the alphabetic product portion of a line and drops totals/tax/payment
  /// lines that never name a food.
  List<String> _parseReceiptProducts(String rawText) {
    final products = <String>[];
    final seen = <String>{};
    // Non-food receipt keywords (multilingual) to skip whole lines.
    const skipWords = {
      'total',
      'totaal',
      'gesamt',
      'suma',
      'subtotal',
      'tax',
      'btw',
      'vat',
      'iva',
      'mwst',
      'change',
      'cash',
      'card',
      'visa',
      'debit',
      'credit',
      'balance',
      'receipt',
      'invoice',
      'bon',
      'ticket',
      'store',
      'tel',
      'phone',
      'www',
      'http',
      'discount',
      'coupon',
      'loyalty',
      'points',
      'thank',
      'welcome',
      'cashier',
      'terminal',
      'auth',
      'ref',
      'date',
      'time',
      'qty',
      'amount',
      'price',
      'ust',
      'summe',
      'zahlung',
      'rabat',
    };
    for (final line in rawText.split(RegExp(r'\n+'))) {
      final lower = line.toLowerCase();
      if (skipWords.any(lower.contains)) continue;
      // Strip a trailing price / weight (e.g. "  2.99", "1,49 €", "0.350 kg").
      var cleaned = line
          .replaceAll(RegExp(r'[€$£]'), ' ')
          .replaceAll(RegExp(r'\b\d+[.,]\d{2,3}\b'), ' ') // prices / kg weights
          .replaceAll(
              RegExp(r'\bx?\s*\d+\s*(pcs?|stk|szt|x)\b', caseSensitive: false),
              ' ')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÿ ]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.length < 3) continue;
      // Prefer a known-product mapping; otherwise keep a plausible food line.
      final mapped = _matchKnownProduct(cleaned) ??
          (cleaned.split(' ').length <= 4 ? _normalizeFoodName(cleaned) : null);
      if (mapped == null || mapped.isEmpty) continue;
      final key = mapped.toLowerCase();
      if (seen.add(key)) products.add(mapped);
    }
    return products;
  }

  /// Show the recognised products in an editable sheet: the user can remove
  /// wrong items, type extra ones, then tap Add to put them on the grocery
  /// list. Nothing is added until the user confirms.
  ///
  /// When [toPantry] is true (fridge / basket / receipt scans) the confirmed
  /// items stock the home-ingredients database (pantry) instead of the buy
  /// list — scanning what you already have should fill your home stock.
  Future<void> _showRecognizedItemsSheet(
    List<String> recognized, {
    bool toPantry = false,
    List<PantryPhotoCandidate>? candidates,
    bool observations = true,
  }) async {
    final l10n = AppLocalizations.of(context);
    final items = mergePantryCandidates(
        candidates ?? recognized.map((name) => PantryPhotoCandidate(name)));
    if (toPantry && observations) {
      final stock = ref.read(pantryProvider).availableItems;
      for (var i = 0; i < items.length; i++) {
        if (items[i].quantity != 1 || items[i].unit != null) continue;
        for (final existing in stock) {
          if (PantryItem.normalizeKey(existing.name) ==
              PantryItem.normalizeKey(items[i].name)) {
            items[i] = PantryPhotoCandidate(items[i].name,
                quantity: existing.quantity, unit: existing.unit);
            break;
          }
        }
      }
    }
    var saving = false;
    final addCtrl = TextEditingController();
    ModalRoute<void>? reviewRoute;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.appSurfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          reviewRoute ??= ModalRoute.of<void>(ctx);
          void addTyped() {
            final t = addCtrl.text.trim();
            if (t.isEmpty) return;
            setSheet(() {
              if (!items.any((item) =>
                  PantryItem.normalizeKey(item.name) ==
                  PantryItem.normalizeKey(t))) {
                items.add(PantryPhotoCandidate(t));
              }
              addCtrl.clear();
            });
          }

          return PopScope<void>(
            canPop: !saving,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.groceryRecognizedTitle,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      toPantry
                          ? l10n.groceryRecognizedHomeSubtitle
                          : l10n.groceryRecognizedSubtitle,
                      style: TextStyle(
                          fontSize: 12.5, color: context.appMutedTextColor)),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(l10n.groceryNothingRecognized,
                          style: TextStyle(color: context.appMutedTextColor)),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (_, i) => ListTile(
                          key: ObjectKey(items[i]),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.check_circle_outline,
                              color: context.primary600),
                          title: TextFormField(
                            initialValue: IngredientLocalizer.localize(
                                items[i].name,
                                targetLang: l10n.locale.languageCode,
                                sourceLang: 'en'),
                            enabled: !saving,
                            decoration:
                                InputDecoration(labelText: l10n.itemName),
                            onChanged: (value) {
                              items[i] = PantryPhotoCandidate(value,
                                  quantity: items[i].quantity,
                                  unit: items[i].unit);
                            },
                          ),
                          subtitle: Row(children: [
                            Expanded(
                                child: TextFormField(
                              initialValue: items[i].quantity.toString(),
                              enabled: !saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: l10n.quantityLabel),
                              onChanged: (value) {
                                items[i] = PantryPhotoCandidate(items[i].name,
                                    quantity: double.tryParse(
                                            value.replaceAll(',', '.')) ??
                                        0,
                                    unit: items[i].unit);
                              },
                            )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: TextFormField(
                              initialValue: items[i].unit ?? '',
                              enabled: !saving,
                              decoration:
                                  InputDecoration(labelText: l10n.unitOptional),
                              onChanged: (value) {
                                items[i] = PantryPhotoCandidate(items[i].name,
                                    quantity: items[i].quantity,
                                    unit: value.trim().isEmpty
                                        ? null
                                        : value.trim());
                              },
                            )),
                          ]),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: saving
                                ? null
                                : () => setSheet(() => items.removeAt(i)),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: addCtrl,
                          enabled: !saving,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.itemName,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => addTyped(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: saving ? null : addTyped,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      child: Text(l10n.cancel)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(toPantry
                          ? Icons.kitchen_outlined
                          : Icons.playlist_add),
                      label: Text(toPantry
                          ? l10n.groceryAddNToHome(items.length)
                          : l10n.groceryAddNItems(items.length)),
                      onPressed: items.isEmpty || saving
                          ? null
                          : () async {
                              if (saving) return;
                              if (items.any((item) =>
                                  item.name.trim().isEmpty ||
                                  !item.quantity.isFinite ||
                                  item.quantity <= 0)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text(l10n.pantryInvalidItems)));
                                return;
                              }
                              setSheet(() => saving = true);
                              try {
                                final reviewed = mergePantryCandidates(items);
                                if (toPantry) {
                                  final now = DateTime.now();
                                  await ref
                                      .read(pantryProvider.notifier)
                                      .saveReviewedItems(
                                          reviewed
                                              .map((item) => PantryItem(
                                                  name: item.name.trim(),
                                                  category:
                                                      _guessCategory(item.name),
                                                  quantity: item.quantity,
                                                  unit: item.unit,
                                                  createdAt: now,
                                                  updatedAt: now))
                                              .toList(),
                                          observations: observations);
                                } else {
                                  for (final item in reviewed) {
                                    await ref
                                        .read(groceryProvider.notifier)
                                        .addItem(
                                          item.name,
                                          quantity: item.quantity.ceil(),
                                          unit: item.unit,
                                          category: _guessCategory(
                                              item.name.toLowerCase()),
                                        );
                                  }
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(toPantry
                                          ? l10n.addedNToHomeStock(items.length)
                                          : l10n
                                              .foundIngredients(items.length)),
                                      backgroundColor: AppTheme.green600,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setSheet(() => saving = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                          content: Text(e is ArgumentError
                                              ? l10n.pantryUnitConflict
                                              : l10n.pantrySaveFailed)));
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await reviewRoute?.completed;
    addCtrl.dispose();
  }

  /// Known scan-label → nice product-name map, shared by the smart suggestions
  /// and the fridge-photo recogniser.
  static const Map<String, String> _productMap = {
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

  /// Normalise a detected food label to a specific grocery product.
  /// E.g. "plain yogurt" → "Yogurt (plain)", "banana" stays "Banana".
  static String _normalizeProduct(String raw) {
    final matched = PantryPhotoService.matchProducts(raw, _productMap);
    if (matched.length == 1) return matched.single;
    return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
  }

  /// Like [_normalizeProduct] but returns null when the term is NOT a
  /// recognised food, so generic labels ("Food", brand text) are ignored by
  /// the fridge-photo recogniser.
  static String? _matchKnownProduct(String raw) {
    final matches = PantryPhotoService.matchProducts(raw, _pantryAliases);
    return matches.isEmpty ? null : matches.first;
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
    final existingNames = ref
        .read(groceryProvider)
        .items
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
      } else if ([
        'bananas',
        'apples',
        'oranges',
        'avocados',
        'lemons',
        'tomatoes',
        'onions',
        'bell peppers',
        'cucumbers',
        'carrots',
        'potatoes',
        'sweet potatoes'
      ].any(product.contains)) {
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

  String _guessCategory(String label) {
    final l = label.toLowerCase();
    const fruits = [
      'apple',
      'banana',
      'berry',
      'orange',
      'grape',
      'mango',
      'peach',
      'pear',
      'plum',
      'melon',
      'kiwi',
      'pine',
      'lemon',
      'cherry',
      'avocado'
    ];
    const vegs = [
      'broc',
      'carrot',
      'pepper',
      'tomato',
      'onion',
      'lettuce',
      'spinach',
      'cucumber',
      'zucchini',
      'kale',
      'celery',
      'potato',
      'pea',
      'bean',
      'asparagus',
      'corn'
    ];
    const proteins = [
      'chicken',
      'beef',
      'pork',
      'salmon',
      'tuna',
      'shrimp',
      'egg',
      'tofu',
      'steak',
      'fish',
      'lamb',
      'turkey',
      'tempeh'
    ];
    const dairy = ['milk', 'cheese', 'yogurt', 'cream', 'butter', 'whey'];
    const grains = [
      'rice',
      'pasta',
      'bread',
      'oat',
      'cereal',
      'quinoa',
      'wheat',
      'flour',
      'noodle',
      'tortilla'
    ];
    const drinks = [
      'juice',
      'coffee',
      'tea',
      'water',
      'soda',
      'smoothie',
      'kombucha'
    ];
    if (fruits.any(l.contains)) return 'Fruits';
    if (vegs.any(l.contains)) return 'Vegetables';
    if (proteins.any(l.contains)) return 'Protein';
    if (dairy.any(l.contains)) return 'Dairy';
    if (grains.any(l.contains)) return 'Grains';
    if (drinks.any(l.contains)) return 'Drinks';
    return 'Other';
  }

  Future<void> _takePhoto(
      int slot, StateSetter setSheetState, BuildContext sheetContext) async {
    if (_photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      final files = await _photoService.pick(ImageSource.camera);
      if (files.isEmpty || !mounted || !sheetContext.mounted) return;
      setState(() => _photos[slot] = files.single);
      setSheetState(() {});
      await _analyzePhotoForFoods(files.single, sheetContext);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).couldNotAnalyzePhoto)));
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  /// Review reference-photo foods before stocking the pantry.
  Future<void> _analyzePhotoForFoods(
      XFile photo, BuildContext sheetContext) async {
    try {
      final candidates = await _photoService.analyzeAll([photo]);
      if (!mounted || !sheetContext.mounted) return;
      await _showRecognizedItemsSheet(
          candidates.map((item) => item.name).toList(),
          toPantry: true,
          candidates: candidates);
    } catch (e) {
      debugPrint('GroceryList: photo food analysis failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).couldNotAnalyzePhoto)));
      }
    }
  }

  String _normalizeFoodName(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    final clean = s
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
      final l10n = AppLocalizations.of(context);
      final suggestions = _buildSuggestions();
      final selected = <int>{};

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.appSurfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.95,
              minChildSize: 0.40,
              builder: (_, scrollCtrl) => Column(
                children: [
                  // ── Handle bar ──────────────────────────────────────
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.smartGrocerySuggestions,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              Text(l10n.basedOnMealHistory,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.appMutedTextColor)),
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
                        Text(
                          l10n.grocerySnapFridge,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.appTextColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.groceryPhotosLocal,
                          style: TextStyle(
                              fontSize: 11, color: context.appMutedTextColor),
                        ),
                        const SizedBox(height: 12),

                        // Three photo tiles
                        Row(
                          children: List.generate(3, (i) {
                            final photo = _photos[i];
                            final labels = [
                              l10n.pantryLocationLabel('fridge'),
                              l10n.pantryLocationLabel('pantry'),
                              l10n.pantryLocationLabel('freezer'),
                            ];
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _takePhoto(i, setSheetState, ctx),
                                child: Container(
                                  height: 90,
                                  margin:
                                      EdgeInsets.only(right: i < 2 ? 8.0 : 0.0),
                                  decoration: BoxDecoration(
                                    color: ctx.primary50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: photo != null
                                          ? ctx.primary400
                                          : context.appBorderColor,
                                    ),
                                  ),
                                  child: photo != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(11),
                                          child: Image.file(
                                            File(photo.path),
                                            fit: BoxFit.cover,
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
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: context
                                                        .appMutedTextColor)),
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
                            Icon(Icons.calendar_today,
                                size: 16, color: context.appMutedTextColor),
                            const SizedBox(width: 8),
                            Text(l10n.howOftenShop,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: context.appTextColor)),
                            const Spacer(),
                            DropdownButton<int>(
                              value: _groceryFrequency,
                              dropdownColor: ctx.appSurfaceColor,
                              style: TextStyle(color: ctx.appTextColor),
                              iconEnabledColor: ctx.appTextColor,
                              underline: const SizedBox.shrink(),
                              items: [1, 2, 3, 4, 5, 7].map((n) {
                                return DropdownMenuItem(
                                    value: n,
                                    child: Text(l10n.timesPerWeek(n)));
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
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Column(
                                children: [
                                  const Icon(Icons.history_outlined,
                                      size: 40, color: AppTheme.gray300),
                                  const SizedBox(height: 8),
                                  Text(l10n.noMealHistoryYet,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: context.appMutedTextColor)),
                                  SizedBox(height: 4),
                                  Text(
                                    l10n.groceryScanMealFirst,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.appMutedTextColor),
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
                              Text(l10n.stockUpHint,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: context.appTextColor)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...suggestions.asMap().entries.map((e) {
                            final idx = e.key;
                            final item = e.value;
                            return CheckboxListTile(
                              value: selected.contains(idx),
                              dense: true,
                              activeColor: ctx.primary600,
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.name,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(
                                  l10n.suggestedQtyLabel(
                                      l10n.groceryCategoryLabel(item.category),
                                      item.suggestedQty),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: context.appMutedTextColor)),
                              onChanged: (v) => setSheetState(() {
                                if (v == true)
                                  selected.add(idx);
                                else
                                  selected.remove(idx);
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
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add_shopping_cart),
                            label: Text(
                              l10n.groceryAddItemsToList(selected.length),
                            ),
                            onPressed: () {
                              for (final idx in selected) {
                                final item = suggestions[idx];
                                ref.read(groceryProvider.notifier).addItem(
                                    item.name,
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

  /// Best food group for a grocery item: its explicit category when set,
  /// otherwise inferred from the product name so the list groups sensibly even
  /// for items added without a category.
  static const _foodGroupKeywords = <String, List<String>>{
    'Fruits': [
      'apple',
      'banana',
      'orange',
      'berr',
      'grape',
      'melon',
      'mango',
      'pear',
      'peach',
      'plum',
      'kiwi',
      'pineapple',
      'lemon',
      'lime',
      'cherry',
      'apricot',
      'fig',
      'date',
      'fruit',
      'avocado'
    ],
    'Vegetables': [
      'tomato',
      'cucumber',
      'lettuce',
      'spinach',
      'carrot',
      'potato',
      'onion',
      'pepper',
      'broccoli',
      'pea',
      'bean',
      'zucchini',
      'courgette',
      'kale',
      'cabbage',
      'garlic',
      'mushroom',
      'corn',
      'salad',
      'celery',
      'leek',
      'beet',
      'radish',
      'pumpkin',
      'squash',
      'asparagus',
      'cauliflower',
      'eggplant',
      'aubergine',
      'veg'
    ],
    'Protein': [
      'chicken',
      'beef',
      'pork',
      'meat',
      'fish',
      'salmon',
      'tuna',
      'egg',
      'tofu',
      'shrimp',
      'prawn',
      'turkey',
      'ham',
      'bacon',
      'sausage',
      'steak',
      'lentil',
      'chickpea',
      'mince'
    ],
    'Dairy': [
      'milk',
      'cheese',
      'yogurt',
      'yoghurt',
      'butter',
      'cream',
      'kefir',
      'quark'
    ],
    'Grains': [
      'bread',
      'rice',
      'pasta',
      'oat',
      'cereal',
      'flour',
      'quinoa',
      'tortilla',
      'bagel',
      'cracker',
      'noodle',
      'couscous',
      'barley',
      'wrap'
    ],
    'Drinks': [
      'water',
      'juice',
      'coffee',
      'tea',
      'soda',
      'cola',
      'beer',
      'wine',
      'drink',
      'smoothie',
      'lemonade'
    ],
    'Snacks': [
      'chocolate',
      'chip',
      'candy',
      'cookie',
      'biscuit',
      'nut',
      'snack',
      'popcorn',
      'crisp',
      'pretzel',
      'bar'
    ],
  };

  String _foodGroupFor(GroceryItem item) {
    const known = [
      'Fruits',
      'Vegetables',
      'Protein',
      'Dairy',
      'Grains',
      'Snacks',
      'Drinks',
    ];
    if (item.category != null && known.contains(item.category)) {
      return item.category!;
    }
    final n = item.name.toLowerCase();
    for (final entry in _foodGroupKeywords.entries) {
      for (final kw in entry.value) {
        if (n.contains(kw)) return entry.key;
      }
    }
    return 'Other';
  }

  /// Order the to-buy list by food group (fruit, vegetables, protein/meat,
  /// dairy, grains, …) with a header per group so the groceries are always
  /// tidily organised.
  List<Widget> _buildGroupedGroceries(
    AppLocalizations l10n,
    List<GroceryItem> items,
    bool smartEnabled,
  ) {
    if (items.isEmpty) return const [];
    const order = [
      'Fruits',
      'Vegetables',
      'Protein',
      'Dairy',
      'Grains',
      'Snacks',
      'Drinks',
      'Other',
    ];
    final groups = <String, List<GroceryItem>>{};
    for (final item in items) {
      groups.putIfAbsent(_foodGroupFor(item), () => []).add(item);
    }
    final widgets = <Widget>[];
    for (final cat in order) {
      final list = groups[cat];
      if (list == null || list.isEmpty) continue;
      widgets.add(_SectionLabel(
        '${l10n.groceryCategoryLabel(cat)} (${list.length})',
        color: context.primary700,
      ));
      widgets.addAll(list.map((item) => _GroceryTile(
            item: item,
            smartEnabled: smartEnabled,
            onBought: () => _markBought(item),
            onToggle: () =>
                ref.read(groceryProvider.notifier).toggleChecked(item),
            onDelete: () => smartEnabled
                ? _dontBuy(item)
                : ref.read(groceryProvider.notifier).deleteItem(item),
            onEdit: () => _editItem(item),
          )));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grocery = ref.watch(groceryProvider);
    final unchecked = grocery.items.where((i) => !i.checked).toList();
    final checked = grocery.items.where((i) => i.checked).toList();
    final smartEnabled = ref.watch(smartGroceryEnabledProvider);
    final pantryItems = smartEnabled
        ? ref.watch(pantryProvider).availableItems
        : const <PantryItem>[];
    final atHome = smartEnabled && _atHome;
    final visiblePantry = pantryItems
        .where((item) =>
            _selectedFoodGroup == null ||
            (item.category ?? _guessCategory(item.name)) == _selectedFoodGroup)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.groceryList),
        actions: [
          // Scan a packaged product's barcode → Open Food Facts (accurate)
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: l10n.groceryScanBarcodeTooltip,
            onPressed: _scanBarcode,
          ),
          if (!atHome && checked.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.groceryClearPurchased,
              onPressed: () =>
                  ref.read(groceryProvider.notifier).clearChecked(),
            ),
          if (!atHome && grocery.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.grocerySelectAllDelete,
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.deleteEntireList),
                    content: Text(
                      l10n.groceryDeleteAllBody(grocery.items.length),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.red500,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(l10n.deleteAll),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(groceryProvider.notifier).clearAll();
                }
              },
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (smartEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: false,
                            label: Text(l10n.pantryGroceries),
                            icon: const Icon(Icons.shopping_cart_outlined)),
                        ButtonSegment(
                            value: true,
                            label: Text(l10n.pantryAtHome),
                            icon: const Icon(Icons.kitchen_outlined)),
                      ],
                      selected: {atHome},
                      onSelectionChanged: (value) => setState(() {
                        _atHome = value.single;
                        _selectedFoodGroup = null;
                      }),
                    ),
                  ),
                // Two primary actions, always at the top of the tab.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(atHome
                              ? l10n.pantryAddItem
                              : l10n.addToGroceryList),
                          onPressed: _showAddDialog,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.isPremiumTheme
                                ? context.visualTheme.primaryAccent
                                : context.primary500,
                            foregroundColor:
                                ThemeData.estimateBrightnessForColor(context
                                                .isPremiumTheme
                                            ? context.visualTheme.primaryAccent
                                            : context.primary500) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          icon:
                              const Icon(Icons.auto_awesome_outlined, size: 18),
                          label: Text(l10n.aiScan),
                          onPressed: _photoBusy
                              ? null
                              : atHome
                                  ? _scanWhatIHave
                                  : _showSmartSuggestSheet,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.isPremiumTheme
                                ? context.visualTheme.cardColor
                                : context.primary600,
                            foregroundColor:
                                ThemeData.estimateBrightnessForColor(
                                            context.isPremiumTheme
                                                ? context.visualTheme.cardColor
                                                : context.primary600) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!atHome)
                  TextButton.icon(
                    onPressed: _scanReceipt,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(l10n.scanReceiptTooltip),
                  ),
                // Food-group selectable variables (like the Recipes tab).
                SizedBox(
                  height: 46,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        _GroceryGroupChip(
                          label: l10n.pantryLocationLabel('all'),
                          selected: _selectedFoodGroup == null,
                          onTap: () =>
                              setState(() => _selectedFoodGroup = null),
                        ),
                        for (final g in _categories)
                          _GroceryGroupChip(
                            label: l10n.groceryCategoryLabel(g),
                            selected: _selectedFoodGroup == g,
                            onTap: () => setState(() => _selectedFoodGroup = g),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: (atHome ? pantryItems.isEmpty : grocery.items.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_cart_outlined,
                                  size: 64, color: AppTheme.gray300),
                              const SizedBox(height: 16),
                              Text(
                                  atHome
                                      ? l10n.pantryEmptyHint
                                      : l10n.groceryListEmpty,
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: context.appMutedTextColor)),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (atHome) ...[
                              _SectionLabel(
                                '${l10n.pantrySectionTitle} (${visiblePantry.length})',
                                color: context.primary700,
                              ),
                              if (pantryItems.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                  child: Text(
                                    l10n.pantryEmptyHint,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.3,
                                      color: context.appMutedTextColor,
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 2, 12, 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: visiblePantry.map((p) {
                                      final q = p.quantity;
                                      final qStr = q == q.roundToDouble()
                                          ? q.toInt().toString()
                                          : q.toStringAsFixed(1);
                                      final qtyLabel = p.unit != null
                                          ? ' $qStr ${p.unit}'
                                          : (q > 1 ? ' ×$qStr' : '');
                                      return InputChip(
                                        label: Text(
                                            '${IngredientLocalizer.localize(p.name, targetLang: l10n.locale.languageCode, sourceLang: 'en')}$qtyLabel'),
                                        backgroundColor:
                                            context.appSubtleFillColor,
                                        labelStyle: TextStyle(
                                          fontSize: 12.5,
                                          color: context.appTextColor,
                                        ),
                                        deleteIconColor:
                                            context.appMutedTextColor,
                                        onPressed: () => _editPantryItem(p),
                                        onDeleted: () => ref
                                            .read(pantryProvider.notifier)
                                            .deleteItem(p),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              const Divider(height: 1),
                            ],
                            if (!atHome)
                              ..._buildGroupedGroceries(
                                l10n,
                                _selectedFoodGroup == null
                                    ? unchecked
                                    : unchecked
                                        .where((i) =>
                                            _foodGroupFor(i) ==
                                            _selectedFoodGroup)
                                        .toList(),
                                smartEnabled,
                              ),
                            if (!atHome &&
                                checked.isNotEmpty &&
                                _selectedFoodGroup == null) ...[
                              _SectionLabel(
                                  l10n.groceryPurchased(checked.length),
                                  color: context.appMutedTextColor),
                              ...checked.map((item) => _GroceryTile(
                                    item: item,
                                    smartEnabled: smartEnabled,
                                    onBought: () => _markBought(item),
                                    onToggle: () => ref
                                        .read(groceryProvider.notifier)
                                        .toggleChecked(item),
                                    onDelete: () => smartEnabled
                                        ? _dontBuy(item)
                                        : ref
                                            .read(groceryProvider.notifier)
                                            .deleteItem(item),
                                    onEdit: () => _editItem(item),
                                  )),
                            ],
                          ],
                        ),
                ),
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
  const _SuggestionItem(
      {required this.name, required this.category, this.suggestedQty = 1});
}

// ── Food-group filter chip (Recipes-tab style pill) ─────────────────────────

class _GroceryGroupChip extends StatelessWidget {
  const _GroceryGroupChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final selectedFill = visual.premium
        ? visual.primaryAccent.withValues(alpha: 0.22)
        : context.primary500;
    final selectedText = visual.premium ? visual.primaryAccent : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedFill : context.appSurfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? context.primary500 : context.appBorderColor,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? selectedText : context.appTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});
  final String text;
  final Color color;

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
    required this.onEdit,
    this.smartEnabled = false,
    this.onBought,
  });

  final GroceryItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final bool smartEnabled;
  final VoidCallback? onBought;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final Widget? qtyBadge = (item.quantity > 0 || item.unit != null)
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.primary100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
                item.unit != null
                    ? '${item.quantity} ${item.unit}'
                    : 'x${item.quantity}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.primary700)),
          )
        : null;

    final Widget? subtitle = item.category != null
        ? Text(l10n.groceryCategoryLabel(item.category!),
            style: TextStyle(fontSize: 12, color: context.appMutedTextColor))
        : null;

    // Smart mode: left = "bought" (adds to pantry), right = "don't buy".
    if (smartEnabled && onBought != null) {
      return Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: AppTheme.red500,
          child: const Icon(Icons.close, color: Colors.white),
        ),
        onDismissed: (_) => onDelete(),
        child: ListTile(
          onTap: onEdit,
          leading: IconButton(
            icon: const Icon(Icons.check_circle_outline),
            color: Colors.green,
            tooltip: l10n.markBoughtTooltip,
            onPressed: onBought,
          ),
          title: Text(
            item.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.appTextColor,
            ),
          ),
          subtitle: subtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (qtyBadge != null) qtyBadge,
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                color: AppTheme.red500,
                tooltip: l10n.dontBuyTooltip,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      );
    }

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
        onTap: onEdit,
        leading: Checkbox(
          value: item.checked,
          onChanged: (_) => onToggle(),
          activeColor: context.primary500,
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            decoration: item.checked ? TextDecoration.lineThrough : null,
            color:
                item.checked ? context.appMutedTextColor : context.appTextColor,
          ),
        ),
        subtitle: subtitle,
        trailing: qtyBadge,
      ),
    );
  }
}
