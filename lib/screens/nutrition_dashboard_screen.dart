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

// ── Nutrient info data ────────────────────────────────────────────────────────

class _NutrientInfo {
  const _NutrientInfo({required this.description, required this.topFoods});
  final String description;
  // (food name, amount with unit)
  final List<(String, String)> topFoods;
}

const _kNutrientInfo = <String, _NutrientInfo>{
  'Calories': _NutrientInfo(
    description: 'Energy currency of the body — powers every heartbeat, thought, and movement. Balancing intake with daily expenditure is the foundation of healthy weight management.',
    topFoods: [
      ('Oils (coconut, olive)', '~900 kcal'),
      ('Butter / ghee', '~720 kcal'),
      ('Macadamia nuts', '~718 kcal'),
      ('Dark chocolate (85%)', '~598 kcal'),
      ('Cheddar cheese', '~400 kcal'),
    ],
  ),
  'Protein': _NutrientInfo(
    description: 'Builds and repairs muscles, skin, enzymes, and hormones. Essential for immune function and satiety — helps keep you feeling full longer after meals.',
    topFoods: [
      ('Spirulina (dried)', '57 g'),
      ('Parmesan cheese', '38 g'),
      ('Hemp seeds', '32 g'),
      ('Chicken breast', '31 g'),
      ('Canned tuna', '30 g'),
    ],
  ),
  'Carbohydrates': _NutrientInfo(
    description: 'Primary fuel for the brain and muscles. Complex carbs provide steady energy and fibre; refined carbs cause rapid blood sugar spikes. Whole grains and legumes are the best choices.',
    topFoods: [
      ('Cornflakes (dry)', '84 g'),
      ('White rice (dry)', '80 g'),
      ('Plain flour', '76 g'),
      ('Pasta (dry)', '75 g'),
      ('Dates (dried)', '75 g'),
    ],
  ),
  'Fat': _NutrientInfo(
    description: 'Needed to absorb fat-soluble vitamins (A, D, E, K), produce hormones, and protect organs. Unsaturated fats from avocado, olive oil, and nuts actively support heart and brain health.',
    topFoods: [
      ('Coconut oil / olive oil', '100 g'),
      ('Butter / ghee', '81 g'),
      ('Macadamia nuts', '76 g'),
      ('Almonds', '50 g'),
      ('Cheddar cheese', '33 g'),
    ],
  ),
  'Dietary Fiber': _NutrientInfo(
    description: 'Feeds beneficial gut bacteria, slows sugar absorption, lowers LDL cholesterol, and keeps bowels regular. High-fibre diets reduce the risk of type 2 diabetes and colon cancer.',
    topFoods: [
      ('Wheat bran', '43 g'),
      ('Chia seeds', '34 g'),
      ('Flaxseed (ground)', '27 g'),
      ('Black beans (dried)', '16 g'),
      ('Avocado', '7 g'),
    ],
  ),
  'Vitamin A': _NutrientInfo(
    description: 'Essential for vision (especially night vision), immune defense, and skin-cell renewal. Also supports healthy bone growth and reproductive function. Retinol in animal foods; beta-carotene in plants.',
    topFoods: [
      ('Beef liver', '9 442 μg'),
      ('Sweet potato', '961 μg'),
      ('Carrots', '835 μg'),
      ('Spinach (raw)', '469 μg'),
      ('Kale', '241 μg'),
    ],
  ),
  'Vitamin C': _NutrientInfo(
    description: 'Potent antioxidant that strengthens immunity, synthesises collagen for skin and joints, and significantly enhances iron absorption from plant-based foods.',
    topFoods: [
      ('Guava', '228 mg'),
      ('Bell pepper (red)', '183 mg'),
      ('Kiwi', '93 mg'),
      ('Broccoli', '89 mg'),
      ('Papaya', '62 mg'),
    ],
  ),
  'Vitamin D': _NutrientInfo(
    description: 'Regulates calcium and phosphorus absorption for strong bones and teeth. Also supports immune function, mood, and muscle health. Sunlight is the primary source; dietary sources are scarce.',
    topFoods: [
      ('Cod liver oil', '250 μg'),
      ('Pickled herring', '27 μg'),
      ('Salmon (cooked)', '16 μg'),
      ('Mackerel (cooked)', '16 μg'),
      ('Egg yolk', '5 μg'),
    ],
  ),
  'Vitamin E': _NutrientInfo(
    description: 'Fat-soluble antioxidant that protects cell membranes from oxidative stress. Supports immune function, skin integrity, and healthy eyes. Works synergistically with vitamin C.',
    topFoods: [
      ('Wheat germ oil', '149 mg'),
      ('Sunflower seeds', '35 mg'),
      ('Almonds', '26 mg'),
      ('Hazelnuts', '15 mg'),
      ('Avocado', '2 mg'),
    ],
  ),
  'Vitamin K': _NutrientInfo(
    description: 'Essential for blood clotting — stops wounds from bleeding. Also activates proteins that direct calcium into bones and keep it out of arteries, benefiting both bone density and heart health.',
    topFoods: [
      ('Fresh parsley', '1 640 μg'),
      ('Kale (raw)', '817 μg'),
      ('Spinach (raw)', '483 μg'),
      ('Collard greens', '389 μg'),
      ('Broccoli', '102 μg'),
    ],
  ),
  'Folate (B9)': _NutrientInfo(
    description: 'Critical for DNA synthesis and cell division — especially during pregnancy to prevent neural tube defects. Also supports red blood cell formation and lowers homocysteine levels.',
    topFoods: [
      ('Chicken liver', '578 μg'),
      ('Edamame', '311 μg'),
      ('Lentils (cooked)', '181 μg'),
      ('Asparagus', '149 μg'),
      ('Spinach (raw)', '146 μg'),
    ],
  ),
  'Vitamin B12': _NutrientInfo(
    description: 'Required for healthy nerve function, red blood cell production, and DNA synthesis. Found almost exclusively in animal products — vegans and vegetarians should supplement regularly.',
    topFoods: [
      ('Clams (cooked)', '98 μg'),
      ('Beef liver', '83 μg'),
      ('Mussels', '12 μg'),
      ('Mackerel', '8 μg'),
      ('Salmon (cooked)', '4 μg'),
    ],
  ),
  'Calcium': _NutrientInfo(
    description: 'The primary mineral in bones and teeth, providing structural strength. Also regulates muscle contractions (including the heartbeat), nerve signals, and blood clotting.',
    topFoods: [
      ('Parmesan cheese', '1 184 mg'),
      ('Sesame seeds (whole)', '975 mg'),
      ('Sardines (with bones)', '382 mg'),
      ('Kale (raw)', '150 mg'),
      ("Cow's milk", '125 mg'),
    ],
  ),
  'Iron': _NutrientInfo(
    description: 'Carries oxygen in haemoglobin (red blood cells) and myoglobin (muscles). Deficiency causes fatigue, weakness, and anaemia. Vitamin C consumed alongside iron-rich foods significantly boosts absorption.',
    topFoods: [
      ('Spirulina (dried)', '28 mg'),
      ('Chicken liver', '13 mg'),
      ('Pumpkin seeds', '8 mg'),
      ('Lentils (cooked)', '6 mg'),
      ('Spinach (cooked)', '4 mg'),
    ],
  ),
  'Magnesium': _NutrientInfo(
    description: 'Involved in over 300 enzyme reactions — energy production, muscle and nerve function, blood sugar regulation, and bone density. Most people consume less than the recommended amount.',
    topFoods: [
      ('Pumpkin seeds', '592 mg'),
      ('Cocoa powder (raw)', '499 mg'),
      ('Hemp seeds', '483 mg'),
      ('Almonds', '270 mg'),
      ('Spinach (cooked)', '79 mg'),
    ],
  ),
  'Potassium': _NutrientInfo(
    description: 'Maintains fluid and electrolyte balance, supports nerve transmission and muscle contractions, and directly counteracts the blood-pressure-raising effect of sodium.',
    topFoods: [
      ('Dried apricots', '1 162 mg'),
      ('Pistachios', '1 025 mg'),
      ('White beans (cooked)', '561 mg'),
      ('Spinach (cooked)', '558 mg'),
      ('Avocado', '485 mg'),
    ],
  ),
  'Sodium': _NutrientInfo(
    description: 'Essential for fluid balance and nerve function, but excess intake raises blood pressure and increases cardiovascular and kidney disease risk. Most sodium is hidden in processed and packaged foods.',
    topFoods: [
      ('Table salt', '38 758 mg'),
      ('Soy sauce', '5 765 mg'),
      ('Processed cheese', '1 500 mg'),
      ('Salted crackers', '830 mg'),
      ('Commercial bread', '490 mg'),
    ],
  ),
  'Zinc': _NutrientInfo(
    description: 'Supports immune function, wound healing, protein synthesis, and the senses of taste and smell. Also crucial for testosterone production, healthy growth during adolescence, and DNA repair.',
    topFoods: [
      ('Oysters (cooked)', '78 mg'),
      ('Hemp seeds', '10 mg'),
      ('Beef liver', '9 mg'),
      ('Pumpkin seeds', '7 mg'),
      ('Beef (cooked)', '5 mg'),
    ],
  ),
};

// ── Nutrient row ──────────────────────────────────────────────────────────────

class _NutrientRow extends StatefulWidget {
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

  @override
  State<_NutrientRow> createState() => _NutrientRowState();
}

class _NutrientRowState extends State<_NutrientRow> {
  bool _expanded = false;

  Color _barColor(double pct, BuildContext context) =>
      _nutrientBarColor(pct, isLimit: widget.isLimit, context: context);

  String _fmt(double v) {
    if (v == 0) return '0';
    if (v < 10) return v.toStringAsFixed(1);
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.drv > 0 ? (widget.current / widget.drv).clamp(0.0, 1.5) : 0.0;
    final displayPct = (pct * 100).round().clamp(0, 999);
    final barColor = _barColor(pct, context);
    final info = _kNutrientInfo[widget.name];

    return InkWell(
      onTap: info != null ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 24, height: 24, child: Center(child: widget.icon)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.gray700,
                    ),
                  ),
                ),
                Text(
                  '${_fmt(widget.current)} / ${_fmt(widget.drv)} ${widget.unit}',
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
                if (info != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppTheme.gray400,
                  ),
                ],
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
            // Expandable detail panel
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _expanded && info != null
                  ? _NutrientDetailPanel(info: info)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NutrientDetailPanel extends StatelessWidget {
  const _NutrientDetailPanel({required this.info});
  final _NutrientInfo info;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.primary50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.primary200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.description,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.gray600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'TOP 5 SOURCES (per 100 g)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.primary600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            ...info.topFoods.map(
              ((String food, String amount) f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text('• ',
                        style: TextStyle(
                            color: context.primary500, fontSize: 12)),
                    Expanded(
                      child: Text(
                        f.$1,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.gray700),
                      ),
                    ),
                    Text(
                      f.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.primary600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
