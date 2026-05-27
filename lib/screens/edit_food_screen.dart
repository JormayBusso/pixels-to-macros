import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Edit a detected food item's label and calorie values after a scan.
class EditFoodScreen extends ConsumerStatefulWidget {
  const EditFoodScreen({
    super.key,
    required this.scanId,
    required this.food,
  });
  final int scanId;
  final DetectedFood food;

  @override
  ConsumerState<EditFoodScreen> createState() => _EditFoodScreenState();
}

class _EditFoodScreenState extends ConsumerState<EditFoodScreen> {
  late TextEditingController _labelCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _calMinCtrl;
  late TextEditingController _calMaxCtrl;
  List<FoodData> _suggestions = [];
  bool _showSuggestions = false;
  bool _weightTouched = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.food.label);
    _weightCtrl = TextEditingController(
      text: widget.food.volumeCm3.round().toString(),
    );
    _calMinCtrl = TextEditingController(
        text: widget.food.caloriesMin.round().toString());
    _calMaxCtrl = TextEditingController(
        text: widget.food.caloriesMax.round().toString());
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final foods = await DatabaseService.instance.getAllFoods();
    if (!mounted) return;
    setState(() {
      _suggestions = foods;
      if (!_weightTouched) _syncWeightFromCurrentFood();
    });
  }

  void _applyFoodSuggestion(FoodData food) {
    _labelCtrl.text = food.label;
    if (!_weightTouched) {
      _syncWeightFromCurrentFood(food);
    }
    _recalculateCaloriesFromWeight(foodData: food, notify: false);
    setState(() => _showSuggestions = false);
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final foodData = _foodForLabel(label);
    final grams = _parsePositiveDouble(_weightCtrl.text);
    final volumeCm3 = grams == null
        ? widget.food.volumeCm3
        : grams / _averageDensity(foodData);
    final calMin = double.tryParse(_calMinCtrl.text) ?? widget.food.caloriesMin;
    final calMax = double.tryParse(_calMaxCtrl.text) ?? widget.food.caloriesMax;

    if (widget.food.id != null) {
      await DatabaseService.instance.updateDetectedFood(
        widget.food.id!,
        label: label,
        caloriesMin: calMin,
        caloriesMax: calMax,
        volumeCm3: volumeCm3,
      );
    }

    await ref.read(historyProvider.notifier).load();
    await ref.read(dailyIntakeProvider.notifier).load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).foodUpdated)),
      );
      Navigator.of(context).pop(true); // true = edited
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _weightCtrl.dispose();
    _calMinCtrl.dispose();
    _calMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avg = ((double.tryParse(_calMinCtrl.text) ?? 0) +
            (double.tryParse(_calMaxCtrl.text) ?? 0)) /
        2;
    final grams = _parsePositiveDouble(_weightCtrl.text) ?? _currentWeightG();
    final volume = _currentVolumeCm3();

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).editFood)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Preview ─────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '≈ ${avg.round()} kcal',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.primary700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${grams.toStringAsFixed(grams >= 10 ? 0 : 1)} g • '
                    '${volume.toStringAsFixed(1)} cm³ volume',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.gray400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Label field ─────────────────────────────────────────────
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: 'Food label',
              prefixIcon: const Icon(Icons.restaurant),
              suffixIcon: IconButton(
                icon: Icon(
                  _showSuggestions
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
                onPressed: () =>
                    setState(() => _showSuggestions = !_showSuggestions),
              ),
            ),
            onChanged: (_) => _recalculateCaloriesFromWeight(),
          ),

          // ── Quick-pick from DB ──────────────────────────────────────
          if (_showSuggestions) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.primary200),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredSuggestions.length,
                itemBuilder: (context, i) {
                  final food = _filteredSuggestions[i];
                  return ListTile(
                    dense: true,
                    title: Text(food.label),
                    subtitle: Text('${food.kcalPer100g.round()} kcal/100g'),
                    onTap: () => _applyFoodSuggestion(food),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),

          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Weight',
              suffixText: 'g',
              prefixIcon: Icon(Icons.scale),
            ),
            onChanged: (_) {
              _weightTouched = true;
              _recalculateCaloriesFromWeight();
            },
          ),
          const SizedBox(height: 16),

          // ── Calorie fields ──────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _calMinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Min kcal',
                    prefixIcon: Icon(Icons.arrow_downward),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _calMaxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max kcal',
                    prefixIcon: Icon(Icons.arrow_upward),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Save button ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Save Changes'),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  List<FoodData> get _filteredSuggestions {
    final q = _labelCtrl.text.toLowerCase();
    if (q.isEmpty) return _suggestions;
    return _suggestions.where((f) => f.label.toLowerCase().contains(q)).toList();
  }

  FoodData? _foodForLabel([String? label]) {
    final q = (label ?? _labelCtrl.text).trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final food in _suggestions) {
      if (food.label.toLowerCase() == q) return food;
    }
    return null;
  }

  double _averageDensity(FoodData? foodData) {
    if (foodData == null) return 1.0;
    final density = (foodData.densityMin + foodData.densityMax) / 2.0;
    return density <= 0 ? 1.0 : density;
  }

  double _currentWeightG([FoodData? foodData]) {
    return widget.food.volumeCm3 * _averageDensity(foodData ?? _foodForLabel());
  }

  double _currentVolumeCm3() {
    final grams = _parsePositiveDouble(_weightCtrl.text);
    if (grams == null) return widget.food.volumeCm3;
    return grams / _averageDensity(_foodForLabel());
  }

  void _syncWeightFromCurrentFood([FoodData? foodData]) {
    final weight = _currentWeightG(foodData);
    _weightCtrl.text = weight.toStringAsFixed(weight >= 10 ? 0 : 1);
  }

  void _recalculateCaloriesFromWeight({
    FoodData? foodData,
    bool notify = true,
  }) {
    final grams = _parsePositiveDouble(_weightCtrl.text);
    final food = foodData ?? _foodForLabel();
    if (grams != null && food != null && food.kcalPer100g > 0) {
      final kcal = food.kcalPer100g * grams / 100.0;
      _calMinCtrl.text = (kcal * 0.95).round().toString();
      _calMaxCtrl.text = (kcal * 1.05).round().toString();
    }
    if (notify && mounted) setState(() {});
  }

  double? _parsePositiveDouble(String raw) {
    final value = double.tryParse(raw.replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return value;
  }
}
