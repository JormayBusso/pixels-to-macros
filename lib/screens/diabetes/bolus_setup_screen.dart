import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_localizations.dart';
import '../../providers/diabetes_provider.dart';
import '../../theme/app_theme.dart';
import 'insulin_settings_survey_screen.dart';

const Color kDiabetesBlue = Color(0xFF1976D2);

/// Entry point for enabling Bolus Calculator Mode.
///
/// User flow (matches the feature spec):
///   1. Confirm diabetes support is on.
///   2. Ask whether the user uses insulin.
///   3. If yes, offer optional Bolus Calculator Mode.
///   4. Show a safety disclaimer + require explicit consent.
///   5. Launch the Diabetes Insulin Settings Survey.
///
/// ⚠️ Bolus Calculator Mode is OFF by default and only becomes available after
/// the survey is completed and validated. This screen only collects consent
/// and routes to the survey; it never enables the calculator on its own.
class BolusSetupScreen extends ConsumerStatefulWidget {
  const BolusSetupScreen({super.key});

  @override
  ConsumerState<BolusSetupScreen> createState() => _BolusSetupScreenState();
}

class _BolusSetupScreenState extends ConsumerState<BolusSetupScreen> {
  bool _consentAccepted = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(insulinSettingsProvider);
    final notifier = ref.read(insulinSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).bolusCalculatorMode),
        backgroundColor: kDiabetesBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _warningBanner(),
          const SizedBox(height: 16),

          // 2. Uses insulin?
          _card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: kDiabetesBlue,
              value: settings.usesInsulin,
              onChanged: (v) => notifier.setUsesInsulin(v),
              title: Text(AppLocalizations.of(context).iUseInsulin),
              subtitle: Text(AppLocalizations.of(context).iUseInsulinDesc),
            ),
          ),

          if (settings.usesInsulin) ...[
            const SizedBox(height: 16),
            // 4. Safety disclaimer + consent.
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: kDiabetesBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context).beforeYouEnable,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(AppLocalizations.of(context).diabetesBeforeEnabling,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.gray700, height: 1.4)),
                  const SizedBox(height: 12),
                  Text(AppLocalizations.of(context).diabetesGeneralDisclaimer,
                      style:
                          TextStyle(fontSize: 12, color: context.appMutedTextColor, height: 1.4)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.amber100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppLocalizations.of(context).diabetesRegulatoryNotice,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.amber700, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: kDiabetesBlue,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _consentAccepted,
                    onChanged: (v) =>
                        setState(() => _consentAccepted = v ?? false),
                    title: Text(
                      AppLocalizations.of(context)
                          .diabetesSettingsSourceConfirmation,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 5. Continue to survey.
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kDiabetesBlue,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _consentAccepted ? _continueToSurvey : null,
              icon: const Icon(Icons.assignment_outlined),
              label: Text(AppLocalizations.of(context).continueToSurvey),
            ),

            if (settings.bolusCalculatorEnabled) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: AppTheme.red700,
                ),
                onPressed: () => notifier.disableBolusCalculator(),
                icon: const Icon(Icons.block),
                label:
                    Text(AppLocalizations.of(context).disableBolusCalculatorMode),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _continueToSurvey() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const InsulinSettingsSurveyScreen(),
      ),
    );
  }

  Widget _warningBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.red100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.red500),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.red700, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(
                builder: (context) => Text(
                  AppLocalizations.of(context).highRiskFeature,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.red700, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}
