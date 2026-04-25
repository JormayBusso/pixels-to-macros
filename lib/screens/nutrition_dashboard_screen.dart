import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
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
                        icon: _ElementIcon('A', const Color(0xFFFF8C00)),
                        name: 'Vitamin A',
                        current: intake.nutrientTotals.vitaminAUg,
                        drv: NutrientDRV.vitaminAUg,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('C', const Color(0xFFFFA500)),
                        name: 'Vitamin C',
                        current: intake.nutrientTotals.vitaminCMg,
                        drv: NutrientDRV.vitaminCMg,
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
                        icon: _ElementIcon('E', const Color(0xFF4CAF50)),
                        name: 'Vitamin E',
                        current: intake.nutrientTotals.vitaminEMg,
                        drv: NutrientDRV.vitaminEMg,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('K', const Color(0xFF2E7D32)),
                        name: 'Vitamin K',
                        current: intake.nutrientTotals.vitaminKUg,
                        drv: NutrientDRV.vitaminKUg,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('B9', const Color(0xFF795548)),
                        name: 'Folate (B9)',
                        current: intake.nutrientTotals.folateMcg,
                        drv: NutrientDRV.folateMcg,
                        unit: 'μg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('B12', const Color(0xFFD32F2F)),
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
                        icon: _ElementIcon('Ca', const Color(0xFF90CAF9)),
                        name: 'Calcium',
                        current: intake.nutrientTotals.calciumMg,
                        drv: NutrientDRV.calciumMg,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Fe', const Color(0xFFB71C1C)),
                        name: 'Iron',
                        current: intake.nutrientTotals.ironMg,
                        drv: NutrientDRV.ironMg,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Mg', const Color(0xFF7B1FA2)),
                        name: 'Magnesium',
                        current: intake.nutrientTotals.magnesiumMg,
                        drv: NutrientDRV.magnesiumMg,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('K', const Color(0xFFE65100)),
                        name: 'Potassium',
                        current: intake.nutrientTotals.potassiumMg,
                        drv: NutrientDRV.potassiumMg,
                        unit: 'mg',
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Na', const Color(0xFF546E7A)),
                        name: 'Sodium',
                        current: intake.nutrientTotals.sodiumMg,
                        drv: NutrientDRV.sodiumMaxMg,
                        unit: 'mg',
                        isLimit: true,
                      ),
                      const _Divider(),
                      _NutrientRow(
                        icon: _ElementIcon('Zn', const Color(0xFF607D8B)),
                        name: 'Zinc',
                        current: intake.nutrientTotals.zincMg,
                        drv: NutrientDRV.zincMg,
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
    final pctColor = pct > 110
        ? AppTheme.red500
        : pct >= 80
            ? context.primary600
            : AppTheme.amber500;

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

  Color _barColor(double pct, BuildContext context) {
    if (isLimit) {
      if (pct > 1.0) return AppTheme.red500;
      if (pct > 0.7) return AppTheme.amber600;
      return context.primary500;
    }
    if (pct < 0.30) return AppTheme.red500;
    if (pct < 0.70) return AppTheme.amber600;
    return context.primary500;
  }

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
