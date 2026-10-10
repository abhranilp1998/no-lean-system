// App lock for other apps (Oct 2026): what to block and when.
//
// Pure model. Enforcement is native (Android UsageStats + a foreground
// service, see `services/app_lock_gateway.dart`); the exit plan that keeps
// legitimate use possible lives in `exit_plan.dart`.
//
// This is NOT the in-app lock (`recovery/domain/app_lock_session.dart`),
// which locks NO LEAN itself behind PIN/biometrics.

import '../../recovery/domain/risk_window.dart';
import 'never_lockable.dart';

/// One app the user wants blocked. Identified by Android package name.
class LockedApp {
  const LockedApp({
    required this.packageName,
    required this.label,
    this.enabled = true,
    this.paymentApp = false,
  });

  /// e.g. `com.whatsapp`. Unique key.
  final String packageName;

  /// Display name captured when the user picked the app.
  final String label;

  /// Lets the user pause one entry without deleting it.
  final bool enabled;

  /// Payment apps get the quick exit path (shorter wait).
  final bool paymentApp;

  LockedApp copyWith({String? label, bool? enabled, bool? paymentApp}) =>
      LockedApp(
        packageName: packageName,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        paymentApp: paymentApp ?? this.paymentApp,
      );

  Map<String, Object> toJson() => {
    'packageName': packageName,
    'label': label,
    'enabled': enabled,
    'paymentApp': paymentApp,
  };

  factory LockedApp.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Locked app must be an object.');
    }
    final packageName = json['packageName'];
    final label = json['label'];
    if (packageName is! String ||
        packageName.trim().isEmpty ||
        label is! String) {
      throw const FormatException('Locked app is missing required fields.');
    }
    return LockedApp(
      packageName: packageName.trim(),
      label: label.trim(),
      enabled: json['enabled'] != false,
      paymentApp: json['paymentApp'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LockedApp &&
      other.packageName == packageName &&
      other.label == label &&
      other.enabled == enabled &&
      other.paymentApp == paymentApp;

  @override
  int get hashCode => Object.hash(packageName, label, enabled, paymentApp);
}

/// When locked apps should actually be blocked.
enum AppLockSchedule {
  /// Only the danger-zone rule (if on) blocks.
  off,

  /// Block at all times.
  always,

  /// Block only inside the user's risk window (reuses [RiskWindow]).
  riskWindow,

  /// Block inside [AppLockPolicy.customWindow].
  custom,
}

extension AppLockScheduleLabel on AppLockSchedule {
  String get label => switch (this) {
    AppLockSchedule.off => 'Danger zones only',
    AppLockSchedule.always => 'Always',
    AppLockSchedule.riskWindow => 'Risk window',
    AppLockSchedule.custom => 'Custom window',
  };
}

/// What to block and when. Pure; enforcement lives behind `AppLockGateway`.
///
/// Persisted in state v13+ under `appLockPolicy`. Never exported as a
/// portable preference and never switched on by an import. Loosening it
/// (see [isLooserThan]) needs the relapse lock, like deleting a zone.
class AppLockPolicy {
  const AppLockPolicy({
    this.enabled = false,
    this.apps = const [],
    this.schedule = AppLockSchedule.riskWindow,
    this.customWindow,
    this.lockInsideDangerZones = true,
    this.dailyUnlockBudget = defaultDailyUnlockBudget,
  });

  static const defaultDailyUnlockBudget = 3;
  static const maxDailyUnlockBudget = 10;
  static const maxApps = 50;

  /// Master switch.
  final bool enabled;
  final List<LockedApp> apps;
  final AppLockSchedule schedule;

  /// Used only when [schedule] is [AppLockSchedule.custom].
  final RiskWindow? customWindow;

  /// Also block while the user is inside a danger zone.
  final bool lockInsideDangerZones;

  /// "I need this app" unlocks per day before the PIN is required.
  final int dailyUnlockBudget;

  AppLockPolicy copyWith({
    bool? enabled,
    List<LockedApp>? apps,
    AppLockSchedule? schedule,
    RiskWindow? customWindow,
    bool? lockInsideDangerZones,
    int? dailyUnlockBudget,
  }) => AppLockPolicy(
    enabled: enabled ?? this.enabled,
    apps: apps ?? this.apps,
    schedule: schedule ?? this.schedule,
    customWindow: customWindow ?? this.customWindow,
    lockInsideDangerZones: lockInsideDangerZones ?? this.lockInsideDangerZones,
    dailyUnlockBudget: dailyUnlockBudget ?? this.dailyUnlockBudget,
  );

  /// Drops never-lockable and duplicate packages and clamps the budget.
  AppLockPolicy sanitized({Set<String> extraProtected = const {}}) {
    final seen = <String>{};
    final clean = [
      for (final app in apps)
        if (!isNeverLockable(app.packageName, extra: extraProtected) &&
            seen.add(app.packageName))
          app,
    ].take(maxApps).toList(growable: false);
    return AppLockPolicy(
      enabled: enabled,
      apps: clean,
      schedule: schedule,
      customWindow: customWindow,
      lockInsideDangerZones: lockInsideDangerZones,
      dailyUnlockBudget: dailyUnlockBudget.clamp(0, maxDailyUnlockBudget),
    );
  }

  /// Package names currently enabled for locking.
  Set<String> get enabledPackages => {
    for (final app in apps)
      if (app.enabled && !isNeverLockable(app.packageName)) app.packageName,
  };

  /// True when enforcement has anything to do (the service should run).
  bool get armed =>
      enabled &&
      enabledPackages.isNotEmpty &&
      (schedule != AppLockSchedule.off || lockInsideDangerZones);

  LockedApp? appFor(String packageName) =>
      apps.where((app) => app.packageName == packageName).firstOrNull;

  /// The time window that applies to [schedule], if any.
  RiskWindow? effectiveWindow(RiskWindow riskWindow) => switch (schedule) {
    AppLockSchedule.riskWindow => riskWindow,
    AppLockSchedule.custom => customWindow,
    _ => null,
  };

  /// Whether the policy blocks right now.
  bool isActiveAt(
    DateTime at, {
    required RiskWindow riskWindow,
    bool insideDangerZone = false,
  }) {
    if (!enabled || enabledPackages.isEmpty) return false;
    if (lockInsideDangerZones && insideDangerZone) return true;
    return switch (schedule) {
      AppLockSchedule.off => false,
      AppLockSchedule.always => true,
      AppLockSchedule.riskWindow => riskWindow.contains(at),
      AppLockSchedule.custom => customWindow?.contains(at) ?? false,
    };
  }

  /// Whether [packageName] should be blocked at [at].
  bool blocks(
    String packageName,
    DateTime at, {
    required RiskWindow riskWindow,
    bool insideDangerZone = false,
  }) =>
      enabledPackages.contains(packageName) &&
      isActiveAt(
        at,
        riskWindow: riskWindow,
        insideDangerZone: insideDangerZone,
      );

  /// Whether moving from [previous] to this policy makes blocking weaker
  /// (needs the relapse lock). Tightening is always free.
  bool isLooserThan(AppLockPolicy previous) {
    if (!previous.enabled) return false;
    if (!enabled) return true;
    if (!enabledPackages.containsAll(previous.enabledPackages)) return true;
    if (schedule != previous.schedule && schedule != AppLockSchedule.always) {
      return true;
    }
    if (schedule == AppLockSchedule.custom &&
        previous.schedule == AppLockSchedule.custom &&
        customWindow?.toJson().toString() !=
            previous.customWindow?.toJson().toString()) {
      return true;
    }
    if (previous.lockInsideDangerZones && !lockInsideDangerZones) return true;
    if (dailyUnlockBudget > previous.dailyUnlockBudget) return true;
    final paymentBefore = {
      for (final app in previous.apps)
        if (app.paymentApp) app.packageName,
    };
    // Marking an already-locked app as a payment app shortens its wait.
    final lockedBefore = previous.enabledPackages;
    return apps.any(
      (app) =>
          app.paymentApp &&
          lockedBefore.contains(app.packageName) &&
          !paymentBefore.contains(app.packageName),
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'apps': apps.map((app) => app.toJson()).toList(),
    'schedule': schedule.name,
    'customWindow': customWindow?.toJson(),
    'lockInsideDangerZones': lockInsideDangerZones,
    'dailyUnlockBudget': dailyUnlockBudget,
  };

  /// Tolerant decode: malformed parts fall back to safe defaults. A
  /// malformed `enabled` reads as off (it never locks anything by surprise).
  factory AppLockPolicy.fromJson(Object? json) {
    if (json is! Map) return const AppLockPolicy();
    final apps = <LockedApp>[];
    final rawApps = json['apps'];
    if (rawApps is List) {
      for (final raw in rawApps) {
        try {
          apps.add(LockedApp.fromJson(raw));
        } on FormatException {
          /* Skip one bad entry, keep the rest. */
        }
      }
    }
    final budget = json['dailyUnlockBudget'];
    return AppLockPolicy(
      enabled: json['enabled'] == true,
      apps: apps,
      schedule: AppLockSchedule.values.firstWhere(
        (value) => value.name == json['schedule'],
        orElse: () => AppLockSchedule.riskWindow,
      ),
      customWindow: json['customWindow'] is Map
          ? RiskWindow.fromJson(json['customWindow'])
          : null,
      lockInsideDangerZones: json['lockInsideDangerZones'] != false,
      dailyUnlockBudget: budget is num && budget.isFinite
          ? budget.round()
          : defaultDailyUnlockBudget,
    ).sanitized();
  }

  @override
  bool operator ==(Object other) =>
      other is AppLockPolicy &&
      other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}
