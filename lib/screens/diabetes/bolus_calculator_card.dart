import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_localizations.dart';
import '../../core/diabetes/diabetes_constants.dart';
import '../../core/diabetes/diabetes_safety_copy.dart' show generateCalculationId;
import '../../core/diabetes/glucose_conversion.dart';
import '../../models/bolus_audit_record.dart';
import '../../models/bolus_models.dart';
import '../../models/calc_info.dart';
import '../../models/insulin_dose_log.dart';
import '../../models/insulin_settings.dart';
import '../../providers/diabetes_provider.dart';
import '../../services/diabetes/bolus_calculator_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/calc_info_button.dart';
import 'bolus_setup_screen.dart' show kDiabetesBlue;

/// A meal-time bolus *estimate* card.
///
/// ⚠️ SAFETY: this only shows an estimate when the calculator is available
/// (enabled + survey completed + consent + current review). It never tells the
/// user to "take X units"; it shows an estimate the user is responsible for
/// confirming. Below the configured low-glucose threshold it refuses to
/// estimate. Above the configured max single bolus it hard-blocks.
///
/// TODO(clinical-review): wording, formulas, and gating require clinical sign-off.
/// TODO(regulatory-review): may be regulated as medical-device software.
class BolusCalculatorCard extends ConsumerStatefulWidget {
  const BolusCalculatorCard({
    super.key,
    this.initialCarbsG,
    this.mealId,
  });

  /// Optional pre-fill from the meal being logged.
  final double? initialCarbsG;

  /// Optional id of the meal this estimate is attached to (audit linkage).
  final int? mealId;

  @override
  ConsumerState<BolusCalculatorCard> createState() =>
      _BolusCalculatorCardState();
}

class _BolusCalculatorCardState extends ConsumerState<BolusCalculatorCard> {
  late final TextEditingController _carbsCtrl;
  final TextEditingController _glucoseCtrl = TextEditingController();

  bool _includeCorrection = false;
  bool _includeIob = false;
  bool _finalConfirmed = false;
  DateTime? _glucoseReadingAt;

  BolusResult? _result;

  @override
  void initState() {
    super.initState();
    _carbsCtrl = TextEditingController(
      text: widget.initialCarbsG != null
          ? widget.initialCarbsG!.toStringAsFixed(0)
          : '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeAutoShowCalcInfo(context, CalcInfoId.bolusEstimate);
    });
  }

  @override
  void dispose() {
    _carbsCtrl.dispose();
    _glucoseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(bolusCalculatorAvailableProvider);
    final settings = ref.watch(insulinSettingsProvider);

    if (!available) {
      return _disabledCard(settings);
    }

    final isMmol = settings.glucoseUnit.isMmol;

    return Container(
      // Bolus Calculator Mode is intentionally locked to a clean white +
      // diabetes-blue palette (never the app theme/premium color) so the
      // safety-critical numbers stay maximally readable in every theme.
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDiabetesBlue.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, color: kDiabetesBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(AppLocalizations.of(context).bolusEstimate,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kDiabetesBlue)),
              ),
              const CalcInfoButton(
                  id: CalcInfoId.bolusEstimate, color: kDiabetesBlue),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).diabetesGeneralDisclaimer,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.gray500, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _carbsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mealCarbohydratesG,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _clearResult(),
          ),
          const SizedBox(height: 12),
          if (settings.correctionEnabled) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(AppLocalizations.of(context).addCorrectionForGlucose),
              value: _includeCorrection,
              activeColor: kDiabetesBlue,
              onChanged: (v) {
                setState(() {
                  _includeCorrection = v;
                  _clearResult();
                });
              },
            ),
            if (_includeCorrection)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _glucoseCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)
                            .currentGlucoseUnit(isMmol ? 'mmol/L' : 'mg/dL'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        _glucoseReadingAt ??= DateTime.now();
                        _clearResult();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _glucoseReadingAt = DateTime.now());
                    },
                    child: Text(
                      _glucoseReadingAt == null
                          ? AppLocalizations.of(context).setTime
                          : AppLocalizations.of(context)
                              .nowTime(_fmtTime(_glucoseReadingAt!)),
                    ),
                  ),
                ],
              ),
          ],
          if (settings.iobEnabled)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Row(
                children: [
                  Flexible(child: Text(AppLocalizations.of(context).subtractIob)),
                  const CalcInfoButton(
                      id: CalcInfoId.insulinOnBoard, color: kDiabetesBlue),
                ],
              ),
              subtitle: Text(
                AppLocalizations.of(context).subtractIobCardDesc,
                style: const TextStyle(fontSize: 11),
              ),
              value: _includeIob,
              activeColor: kDiabetesBlue,
              onChanged: (v) {
                setState(() {
                  _includeIob = v;
                  _clearResult();
                });
              },
            ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDiabetesBlue,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: _calculate,
            child: Text(AppLocalizations.of(context).calculateEstimate),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            _resultSection(_result!, settings),
          ],
        ],
      ),
    );
  }

  // ── Disabled state ─────────────────────────────────────────────────────────
  Widget _disabledCard(InsulinSettings settings) {
    if (!settings.bolusCalculatorEnabled) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.amber100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        AppLocalizations.of(context).bolusUnavailableUntilReview,
        style: const TextStyle(fontSize: 12.5, color: AppTheme.amber700),
      ),
    );
  }

  // ── Calculation ─────────────────────────────────────────────────────────────
  void _clearResult() {
    if (_result != null) setState(() => _result = null);
  }

  Future<void> _calculate() async {
    final settings = ref.read(insulinSettingsProvider);
    final isMmol = settings.glucoseUnit.isMmol;

    final carbs = double.tryParse(_carbsCtrl.text.trim());
    if (carbs == null) {
      _show(BolusResult.blocked(
        [BolusBlockReason.mealCarbsMissingOrInvalid],
        settingsVersion: settings.settingsVersion,
      ));
      return;
    }

    double? glucoseMgdl;
    if (_includeCorrection) {
      final raw = double.tryParse(_glucoseCtrl.text.trim());
      if (raw != null) {
        glucoseMgdl = isMmol ? GlucoseConversion.mmolToMgdl(raw) : raw;
      }
    }

    final doses = _includeIob
        ? ref.read(insulinDoseLogProvider)
        : const <InsulinDoseLog>[];

    final input = BolusInput(
      mealCarbsG: carbs,
      requestCorrection: _includeCorrection,
      currentGlucoseMgdl: glucoseMgdl,
      glucoseReadingAt: _includeCorrection ? _glucoseReadingAt : null,
      requestIob: _includeIob,
      recentDoses: doses,
    );

    final result =
        BolusCalculatorService.calculate(settings: settings, input: input);
    _show(result);

    // Audit every calculation that produced an estimate (not the hard blocks
    // that produced nothing the user could act on). userConfirmed starts false
    // and is updated when the user confirms.
    if (!result.blocked && result.breakdown != null) {
      await _writeAudit(result, settings, confirmed: false);
    }
  }

  void _show(BolusResult r) {
    setState(() {
      _result = r;
      _finalConfirmed = false;
    });
  }

  String? _lastCalculationId;

  Future<void> _writeAudit(
    BolusResult result,
    InsulinSettings settings, {
    required bool confirmed,
  }) async {
    final b = result.breakdown!;
    _lastCalculationId = generateCalculationId();
    final record = BolusAuditRecord(
      calculationId: _lastCalculationId!,
      timestamp: DateTime.now(),
      mealId: widget.mealId,
      carbsG: b.mealCarbsG,
      currentGlucoseMgdl: b.currentGlucoseMgdl,
      glucoseUnit: settings.glucoseUnit.isMmol ? 'mmol' : 'mgdl',
      targetGlucoseMgdl: b.targetGlucoseMgdl,
      icrUsed: b.icrUsed,
      isfUsed: b.isfUsed,
      mealBolusComponent: b.mealBolusUnits,
      correctionComponent: b.correctionUnits,
      iobComponent: b.iobUnits,
      rawBolus: b.rawBolusUnits,
      roundedBolus: b.roundedBolusUnits,
      maxBolus: b.maxSingleBolusUnits,
      warnings: result.warnings.map((w) => w.name).join(';'),
      settingsVersion: result.settingsVersion,
      userConfirmed: confirmed,
    );
    await ref.read(bolusAuditProvider)(record);
  }

  // ── Result display ──────────────────────────────────────────────────────────
  Widget _resultSection(BolusResult result, InsulinSettings settings) {
    final l10n = AppLocalizations.of(context);
    if (result.blocked) {
      return _blockedBox(result);
    }
    final b = result.breakdown!;
    final isMmol = settings.glucoseUnit.isMmol;
    final unit = isMmol ? 'mmol/L' : 'mg/dL';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.green100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.estimatedBolusLabel,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.gray700),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.bolusUnitsValue(_fmtUnits(b.roundedBolusUnits)),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.green700),
              ),
              Text(
                l10n.responsibleForDose,
                style: const TextStyle(fontSize: 11, color: AppTheme.gray600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...result.warnings.map((w) => _warningBox(w.localizedMessage(l10n))),
        const SizedBox(height: 4),
        _breakdownTable(b, unit),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _finalConfirmed,
          activeColor: kDiabetesBlue,
          title: Text(
            l10n.diabetesFinalResponsibility,
            style: const TextStyle(fontSize: 12.5),
          ),
          onChanged: (v) => setState(() => _finalConfirmed = v ?? false),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kDiabetesBlue,
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: _finalConfirmed
              ? () => _openDoseLog(b.roundedBolusUnits, settings)
              : null,
          icon: const Icon(Icons.edit_note),
          label: Text(l10n.logDoseITook),
        ),
      ],
    );
  }

  Widget _breakdownTable(BolusBreakdown b, String unit) {
    final l10n = AppLocalizations.of(context);
    String g(double? mgdl) => mgdl == null
        ? '—'
        : GlucoseConversion.formatForDisplay(mgdl,
            unitIsMmol: unit == 'mmol/L');

    final rows = <(String, String)>[
      (l10n.bdMealCarbs, '${_fmtUnits(b.mealCarbsG)} g'),
      if (b.icrUsed != null)
        (l10n.bdIcrUsed, '1u : ${_fmtUnits(b.icrUsed!)} g'),
      (l10n.bdMealComponent, '${_fmtUnits(b.mealBolusUnits)} u'),
      if (b.currentGlucoseMgdl != null)
        (l10n.bdCurrentGlucose, '${g(b.currentGlucoseMgdl)} $unit'),
      if (b.targetGlucoseMgdl != null)
        (l10n.bdTargetGlucose, '${g(b.targetGlucoseMgdl)} $unit'),
      if (b.isfUsed != null)
        (l10n.bdCorrectionFactorUsed, '1u : ${g(b.isfUsed)} $unit'),
      (l10n.bdCorrectionComponent, '${_fmtUnits(b.correctionUnits)} u'),
      (l10n.bdIobSubtracted, '${_fmtUnits(b.iobUnits)} u'),
      (l10n.bdRawTotal, '${_fmtUnits(b.rawBolusUnits)} u'),
      (
        l10n.bdRoundedTo(_fmtUnits(b.minIncrement)),
        '${_fmtUnits(b.roundedBolusUnits)} u'
      ),
      (l10n.bdMaxSingleBolus, '${_fmtUnits(b.maxSingleBolusUnits)} u'),
      (l10n.bdTimeBlock, b.timeBlockLabel),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gray50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.howThisCalculated,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(r.$1,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.gray600)),
                  ),
                  Text(r.$2,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockedBox(BolusResult result) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.red100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, color: AppTheme.red700, size: 20),
              const SizedBox(width: 8),
              Text(l10n.noEstimateShown,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppTheme.red700)),
            ],
          ),
          const SizedBox(height: 8),
          ...result.blockReasons.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• ${r.localizedMessage(l10n)}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.red700, height: 1.35)),
            ),
          ),
          ...result.warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(w.localizedMessage(l10n),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.gray700, height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warningBox(String message) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.amber100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.amber700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.amber700, height: 1.35)),
            ),
          ],
        ),
      );

  // ── Dose logging ────────────────────────────────────────────────────────────
  Future<void> _openDoseLog(double estimate, InsulinSettings settings) async {
    // Mark the audit record as user-confirmed (they accepted responsibility).
    if (_lastCalculationId != null) {
      final settingsNow = ref.read(insulinSettingsProvider);
      if (_result != null && !_result!.blocked) {
        await _writeAudit(_result!, settingsNow, confirmed: true);
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => InsulinDoseLogSheet(
        prefillUnits: estimate,
        calculationId: _lastCalculationId,
      ),
    );
  }

  // ── Formatting ──────────────────────────────────────────────────────────────
  String _fmtUnits(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
          RegExp(r'\.$'),
          '',
        );
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Bottom sheet to log the *actual* insulin dose the user took. Requires an
/// explicit confirmation checkbox before the dose is saved. The app never logs
/// an estimate as a taken dose automatically.
class InsulinDoseLogSheet extends ConsumerStatefulWidget {
  const InsulinDoseLogSheet({
    super.key,
    this.prefillUnits,
    this.calculationId,
  });

  final double? prefillUnits;
  final String? calculationId;

  @override
  ConsumerState<InsulinDoseLogSheet> createState() =>
      _InsulinDoseLogSheetState();
}

class _InsulinDoseLogSheetState extends ConsumerState<InsulinDoseLogSheet> {
  late final TextEditingController _unitsCtrl;
  final TextEditingController _notesCtrl = TextEditingController();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _unitsCtrl = TextEditingController(
      text: widget.prefillUnits != null
          ? widget.prefillUnits!.toStringAsFixed(
              widget.prefillUnits! == widget.prefillUnits!.roundToDouble()
                  ? 0
                  : 1)
          : '',
    );
  }

  @override
  void dispose() {
    _unitsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.logInsulinDose,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            l10n.enterDoseDesc,
            style: const TextStyle(fontSize: 12, color: AppTheme.gray500),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _unitsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.unitsTaken,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: l10n.notesOptional,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            activeColor: kDiabetesBlue,
            title: Text(l10n.iConfirmTookDose,
                style: const TextStyle(fontSize: 13)),
            onChanged: (v) => setState(() => _confirmed = v ?? false),
          ),
          const SizedBox(height: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDiabetesBlue,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: _confirmed ? _save : null,
            child: Text(l10n.saveDose),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final units = double.tryParse(_unitsCtrl.text.trim());
    if (units == null ||
        units <= 0 ||
        units > DiabetesConstants.maxMaxSingleBolusUnits) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterValidUnits)),
      );
      return;
    }
    final dose = InsulinDoseLog(
      units: units,
      timestamp: DateTime.now(),
      confirmed: true,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      calculationId: widget.calculationId,
    );
    await ref.read(insulinDoseLogProvider.notifier).addConfirmedDose(dose);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.doseLogged)),
    );
  }
}
