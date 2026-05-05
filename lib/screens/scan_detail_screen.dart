import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
import '../models/glucose_spike_model.dart';
import '../models/nutrition_goal.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../services/native_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/confidence_badge.dart';
import '../widgets/glucose_spike_card.dart';
import '../widgets/plate_score_widget.dart';
import 'edit_food_screen.dart';
import 'ground_truth_screen.dart';

/// Detail view for a single scan result.
class ScanDetailScreen extends ConsumerStatefulWidget {
  const ScanDetailScreen({super.key, required this.scan});
  final ScanResult scan;

  @override
  ConsumerState<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends ConsumerState<ScanDetailScreen> {
  late ScanResult _scan;
  Map<String, FoodData> _foodMap = const {};

  @override
  void initState() {
    super.initState();
    _scan = widget.scan;
    _loadFoodMap();
  }

  Future<void> _loadFoodMap() async {
    final foods = await DatabaseService.instance.getAllFoods();
    if (!mounted) return;
    setState(() {
      _foodMap = {for (final f in foods) f.label.toLowerCase(): f};
    });
  }

  /// Look up the FoodData for a detected label (case-insensitive).
  FoodData? _foodFor(String label) => _foodMap[label.toLowerCase()];

  /// Estimate grams from volumeCm³ using density from FoodData.
  double _gramsFor(DetectedFood food) {
    final fd = _foodFor(food.label);
    if (fd == null) return food.volumeCm3; // assume density ≈ 1.0
    final avgDensity = (fd.densityMin + fd.densityMax) / 2.0;
    return food.volumeCm3 * avgDensity;
  }

  Future<void> _refresh() async {
    await ref.read(historyProvider.notifier).load();
    final history = ref.read(historyProvider);
    final updated = history.scans.where((s) => s.id == _scan.id).firstOrNull;
    if (updated != null) {
      setState(() => _scan = updated);
    }
  }

  void _editFood(DetectedFood food) async {
    if (_scan.id == null) return;
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditFoodScreen(scanId: _scan.id!, food: food),
      ),
    );
    if (edited == true) {
      await _refresh();
    }
  }

  void _recordGroundTruth(DetectedFood food) async {
    if (_scan.id == null || food.id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroundTruthScreen(
          scanId: _scan.id!,
          food: food,
        ),
      ),
    );
  }

  Future<void> _exportPLY() async {
    final ply = await NativeBridge.instance.exportPointCloud();
    if (ply == null || ply.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No depth data available for point cloud')),
        );
      }
      return;
    }
    final path = await DataExportService.instance.saveToFile(
      ply,
      'scan_${_scan.id}_${DateTime.now().millisecondsSinceEpoch}.ply',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PLY saved to $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avgTotal = (_scan.totalCaloriesMin + _scan.totalCaloriesMax) / 2;
    final margin = (_scan.totalCaloriesMax - _scan.totalCaloriesMin) / 2;

    final prefs = ref.watch(userPrefsProvider);
    final isDiabetic = prefs.nutritionGoal == NutritionGoalType.diabetes;
    final icr = prefs.icrGramsPerUnit;

    // Total carbs across the meal — only computed when needed.
    double totalCarbsG = 0;
    if (isDiabetic) {
      for (final f in _scan.foods) {
        final fd = _foodFor(f.label);
        if (fd == null) continue;
        totalCarbsG += fd.carbsPer100g * _gramsFor(f) / 100.0;
      }
    }
    final totalBolus = (isDiabetic && totalCarbsG > 0 && icr > 0)
        ? (totalCarbsG / icr * 10).round() / 10
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'Export 3D point cloud',
            onPressed: _exportPLY,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.red500),
            tooltip: 'Delete scan',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header card ──────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.check_circle,
                      size: 48, color: context.primary500),
                  const SizedBox(height: 12),
                  Text(
                    '${avgTotal.round()} kcal',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gray900,
                    ),
                  ),
                  Text(
                    '± ${margin.round()} kcal',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.gray400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _InfoChip(
                        icon: Icons.visibility,
                        label: _scan.depthMode,
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.restaurant,
                        label:
                            '${_scan.foods.length} item${_scan.foods.length == 1 ? '' : 's'}',
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.access_time,
                        label: _formatTime(_scan.timestamp),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Date info ────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 18, color: context.primary500),
                  const SizedBox(width: 12),
                  Text(
                    _formatFullDate(_scan.timestamp),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Confidence score ─────────────────────────────────────────
          ConfidenceRingCard(
            caloriesMin: _scan.totalCaloriesMin,
            caloriesMax: _scan.totalCaloriesMax,
          ),
          const SizedBox(height: 12),

          // ── Plate Score ──────────────────────────────────────────────
          if (_scan.foods.isNotEmpty) ...[
            Builder(builder: (context) {
              final mealCal = (_scan.totalCaloriesMin + _scan.totalCaloriesMax) / 2;
              double mealProtein = 0;
              double mealFiber = 0;
              double mealGL = 0;
              for (final f in _scan.foods) {
                final fd = _foodMap[f.label.toLowerCase()];
                if (fd == null) continue;
                final g = _gramsFor(f);
                mealProtein += fd.proteinPer100g * g / 100;
                mealFiber += fd.fiberPer100g * g / 100;
                mealGL += fd.glForGrams(g);
              }
              final breakdown = calculatePlateScore(
                mealCalories: mealCal,
                dailyGoal: prefs.dailyCalorieGoal,
                proteinG: mealProtein,
                fiberG: mealFiber,
                foodCount: _scan.foods.length,
                totalGL: mealGL,
              );
              return PlateScoreReveal(
                score: breakdown.total,
                breakdown: breakdown,
              );
            }),
            const SizedBox(height: 16),
          ],

          // ── Meal Bolus card (diabetes goal only) ─────────────────────
          if (totalBolus != null) ...[
            Card(
              color: const Color(0xFFE3F2FD),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF1976D2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.vaccines_outlined,
                        color: Color(0xFF1976D2), size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Suggested Meal Bolus',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1976D2),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${totalBolus.toStringAsFixed(1)} units',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D47A1),
                            ),
                          ),
                          Text(
                            '${totalCarbsG.toStringAsFixed(1)} g carbs ÷ '
                            '${icr.toStringAsFixed(0)} g/unit',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF1976D2)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '⚠️ Carbohydrate-cover bolus only. Always confirm with your healthcare provider.',
                style: TextStyle(fontSize: 11, color: AppTheme.gray400),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── GL Thermometer (diabetes goal only) ───────────────────────
          if (isDiabetic && _scan.foods.isNotEmpty) ...[
            _GlThermometerCard(
              scan: _scan,
              foodMap: _foodMap,
              gramsForFood: _gramsFor,
            ),
            const SizedBox(height: 8),
            // ── Glucose Spike Prediction Chart ──────────────────────────
            GlucoseSpikeCard(
              mealItems: _scan.foods.map((f) {
                final fd = _foodMap[f.label.toLowerCase()];
                if (fd == null) return null;
                final g = _gramsFor(f);
                return MealItemInput(
                  netCarbsG: (fd.carbsPer100g - fd.fiberPer100g).clamp(0, 999) * g / 100,
                  gi: fd.estimatedGI.toDouble(),
                  proteinG: fd.proteinPer100g * g / 100,
                  fatG: fd.fatPer100g * g / 100,
                  fiberG: fd.fiberPer100g * g / 100,
                );
              }).whereType<MealItemInput>().toList(),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Detected Foods',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(height: 8),
          ..._scan.foods.map((f) {
            final fd = _foodFor(f.label);
            final grams = _gramsFor(f);
            final foodBolus = (isDiabetic && fd != null)
                ? fd.bolusForGrams(grams, icr)
                : null;
            final row = _FoodDetailRow(
              food: f,
              grams: grams,
              bolusUnits: foodBolus,
              onEdit: () => _editFood(f),
              onGroundTruth: () => _recordGroundTruth(f),
            );
            // Allow swipe-to-delete only when the food has a stable id.
            if (f.id == null) return row;
            return Dismissible(
              key: ValueKey('food-${f.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24, bottom: 8),
                color: AppTheme.red500,
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove this item?'),
                    content: Text('Remove "${f.label}" from this scan?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove',
                            style: TextStyle(color: AppTheme.red500)),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) async {
                await ref
                    .read(historyProvider.notifier)
                    .deleteDetectedFood(f.id!);
                await ref.read(dailyIntakeProvider.notifier).load();
                await _refresh();
              },
              child: row,
            );
          }),

          // Tap hint
          if (_scan.foods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Tap to edit  •  Long-press for ground truth  •  Swipe ← to remove',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.gray400),
              ),
            ),

          // ── Calorie range breakdown ──────────────────────────────────
          const SizedBox(height: 16),
          Text(
            'Calorie Range',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _RangeRow(
                    label: 'Minimum',
                    value: '${_scan.totalCaloriesMin.round()} kcal',
                    color: context.primary600,
                  ),
                  const SizedBox(height: 8),
                  _RangeRow(
                    label: 'Average',
                    value: '${avgTotal.round()} kcal',
                    color: AppTheme.gray900,
                  ),
                  const SizedBox(height: 8),
                  _RangeRow(
                    label: 'Maximum',
                    value: '${_scan.totalCaloriesMax.round()} kcal',
                    color: AppTheme.amber700,
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: _scan.totalCaloriesMin.round(),
                          child: Container(
                            height: 8,
                            color: context.primary400,
                          ),
                        ),
                        Expanded(
                          flex: (avgTotal - _scan.totalCaloriesMin).round().clamp(1, 9999),
                          child: Container(
                            height: 8,
                            color: context.primary200,
                          ),
                        ),
                        Expanded(
                          flex: (_scan.totalCaloriesMax - avgTotal).round().clamp(1, 9999),
                          child: Container(
                            height: 8,
                            color: AppTheme.amber500.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Camera pose data (Part 9) ──────────────────────────────────
          if (_scan.topCameraPosition != null ||
              _scan.sideCameraPosition != null) ...[
            const SizedBox(height: 16),
            Text(
              'Camera Pose',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.gray700,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_scan.topCameraPosition != null)
                      _InfoRow(
                        label: 'Top position',
                        value: _scan.topCameraPosition!,
                      ),
                    if (_scan.sideCameraPosition != null)
                      _InfoRow(
                        label: 'Side position',
                        value: _scan.sideCameraPosition!,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Full 4×4 transform stored for geometry reconstruction',
                      style: TextStyle(fontSize: 11, color: AppTheme.gray400),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scan?'),
        content:
            const Text('This will permanently remove this scan entry.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppTheme.red500)),
          ),
        ],
      ),
    );
    if (confirmed == true && _scan.id != null) {
      await ref.read(historyProvider.notifier).deleteScan(_scan.id!);
      await ref.read(dailyIntakeProvider.notifier).load();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at ${_formatTime(dt)}';
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.primary50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.primary200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.primary600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.primary700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppTheme.gray400)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
                color: AppTheme.gray700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodDetailRow extends StatelessWidget {
  const _FoodDetailRow({
    required this.food,
    required this.grams,
    this.bolusUnits,
    required this.onEdit,
    required this.onGroundTruth,
  });
  final DetectedFood food;
  final double grams;
  final double? bolusUnits;
  final VoidCallback onEdit;
  final VoidCallback onGroundTruth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onGroundTruth();
      },
      child: _FoodDetailCard(food: food, grams: grams, bolusUnits: bolusUnits),
    );
  }
}

class _FoodDetailCard extends StatelessWidget {
  const _FoodDetailCard({
    required this.food,
    required this.grams,
    this.bolusUnits,
  });
  final DetectedFood food;
  final double grams;
  final double? bolusUnits;

  /// Returns a color indicating uncertainty: green=low, amber=med, red=high.
  Color _uncertaintyColor(double margin, double avg, BuildContext context) {
    if (avg == 0) return AppTheme.gray200;
    final pct = margin / avg; // relative uncertainty
    if (pct < 0.15) return context.primary400;
    if (pct < 0.30) return AppTheme.amber500;
    return AppTheme.red500;
  }

  @override
  Widget build(BuildContext context) {
    final avg = (food.caloriesMin + food.caloriesMax) / 2;
    final margin = (food.caloriesMax - food.caloriesMin) / 2;
    final uColor = _uncertaintyColor(margin, avg, context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.primary100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.restaurant,
                        color: context.primary600, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          food.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${grams.toStringAsFixed(0)} g  •  ${food.volumeCm3.toStringAsFixed(1)} cm³',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.gray400,
                          ),
                        ),
                        if (bolusUnits != null && bolusUnits! > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '💉 ${bolusUnits!.toStringAsFixed(1)} u insulin',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1976D2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${avg.round()} kcal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.primary700,
                        ),
                      ),
                      Text(
                        '± ${margin.round()}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.gray400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: AppTheme.gray300),
                ],
              ),
              // ── Uncertainty bar ────────────────────────────────────────
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${food.caloriesMin.round()}',
                    style: TextStyle(fontSize: 10, color: AppTheme.gray400),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background track
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.gray100,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Uncertainty range
                        FractionallySizedBox(
                          widthFactor: avg > 0
                              ? ((food.caloriesMax - food.caloriesMin) /
                                      (food.caloriesMax * 1.2))
                                  .clamp(0.05, 1.0)
                              : 0.05,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: uColor.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        // Center dot (average)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: uColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white, width: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${food.caloriesMax.round()}',
                    style: TextStyle(fontSize: 10, color: AppTheme.gray400),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.gray400)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── GL Thermometer card ───────────────────────────────────────────────────────

class _GlThermometerCard extends StatelessWidget {
  const _GlThermometerCard({
    required this.scan,
    required this.foodMap,
    required this.gramsForFood,
  });

  final ScanResult scan;
  final Map<String, FoodData> foodMap;
  final double Function(DetectedFood) gramsForFood;

  @override
  Widget build(BuildContext context) {
    // Compute total GL for the meal.
    double totalGL = 0;
    for (final f in scan.foods) {
      final fd = foodMap[f.label.toLowerCase()];
      if (fd != null) totalGL += fd.glForGrams(gramsForFood(f));
    }

    // GL classification:
    //  < 10 = LOW  (cool/blue)
    //  10-19 = MEDIUM (warm/orange)
    //  >= 20 = HIGH (hot/red)
    final String level;
    final Color color;
    final Color bgColor;
    final String tip;

    if (totalGL < 10) {
      level = 'Cool Meal 🧊';
      color = const Color(0xFF1976D2);
      bgColor = const Color(0xFFE3F2FD);
      tip = 'Low glycaemic load — slow glucose release. '
          'Blood sugar rise will be gradual.';
    } else if (totalGL < 20) {
      level = 'Warm Meal 🌤';
      color = const Color(0xFFF57C00);
      bgColor = const Color(0xFFFFF3E0);
      tip = 'Moderate glycaemic load — expect a moderate glucose rise '
          'over ~90 min.';
    } else {
      level = 'Hot Meal 🌶️';
      color = const Color(0xFFD32F2F);
      bgColor = const Color(0xFFFFEBEE);
      tip = 'High glycaemic load — rapid glucose spike likely. '
          'Consider adding fibre or fat to slow absorption.';
    }

    // Scale bar: cap at GL=40 for display
    final barFraction = (totalGL / 40.0).clamp(0.0, 1.0);

    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.thermostat_outlined, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Glycaemic Load Thermometer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1976D2),
                                Color(0xFFFFA726),
                                Color(0xFFD32F2F),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: barFraction *
                              (MediaQuery.of(context).size.width - 80) -
                              6,
                          top: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'GL: ${totalGL.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(level,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Text(tip,
                style: TextStyle(fontSize: 11, color: color)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Cool', style: TextStyle(fontSize: 10)),
                const Spacer(),
                const Text('🌶️ Hot', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
