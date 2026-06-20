import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(
        title: const Text('Insulin Settings Review'),
        backgroundColor: kDiabetesBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(status),
          const SizedBox(height: 16),
          _dateRow('Last reviewed', s.surveyLastCompletedAt),
          _dateRow('Next review due', s.surveyNextDueAt),
          if (s.surveySnoozedUntil != null)
            _dateRow('Reminder snoozed until', s.surveySnoozedUntil),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kDiabetesBlue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () =>
                ref.read(insulinSettingsProvider.notifier).markReviewed(),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Confirm my settings are still correct'),
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
            label: const Text('Update my insulin settings'),
          ),
          const SizedBox(height: 20),
          Text(
            'Reviewing your settings regularly keeps the calculator safe. '
            'Confirming marks them current for the next '
            '${DiabetesConstants.reviewInterval.inDays} days.',
            style: const TextStyle(fontSize: 12, color: AppTheme.gray500),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(ReviewStatus status) {
    final (color, bg, label, detail) = switch (status) {
      ReviewStatus.current => (
        AppTheme.green700,
        AppTheme.green100,
        'Current',
        'Your settings are reviewed and the calculator is available.'
      ),
      ReviewStatus.snoozed => (
        AppTheme.amber700,
        AppTheme.amber100,
        'Review due (reminder snoozed)',
        'A review is due. The reminder is snoozed, but the calculator stays '
            'disabled until you review.'
      ),
      ReviewStatus.overdue => (
        AppTheme.red700,
        AppTheme.red100,
        'Overdue',
        'Your settings review is overdue. Bolus calculations are disabled '
            'until you review and confirm.'
      ),
      ReviewStatus.neverCompleted => (
        AppTheme.red700,
        AppTheme.red100,
        'Not completed',
        'Complete the insulin settings survey to use the calculator.'
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
          Text('Status: $label',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: color)),
          const SizedBox(height: 6),
          Text(detail,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.4)),
        ],
      ),
    );
  }

  Widget _dateRow(String label, DateTime? date) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.gray600)),
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
            children: const [
              Icon(Icons.event_repeat, color: AppTheme.amber700, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Insulin settings review needed',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.amber700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'For safety, the bolus calculator is disabled until you review and '
            'confirm your insulin settings.',
            style: TextStyle(fontSize: 12, color: AppTheme.gray700, height: 1.4),
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
                child: const Text('Review now'),
              ),
              OutlinedButton(
                onPressed: () => notifier.snooze(DiabetesConstants.snoozeOneDay),
                child: const Text('Remind me tomorrow'),
              ),
              OutlinedButton(
                onPressed: () =>
                    notifier.snooze(DiabetesConstants.snoozeTwoDays),
                child: const Text('In 2 days'),
              ),
              OutlinedButton(
                onPressed: () =>
                    notifier.snooze(DiabetesConstants.snoozeOneWeek),
                child: const Text('In 1 week'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
