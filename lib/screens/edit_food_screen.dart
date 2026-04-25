import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late TextEditingController _calMinCtrl;
  late TextEditingController _calMaxCtrl;
  List<FoodData> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.food.label);
    _calMinCtrl = TextEditingController(
        text: widget.food.caloriesMin.round().toString());
    _calMaxCtrl = TextEditingController(
        text: widget.food.caloriesMax.round().toString());
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final foods = await DatabaseService.instance.getAllFoods();
    setState(() => _suggestions = foods);
  }

  void _applyFoodSuggestion(FoodData food) {
    _labelCtrl.text = food.label;
    // Recalculate calories using the food's data and original volume
    final range = food.calorieRange(widget.food.volumeCm3);
    _calMinCtrl.text = range.min.round().toString();
    _calMaxCtrl.text = range.max.round().toString();
    setState(() => _showSuggestions = false);
  }

  Future<void> _save() async {
    final calMin = double.tryParse(_calMinCtrl.text) ?? widget.food.caloriesMin;
    final calMax = double.tryParse(_calMaxCtrl.text) ?? widget.food.caloriesMax;

    if (widget.food.id != null) {
      await DatabaseService.instance.updateDetectedFood(
        widget.food.id!,
        label: _labelCtrl.text.trim(),
        caloriesMin: calMin,
        caloriesMax: calMax,
      );
    }

    await ref.read(historyProvider.notifier).load();
    await ref.read(dailyIntakeProvider.notifier).load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Food updated')),
      );
      Navigator.of(context).pop(true); // true = edited
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _calMinCtrl.dispose();
    _calMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avg = ((double.tryParse(_calMinCtrl.text) ?? 0) +
            (double.tryParse(_calMaxCtrl.text) ?? 0)) /
        2;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Food')),
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
                    '${widget.food.volumeCm3.toStringAsFixed(1)} cm³ volume',
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
            onChanged: (_) => setState(() {}),
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
}
