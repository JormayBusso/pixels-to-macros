import 'package:flutter/material.dart';

import '../models/ground_truth.dart';
import '../models/scan_result.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Screen for entering actual weighed measurements for a detected food item.
///
/// Part of the scientific evaluation pipeline — lets the user record
/// ground truth to compute accuracy metrics.
class GroundTruthScreen extends StatefulWidget {
  const GroundTruthScreen({
    super.key,
    required this.scanId,
    required this.food,
  });
  final int scanId;
  final DetectedFood food;

  @override
  State<GroundTruthScreen> createState() => _GroundTruthScreenState();
}

class _GroundTruthScreenState extends State<GroundTruthScreen> {
  final _weightCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;
  GroundTruth? _existing;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (widget.food.id == null) return;
    final gt =
        await DatabaseService.instance.getGroundTruthForFood(widget.food.id!);
    if (gt != null && mounted) {
      setState(() {
        _existing = gt;
        _weightCtrl.text = gt.actualWeightGrams.toStringAsFixed(1);
        if (gt.actualCalories != null) {
          _caloriesCtrl.text = gt.actualCalories!.toStringAsFixed(1);
        }
        if (gt.notes != null) {
          _notesCtrl.text = gt.notes!;
        }
      });
    }
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight in grams')),
      );
      return;
    }

    final calories = double.tryParse(_caloriesCtrl.text);
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    setState(() => _saving = true);

    // Delete existing if updating
    if (_existing != null) {
      await DatabaseService.instance.deleteGroundTruth(_existing!.id!);
    }

    final gt = GroundTruth(
      detectedFoodId: widget.food.id!,
      scanId: widget.scanId,
      actualWeightGrams: weight,
      actualCalories: calories,
      notes: notes,
      timestamp: DateTime.now(),
    );

    await DatabaseService.instance.insertGroundTruth(gt);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Ground truth saved for ${widget.food.label}')),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _caloriesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avg = (widget.food.caloriesMin + widget.food.caloriesMax) / 2;
    final margin = (widget.food.caloriesMax - widget.food.caloriesMin) / 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ground Truth'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Predicted values (read-only) ──────────────────────────────
          Card(
            color: context.primary50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 18, color: context.primary600),
                      const SizedBox(width: 8),
                      Text(
                        'Model Prediction',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.primary700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PredictionRow(
                    label: 'Food',
                    value: widget.food.label,
                  ),
                  _PredictionRow(
                    label: 'Volume',
                    value: '${widget.food.volumeCm3.toStringAsFixed(1)} cm³',
                  ),
                  _PredictionRow(
                    label: 'Calories',
                    value: '${avg.round()} ± ${margin.round()} kcal',
                  ),
                  _PredictionRow(
                    label: 'Range',
                    value:
                        '${widget.food.caloriesMin.round()}–${widget.food.caloriesMax.round()} kcal',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Actual values (editable) ──────────────────────────────────
          const Text(
            'Actual Measurement',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Weigh the food on a kitchen scale and enter the result.',
            style: TextStyle(fontSize: 13, color: AppTheme.gray400),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Actual weight',
              prefixIcon: Icon(Icons.scale),
              suffixText: 'grams',
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _caloriesCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Actual calories (optional)',
              prefixIcon: Icon(Icons.local_fire_department),
              suffixText: 'kcal',
              helperText: 'From nutrition label or known value',
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              prefixIcon: Icon(Icons.note),
              hintText: 'e.g. "slightly overflowing plate"',
            ),
          ),
          const SizedBox(height: 24),

          // ── Quick calorie calculator ──────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calculate,
                          size: 16, color: AppTheme.gray400),
                      const SizedBox(width: 8),
                      const Text(
                        'Quick Calculator',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gray700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you know kcal/100g, enter weight above and the '
                    'calories will be estimated below.',
                    style: TextStyle(fontSize: 12, color: AppTheme.gray400),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder(
                    valueListenable: _weightCtrl,
                    builder: (_, __, ___) {
                      final w = double.tryParse(_weightCtrl.text);
                      if (w == null || w <= 0) {
                        return const SizedBox.shrink();
                      }
                      // Use the food DB kcal/100g from the prediction
                      // Rough estimate: predicted avg kcal / predicted volume * density
                      return Wrap(
                        spacing: 8,
                        children: [50, 100, 150, 200, 250]
                            .map(
                              (kcalPer100) => ActionChip(
                                label: Text(
                                    '${(w * kcalPer100 / 100).round()} kcal @ $kcalPer100/100g'),
                                onPressed: () {
                                  _caloriesCtrl.text =
                                      (w * kcalPer100 / 100).toStringAsFixed(1);
                                },
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.science),
              label: Text(_existing != null
                  ? 'Update Ground Truth'
                  : 'Save Ground Truth'),
              onPressed: _saving ? null : _save,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PredictionRow extends StatelessWidget {
  const _PredictionRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.gray400),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.gray700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
