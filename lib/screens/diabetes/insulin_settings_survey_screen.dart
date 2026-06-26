import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_localizations.dart';
import '../../core/diabetes/glucose_conversion.dart';
import '../../models/insulin_settings.dart';
import '../../providers/diabetes_provider.dart';
import '../../services/diabetes/diabetes_safety_validator.dart';
import 'bolus_setup_screen.dart' show kDiabetesBlue;

/// Diabetes Insulin Settings Survey.
///
/// Collects ONLY user-provided, clinician-sourced settings (the app never
/// invents values). On save it validates everything; if valid and the
/// confirmation checkbox is accepted, it marks the survey complete, records
/// consent, sets the next 90-day review date, and enables the calculator.
///
/// Time blocks: the spec's example uses three daily blocks. To keep entry
/// simple we present three fixed windows (overnight/day/evening) and let the
/// user set the ICR and ISF value for each. The fixed windows never overlap.
class InsulinSettingsSurveyScreen extends ConsumerStatefulWidget {
  const InsulinSettingsSurveyScreen({super.key});

  @override
  ConsumerState<InsulinSettingsSurveyScreen> createState() =>
      _InsulinSettingsSurveyScreenState();
}

class _InsulinSettingsSurveyScreenState
    extends ConsumerState<InsulinSettingsSurveyScreen> {
  // Fixed, non-overlapping time windows (minutes since midnight).
  static const _windows = [
    (label: 'Overnight (00:00–10:59)', start: 0, end: 659),
    (label: 'Daytime (11:00–16:59)', start: 660, end: 1019),
    (label: 'Evening (17:00–23:59)', start: 1020, end: 1439),
  ];

  BgUnit _unit = BgUnit.mgdl;
  DiabetesType _type = DiabetesType.preferNotToSay;
  bool _usesCgm = false;
  bool _correctionEnabled = true;
  bool _mealBolusEnabled = true;
  bool _iobEnabled = false;
  bool _confirmed = false;

  final _icrCtrls = [for (var i = 0; i < 3; i++) TextEditingController()];
  final _isfCtrls = [for (var i = 0; i < 3; i++) TextEditingController()];
  final _targetCtrl = TextEditingController();
  final _hypoCtrl = TextEditingController();
  final _hyperCtrl = TextEditingController();
  final _diaCtrl = TextEditingController();
  final _maxBolusCtrl = TextEditingController();
  double _increment = 0.5;

  @override
  void initState() {
    super.initState();
    final s = ref.read(insulinSettingsProvider);
    _unit = s.glucoseUnit;
    _type = s.diabetesType;
    _usesCgm = s.usesCgm;
    _correctionEnabled = s.correctionEnabled;
    _mealBolusEnabled = s.mealBolusEnabled;
    _iobEnabled = s.iobEnabled;
    _increment = s.minBolusIncrement ?? 0.5;
    // Pre-fill from existing blocks where windows match.
    for (var i = 0; i < _windows.length; i++) {
      final w = _windows[i];
      final icr = s.icrBlocks
          .where((b) => b.startMinute == w.start && b.endMinute == w.end)
          .firstOrNull;
      if (icr != null) _icrCtrls[i].text = _fmt(icr.value);
      final isf = s.isfBlocks
          .where((b) => b.startMinute == w.start && b.endMinute == w.end)
          .firstOrNull;
      if (isf != null) _isfCtrls[i].text = _fmtGlucose(isf.value);
    }
    if (s.targetGlucoseMgdl != null) {
      _targetCtrl.text = _fmtGlucose(s.targetGlucoseMgdl!);
    }
    if (s.hypoThresholdMgdl != null) {
      _hypoCtrl.text = _fmtGlucose(s.hypoThresholdMgdl!);
    }
    if (s.hyperThresholdMgdl != null) {
      _hyperCtrl.text = _fmtGlucose(s.hyperThresholdMgdl!);
    }
    if (s.insulinActionDurationHours != null) {
      _diaCtrl.text = _fmt(s.insulinActionDurationHours!);
    }
    if (s.maxSingleBolusUnits != null) {
      _maxBolusCtrl.text = _fmt(s.maxSingleBolusUnits!);
    }
  }

  @override
  void dispose() {
    for (final c in [..._icrCtrls, ..._isfCtrls]) {
      c.dispose();
    }
    for (final c in [
      _targetCtrl,
      _hypoCtrl,
      _hyperCtrl,
      _diaCtrl,
      _maxBolusCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String _fmtGlucose(double mgdl) =>
      GlucoseConversion.formatForDisplay(mgdl, unitIsMmol: _unit.isMmol);

  double? _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.'));

  /// Convert a user-entered glucose value (in [_unit]) to canonical mg/dL.
  double? _glucoseToMgdl(TextEditingController c) {
    final v = _parse(c);
    if (v == null) return null;
    return _unit.isMmol ? GlucoseConversion.mmolToMgdl(v) : v;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l10n.insulinSettingsSurvey),
        backgroundColor: kDiabetesBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(l10n.diabetesGeneralSection),
          _unitToggle(),
          const SizedBox(height: 12),
          _enumDropdown<DiabetesType>(
            label: l10n.diabetesTypeField,
            value: _type,
            values: DiabetesType.values,
            labelOf: (t) => l10n.diabetesTypeLabel(t.name),
            onChanged: (v) => setState(() => _type = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: kDiabetesBlue,
            value: _usesCgm,
            onChanged: (v) => setState(() => _usesCgm = v),
            title: Text(l10n.usesCgm),
          ),
          _section(l10n.calculatorComponents),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: kDiabetesBlue,
            value: _mealBolusEnabled,
            onChanged: (v) => setState(() => _mealBolusEnabled = v),
            title: Text(l10n.enableMealBolus),
            subtitle: Text(l10n.enableMealBolusDesc),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: kDiabetesBlue,
            value: _correctionEnabled,
            onChanged: (v) => setState(() => _correctionEnabled = v),
            title: Text(l10n.enableCorrectionDose),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: kDiabetesBlue,
            value: _iobEnabled,
            onChanged: (v) => setState(() => _iobEnabled = v),
            title: Text(l10n.subtractIob),
            subtitle: Text(l10n.subtractIobSurveyDesc),
          ),
          _section(l10n.glucoseTargetsSection(_unit.label)),
          _numField(_targetCtrl, l10n.targetGlucoseField),
          _numField(_hypoCtrl, l10n.lowHypoThreshold),
          _numField(_hyperCtrl, l10n.highHyperThreshold),
          if (_mealBolusEnabled) ...[
            _section(l10n.icrSection),
            for (var i = 0; i < _windows.length; i++)
              _numField(_icrCtrls[i], _windowLabel(l10n, i)),
          ],
          if (_correctionEnabled) ...[
            _section(l10n.isfSection(_unit.label)),
            for (var i = 0; i < _windows.length; i++)
              _numField(_isfCtrls[i], _windowLabel(l10n, i)),
          ],
          _section(l10n.insulinActionLimits),
          _numField(_diaCtrl, l10n.insulinActionDurationHours),
          _numField(_maxBolusCtrl, l10n.maxSingleBolusUnitsField),
          const SizedBox(height: 8),
          _incrementPicker(),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: kDiabetesBlue,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: Text(
              l10n.diabetesSettingsSourceConfirmation,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDiabetesBlue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _confirmed ? _save : null,
            child: Text(l10n.validateAndSaveSettings),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _windowLabel(AppLocalizations l10n, int i) => switch (i) {
        0 => l10n.windowOvernight,
        1 => l10n.windowDaytime,
        _ => l10n.windowEvening,
      };

  String _issueText(AppLocalizations l10n, ValidationIssue e) {
    final code = e.code;
    if (code == null) return e.message;
    String? label;
    if (e.labelKey == 'icr') {
      label = l10n.validatorLabelIcr;
    } else if (e.labelKey == 'isf') {
      label = l10n.validatorLabelIsf;
    }
    return l10n.validatorMessage(code, label: label);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final base = ref.read(insulinSettingsProvider);

    List<InsulinTimeBlock> blocks(
        List<TextEditingController> ctrls, bool glucose) {
      final out = <InsulinTimeBlock>[];
      for (var i = 0; i < _windows.length; i++) {
        final raw = _parse(ctrls[i]);
        if (raw == null) continue;
        final value =
            glucose && _unit.isMmol ? GlucoseConversion.mmolToMgdl(raw) : raw;
        out.add(InsulinTimeBlock(
          startMinute: _windows[i].start,
          endMinute: _windows[i].end,
          value: value,
        ));
      }
      return out;
    }

    final candidate = base.copyWith(
      diabetesEnabled: true,
      usesInsulin: true,
      bolusCalculatorEnabled: true,
      diabetesType: _type,
      glucoseUnit: _unit,
      usesCgm: _usesCgm,
      targetGlucoseMgdl: _glucoseToMgdl(_targetCtrl),
      hypoThresholdMgdl: _glucoseToMgdl(_hypoCtrl),
      hyperThresholdMgdl: _glucoseToMgdl(_hyperCtrl),
      icrBlocks: blocks(_icrCtrls, false),
      isfBlocks: blocks(_isfCtrls, true),
      insulinActionDurationHours: _parse(_diaCtrl),
      maxSingleBolusUnits: _parse(_maxBolusCtrl),
      minBolusIncrement: _increment,
      correctionEnabled: _correctionEnabled,
      mealBolusEnabled: _mealBolusEnabled,
      iobEnabled: _iobEnabled,
    );

    // Validate before saving.
    final result = DiabetesSafetyValidator.validateSettings(candidate);

    // Required-field checks specific to enabling the calculator.
    final missing = <String>[];
    if (_mealBolusEnabled && candidate.icrBlocks.isEmpty) {
      missing.add(l10n.missingAtLeastOneIcr);
    }
    if (!_mealBolusEnabled && !_correctionEnabled) {
      missing.add(l10n.missingComponent);
    }
    if (candidate.maxSingleBolusUnits == null) missing.add(l10n.missingMaxBolus);
    if (_correctionEnabled && candidate.targetGlucoseMgdl == null) {
      missing.add(l10n.missingTargetGlucose);
    }
    if (_correctionEnabled && candidate.isfBlocks.isEmpty) {
      missing.add(l10n.missingCorrectionFactor);
    }
    if (_iobEnabled && candidate.insulinActionDurationHours == null) {
      missing.add(l10n.missingActionDuration);
    }

    if (result.hasErrors || missing.isNotEmpty) {
      final msgs = <String>[
        ...result.errors.map((e) => _issueText(l10n, e)),
        if (missing.isNotEmpty) l10n.pleaseProvide(missing.join(', ')),
      ];
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.pleaseFixSettings),
            content: Text(msgs.join('\n\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (result.hasWarnings && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.pleaseConfirmTitle),
          content: Text(
              result.warnings.map((w) => _issueText(l10n, w)).join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.goBack),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await ref.read(insulinSettingsProvider.notifier).completeSurvey(candidate);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bolusCalculatorEnabledMsg)),
      );
      Navigator.of(context).pop();
    }
  }

  // ── small UI helpers ───────────────────────────────────────────────────

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: kDiabetesBlue)),
      );

  Widget _numField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _unitToggle() => Row(
        children: [
          Text(AppLocalizations.of(context).bloodGlucoseUnitColon),
          const SizedBox(width: 12),
          SegmentedButton<BgUnit>(
            segments: const [
              ButtonSegment(value: BgUnit.mgdl, label: Text('mg/dL')),
              ButtonSegment(value: BgUnit.mmol, label: Text('mmol/L')),
            ],
            selected: {_unit},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
        ],
      );

  Widget _incrementPicker() => Row(
        children: [
          Text(AppLocalizations.of(context).roundingIncrement),
          const SizedBox(width: 12),
          DropdownButton<double>(
            value: _increment,
            dropdownColor: Colors.white,
            items: const [
              DropdownMenuItem(value: 0.1, child: Text('0.1 u')),
              DropdownMenuItem(value: 0.5, child: Text('0.5 u')),
              DropdownMenuItem(value: 1.0, child: Text('1.0 u')),
            ],
            onChanged: (v) => setState(() => _increment = v ?? 0.5),
          ),
        ],
      );

  Widget _enumDropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) =>
      InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            dropdownColor: Colors.white,
            items: [
              for (final v in values)
                DropdownMenuItem(value: v, child: Text(labelOf(v))),
            ],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        ),
      );
}
