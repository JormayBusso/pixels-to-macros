import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_localizations.dart';
import '../../core/diabetes/diabetes_constants.dart';
import '../../providers/diabetes_provider.dart';
import '../../services/diabetes/diabetes_survey_scheduler.dart';
import '../../theme/app_theme.dart';
import 'bolus_setup_screen.dart' show kDiabetesBlue;
import 'insulin_settings_survey_screen.dart';

/// Shows the 90-day review status and lets the user confirm/update settings.
class DiabetesReviewScreen extends ConsumerWidget {
  const DiabetesReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(insulinSettingsProvider);
    final now = DateTime.now();
    final status = DiabetesSurveyScheduler.statusAt(s, now);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).insulinSettingsReview),
        backgroundColor: kDiabetesBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(context, status),
          const SizedBox(height: 16),
          _dateRow(context, AppLocalizations.of(context).lastReviewed,
              s.surveyLastCompletedAt),
          _dateRow(context, AppLocalizations.of(context).nextReviewDue,
              s.surveyNextDueAt),
          if (s.surveySnoozedUntil != null)
            _dateRow(context, AppLocalizations.of(context).reminderSnoozedUntil,
                s.surveySnoozedUntil),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kDiabetesBlue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () =>
                ref.read(insulinSettingsProvider.notifier).markReviewed(),
            icon: const Icon(Icons.verified_outlined),
            label: Text(AppLocalizations.of(context).confirmSettingsCorrect),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const InsulinSettingsSurveyScreen(),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: Text(AppLocalizations.of(context).updateInsulinSettings),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)
                .reviewKeepsSafe(DiabetesConstants.reviewInterval.inDays),
            style: TextStyle(fontSize: 12, color: AppTheme.gray500),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, ReviewStatus status) {
    final l10n = AppLocalizations.of(context);
    final (color, bg, label, detail) = switch (status) {
      ReviewStatus.current => (
        AppTheme.green700,
        AppTheme.green100,
        l10n.reviewStatusCurrent,
        l10n.reviewStatusCurrentDetail
      ),
      ReviewStatus.snoozed => (
        AppTheme.amber700,
        AppTheme.amber100,
        l10n.reviewStatusSnoozed,
        l10n.reviewStatusSnoozedDetail
      ),
      ReviewStatus.overdue => (
        AppTheme.red700,
        AppTheme.red100,
        l10n.reviewStatusOverdue,
        l10n.reviewStatusOverdueDetail
      ),
      ReviewStatus.neverCompleted => (
        AppTheme.red700,
        AppTheme.red100,
        l10n.reviewStatusNotCompleted,
        l10n.reviewStatusNotCompletedDetail
      ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reviewStatusLabel(label),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          const SizedBox(height: 6),
          Text(detail,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.4)),
        ],
      ),
    );
  }

  Widget _dateRow(BuildContext context, String label, DateTime? date) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 13, color: AppTheme.gray500)),
            Text(
              date == null ? '—' : _fmtDate(date),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A compact banner prompting a settings review. Show where appropriate (home
/// or meal screen) when [diabetesReviewReminderProvider] is true. Offers the
/// three snooze options and a "review now" action.
class DiabetesReviewReminderBanner extends ConsumerWidget {
  const DiabetesReviewReminderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(diabetesReviewReminderProvider);
    if (!show) return const SizedBox.shrink();
    final notifier = ref.read(insulinSettingsProvider.notifier);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.amber100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amber500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat, color: AppTheme.amber700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).insulinReviewNeeded,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.amber700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).bolusDisabledUntilReview,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.gray700, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.amber600),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiabetesReviewScreen(),
                  ),
                ),
                child: Text(AppLocalizations.of(context).reviewNow),
              ),
              OutlinedButton(
                onPressed: () => notifier.snooze(DiabetesConstants.snoozeOneDay),
                child: Text(AppLocalizations.of(context).remindTomorrow),
              ),
              OutlinedButton(
                onPressed: () =>
                    notifier.snooze(DiabetesConstants.snoozeTwoDays),
                child: Text(AppLocalizations.of(context).inTwoDays),
              ),
              OutlinedButton(
                onPressed: () =>
                    notifier.snooze(DiabetesConstants.snoozeOneWeek),
                child: Text(AppLocalizations.of(context).inOneWeek),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
