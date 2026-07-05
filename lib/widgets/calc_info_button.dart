import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_localizations.dart';
import '../models/calc_info.dart';

/// Builds the localised [CalcInfo] for a given calculation feature.
CalcInfo calcInfoFor(BuildContext context, CalcInfoId id) {
  final l10n = AppLocalizations.of(context);
  switch (id) {
    case CalcInfoId.dailyCalories:
      return CalcInfo(
        id: id,
        title: l10n.calcCaloriesTitle,
        explanation: l10n.calcCaloriesExplain,
        legitimacy: l10n.calcCaloriesWhy,
        sourceLabel:
            'European Food Safety Authority (EFSA) — Dietary Reference Values for energy',
      );
    case CalcInfoId.macroTargets:
      return CalcInfo(
        id: id,
        title: l10n.calcMacrosTitle,
        explanation: l10n.calcMacrosExplain,
        legitimacy: l10n.calcMacrosWhy,
        sourceLabel:
            'European Food Safety Authority (EFSA) — Dietary Reference Values for macronutrients',
      );
    case CalcInfoId.microTargets:
      return CalcInfo(
        id: id,
        title: l10n.calcMicroTitle,
        explanation: l10n.calcMicroExplain,
        legitimacy: l10n.calcMicroWhy,
        sourceLabel:
            'European Food Safety Authority (EFSA) — Dietary Reference Values for vitamins & minerals',
      );
    case CalcInfoId.plateScore:
      return CalcInfo(
        id: id,
        title: l10n.calcPlateTitle,
        explanation: l10n.calcPlateExplain,
        legitimacy: l10n.calcPlateWhy,
        sourceLabel: 'European Commission — Food-Based Dietary Guidelines',
      );
    case CalcInfoId.bodyMapScore:
      return CalcInfo(
        id: id,
        title: l10n.calcBodyMapTitle,
        explanation: l10n.calcBodyMapExplain,
        legitimacy: l10n.calcBodyMapWhy,
        sourceLabel:
            'European Food Safety Authority (EFSA) — Dietary Reference Values for vitamins & minerals',
      );
    case CalcInfoId.glycemicLoad:
      return CalcInfo(
        id: id,
        title: l10n.calcGlTitle,
        explanation: l10n.calcGlExplain,
        legitimacy: l10n.calcGlWhy,
        sourceLabel:
            'European Association for the Study of Diabetes (EASD) — Diabetes and Nutrition Study Group',
      );
    case CalcInfoId.bolusEstimate:
      return CalcInfo(
        id: id,
        title: l10n.calcBolusTitle,
        explanation: l10n.calcBolusExplain,
        legitimacy: l10n.calcBolusWhy,
        sourceLabel:
            'European Association for the Study of Diabetes (EASD) — clinical practice guidelines',
      );
    case CalcInfoId.insulinOnBoard:
      return CalcInfo(
        id: id,
        title: l10n.calcIobTitle,
        explanation: l10n.calcIobExplain,
        legitimacy: l10n.calcIobWhy,
        sourceLabel:
            'European Association for the Study of Diabetes (EASD) — clinical practice guidelines',
      );
    case CalcInfoId.insulinRatios:
      return CalcInfo(
        id: id,
        title: l10n.calcRatiosTitle,
        explanation: l10n.calcRatiosExplain,
        legitimacy: l10n.calcRatiosWhy,
        sourceLabel:
            'European Association for the Study of Diabetes (EASD) — clinical practice guidelines',
      );
    case CalcInfoId.recommendations:
      return CalcInfo(
        id: id,
        title: l10n.calcRecsTitle,
        explanation: l10n.calcRecsExplain,
        legitimacy: l10n.calcRecsWhy,
        sourceLabel: 'European Commission — Food-Based Dietary Guidelines',
      );
    case CalcInfoId.streak:
      return CalcInfo(
        id: id,
        title: l10n.calcStreakTitle,
        explanation: l10n.calcStreakExplain,
        legitimacy: l10n.calcStreakWhy,
        sourceLabel: 'European Commission — Food-Based Dietary Guidelines',
      );
    case CalcInfoId.weeklyBadges:
      return CalcInfo(
        id: id,
        title: l10n.calcBadgesTitle,
        explanation: l10n.calcBadgesExplain,
        legitimacy: l10n.calcBadgesWhy,
        sourceLabel: 'European Commission — Food-Based Dietary Guidelines',
      );
    case CalcInfoId.recipeGoalMatch:
      return CalcInfo(
        id: id,
        title: l10n.calcRecipeMatchTitle,
        explanation: l10n.calcRecipeMatchExplain,
        legitimacy: l10n.calcRecipeMatchWhy,
        sourceLabel: 'European Commission — Food-Based Dietary Guidelines',
      );
  }
}

/// Opens the explainer sheet for [id].
Future<void> showCalcInfo(BuildContext context, CalcInfoId id) {
  final info = calcInfoFor(context, id);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CalcInfoSheet(info: info),
  );
}

/// Shows the explainer automatically the first time a calculation feature is
/// seen, then never auto-shows again (the ⓘ button re-opens it on demand).
Future<void> maybeAutoShowCalcInfo(BuildContext context, CalcInfoId id) async {
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    return;
  }
  final key = 'calc_info_seen_${id.name}';
  if (prefs.getBool(key) ?? false) return;
  await prefs.setBool(key, true);
  if (!context.mounted) return;
  await showCalcInfo(context, id);
}

/// Small ⓘ button that opens the explainer for [id].
class CalcInfoButton extends StatelessWidget {
  const CalcInfoButton({
    super.key,
    required this.id,
    this.color,
    this.size = 18,
  });

  final CalcInfoId id;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      icon: Icon(Icons.info_outline, size: size),
      color: color ?? Colors.grey.shade600,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: l10n.howThisIsCalculated,
      onPressed: () => showCalcInfo(context, id),
    );
  }
}

class _CalcInfoSheet extends StatelessWidget {
  const _CalcInfoSheet({required this.info});

  final CalcInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.calculate_outlined,
                      size: 22, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      info.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                info.explanation,
                style: const TextStyle(
                    fontSize: 14, height: 1.4, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              _SectionLabel(l10n.calcWhyTrust),
              const SizedBox(height: 4),
              Text(
                info.legitimacy,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              _SectionLabel(l10n.calcSource),
              const SizedBox(height: 4),
              Text(
                info.sourceLabel,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.gotIt),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: Colors.grey.shade500,
      ),
    );
  }
}
