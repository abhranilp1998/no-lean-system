/// What the home-screen widgets receive over `no_lean/widget`.
///
/// In privacy mode nothing recovery-specific is sent, so nothing is stored in
/// the widget's SharedPreferences either: no clean time, no streak, no risk
/// state, no pledge state. The native side renders neutral copy and removes
/// any previously stored last-dose timestamp when `privacy` is true.
Map<String, Object> homeWidgetPayload({
  required DateTime lastDose,
  required String cleanTime,
  required int streak,
  required bool isRiskWindow,
  required bool hasPledgedToday,
  required bool privacy,
  int? riskStartMinutes,
  int? riskEndMinutes,
  DateTime? lastPledge,
}) {
  if (privacy) {
    return const <String, Object>{
      'privacy': true,
      'lastDoseEpochMillis': 0,
      'cleanTime': '',
      'streak': '',
      'isRiskWindow': false,
      'hasPledgedToday': false,
    };
  }
  return <String, Object>{
    'privacy': false,
    'lastDoseEpochMillis': lastDose.millisecondsSinceEpoch,
    'cleanTime': cleanTime,
    'streak': widgetStreakText(streak),
    'isRiskWindow': isRiskWindow,
    'hasPledgedToday': hasPledgedToday,
    // The night-timeline widget redraws hourly from these without the app.
    'riskStartMinutes': ?riskStartMinutes,
    'riskEndMinutes': ?riskEndMinutes,
    // The widget compares this with its own clock, so "TODAY LOCKED" ends at
    // midnight even if the app is not opened.
    'lastPledgeEpochMillis': ?lastPledge?.millisecondsSinceEpoch,
  };
}

/// "1 DAY CLEAN" / "12 DAYS CLEAN": same wording as the native widget's
/// `widget_clean_days` plural, used before the first live tick.
String widgetStreakText(int days) =>
    '$days ${days == 1 ? 'DAY' : 'DAYS'} CLEAN';
