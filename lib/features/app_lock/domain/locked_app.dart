// PLACEHOLDER (not wired to any enforcement yet).
//
// Groundwork for "lock specific apps" (e.g. a dealer's chat app, a payment
// app) during risky times. Nothing here blocks anything today; the
// `AppLockGateway` stub reports that locking is unavailable.
//
// This is NOT the existing in-app lock (`recovery/domain/app_lock_session.dart`),
// which locks NO LEAN itself behind PIN/biometrics.

import '../../recovery/domain/risk_window.dart';

/// One app the user wants blocked. Identified by Android package name.
class LockedApp {
  const LockedApp({
    required this.packageName,
    required this.label,
    this.enabled = true,
  });

  /// e.g. `com.whatsapp`. Unique key.
  final String packageName;

  /// Display name captured when the user picked the app.
  final String label;

  /// Lets the user pause one entry without deleting it.
  final bool enabled;

  LockedApp copyWith({String? label, bool? enabled}) => LockedApp(
    packageName: packageName,
    label: label ?? this.label,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object> toJson() => {
    'packageName': packageName,
    'label': label,
    'enabled': enabled,
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LockedApp &&
      other.packageName == packageName &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(packageName, label, enabled);
}

/// When locked apps should actually be blocked.
enum AppLockSchedule {
  /// Never block (feature configured but paused).
  off,

  /// Block at all times.
  always,

  /// Block only inside the user's risk window (reuses [RiskWindow]).
  riskWindow,

  /// Block inside [AppLockPolicy.customWindow].
  custom,
}

/// What to block and when. Pure; enforcement lives behind `AppLockGateway`.
///
/// TODO(app-lock): persist under a new state key (e.g. `appLockPolicy`)
/// once enforcement exists; follow the existing rules: imported preferences
/// never switch it on, and loosening it (removing an app, turning it off)
/// should require the relapse lock just like deleting a danger zone.
class AppLockPolicy {
  const AppLockPolicy({
    this.apps = const [],
    this.schedule = AppLockSchedule.off,
    this.customWindow,
    this.lockInsideDangerZones = false,
  });

  final List<LockedApp> apps;
  final AppLockSchedule schedule;

  /// Used only when [schedule] is [AppLockSchedule.custom].
  final RiskWindow? customWindow;

  /// Hook: also block while the user is inside a danger zone.
  /// TODO(app-lock): feed from zone presence once enforcement exists.
  final bool lockInsideDangerZones;

  /// Package names currently enabled for locking.
  Set<String> get enabledPackages => {
    for (final app in apps)
      if (app.enabled) app.packageName,
  };

  /// Whether the policy would block right now. Risk-window/schedule hook for
  /// the future enforcement service; nothing calls it to block yet.
  bool isActiveAt(
    DateTime at, {
    required RiskWindow riskWindow,
    bool insideDangerZone = false,
  }) {
    if (enabledPackages.isEmpty) return false;
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
}
