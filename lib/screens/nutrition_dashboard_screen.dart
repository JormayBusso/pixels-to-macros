import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// Full nutrition breakdown: macros + vitamins + minerals.
/// Navigate here by tapping the mascot on the home screen.
class NutritionDashboardScreen extends ConsumerWidget {
  const NutritionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs  = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final isFemale = prefs.gender == UserGender.female;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Nutrition'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: intake.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              children: [
                // ── Calorie summary card ──────────────────────────────────
                _SummaryCard(
                  calories: intake.caloriesAvg.round(),
                  calorieGoal: prefs.dailyCalorieGoal,
                  scanCount: intake.scanCount,
                ),
                const SizedBox(height: 8),

                // ── Macronutrients ────────────────────────────────────────
                const _SectionHeader('Macronutrients'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _NutrientRow(
                        icon: const Text('🔥', style: TextStyle(fontSize: 16)),
                        name: 'Calories',
                        current: intake.caloriesAvg,
                        drv: prefs.dailyCalorieGoal.toDouble(),
                        unit: 'kcal',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('💪', style: TextStyle(fontSize: 16)),
                        name: 'Protein',
                        current: intake.proteinG,
                        drv: prefs.dailyProteinTargetG.toDouble(),
                        unit: 'g',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🍞', style: TextStyle(fontSize: 16)),
                        name: 'Carbohydrates',
                        current: intake.carbsG,
                        drv: prefs.dailyCarbLimitG.toDouble(),
                        unit: 'g',
                        isLimit: true,
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🥑', style: TextStyle(fontSize: 16)),
                        name: 'Fat',
                        current: intake.fatG,
                        drv: prefs.dailyFatTargetG.toDouble(),
                        unit: 'g',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🌾', style: TextStyle(fontSize: 16)),
                        name: 'Dietary Fiber',
                        current: intake.nutrientTotals.fiberG,
                        drv: NutrientDRV.fiberG,
                        unit: 'g',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Vitamins ──────────────────────────────────────────────
                const _SectionHeader('Vitamins'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _NutrientRow(
                        icon: const Text('🥕', style: TextStyle(fontSize: 16)),
                        name: 'Vitamin A',
                        current: intake.nutrientTotals.vitaminAUg,
                        drv: isFemale ? NutrientDRV.vitaminAUg_female : NutrientDRV.vitaminAUg_male,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🍊', style: TextStyle(fontSize: 16)),
                        name: 'Vitamin C',
                        current: intake.nutrientTotals.vitaminCMg,
                        drv: isFemale ? NutrientDRV.vitaminCMg_female : NutrientDRV.vitaminCMg_male,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('☀️', style: TextStyle(fontSize: 16)),
                        name: 'Vitamin D',
                        current: intake.nutrientTotals.vitaminDUg,
                        drv: NutrientDRV.vitaminDUg,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🌻', style: TextStyle(fontSize: 16)),
                        name: 'Vitamin E',
                        current: intake.nutrientTotals.vitaminEMg,
                        drv: NutrientDRV.vitaminEMg,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🥬', style: TextStyle(fontSize: 16)),
                        name: 'Vitamin K',
                        current: intake.nutrientTotals.vitaminKUg,
                        drv: isFemale ? NutrientDRV.vitaminKUg_female : NutrientDRV.vitaminKUg_male,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🫘', style: TextStyle(fontSize: 16)),
                        name: 'Folate (B9)',
                        current: intake.nutrientTotals.folateMcg,
                        drv: NutrientDRV.folateMcg,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: const Text('🥩', style: TextStyle(fontSize: 16)),
                        name: 'Vitamin B12',
                        current: intake.nutrientTotals.b12Mcg,
                        drv: NutrientDRV.b12Mcg,
                        unit: 'μg',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Minerals ──────────────────────────────────────────────
                const _SectionHeader('Minerals'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _NutrientRow(
                        icon: _ElementIcon('Ca', const Color(0xFFE5E4E2)),
                        name: 'Calcium',
                        current: intake.nutrientTotals.calciumMg,
                        drv: isFemale ? NutrientDRV.calciumMg_female : NutrientDRV.calciumMg_male,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Fe', const Color(0xFF7A7A78)),
                        name: 'Iron',
                        current: intake.nutrientTotals.ironMg,
                        drv: isFemale ? NutrientDRV.ironMg_female : NutrientDRV.ironMg_male,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Mg', const Color(0xFFDCDEDD)),
                        name: 'Magnesium',
                        current: intake.nutrientTotals.magnesiumMg,
                        drv: isFemale ? NutrientDRV.magnesiumMg_female : NutrientDRV.magnesiumMg_male,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('K', const Color(0xFFB5B7B5)),
                        name: 'Potassium',
                        current: intake.nutrientTotals.potassiumMg,
                        drv: isFemale ? NutrientDRV.potassiumMg_female : NutrientDRV.potassiumMg_male,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Na', const Color(0xFFC6C8C7)),
                        name: 'Sodium',
                        current: intake.nutrientTotals.sodiumMg,
                        drv: NutrientDRV.sodiumMaxMg,
                        unit: 'mg',
                        isLimit: true,
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Zn', const Color(0xFFBAC4C8)),
                        name: 'Zinc',
                        current: intake.nutrientTotals.zincMg,
                        drv: isFemale ? NutrientDRV.zincMg_female : NutrientDRV.zincMg_male,
                        unit: 'mg',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Disclaimer ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '* Vitamin and mineral values are estimated from food categories '
                    'using average nutrient densities (USDA FoodData Central). '
                    'For precise tracking, consult a registered dietitian.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.gray400,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}

// ── 7-zone color logic ────────────────────────────────────────────────────────
//
// For targets (isLimit = false):
//   <10%          → red    (severely deficient)
//   10% – 30%     → amber  (deficient)
//   30% – 60%     → orange (getting there)
//   60% – 110%    → green  (good / optimal)
//   110% – 130%   → orange (slightly over)
//   130% – 150%   → amber  (over)
//   >150%         → red    (too much)
//
// For limits (isLimit = true, e.g. sodium, carbs):
//   ≤70%          → green  (well under)
//   70% – 95%     → primary (approaching)
//   95% – 110%    → amber  (near limit)
//   >110%         → red    (over limit)

Color _nutrientBarColor(double pct, {
  required bool isLimit,
  required BuildContext context,
}) {
  if (isLimit) {
    if (pct > 1.10) return AppTheme.red500;
    if (pct > 0.95) return AppTheme.amber600;
    if (pct > 0.70) return context.primary500;
    return context.primary500; // well under limit — just use green
  }
  // Target nutrients
  if (pct < 0.10) return AppTheme.red500;
  if (pct < 0.30) return AppTheme.amber600;
  if (pct < 0.60) return Colors.orange.shade600;
  if (pct <= 1.10) return context.primary500; // green / optimal zone
  if (pct <= 1.30) return Colors.orange.shade600;
  if (pct <= 1.50) return AppTheme.amber600;
  return AppTheme.red500;
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.calories,
    required this.calorieGoal,
    required this.scanCount,
  });
  final int calories;
  final int calorieGoal;
  final int scanCount;

  @override
  Widget build(BuildContext context) {
    final pct = calorieGoal > 0 ? (calories / calorieGoal * 100).round() : 0;
    final pctFrac = calorieGoal > 0 ? calories / calorieGoal : 0.0;
    // 7-zone color for calories (not a hard limit, treat as target)
    final pctColor = _nutrientBarColor(pctFrac, isLimit: false, context: context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's Intake",
                    style: TextStyle(fontSize: 12, color: AppTheme.gray400),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$calories kcal',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gray900,
                    ),
                  ),
                  Text(
                    'of $calorieGoal kcal goal',
                    style: const TextStyle(fontSize: 12, color: AppTheme.gray400),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: pctColor,
                  ),
                ),
                Text(
                  '$scanCount scan${scanCount == 1 ? '' : 's'} today',
                  style: const TextStyle(fontSize: 11, color: AppTheme.gray400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.gray400,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── Divider ───────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 16, endIndent: 0);
}

// ── Nutrient row ──────────────────────────────────────────────────────────────

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.icon,
    required this.name,
    required this.current,
    required this.drv,
    required this.unit,
    this.isLimit = false,
  });

  final Widget icon;
  final String name;
  final double current;
  final double drv;
  final String unit;
  final bool isLimit;

  Color _barColor(double pct, BuildContext context) =>
      _nutrientBarColor(pct, isLimit: isLimit, context: context);

  String _fmt(double v) {
    if (v == 0) return '0';
    if (v < 10) return v.toStringAsFixed(1);
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final pct = drv > 0 ? (current / drv).clamp(0.0, 1.5) : 0.0;
    final displayPct = (pct * 100).round().clamp(0, 999);
    final barColor = _barColor(pct, context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 24, height: 24, child: Center(child: icon)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gray700,
                  ),
                ),
              ),
              Text(
                '${_fmt(current)} / ${_fmt(drv)} $unit',
                style: const TextStyle(fontSize: 11, color: AppTheme.gray400),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '$displayPct%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: AppTheme.gray100,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Element symbol icon (periodic-table style) ────────────────────────────────

class _ElementIcon extends StatelessWidget {
  const _ElementIcon(this.symbol, this.color);
  final String symbol;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: symbol.length > 2 ? 8 : 10,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}
