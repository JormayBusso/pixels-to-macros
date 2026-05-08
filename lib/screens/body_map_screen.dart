import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/nutrient_data.dart';
import '../models/scan_result.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Anatomy-style body map.
///
/// Renders a stylised human silhouette in a single CustomPainter and tints
/// each organ region (brain, heart, lungs, liver, gut, bones, muscles, skin,
/// blood, eyes, immune nodes) with a colour derived from how well today's
/// intake of the relevant nutrients meets the daily reference values (DRVs).
///
/// Replaces the previous circle-overlay implementation: the body parts
/// themselves now light up red → orange → green as nutrient sufficiency
/// improves, which is what the user asked for ("the bones inside the greyed-
/// out man become green if someone eats enough calcium").
class BodyMapScreen extends ConsumerStatefulWidget {
  const BodyMapScreen({super.key});

  @override
  ConsumerState<BodyMapScreen> createState() => _BodyMapScreenState();
}

class _BodyMapScreenState extends ConsumerState<BodyMapScreen> {
  _OrganRegion? _selected;

  // Organ positions as fractions of the body_map.jpeg (1024×1536).
  // Each entry: (cx, cy) = normalised centre; size = tap-circle diameter in px.
  static const _organLayout = <_OrganRegion, ({double cx, double cy, double size})>{
    _OrganRegion.brain:       (cx: 0.500, cy: 0.080, size: 50),
    _OrganRegion.eyes:        (cx: 0.500, cy: 0.105, size: 36),
    _OrganRegion.lungs:       (cx: 0.500, cy: 0.265, size: 56),
    _OrganRegion.heart:       (cx: 0.440, cy: 0.260, size: 38),
    _OrganRegion.liver:       (cx: 0.570, cy: 0.330, size: 42),
    _OrganRegion.stomach:     (cx: 0.430, cy: 0.350, size: 38),
    _OrganRegion.intestines:  (cx: 0.500, cy: 0.440, size: 50),
    _OrganRegion.kidneys:     (cx: 0.500, cy: 0.380, size: 38),
    _OrganRegion.bones:       (cx: 0.500, cy: 0.295, size: 32),
    _OrganRegion.muscles:     (cx: 0.240, cy: 0.300, size: 38),
    _OrganRegion.skin:        (cx: 0.740, cy: 0.200, size: 32),
    _OrganRegion.blood:       (cx: 0.460, cy: 0.245, size: 30),
  };

  // The SVG viewport is 474 × 711.  Given the container size, compute the
  // rendered image rect (BoxFit.contain centres the image).
  static ({double left, double top, double width, double height})
      _imageRect(double cw, double ch) {
    const imgW = 474.0, imgH = 711.0;
    final scale = (cw / imgW).compareTo(ch / imgH) <= 0 ? cw / imgW : ch / imgH;
    final rw = imgW * scale, rh = imgH * scale;
    return (left: (cw - rw) / 2, top: (ch - rh) / 2, width: rw, height: rh);
  }

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final scores = _computeOrganScores(intake.nutrientTotals, isMale);
    final foods = intake.foods;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Body Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How this works',
            onPressed: _showInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cw = constraints.maxWidth;
                final ch = constraints.maxHeight;
                final img = _imageRect(cw, ch);

                // Build tappable organ circles
                final circles = _organLayout.entries.map((e) {
                  final region = e.key;
                  final layout = e.value;
                  final score = scores[region]?.score ?? 0;
                  final color = _scoreColor(score);
                  final isHi = _selected == region;
                  final cx = img.left + layout.cx * img.width;
                  final cy = img.top  + layout.cy * img.height;
                  final d  = layout.size;

                  return Positioned(
                    left: cx - d / 2,
                    top:  cy - d / 2,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selected = region);
                        _showDetail(region, scores[region]!, foods, isMale);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: d,
                        height: d,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                              color: color.withOpacity(isHi ? 0.40 : 0.22),
                          border: Border.all(
                            color: color,
                            width: isHi ? 3.0 : 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                                  color: color.withOpacity(isHi ? 0.50 : 0.28),
                              blurRadius: isHi ? 16 : 10,
                              spreadRadius: isHi ? 4 : 2,
                            ),
                          ],
                        ),
                            child: Icon(
                              region.icon,
                              size: d * 0.45,
                              color: Colors.white.withOpacity(isHi ? 0.95 : 0.78),
                            ),
                      ),
                    ),
                  );
                }).toList();

                return Stack(
                  children: [
                    // Body SVG
                    Positioned.fill(
                      child: SvgPicture.asset(
                        'assets/body_map_svg.svg',
                        fit: BoxFit.contain,
                      ),
                    ),
                    // Organ tap circles
                    ...circles,
                  ],
                );
              },
            ),
          ),
          _Legend(),
        ],
      ),
    );
  }

  void _showDetail(
    _OrganRegion region,
    _OrganScore score,
    List<DetectedFood> foods,
    bool isMale,
  ) {
    final colorScheme = _scoreColor(score.score);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.withOpacity(0.18),
                    border: Border.all(color: colorScheme, width: 2),
                  ),
                  alignment: Alignment.center,
                      child: Icon(region.icon, color: colorScheme),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        region.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${(score.score * 100).round()}% nourished today',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              region.explanation,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.gray600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Key nutrients today',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ...score.nutrients.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        n.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.gray600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: n.ratio.clamp(0.0, 1.0),
                          backgroundColor: AppTheme.gray100,
                          valueColor: AlwaysStoppedAnimation(
                            _scoreColor(n.ratio),
                          ),
                          minHeight: 7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${(n.ratio * 100).round().clamp(0, 999)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Top foods affecting this body part',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<_FoodContribution>>(
              future: _computeTopFoodsForRegion(
                region: region,
                foods: foods,
                isMale: isMale,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Calculating food impact...',
                      style: TextStyle(fontSize: 12, color: AppTheme.gray600),
                    ),
                  );
                }

                final items = snapshot.data ?? const <_FoodContribution>[];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No food contributors available yet. Log meals to see which foods drive this color.',
                      style: TextStyle(fontSize: 12, color: AppTheme.gray600),
                    ),
                  );
                }

                return Column(
                  children: items.map((f) {
                    final pct = (f.impact * 100).clamp(0, 999).round();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              f.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${f.kcal.round()} kcal',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.gray600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _scoreColor(f.impact).withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$pct%',
                              style: TextStyle(
                                fontSize: 11,
                                color: _scoreColor(f.impact),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('How the Body Map works'),
        content: const Text(
          'Each organ lights up based on how well today\'s food covers the '
          'nutrients that organ depends on, compared to your daily '
          'reference value (DRV).\n\n'
          '• Grey – not enough data yet today\n'
          '• Red / Orange – well below DRV\n'
          '• Yellow – getting close\n'
          '• Green – DRV met\n'
          '• Deep red – far above safe upper level\n\n'
          'Tap any organ to see the exact nutrients driving its score.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Score model ─────────────────────────

enum _OrganRegion {
  brain,
  eyes,
  lungs,
  heart,
  liver,
  stomach,
  intestines,
  kidneys,
  bones,
  muscles,
  skin,
  blood,
}

extension on _OrganRegion {
  String get label => switch (this) {
        _OrganRegion.brain => 'Brain',
        _OrganRegion.eyes => 'Eyes',
        _OrganRegion.lungs => 'Lungs',
        _OrganRegion.heart => 'Heart',
        _OrganRegion.liver => 'Liver',
        _OrganRegion.stomach => 'Stomach',
        _OrganRegion.intestines => 'Intestines',
        _OrganRegion.kidneys => 'Kidneys',
        _OrganRegion.bones => 'Bones',
        _OrganRegion.muscles => 'Muscles',
        _OrganRegion.skin => 'Skin',
        _OrganRegion.blood => 'Blood',
      };

  IconData get icon => switch (this) {
        _OrganRegion.brain => Icons.psychology_outlined,
        _OrganRegion.eyes => Icons.visibility_outlined,
        _OrganRegion.lungs => Icons.air,
        _OrganRegion.heart => Icons.favorite_border,
        _OrganRegion.liver => Icons.local_drink_outlined,
        _OrganRegion.stomach => Icons.restaurant_outlined,
        _OrganRegion.intestines => Icons.swap_calls,
        _OrganRegion.kidneys => Icons.water_drop_outlined,
        _OrganRegion.bones => Icons.accessibility_new,
        _OrganRegion.muscles => Icons.fitness_center,
        _OrganRegion.skin => Icons.face_outlined,
        _OrganRegion.blood => Icons.bloodtype_outlined,
      };

  String get explanation => switch (this) {
        _OrganRegion.brain =>
          'B12 and folate keep nerves firing. Iron carries oxygen to brain tissue and supports focus and memory.',
        _OrganRegion.eyes =>
          'Vitamin A is essential for night vision. Vitamin C and zinc protect against age-related macular degeneration.',
        _OrganRegion.lungs =>
          'Antioxidants like vitamin C, E and A defend lung tissue against oxidative stress and inflammation.',
        _OrganRegion.heart =>
          'Potassium regulates heartbeat, magnesium relaxes blood vessels, and vitamin E protects cells from oxidative damage.',
        _OrganRegion.liver =>
          'The liver stores fat-soluble vitamins. Vitamin K supports clotting; B12 is processed and stored here.',
        _OrganRegion.stomach =>
          'Zinc maintains the stomach lining. B-vitamins support the production of digestive enzymes.',
        _OrganRegion.intestines =>
          'Dietary fiber feeds healthy gut bacteria. Magnesium and potassium keep intestinal muscles contracting smoothly.',
        _OrganRegion.kidneys =>
          'Potassium and magnesium balance helps the kidneys filter waste; staying hydrated reduces kidney load.',
        _OrganRegion.bones =>
          'Calcium builds bone density. Vitamin D drives calcium absorption. Vitamin K guides calcium into bone, not arteries.',
        _OrganRegion.muscles =>
          'Magnesium and potassium prevent cramps. Calcium triggers contraction. Adequate protein repairs muscle fibers.',
        _OrganRegion.skin =>
          'Vitamin C builds collagen, vitamin E shields against UV damage, and zinc accelerates wound healing.',
        _OrganRegion.blood =>
          'Iron is the core of haemoglobin. B12 and folate are required to produce healthy red blood cells.',
      };
}

class _OrganScore {
  const _OrganScore(this.score, this.nutrients);
  final double score;
  final List<_NutrientRatio> nutrients;
}

class _NutrientRatio {
  const _NutrientRatio(this.name, this.ratio);
  final String name;
  final double ratio;
}

class _FoodContribution {
  const _FoodContribution({
    required this.label,
    required this.impact,
    required this.kcal,
  });

  final String label;
  final double impact;
  final double kcal;
}

class _FoodContributionAcc {
  _FoodContributionAcc(this.label);
  final String label;
  double impactTimesKcal = 0;
  double kcal = 0;
}

List<String> _nutrientNamesForRegion(_OrganRegion region) {
  return switch (region) {
    _OrganRegion.brain => ['B12', 'Folate', 'Iron'],
    _OrganRegion.eyes => ['Vitamin A', 'Vitamin C', 'Zinc'],
    _OrganRegion.lungs => ['Vitamin C', 'Vitamin E', 'Vitamin A'],
    _OrganRegion.heart => ['Potassium', 'Magnesium', 'Vitamin E'],
    _OrganRegion.liver => ['Vitamin E', 'Vitamin K', 'B12'],
    _OrganRegion.stomach => ['Zinc', 'B12'],
    _OrganRegion.intestines => ['Fiber', 'Magnesium', 'Potassium'],
    _OrganRegion.kidneys => ['Potassium', 'Magnesium'],
    _OrganRegion.bones => ['Calcium', 'Vitamin D', 'Vitamin K'],
    _OrganRegion.muscles => ['Magnesium', 'Potassium', 'Calcium'],
    _OrganRegion.skin => ['Vitamin C', 'Vitamin E', 'Zinc'],
    _OrganRegion.blood => ['Iron', 'B12', 'Folate'],
  };
}

double _ratioForNutrientName(String name, NutrientTotals totals, bool isMale) {
  double r(double current, double drv) => drv > 0 ? current / drv : 0;
  return switch (name) {
    'Vitamin A' => r(
      totals.vitaminAUg,
      isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female,
    ),
    'Vitamin C' => r(
      totals.vitaminCMg,
      isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female,
    ),
    'Vitamin D' => r(totals.vitaminDUg, NutrientDRV.vitaminDUg),
    'Vitamin E' => r(totals.vitaminEMg, NutrientDRV.vitaminEMg),
    'Vitamin K' => r(
      totals.vitaminKUg,
      isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female,
    ),
    'Folate' => r(totals.folateMcg, NutrientDRV.folateMcg),
    'B12' => r(totals.b12Mcg, NutrientDRV.b12Mcg),
    'Calcium' => r(
      totals.calciumMg,
      isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female,
    ),
    'Iron' => r(
      totals.ironMg,
      isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female,
    ),
    'Magnesium' => r(
      totals.magnesiumMg,
      isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female,
    ),
    'Potassium' => r(
      totals.potassiumMg,
      isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female,
    ),
    'Zinc' => r(
      totals.zincMg,
      isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female,
    ),
    'Fiber' => r(totals.fiberG, NutrientDRV.fiberG),
    _ => 0,
  };
}

Future<List<_FoodContribution>> _computeTopFoodsForRegion({
  required _OrganRegion region,
  required List<DetectedFood> foods,
  required bool isMale,
}) async {
  if (foods.isEmpty) return const <_FoodContribution>[];

  final keys = _nutrientNamesForRegion(region);
  final byLabel = <String, _FoodContributionAcc>{};

  for (final food in foods) {
    var lookupLabel = food.label;
    const aliases = {'chicken duck': 'chicken'};
    final alias = aliases[lookupLabel.toLowerCase()];
    if (alias != null) lookupLabel = alias;

    final foodData = await DatabaseService.instance.getFoodByLabel(lookupLabel);
    if (foodData == null || foodData.kcalPer100g <= 0) continue;

    final kcal = (food.caloriesMin + food.caloriesMax) / 2;
    final weightG = kcal / (foodData.kcalPer100g / 100);
    if (kcal <= 0 || weightG <= 0) continue;

    final nt = nutrientsForFood(food: foodData, weightG: weightG);
    final ratios = keys.map((k) => _ratioForNutrientName(k, nt, isMale)).toList();
    final impact = ratios.isEmpty
        ? 0.0
        : ratios.reduce((a, b) => a + b) / ratios.length;

    if (impact <= 0) continue;

    final acc = byLabel.putIfAbsent(food.label, () => _FoodContributionAcc(food.label));
    acc.impactTimesKcal += impact * kcal;
    acc.kcal += kcal;
  }

  final out = byLabel.values
      .where((a) => a.kcal > 0)
      .map(
        (a) => _FoodContribution(
          label: a.label,
          impact: (a.impactTimesKcal / a.kcal).clamp(0.0, 2.0),
          kcal: a.kcal,
        ),
      )
      .toList()
    ..sort((a, b) => b.impact.compareTo(a.impact));

  return out.take(5).toList();
}

Map<_OrganRegion, _OrganScore> _computeOrganScores(
  NutrientTotals totals,
  bool isMale,
) {
  double r(double current, double drv) => drv > 0 ? current / drv : 0;
  double avg(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  final vitA = r(totals.vitaminAUg,
      isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female);
  final vitC = r(totals.vitaminCMg,
      isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female);
  final vitD = r(totals.vitaminDUg, NutrientDRV.vitaminDUg);
  final vitE = r(totals.vitaminEMg, NutrientDRV.vitaminEMg);
  final vitK = r(totals.vitaminKUg,
      isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female);
  final folate = r(totals.folateMcg, NutrientDRV.folateMcg);
  final b12 = r(totals.b12Mcg, NutrientDRV.b12Mcg);
  final calcium = r(totals.calciumMg,
      isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female);
  final iron = r(totals.ironMg,
      isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female);
  final mag = r(totals.magnesiumMg,
      isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female);
  final potassium = r(totals.potassiumMg,
      isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female);
  final zinc = r(totals.zincMg,
      isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female);
  final fiber = r(totals.fiberG, NutrientDRV.fiberG);

  return {
    _OrganRegion.brain: _OrganScore(
      avg([b12, folate, iron]).clamp(0.0, 2.0),
      [
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
        _NutrientRatio('Iron', iron),
      ],
    ),
    _OrganRegion.eyes: _OrganScore(
      avg([vitA, vitC, zinc]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Vitamin A', vitA),
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _OrganRegion.lungs: _OrganScore(
      avg([vitC, vitE, vitA]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin A', vitA),
      ],
    ),
    _OrganRegion.heart: _OrganScore(
      avg([potassium, mag, vitE]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Vitamin E', vitE),
      ],
    ),
    _OrganRegion.liver: _OrganScore(
      avg([vitE, vitK, b12]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin K', vitK),
        _NutrientRatio('B12', b12),
      ],
    ),
    _OrganRegion.stomach: _OrganScore(
      avg([zinc, b12]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Zinc', zinc),
        _NutrientRatio('B12', b12),
      ],
    ),
    _OrganRegion.intestines: _OrganScore(
      avg([fiber, mag, potassium]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Fiber', fiber),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
      ],
    ),
    _OrganRegion.kidneys: _OrganScore(
      avg([potassium, mag]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Magnesium', mag),
      ],
    ),
    _OrganRegion.bones: _OrganScore(
      avg([calcium, vitD, vitK]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Calcium', calcium),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Vitamin K', vitK),
      ],
    ),
    _OrganRegion.muscles: _OrganScore(
      avg([mag, potassium, calcium]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Calcium', calcium),
      ],
    ),
    _OrganRegion.skin: _OrganScore(
      avg([vitC, vitE, zinc]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _OrganRegion.blood: _OrganScore(
      avg([iron, b12, folate]).clamp(0.0, 2.0),
      [
        _NutrientRatio('Iron', iron),
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
      ],
    ),
  };
}

/// Maps a nutrient sufficiency score to a colour.
///
/// Under-intake (0 → 1.0): red → orange → yellow → green
/// Over-intake  (1.0 → 2.0+): green → yellow → orange → red
///
/// score = 0   → grey  (no data logged yet today)
/// score = 1.0 → green (daily goal met)
/// score ≥ 2.0 → red   (significantly over safe upper level)
Color _scoreColor(double score) {
  if (score <= 0) return const Color(0xFFB0BEC5); // grey: no data

  const red    = Color(0xFFFF3B30);
  const orange = Color(0xFFFF9500);
  const yellow = Color(0xFFFFCC00);
  const green  = Color(0xFF34C759);

  if (score <= 1.0) {
    // Under-intake: red → orange → yellow → green
    if (score < 0.33) {
      return Color.lerp(red,    orange, score / 0.33)!;
    } else if (score < 0.66) {
      return Color.lerp(orange, yellow, (score - 0.33) / 0.33)!;
    } else {
      return Color.lerp(yellow, green,  (score - 0.66) / 0.34)!;
    }
  }

  // Over-intake: green → yellow → orange → red
  final t = ((score - 1.0) / 1.0).clamp(0.0, 1.0);
  if (t < 0.33) {
    return Color.lerp(green,  yellow, t / 0.33)!;
  } else if (t < 0.66) {
    return Color.lerp(yellow, orange, (t - 0.33) / 0.33)!;
  } else {
    return Color.lerp(orange, red,    (t - 0.66) / 0.34)!;
  }
}

// ───────────────────────── Legend ─────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gray100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          _LegendDot(color: Color(0xFFB0BEC5), label: 'No data'),
          _LegendDot(color: Color(0xFFFF3B30), label: 'Low'),
          _LegendDot(color: Color(0xFFFF9500), label: 'Fair'),
          _LegendDot(color: Color(0xFFFFCC00), label: 'Good'),
          _LegendDot(color: Color(0xFF34C759), label: 'Goal ✓'),
          _LegendDot(color: Color(0xFFFF3B30), label: 'Over!'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.gray600),
        ),
      ],
    );
  }
}
