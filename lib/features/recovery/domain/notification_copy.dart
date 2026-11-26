import '../../zones/domain/position_status.dart';
import 'craving_peak.dart';
import 'daily_check_in.dart';
import 'notification_policy.dart';
import 'risk_alert_plan.dart';
import 'risk_window.dart';
import 'use_check.dart';

/// Words that must never appear in a private notification: titles, bodies,
/// channel names, descriptions, ticker, subtext or action labels. Matching
/// is case-insensitive and uses word boundaries so "replacement" is fine.
const sensitiveNotificationWords = <String>[
  'lean',
  'codeine',
  'benzo',
  'craving',
  'relapse',
  'clean',
  'place',
  'places',
  'sober',
  'addict',
  'recovery',
  'danger',
  'risk',
  'drug',
  'urge',
  'sos',
];

final sensitiveNotificationPattern = RegExp(
  r'\b(?:' + sensitiveNotificationWords.join('|') + r')s?\b',
  caseSensitive: false,
);

/// One Android notification channel whose visible name and description
/// switch with [NotificationPrefs.hideSensitive]. The id stays the same so
/// already-scheduled notifications keep their channel (Android only lets the
/// name and description change after creation).
class NotificationChannelCopy {
  const NotificationChannelCopy({
    required this.id,
    required this.publicName,
    required this.publicDescription,
    required this.privateName,
    required this.privateDescription,
    this.importance = NotificationChannelImportance.defaultImportance,
  });

  final String id;
  final String publicName;
  final String publicDescription;
  final String privateName;
  final String privateDescription;
  final NotificationChannelImportance importance;

  String name(bool hideSensitive) => hideSensitive ? privateName : publicName;

  String description(bool hideSensitive) =>
      hideSensitive ? privateDescription : publicDescription;
}

/// Importance values, kept free of the plugin so this file stays pure.
enum NotificationChannelImportance { min, low, defaultImportance, high, max }

/// Every Flutter-posted notification channel. Native app-lock channels live
/// in `PrivateNotifications.kt` and are covered by the Kotlin tests.
class NotificationChannels {
  static const riskWindow = NotificationChannelCopy(
    id: 'risk_window_v2',
    publicName: 'NO LEAN risk window',
    publicDescription:
        'High-visibility recovery interrupts during your configured risk window',
    privateName: 'Reminders',
    privateDescription: 'Time-of-day reminders',
    importance: NotificationChannelImportance.max,
  );

  static const dangerZone = NotificationChannelCopy(
    id: 'danger_zone_v1',
    publicName: 'NO LEAN danger zones',
    publicDescription:
        'Interrupts when you enter a place you marked as a danger zone',
    privateName: 'Alerts',
    privateDescription: 'Location alerts',
    importance: NotificationChannelImportance.max,
  );

  static const positionStatus = NotificationChannelCopy(
    id: 'position_status_v1',
    publicName: 'Position status',
    publicDescription:
        'Quiet, always-on position indicator while NO LEAN is open',
    privateName: 'Status',
    privateDescription: 'Quiet status while the app is open',
    importance: NotificationChannelImportance.low,
  );

  static const codeTimer = NotificationChannelCopy(
    id: 'code_timer_v1',
    publicName: 'NO LEAN focus timer',
    publicDescription: 'Tells you when a Code Instead block ends',
    privateName: 'Timer',
    privateDescription: 'Tells you when a timer ends',
    importance: NotificationChannelImportance.defaultImportance,
  );

  static const useCheck = NotificationChannelCopy(
    id: 'use_check_v1',
    publicName: 'NO LEAN follow-up check-in',
    publicDescription: 'Asks "did you use?" after a risky moment',
    privateName: 'Daily check-in',
    privateDescription: 'A follow-up reminder',
    importance: NotificationChannelImportance.defaultImportance,
  );

  static const zoneFollowUp = NotificationChannelCopy(
    id: 'zone_followup_v1',
    publicName: 'NO LEAN check-ins',
    publicDescription: 'Checks on you after a danger zone',
    privateName: 'Check-in',
    privateDescription: 'A follow-up reminder',
    importance: NotificationChannelImportance.high,
  );

  static const cravingCheck = NotificationChannelCopy(
    id: 'craving_check_v1',
    publicName: 'NO LEAN craving recheck',
    publicDescription: 'Asks how a logged craving is going 15 minutes later',
    privateName: 'Check-in',
    privateDescription: 'A follow-up reminder',
    importance: NotificationChannelImportance.defaultImportance,
  );

  /// #37 heads-up before a usual peak. Wording from [cravingPeakChannel].
  static final cravingPeak = NotificationChannelCopy(
    id: cravingPeakChannel.id,
    publicName: cravingPeakChannel.publicName,
    publicDescription: cravingPeakChannel.publicDescription,
    privateName: cravingPeakChannel.privateName,
    privateDescription: cravingPeakChannel.privateDescription,
    importance: NotificationChannelImportance.high,
  );

  /// #39 daily check-in. Wording from [dailyCheckInChannel].
  static final dailyCheckIn = NotificationChannelCopy(
    id: dailyCheckInChannel.id,
    publicName: dailyCheckInChannel.publicName,
    publicDescription: dailyCheckInChannel.publicDescription,
    privateName: dailyCheckInChannel.privateName,
    privateDescription: dailyCheckInChannel.privateDescription,
    importance: NotificationChannelImportance.high,
  );

  /// Every channel the Dart notification service posts through.
  static final all = <NotificationChannelCopy>[
    riskWindow,
    dangerZone,
    positionStatus,
    codeTimer,
    useCheck,
    zoneFollowUp,
    cravingCheck,
    cravingPeak,
    dailyCheckIn,
  ];
}

class NotificationActionCopy {
  const NotificationActionCopy({
    required this.id,
    required this.label,
    this.showsUserInterface = true,
    this.cancelNotification = true,
  });

  final String id;
  final String label;
  final bool showsUserInterface;
  final bool cancelNotification;
}

/// The lock-screen-visible surface of one notification, used both to post
/// and to test that private mode never leaks recovery wording.
class NotificationSurface {
  const NotificationSurface({
    required this.source,
    required this.channel,
    required this.title,
    required this.body,
    required this.ticker,
    required this.lockScreenPublic,
    this.subText,
    this.actions = const [],
    required this.hideSensitive,
  });

  final String source;
  final NotificationChannelCopy channel;
  final String title;
  final String body;
  final String ticker;
  final bool lockScreenPublic;
  final String? subText;
  final List<NotificationActionCopy> actions;
  final bool hideSensitive;

  String get channelName => channel.name(hideSensitive);
  String get channelDescription => channel.description(hideSensitive);

  /// Everything a lock screen, shade, ticker or the system Settings page
  /// can show for this notification.
  List<String> get visibleStrings => [
    channelName,
    channelDescription,
    title,
    body,
    ticker,
    if (subText != null && subText!.isNotEmpty) subText!,
    for (final action in actions) action.label,
  ];

  String get visibleText => visibleStrings.join('\n');
}

NotificationSurface _surface({
  required String source,
  required NotificationChannelCopy channel,
  required NotificationPrefs prefs,
  required String title,
  required String body,
  String? subText,
  List<NotificationActionCopy> actions = const [],
}) {
  final text = prefs.textFor(title, body);
  return NotificationSurface(
    source: source,
    channel: channel,
    title: text.title,
    body: text.body,
    ticker: text.title,
    lockScreenPublic: prefs.hideSensitive,
    subText: prefs.hideSensitive ? null : subText,
    actions: actions,
    hideSensitive: prefs.hideSensitive,
  );
}

NotificationActionCopy _action(
  NotificationPrefs prefs,
  String id,
  String sensitive,
  String neutral, {
  bool showsUserInterface = true,
  bool cancelNotification = true,
}) => NotificationActionCopy(
  id: id,
  label: prefs.label(sensitive, neutral),
  showsUserInterface: showsUserInterface,
  cancelNotification: cancelNotification,
);

NotificationSurface riskWindowSurface({
  required NotificationPrefs prefs,
  required RiskAlert alert,
  required RiskWindow riskWindow,
}) => _surface(
  source: 'riskWindow:${alert.kind.name}',
  channel: NotificationChannels.riskWindow,
  prefs: prefs,
  title: alert.title,
  body: alert.body,
  subText: riskWindow.label,
  actions: [
    _action(prefs, 'action_sos', 'OPEN SOS', 'OPEN'),
    if (alert.kind == RiskAlertKind.preWindow)
      _action(prefs, 'action_code', 'CODE INSTEAD', 'START TASK')
    else
      _action(prefs, 'action_safe', "I'M SAFE", 'OK'),
    _action(prefs, 'action_crave', 'LOG CRAVING', 'LOG'),
  ],
);

NotificationSurface dangerZoneSurface({
  required NotificationPrefs prefs,
  required String title,
  required String body,
}) => _surface(
  source: 'dangerZone',
  channel: NotificationChannels.dangerZone,
  prefs: prefs,
  title: title,
  body: body,
  actions: [
    _action(prefs, 'action_sos', 'OPEN SOS', 'OPEN'),
    _action(prefs, 'action_crave', 'LOG CRAVING', 'LOG'),
    _action(prefs, 'action_locate', 'LOCATE ME', 'CHECK'),
    _action(prefs, 'action_zone_exit', "I'M LEAVING", 'DISMISS'),
  ],
);

/// Position status is already neutralized by [buildPositionStatusText]; this
/// only wraps it with the channel, ticker and lock-screen visibility.
NotificationSurface positionStatusSurface({
  required NotificationPrefs prefs,
  required String title,
  required String body,
}) {
  final text = prefs.hideSensitive
      ? const NotificationText(
          title: neutralPositionTitle,
          body: neutralPositionBody,
        )
      : NotificationText(title: title, body: body);
  return NotificationSurface(
    source: 'positionStatus',
    channel: NotificationChannels.positionStatus,
    title: text.title,
    body: text.body,
    ticker: text.title,
    lockScreenPublic: prefs.hideSensitive,
    hideSensitive: prefs.hideSensitive,
  );
}

NotificationSurface codeTimerSurface({
  required NotificationPrefs prefs,
  required String task,
}) => _surface(
  source: 'codeTimer',
  channel: NotificationChannels.codeTimer,
  prefs: prefs,
  title: 'CODE BLOCK DONE',
  body: 'Time is up on: $task Log how it went, or start another block.',
);

NotificationSurface useCheckSurface({
  required NotificationPrefs prefs,
  required UseCheck check,
}) {
  // #30: a zone visit asks with its own title and clearer answers.
  final zone = check.trigger == UseCheckTrigger.zoneVisit;
  return _surface(
    source: 'useCheck:${check.trigger.name}',
    channel: NotificationChannels.useCheck,
    prefs: prefs,
    title: check.trigger.notificationTitle,
    body: '${check.trigger.body} Did you use? Either answer is OK.',
    actions: [
      _action(prefs, 'action_use_yes', 'YES', 'YES'),
      _action(prefs, 'action_use_no', zone ? 'NO, STAYED CLEAN' : 'NO', 'NO'),
      _action(prefs, 'action_use_later', zone ? 'NOT SURE' : 'LATER', 'LATER'),
    ],
  );
}

NotificationSurface zoneFollowUpSurface({
  required NotificationPrefs prefs,
  required int index,
}) {
  final text = zoneFollowUpSource(index);
  return _surface(
    source: 'zoneFollowUp:$index',
    channel: NotificationChannels.zoneFollowUp,
    prefs: prefs,
    title: text.title,
    body: text.body,
    actions: [
      _action(prefs, 'action_safe', "I'M OK", 'OK', showsUserInterface: false),
      _action(prefs, 'action_sos', 'OPEN SOS', 'OPEN'),
    ],
  );
}

/// Sensitive copy for a zone follow-up, before privacy is applied.
NotificationText zoneFollowUpSource(int index) => NotificationText(
  title: 'CHECKING IN',
  body: index == 0
      ? "It's been 15 minutes. Still OK? Tap if you need SOS."
      : 'Quick check: how are you doing? No judgement either way.',
);

NotificationSurface cravingCheckSurface({required NotificationPrefs prefs}) =>
    _surface(
      source: 'cravingCheck',
      channel: NotificationChannels.cravingCheck,
      prefs: prefs,
      title: 'CRAVING RECHECK',
      body: '15 minutes on. Rate it again: did it pass, ease or grow?',
      actions: [
        _action(prefs, 'action_recheck', 'RATE IT NOW', 'OPEN'),
        _action(prefs, 'action_used', 'I USED', 'LOG'),
      ],
    );

/// #37 usual-peak heads-up.
NotificationSurface cravingPeakSurface({
  required NotificationPrefs prefs,
  required String title,
  required String body,
}) => _surface(
  source: 'cravingPeak',
  channel: NotificationChannels.cravingPeak,
  prefs: prefs,
  title: title,
  body: body,
  actions: [
    _action(prefs, 'action_code', 'CODE INSTEAD', 'START TASK'),
    _action(prefs, 'action_sos', 'OPEN SOS', 'OPEN'),
  ],
);

/// #39 daily check-in. Its private wording comes from [dailyCheckInCopy]
/// (custom labels, not [NotificationPrefs.textFor]).
NotificationSurface dailyCheckInSurface({
  required NotificationPrefs prefs,
  bool usedOpensApp = false,
}) {
  final copy = dailyCheckInCopy(hideSensitive: prefs.hideSensitive);
  return NotificationSurface(
    source: 'dailyCheckIn',
    channel: NotificationChannels.dailyCheckIn,
    title: copy.title,
    body: copy.body,
    ticker: copy.title,
    lockScreenPublic: prefs.hideSensitive,
    hideSensitive: prefs.hideSensitive,
    actions: [
      NotificationActionCopy(
        id: checkInOkayAction,
        label: copy.okayLabel,
        showsUserInterface: false,
      ),
      NotificationActionCopy(
        id: checkInStrugglingAction,
        label: copy.strugglingLabel,
      ),
      NotificationActionCopy(
        id: usedOpensApp ? checkInUsedOpenAction : checkInUsedAction,
        label: copy.usedLabel,
        showsUserInterface: usedOpensApp,
      ),
    ],
  );
}

/// Every Flutter notification the app can post, with representative copy.
/// Native app-lock notifications are listed in [nativeNotificationSources].
List<NotificationSurface> everyFlutterNotificationSurface(
  NotificationPrefs prefs, {
  RiskAlert? alert,
  RiskWindow riskWindow = const RiskWindow.defaultWindow(),
  String zoneTitle = 'DANGER ZONE',
  String zoneBody = 'You are near a marked place. Leave if you can.',
  String positionTitle = 'INSIDE Depot',
  String positionBody = 'Nearest place is 200 m away.',
  String codeTask = 'ride out a craving',
  UseCheck? useCheck,
}) {
  final sampleAlert =
      alert ??
      RiskAlert(
        id: 1,
        kind: RiskAlertKind.windowOpen,
        minuteOfDay: 17 * 60,
        title: 'RISK WINDOW OPEN // 17:00—21:00',
        body: 'Clean since 1 Nov. Log the craving or open SOS.',
      );
  final preAlert = RiskAlert(
    id: 0,
    kind: RiskAlertKind.preWindow,
    minuteOfDay: 16 * 60 + 45,
    title: 'RISK WINDOW IN 15 MIN // 17:00—21:00',
    body: 'Set the plan before it starts: SOS, move, or call.',
  );
  final check =
      useCheck ??
      UseCheck(
        trigger: UseCheckTrigger.craving,
        triggeredAt: DateTime(2026, 11, 26, 18),
      );
  return [
    riskWindowSurface(prefs: prefs, alert: sampleAlert, riskWindow: riskWindow),
    riskWindowSurface(prefs: prefs, alert: preAlert, riskWindow: riskWindow),
    dangerZoneSurface(prefs: prefs, title: zoneTitle, body: zoneBody),
    positionStatusSurface(
      prefs: prefs,
      title: positionTitle,
      body: positionBody,
    ),
    codeTimerSurface(prefs: prefs, task: codeTask),
    useCheckSurface(prefs: prefs, check: check),
    useCheckSurface(
      prefs: prefs,
      check: UseCheck(
        trigger: UseCheckTrigger.zoneExit,
        triggeredAt: DateTime(2026, 11, 26, 18),
      ),
    ),
    useCheckSurface(
      prefs: prefs,
      check: UseCheck(
        trigger: UseCheckTrigger.zoneVisit,
        triggeredAt: DateTime(2026, 11, 26, 18),
      ),
    ),
    zoneFollowUpSurface(prefs: prefs, index: 0),
    zoneFollowUpSurface(prefs: prefs, index: 1),
    cravingCheckSurface(prefs: prefs),
    cravingPeakSurface(
      prefs: prefs,
      title: 'USUAL PEAK IN 30 MIN',
      body: 'Cravings often hit around 21:00. Have a plan ready.',
    ),
    dailyCheckInSurface(prefs: prefs),
    dailyCheckInSurface(prefs: prefs, usedOpensApp: true),
  ];
}

/// Native (Kotlin) notification sources, for the enumeration test that
/// reads their wording helpers. Keep in sync with PrivateNotifications.kt.
const nativeNotificationSources = <String>[
  'appLockHealth',
  'appLockService',
  'appLockBlock',
];
