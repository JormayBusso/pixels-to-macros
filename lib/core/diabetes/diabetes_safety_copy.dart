/// User-facing legal/safety copy for Bolus Calculator Mode, kept in one place
/// so wording can be reviewed by clinical/legal/regulatory reviewers.
///
/// TODO(legal-review): all strings below are developer drafts and must be
/// reviewed/approved by legal and clinical reviewers before production.
class DiabetesSafetyCopy {
  DiabetesSafetyCopy._();

  static const String generalDisclaimer =
      'This insulin estimate is calculated from settings you entered. It is not '
      'a substitute for medical advice. Incorrect settings, carb counts, '
      'glucose readings, or insulin history can cause dangerous low or high '
      'glucose. Always follow your diabetes care plan.';

  static const String beforeEnabling =
      'Only use this feature if your insulin-to-carb ratio, correction factor, '
      'target glucose, and insulin action duration were provided by your '
      'clinician, diabetes educator, pump, or official care plan.';

  static const String overdueReview =
      'Your insulin settings have not been reviewed in over 90 days. For '
      'safety, bolus calculations are disabled until you review and confirm '
      'your settings.';

  static const String iobWarning =
      'You logged recent insulin. This estimate subtracts calculated '
      'insulin-on-board, but IOB may be inaccurate. Be careful about insulin '
      'stacking and follow your care plan.';

  static const String lowGlucose =
      'Your glucose is below your configured low threshold. This app cannot '
      'recommend insulin. Follow your hypoglycemia care plan.';

  static const String maxBolusExceeded =
      'The calculated amount exceeds your configured maximum single bolus. '
      'This calculation is blocked. Follow your care plan or contact your '
      'clinician.';

  /// Confirmation checkbox shown in the survey before settings can be saved.
  static const String settingsSourceConfirmation =
      'I understand this app does not replace medical advice. I confirm that '
      'the insulin settings I entered are from my clinician, insulin pump, '
      'diabetes educator, or official diabetes care plan. I understand '
      'incorrect settings can cause dangerous low or high blood glucose.';

  /// Final confirmation before an estimate is shown/saved.
  static const String finalResponsibilityConfirmation =
      'I understand this is calculated from my saved settings and I am '
      'responsible for confirming my dose.';

  /// Regulatory note surfaced in the setup screen.
  static const String regulatoryNotice =
      'Depending on where you live, an insulin calculator may be regulated as '
      'medical-device software. This feature is provided for informational '
      'support only and has not been cleared or certified as a medical device.';
}

/// Generates a reasonably-unique calculation id without adding a uuid
/// dependency. Format: epoch-millis "-" 0..9999.
String generateCalculationId() {
  final ms = DateTime.now().microsecondsSinceEpoch;
  final rand = ms % 10000;
  return '$ms-$rand';
}
