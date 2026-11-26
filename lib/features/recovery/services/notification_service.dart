import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/use_check.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_theme.dart';
import '../domain/notification_copy.dart';
import '../domain/notification_policy.dart';
import '../domain/risk_alert_plan.dart';
import '../domain/risk_window.dart';

/// Monochrome status-bar icon (`res/drawable/ic_stat_no_lean.xml`). Android
/// draws small icons from alpha only, and the name is resolved at runtime, so
/// `res/raw/keep.xml` must keep it from the release resource shrinker.
const notificationSmallIcon = 'ic_stat_no_lean';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  /// Quiet hours and lock-screen privacy. The controller keeps this in sync;
  /// background isolates pass prefs read from the state file instead.
  NotificationPrefs prefs = const NotificationPrefs();

  final _actionStreamController = StreamController<String>.broadcast();
  Stream<String> get actionStream => _actionStreamController.stream;

  /// Simulates a tapped notification action in tests.
  @visibleForTesting
  void debugEmitAction(String actionId) =>
      _actionStreamController.add(actionId);

  Future<void> _initialize({required bool requestPermission}) async {
    if (!_initialized) {
      try {
        final zone = await const MethodChannel(
          'no_lean/timezone',
        ).invokeMethod<String>('get');
        if (zone != null) {
          tz.setLocalLocation(tz.getLocation(zone));
        }
      } catch (_) {
        // UTC is the safe fallback if a platform does not expose its IANA zone.
      }

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(notificationSmallIcon),
        ),
        onDidReceiveNotificationResponse: (response) {
          final action = actionFor(
            response.actionId,
            response.id,
            response.payload,
          );
          if (action != null) _actionStreamController.add(action);
        },
      );
      _initialized = true;
    }

    if (requestPermission && !_permissionRequested) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      _permissionRequested = true;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether Android currently allows exact alarms for this app.
  Future<bool> exactAlarmsAllowed() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Alarms & reminders" grant. Returns the new state.
  Future<bool> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {
      /* Older Android versions grant exact alarms implicitly. */
    }
    return exactAlarmsAllowed();
  }

  Future<void> scheduleRiskWindow(
    List<RiskAlert> alerts, {
    required RiskWindow riskWindow,
  }) async {
    try {
      await _initialize(requestPermission: true);
      await _cancelScheduled();
      if (alerts.isEmpty) return;

      var exactAllowed = await exactAlarmsAllowed();
      for (final alert in alerts) {
        final hour = alert.minuteOfDay ~/ 60;
        final minute = alert.minuteOfDay % 60;
        final now = tz.TZDateTime.now(tz.local);
        var scheduled = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
        if (!scheduled.isAfter(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
        }
        // Risk-window alerts are critical: quiet hours never mute them.
        final surface = riskWindowSurface(
          prefs: prefs,
          alert: alert,
          riskWindow: riskWindow,
        );
        final mode = await scheduleWithExactFallback(
          exactAllowed: exactAllowed,
          schedule: (mode) => _plugin.zonedSchedule(
            alert.id,
            surface.title,
            surface.body,
            scheduled,
            _details(surface),
            androidScheduleMode: mode,
            matchDateTimeComponents: DateTimeComponents.time,
          ),
        );
        exactAllowed = mode == AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {
      // Notification support must never prevent local recovery tracking.
    }
  }

  NotificationDetails _details(NotificationSurface surface) =>
      NotificationDetails(
        android: androidDetailsFor(
          surface,
          color: red,
          colorized: !surface.hideSensitive,
          enableLights: true,
          ledColor: cyan,
        ),
      );

  /// Default lock-screen visibility when private notifications are off:
  /// Android redacts the content on lock screens set to hide sensitive
  /// notifications. When private notifications are on, each post uses
  /// [NotificationVisibility.public] because the wording is already
  /// neutral, so the lock screen shows "Reminder" instead of
  /// "Contents hidden". flutter_local_notifications 19.5 cannot set a
  /// custom publicVersion.
  static const lockScreenVisibility = NotificationVisibility.private;

  /// Rewrites every channel's visible name and description to match
  /// [prefs], and refreshes a pending use-check so it does not fire with
  /// the old wording. Risk-window alerts are rescheduled by the
  /// controller when the setting changes.
  Future<void> applyPrivacy() async {
    try {
      await _initialize(requestPermission: false);
      final hide = prefs.hideSensitive;
      for (final channel in NotificationChannels.all) {
        await _android?.createNotificationChannel(
          AndroidNotificationChannel(
            channel.id,
            channel.name(hide),
            description: channel.description(hide),
            importance: importanceFor(channel.importance),
          ),
        );
      }
      final check = await peekPendingUseCheck();
      if (check != null) await scheduleUseCheck(check);
    } catch (_) {
      // Channel updates must never block the setting itself.
    }
  }

  bool _launchActionTaken = false;

  /// The action button that cold-started the app, if any. Android does not
  /// deliver it through the response callback when the process was dead
  /// (e.g. OPEN SOS on a background danger-zone alert). Returned once.
  Future<String?> takeLaunchAction() async {
    if (_launchActionTaken) return null;
    _launchActionTaken = true;
    try {
      await _initialize(requestPermission: false);
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final r = details?.notificationResponse;
        return actionFor(r?.actionId, r?.id, r?.payload);
      }
    } catch (_) {
      // No launch details on this platform.
    }
    return null;
  }

  static const zoneAlertId = 600;

  /// Loud danger-zone notification. Requests a full-screen intent; Android
  /// only honours it where the app may use full-screen intents (and shows a
  /// heads-up notification otherwise). "I'M LEAVING" dismisses in one tap.
  Future<void> showZoneAlert({
    required String title,
    required String body,
    NotificationPrefs? prefs,
  }) async {
    // Zone alerts are critical: quiet hours never mute them.
    final policy = prefs ?? this.prefs;
    final surface = dangerZoneSurface(prefs: policy, title: title, body: body);
    try {
      await _initialize(requestPermission: false);
      await _plugin.show(
        zoneAlertId,
        surface.title,
        surface.body,
        payload: zoneAlertPayload,
        NotificationDetails(
          android: androidDetailsFor(
            surface,
            color: red,
            colorized: !policy.hideSensitive,
            fullScreenIntent: true,
          ),
        ),
      );
    } catch (_) {
      // A missing notification must never break location handling.
    }
  }

  static const positionStatusId = 800;

  /// Always-on position indicator while the app is open (see
  /// `PositionStatusHost`). Deliberately separate from every alert:
  /// - its own low-importance channel, silent, no heads-up, no vibration;
  /// - never filtered by quiet hours or the zone de-duplication (it is not a
  ///   [NotificationKind] at all), and it never replaces [zoneAlertId];
  /// - `ongoing` so it is not cleared by "Clear all" (Android 14+ still lets
  ///   the user swipe it away; the next refresh re-posts it);
  /// - `timeoutAfter` removes it if the process dies without a lifecycle
  ///   callback (e.g. swiped from recents), since the host refreshes it at
  ///   least every 15 s while the app is open.
  /// Uses the same monochrome small icon as every other notification, which
  /// `res/raw/keep.xml` already keeps from the resource shrinker.
  Future<void> showPositionStatus({
    required String title,
    required String body,
  }) async {
    try {
      await _initialize(requestPermission: true);
      final surface = positionStatusSurface(
        prefs: prefs,
        title: title,
        body: body,
      );
      await _plugin.show(
        positionStatusId,
        surface.title,
        surface.body,
        NotificationDetails(
          android: androidDetailsFor(
            surface,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            playSound: false,
            enableVibration: false,
            showWhen: false,
            timeoutAfter: positionStatusTimeout.inMilliseconds,
            category: AndroidNotificationCategory.status,
          ),
        ),
      );
    } catch (_) {
      // The indicator is optional; it must never break location handling.
    }
  }

  /// Safety net for an orphaned position notification; must stay well above
  /// the host's 15 s refresh interval.
  static const positionStatusTimeout = Duration(minutes: 2);

  Future<void> cancelPositionStatus() async {
    try {
      await _plugin.cancel(positionStatusId);
    } catch (_) {
      // Optional on tests and unsupported platforms.
    }
  }

  static const codeTimerId = 700;

  /// Non-critical: tells the user a Code Instead block ended while the app
  /// was in the background. Skipped entirely when it would land in quiet
  /// hours. Returns whether it was scheduled.
  Future<bool> scheduleCodeTimer({
    required DateTime endsAt,
    required String task,
  }) async {
    if (!prefs.allows(NotificationKind.codeTimer, endsAt)) {
      await cancelCodeTimer();
      return false;
    }
    final surface = codeTimerSurface(prefs: prefs, task: task);
    try {
      await _initialize(requestPermission: true);
      final when = tz.TZDateTime.from(endsAt, tz.local);
      await scheduleWithExactFallback(
        exactAllowed: await exactAlarmsAllowed(),
        schedule: (mode) => _plugin.zonedSchedule(
          codeTimerId,
          surface.title,
          surface.body,
          when,
          NotificationDetails(android: androidDetailsFor(surface)),
          androidScheduleMode: mode,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelCodeTimer() async {
    try {
      await _plugin.cancel(codeTimerId);
    } catch (_) {
      // Optional on tests and unsupported platforms.
    }
  }

  static const useCheckId = 740;
  static const useCheckPrefsKey = 'use_check_pending_v1';

  /// (A) "Did you use?" with YES / NO / LATER. The trigger is kept in prefs
  /// so a tapped action (which carries no payload) can prefill the logger.
  Future<bool> scheduleUseCheck(UseCheck check, {DateTime? at}) async {
    var due = at ?? check.dueAt;
    final store = await SharedPreferences.getInstance();
    await store.setString(useCheckPrefsKey, check.encode());
    // A visit imported late can already be past due: ask in a few seconds
    // rather than scheduling into the past.
    final soonest = DateTime.now().add(const Duration(seconds: 10));
    if (due.isBefore(soonest)) due = soonest;
    // Non-critical: muted in quiet hours. The in-app card still waits.
    if (!prefs.allows(NotificationKind.cravingCheck, due)) return false;
    final surface = useCheckSurface(prefs: prefs, check: check);
    try {
      await _initialize(requestPermission: true);
      await scheduleWithExactFallback(
        exactAllowed: await exactAlarmsAllowed(),
        schedule: (mode) => _plugin.zonedSchedule(
          useCheckId,
          surface.title,
          surface.body,
          tz.TZDateTime.from(due, tz.local),
          NotificationDetails(android: androidDetailsFor(surface)),
          androidScheduleMode: mode,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A tap on the body of the use-check notification opens the prompt.
  static const useCheckOpenAction = 'use_check_open';

  /// Tapping the zone alert itself opens the full-screen SOS (P0-3).
  static String? actionFor(
    String? actionId,
    int? notificationId, [
    String? payload,
  ]) {
    if (actionId != null && actionId.isNotEmpty) return actionId;
    if (payload == zoneAlertPayload) return 'action_zone_open';
    return notificationId == useCheckId ? useCheckOpenAction : null;
  }

  Future<void> cancelUseCheck() async {
    final store = await SharedPreferences.getInstance();
    await store.remove(useCheckPrefsKey);
    try {
      await _initialize(requestPermission: false);
      await _plugin.cancel(useCheckId);
    } catch (_) {}
  }

  /// Reads the pending check without clearing it.
  Future<UseCheck?> peekPendingUseCheck() => takePendingUseCheck(clear: false);

  Future<UseCheck?> takePendingUseCheck({bool clear = true}) async {
    final store = await SharedPreferences.getInstance();
    final check = UseCheck.decode(store.getString(useCheckPrefsKey));
    if (clear) await store.remove(useCheckPrefsKey);
    return check;
  }

  static const zoneAlertPayload = 'zone_alert';

  /// Follow-up check-ins after a zone entry (plan P0-3), 15 and 45 min on.
  static const zoneFollowUpIds = [720, 721];
  static const zoneFollowUpDelays = [
    Duration(minutes: 15),
    Duration(minutes: 45),
  ];

  /// Schedules "are you OK?" check-ins after a zone entry. Safety-relevant,
  /// so quiet hours don't mute them. Returns how many were scheduled.
  Future<int> scheduleZoneFollowUps({
    required DateTime enteredAt,
    required String zoneName,
  }) async {
    var scheduled = 0;
    for (var i = 0; i < zoneFollowUpIds.length; i++) {
      final at = enteredAt.add(zoneFollowUpDelays[i]);
      final surface = zoneFollowUpSurface(prefs: prefs, index: i);
      try {
        await _initialize(requestPermission: true);
        await scheduleWithExactFallback(
          exactAllowed: await exactAlarmsAllowed(),
          schedule: (mode) => _plugin.zonedSchedule(
            zoneFollowUpIds[i],
            surface.title,
            surface.body,
            tz.TZDateTime.from(at, tz.local),
            NotificationDetails(android: androidDetailsFor(surface)),
            androidScheduleMode: mode,
          ),
        );
        scheduled++;
      } catch (_) {}
    }
    return scheduled;
  }

  static const cravingCheckId = 710;

  /// Delay before the craving recheck prompt.
  static const cravingCheckDelay = Duration(minutes: 15);

  /// Non-critical: asks "how is the craving now?" 15 minutes after a craving
  /// was logged. Skipped when it would land in quiet hours. Returns whether
  /// it was scheduled.
  Future<bool> scheduleCravingCheck({required DateTime at}) async {
    if (!prefs.allows(NotificationKind.cravingCheck, at)) {
      await cancelCravingCheck();
      return false;
    }
    final surface = cravingCheckSurface(prefs: prefs);
    try {
      await _initialize(requestPermission: true);
      await scheduleWithExactFallback(
        exactAllowed: await exactAlarmsAllowed(),
        schedule: (mode) => _plugin.zonedSchedule(
          cravingCheckId,
          surface.title,
          surface.body,
          tz.TZDateTime.from(at, tz.local),
          NotificationDetails(android: androidDetailsFor(surface)),
          androidScheduleMode: mode,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelCravingCheck() async {
    try {
      await _plugin.cancel(cravingCheckId);
    } catch (_) {
      // Optional on tests and unsupported platforms.
    }
  }

  Future<void> cancelRiskWindow() async {
    try {
      // Cancellation does not require permission and Android can service it
      // without initializing the notification callback pipeline first.
      await _cancelScheduled();
    } catch (_) {
      // Notifications are optional on tests and unsupported platforms.
    }
  }

  Future<void> _cancelScheduled() async {
    for (var id = riskAlertFirstId; id <= riskAlertLastId; id++) {
      await _plugin.cancel(id);
    }
  }
}

/// Maps our pure importance values onto the plugin's.
Importance importanceFor(NotificationChannelImportance value) =>
    switch (value) {
      NotificationChannelImportance.min => Importance.min,
      NotificationChannelImportance.low => Importance.low,
      NotificationChannelImportance.defaultImportance =>
        Importance.defaultImportance,
      NotificationChannelImportance.high => Importance.high,
      NotificationChannelImportance.max => Importance.max,
    };

Priority priorityFor(NotificationChannelImportance value) => switch (value) {
  NotificationChannelImportance.min => Priority.min,
  NotificationChannelImportance.low => Priority.low,
  NotificationChannelImportance.defaultImportance => Priority.defaultPriority,
  NotificationChannelImportance.high => Priority.high,
  NotificationChannelImportance.max => Priority.max,
};

/// Lock screens show the (already-neutral) wording when privacy is on;
/// otherwise they stay private so a hide-sensitive lock screen redacts them.
NotificationVisibility visibilityFor(bool hideSensitive) => hideSensitive
    ? NotificationVisibility.public
    : NotificationVisibility.private;

/// Builds the Android payload for any [NotificationSurface]. Tests can inspect
/// the surface itself; this is the one place channel/ticker/visibility land.
AndroidNotificationDetails androidDetailsFor(
  NotificationSurface surface, {
  Color? color,
  bool colorized = false,
  bool enableLights = false,
  Color? ledColor,
  bool enableVibration = true,
  bool playSound = true,
  bool fullScreenIntent = false,
  bool ongoing = false,
  bool autoCancel = true,
  bool onlyAlertOnce = false,
  bool silent = false,
  bool showWhen = true,
  int? timeoutAfter,
  AndroidNotificationCategory? category,
}) => AndroidNotificationDetails(
  surface.channel.id,
  surface.channelName,
  channelDescription: surface.channelDescription,
  importance: importanceFor(surface.channel.importance),
  priority: priorityFor(surface.channel.importance),
  color: color,
  colorized: colorized,
  enableLights: enableLights,
  ledColor: ledColor,
  enableVibration: enableVibration,
  playSound: playSound,
  fullScreenIntent: fullScreenIntent,
  ongoing: ongoing,
  autoCancel: autoCancel,
  onlyAlertOnce: onlyAlertOnce,
  silent: silent,
  showWhen: showWhen,
  timeoutAfter: timeoutAfter,
  visibility: visibilityFor(surface.hideSensitive),
  category: category ?? AndroidNotificationCategory.reminder,
  ticker: surface.ticker,
  subText: surface.subText,
  styleInformation: BigTextStyleInformation(
    surface.body,
    contentTitle: surface.title,
  ),
  actions: [
    for (final action in surface.actions)
      AndroidNotificationAction(
        action.id,
        action.label,
        showsUserInterface: action.showsUserInterface,
        cancelNotification: action.cancelNotification,
      ),
  ],
);

/// Schedules with exact alarms when Android allows them and falls back to
/// inexact delivery when they are unavailable or revoked mid-schedule.
/// Returns the mode that was actually used.
Future<AndroidScheduleMode> scheduleWithExactFallback({
  required bool exactAllowed,
  required Future<void> Function(AndroidScheduleMode mode) schedule,
}) async {
  if (exactAllowed) {
    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
      return AndroidScheduleMode.exactAllowWhileIdle;
    } on PlatformException catch (error) {
      if (error.code != 'exact_alarms_not_permitted') rethrow;
    }
  }
  await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
  return AndroidScheduleMode.inexactAllowWhileIdle;
}
