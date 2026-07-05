import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/food_group.dart';
import '../providers/food_group_provider.dart';
import '../theme/app_theme.dart';

/// Daily / weekly food-group balance: how the user's logged fruit, vegetables,
/// protein, dairy and grains compare to recommended servings.
class FoodGroupScreen extends ConsumerStatefulWidget {
  const FoodGroupScreen({super.key});

  @override
  ConsumerState<FoodGroupScreen> createState() => _FoodGroupScreenState();
}

class _FoodGroupScreenState extends ConsumerState<FoodGroupScreen> {
  bool _weekly = false;

  static const _emoji = {
    FoodGroup.fruit: '🍎',
    FoodGroup.vegetables: '🥦',
    FoodGroup.protein: '🍗',
    FoodGroup.dairy: '🥛',
    FoodGroup.grains: '🌾',
  };

  static const _color = {
    FoodGroup.fruit: Color(0xFFEF5350),
    FoodGroup.vegetables: Color(0xFF66BB6A),
    FoodGroup.protein: Color(0xFFEC407A),
    FoodGroup.dairy: Color(0xFF42A5F5),
    FoodGroup.grains: Color(0xFFFFB300),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(foodGroupProvider.notifier).load();
    });
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final balance = ref.watch(foodGroupProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.foodGroupBalanceTitle)),
      body: balance.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l10n.foodGroupBalanceSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: context.appMutedTextColor,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: false, label: Text(l10n.periodToday)),
                      ButtonSegment(
                          value: true, label: Text(l10n.periodThisWeek)),
                    ],
                    selected: {_weekly},
                    onSelectionChanged: (s) =>
                        setState(() => _weekly = s.first),
                  ),
                ),
                const SizedBox(height: 20),
                ...FoodGroup.values.map((g) {
                  final recommendedDaily = kRecommendedDailyServings[g]!;
                  final target =
                      _weekly ? recommendedDaily * 7 : recommendedDaily;
                  final current =
                      _weekly ? balance.weekly(g) : balance.daily(g);
                  final pct = target > 0
                      ? (current / target).clamp(0.0, 1.0)
                      : 0.0;
                  final reached = current + 0.05 >= target;
                  final color = _color[g]!;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_emoji[g]!,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.foodGroupName(g.name),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: context.appTextColor,
                                ),
                              ),
                            ),
                            if (reached)
                              const Icon(Icons.check_circle,
                                  size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(
                              l10n.servingsProgress(
                                  _fmt(current), _fmt(target)),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: context.appMutedTextColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 9,
                            backgroundColor: context.appSubtleFillColor,
                            color: reached ? Colors.green : color,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Text(
                  l10n.foodGroupGuidanceNote,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: context.appMutedTextColor,
                  ),
                ),
              ],
            ),
    );
  }
}
