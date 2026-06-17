import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/glucose_unit.dart';
import '../models/scan_result.dart';
import '../providers/user_prefs_provider.dart';
import '../services/diabetes_advisor.dart';
import '../theme/app_theme.dart';

/// Professional diabetes insulin advisory for a single meal.
///
/// Renders ONLY when the active nutrition goal is Diabetes. It computes a
/// standard carbohydrate-counting bolus, a pre-bolus injection time, the
/// expected glucose-peak time, and food-order guidance — all evidence-based.
///
/// If no Insulin-to-Carb Ratio (ICR) is configured it instead shows a clear
/// warning prompting the user to set one.
class DiabetesInsulinCard extends ConsumerStatefulWidget {
  const DiabetesInsulinCard({super.key, required this.foods});

  /// The foods of the meal being reviewed before logging.
  final List<DetectedFood> foods;

  @override
  ConsumerState<DiabetesInsulinCard> createState() =>
      _DiabetesInsulinCardState();
}

class _DiabetesInsulinCardState extends ConsumerState<DiabetesInsulinCard> {
  MealNutrition? _meal;
  bool _loading = true;

  final _bgCtrl = TextEditingController();
  double? _currentBgMgdl; // canonical mg/dL, null until the user enters one

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final meal = await DiabetesAdvisor.estimateMealNutrition(widget.foods);
    if (mounted) {
      setState(() {
        _meal = meal;
        _loading = false;
      });
    }
  }

  void _applyBg(GlucoseUnit unit) {
    final raw = _bgCtrl.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    setState(() {
      _currentBgMgdl = (value == null || value <= 0) ? null : unit.toMgdl(value);
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(userPrefsProvider);
    final meal = _meal;
    if (_loading || meal == null) {
      return const SizedBox.shrink();
    }

    final advice = DiabetesAdvisor.compute(
      meal: meal,
      icr: prefs.insulinCarbRatio,
      isf: prefs.insulinSensitivityFactor,
      targetBgMgdl: prefs.targetBloodGlucoseMgdl,
      currentBgMgdl: _currentBgMgdl,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: const Color(0xFF1976D2), // diabetes blue
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.medical_services_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Diabetes Insulin Advisor',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    advice.spikeSpeed.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: advice.icrConfigured
                ? _buildAdvice(advice, prefs.glucoseUnit)
                : _buildNoIcrWarning(),
          ),
        ],
      ),
    );
  }

  // ── No ICR set → warning ───────────────────────────────────────────────
  Widget _buildNoIcrWarning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.amber100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.amber500),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.amber700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Insulin-to-Carb Ratio not set',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.amber700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add your ICR in Settings to receive an accurate meal '
                      'insulin dose and injection-timing recommendation.',
                      style: TextStyle(fontSize: 13, color: AppTheme.gray700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _carbsLine(),
        const SizedBox(height: 12),
        _foodOrderTip(),
      ],
    );
  }

  // ── ICR set → full advisory ────────────────────────────────────────────
  Widget _buildAdvice(DiabetesAdvice advice, GlucoseUnit unit) {
    final bolus = advice.bolusRounded ?? 0;
    final hasCorrection = advice.correctionRounded != null;
    final correction = advice.correctionRounded ?? 0;
    final total = advice.totalRounded ?? bolus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Current blood glucose input ──────────────────────────────────
        _buildBgInput(unit, advice),
        const SizedBox(height: 14),

        // ── Dose breakdown: meal bolus + correction = total ──────────────
        Row(
          children: [
            Expanded(
              child: _MetricBox(
                value: _doseStr(bolus),
                unit: 'units',
                label: 'Meal bolus',
                icon: Icons.restaurant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricBox(
                value: hasCorrection
                    ? (correction >= 0 ? '+${_doseStr(correction)}' : _doseStr(correction))
                    : '—',
                unit: hasCorrection ? 'units' : 'add BG',
                label: 'Correction',
                icon: Icons.bloodtype_outlined,
                dimmed: !hasCorrection,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricBox(
                value: _doseStr(total),
                unit: 'units',
                label: 'Total dose',
                icon: Icons.vaccines_outlined,
                highlight: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Timing boxes ─────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _MetricBox(
                value: advice.prebolusMinutes == 0
                    ? 'At meal'
                    : '${advice.prebolusMinutes} min',
                unit: advice.prebolusMinutes == 0 ? '' : 'before',
                label: 'Inject',
                icon: Icons.schedule,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricBox(
                value: '~${advice.timeToPeakMinutes}',
                unit: 'min',
                label: 'Glucose peak',
                icon: Icons.show_chart,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Blood-glucose safety banner (only when a reading is entered) ──
        if (advice.bgStatus != null && advice.bgWarning != null) ...[
          _bgBanner(advice),
          const SizedBox(height: 12),
        ],

        // ── ISF-not-set hint when a BG was entered but no ISF ────────────
        if (_currentBgMgdl != null && !advice.isfConfigured) ...[
          _InfoLine(
            icon: Icons.info_outline,
            color: Colors.orange.shade700,
            text: 'Set your Insulin Sensitivity Factor (ISF) in Settings to '
                'calculate a correction dose from your blood glucose.',
          ),
          const SizedBox(height: 10),
        ],

        // Timing message
        _InfoLine(
          icon: Icons.access_time,
          color: const Color(0xFF1976D2),
          text: advice.timingMessage,
        ),
        const SizedBox(height: 10),
        _carbsLine(),
        const SizedBox(height: 10),
        _foodOrderTip(),
        const SizedBox(height: 14),

        // ── Keep-your-settings-current safety reminder ───────────────────
        _doctorReminderBanner(),
        const SizedBox(height: 12),

        // ── Small-print disclaimer ───────────────────────────────────────
        Text(
          'Meal bolus = carbs ÷ your Insulin-to-Carb Ratio (${_fmt(advice.icr)} '
          'g/unit). '
          '${advice.isfConfigured ? 'Correction = (current BG − target) ÷ your '
              'Insulin Sensitivity Factor. ' : ''}'
          'These are the standard carbohydrate-counting and "1800-rule" '
          'correction formulas used in diabetes care, shown as an educational '
          'estimate for THIS meal only. They do not account for insulin-on-board, '
          'activity or illness and do not replace your healthcare provider\'s '
          'plan. Always confirm before dosing.',
          style: const TextStyle(
            fontSize: 9.5,
            height: 1.35,
            color: AppTheme.gray400,
          ),
        ),
      ],
    );
  }

  // ── Current blood-glucose input row ──────────────────────────────────────
  Widget _buildBgInput(GlucoseUnit unit, DiabetesAdvice advice) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBD9F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bloodtype_outlined,
                  size: 18, color: Color(0xFF1976D2)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Current blood glucose',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gray700,
                  ),
                ),
              ),
              SizedBox(
                width: 86,
                child: TextField(
                  controller: _bgCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => _applyBg(unit),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: unit == GlucoseUnit.mmoll ? '6.5' : '120',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.gray600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Target ${unit.formatWithUnit(_targetBgMgdl)}. Use a fresh, '
                  'correctly-measured reading.',
                  style: const TextStyle(fontSize: 11, color: AppTheme.gray400),
                ),
              ),
              TextButton(
                onPressed: () => _applyBg(unit),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double get _targetBgMgdl =>
      ref.read(userPrefsProvider).targetBloodGlucoseMgdl;

  // ── Blood-glucose status banner ──────────────────────────────────────────
  Widget _bgBanner(DiabetesAdvice advice) {
    final status = advice.bgStatus!;
    final (bg, fg, icon) = switch (status) {
      BgStatus.low => (AppTheme.red100, AppTheme.red500, Icons.dangerous_outlined),
      BgStatus.high => (AppTheme.red100, AppTheme.red500, Icons.priority_high),
      BgStatus.elevated => (AppTheme.amber100, AppTheme.amber700, Icons.trending_up),
      BgStatus.inRange => (const Color(0xFFE8F5E9), Colors.green, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: fg is MaterialColor ? fg.shade800 : fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  advice.bgWarning!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.gray700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reminder to keep ICR/ISF current and to measure BG correctly ────────
  Widget _doctorReminderBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.amber100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.amber500),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.health_and_safety_outlined,
              color: AppTheme.amber700, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Review your Insulin-to-Carb Ratio and Insulin Sensitivity Factor '
              'with your doctor regularly — they change over time. Always '
              'measure your blood glucose correctly (clean hands, fresh strip) '
              'and double-check every dose before injecting.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.gray700, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  String _doseStr(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _carbsLine() {
    final carbs = _meal?.carbsG ?? 0;
    return _InfoLine(
      icon: Icons.bakery_dining_outlined,
      color: Colors.amber.shade800,
      text: 'Estimated meal carbohydrate: ${carbs.round()} g',
    );
  }

  Widget _foodOrderTip() {
    return _InfoLine(
      icon: Icons.eco_outlined,
      color: Colors.green.shade700,
      text:
          'Eat vegetables and protein first, carbs last — this can cut your '
          'post-meal glucose spike by up to ~30%.',
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.value,
    required this.unit,
    required this.label,
    required this.icon,
    this.dimmed = false,
    this.highlight = false,
  });
  final String value;
  final String unit;
  final String label;
  final IconData icon;
  final bool dimmed;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bgColor = highlight
        ? const Color(0xFF1976D2)
        : (dimmed ? AppTheme.gray100 : const Color(0xFFE3F2FD));
    final fgColor = highlight
        ? Colors.white
        : (dimmed ? AppTheme.gray400 : const Color(0xFF1976D2));
    final valueColor = highlight
        ? Colors.white
        : (dimmed ? AppTheme.gray400 : const Color(0xFF0D47A1));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: fgColor),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: TextStyle(
                fontSize: 10,
                color: fgColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                color: highlight ? Colors.white70 : AppTheme.gray600),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppTheme.gray700,
            ),
          ),
        ),
      ],
    );
  }
}
