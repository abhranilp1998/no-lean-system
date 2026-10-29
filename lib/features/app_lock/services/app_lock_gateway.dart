// Platform boundary for locking other apps.
//
// Android implementation (Oct 2026), `MethodChannel('no_lean/app_lock')`,
// native code in android/app/src/main/kotlin/com/nolean/no_lean/AppLock*.kt:
//
// - Detection: UsageStatsManager.queryEvents() polled about once a second by
//   a lightweight foreground service (`AppLockService`, type specialUse)
//   while the lock is armed. Needs PACKAGE_USAGE_STATS, which the user grants
//   on the system "Usage access" screen after NO LEAN's disclosure page.
// - Blocking UI: the service brings NO LEAN to the front with the blocked
//   package; Flutter shows `AppBlockScreen` (exit plan, SOS, Call 112, Go
//   home). Android 10+ only lets a background app open an activity when it
//   may "display over other apps" (SYSTEM_ALERT_WINDOW), so that is the
//   second grant. Without it the service posts a tap-to-open notification.
// - No AccessibilityService on purpose (Google Play's Accessibility API
//   policy). PACKAGE_USAGE_STATS, SYSTEM_ALERT_WINDOW and a specialUse
//   foreground service each still need a Play Console declaration; see
//   docs/CHANGES_AND_ROADMAP.md.
// - Fail-safe: if usage access is revoked or the service dies, nothing is
//   blocked (NO LEAN only ever opens itself on top; Home and Back always
//   work) and the app shows a re-grant banner.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Whether app locking can run right now.
enum AppLockAvailability {
  /// Not Android (or the native side is missing): nothing can be blocked.
  notImplemented,

  /// Usage access (and/or display over other apps) is missing.
  permissionRequired,

  /// Enforcement is possible.
  available,
}

/// Native health of the app lock.
class AppLockStatus {
  const AppLockStatus({
    required this.supported,
    this.usageAccess = false,
    this.overlay = false,
    this.serviceRunning = false,
    this.notifications = true,
  });

  const AppLockStatus.unsupported() : this(supported: false);

  final bool supported;

  /// PACKAGE_USAGE_STATS granted on the Usage access screen.
  final bool usageAccess;

  /// "Display over other apps": lets the service bring NO LEAN to the front.
  final bool overlay;

  /// The foreground service is alive.
  final bool serviceRunning;

  /// Notifications allowed (the fallback block prompt needs them).
  final bool notifications;

  AppLockAvailability get availability => !supported
      ? AppLockAvailability.notImplemented
      : usageAccess && overlay
      ? AppLockAvailability.available
      : AppLockAvailability.permissionRequired;

  factory AppLockStatus.fromMap(Object? raw) {
    if (raw is! Map) return const AppLockStatus.unsupported();
    bool flag(String key, [bool fallback = false]) =>
        raw[key] is bool ? raw[key] as bool : fallback;
    return AppLockStatus(
      supported: true,
      usageAccess: flag('usageAccess'),
      overlay: flag('overlay'),
      serviceRunning: flag('serviceRunning'),
      notifications: flag('notifications', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppLockStatus &&
      other.supported == supported &&
      other.usageAccess == usageAccess &&
      other.overlay == overlay &&
      other.serviceRunning == serviceRunning &&
      other.notifications == notifications;

  @override
  int get hashCode => Object.hash(
    supported,
    usageAccess,
    overlay,
    serviceRunning,
    notifications,
  );
}

/// An app the user could pick to lock.
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.label,
    this.neverLockable = false,
  });

  final String packageName;
  final String label;

  /// Device-specific protection (default dialer, launcher, settings, maps).
  final bool neverLockable;
}

/// A locked app came to the front; NO LEAN was opened over it.
class AppBlockRequest {
  const AppBlockRequest({
    required this.packageName,
    required this.label,
    this.zoneName,
    this.cause = 'schedule',
  });

  final String packageName;
  final String label;

  /// Danger zone the user is in, when that is why it is locked.
  final String? zoneName;

  /// `schedule` or `zone`.
  final String cause;

  static AppBlockRequest? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final packageName = raw['packageName'];
    if (packageName is! String || packageName.isEmpty) return null;
    final label = raw['label'];
    final zone = raw['zoneName'];
    return AppBlockRequest(
      packageName: packageName,
      label: label is String && label.isNotEmpty ? label : packageName,
      zoneName: zone is String && zone.isNotEmpty ? zone : null,
      cause: raw['cause'] == 'zone' ? 'zone' : 'schedule',
    );
  }
}

/// Result of an app-lock call.
class AppLockResult {
  const AppLockResult.unsupported([this.message = notAvailableMessage])
    : supported = false;

  const AppLockResult.ok() : supported = true, message = null;

  static const notAvailableMessage = 'App lock needs Android.';

  final bool supported;
  final String? message;
}

/// Platform boundary for locking specific apps. Everything above it
/// (policy, exit plan, settings, UI) is built and tested without native code.
abstract interface class AppLockGateway {
  /// Whether this platform has an enforcement implementation. This is distinct
  /// from temporary native permission, service or channel failure on Android.
  bool get isSupportedPlatform;

  Future<AppLockAvailability> availability();

  Future<AppLockStatus> status();

  /// Opens the system Usage access screen.
  Future<AppLockResult> requestPermission();

  /// Opens the system "Display over other apps" screen.
  Future<AppLockResult> requestOverlayPermission();

  /// Launchable apps (ACTION_MAIN/CATEGORY_LAUNCHER via a `<queries>`
  /// entry, not QUERY_ALL_PACKAGES).
  Future<List<InstalledAppInfo>> installedApps();

  /// Pushes the native configuration and starts/stops the service.
  Future<AppLockResult> apply(Map<String, Object?> config);

  /// Stops enforcement and clears native state.
  Future<AppLockResult> disable();

  /// Lets [packageName] (only) open for [duration], then opens it.
  Future<bool> grantTemporaryUnlock(String packageName, Duration duration);

  /// Sends the user to the home screen.
  Future<void> goHome();

  /// Block requests that arrived while Dart was not listening.
  Future<List<AppBlockRequest>> drainBlockRequests();

  /// Fires when native code has new block requests to drain.
  Stream<void> get blockRequestsAvailable;
}

/// Non-Android platforms and tests: nothing is ever blocked.
class UnsupportedAppLockGateway implements AppLockGateway {
  const UnsupportedAppLockGateway();

  @override
  bool get isSupportedPlatform => false;

  @override
  Future<AppLockAvailability> availability() async =>
      AppLockAvailability.notImplemented;

  @override
  Future<AppLockStatus> status() async => const AppLockStatus.unsupported();

  @override
  Future<AppLockResult> requestPermission() async =>
      const AppLockResult.unsupported();

  @override
  Future<AppLockResult> requestOverlayPermission() async =>
      const AppLockResult.unsupported();

  @override
  Future<List<InstalledAppInfo>> installedApps() async => const [];

  @override
  Future<AppLockResult> apply(Map<String, Object?> config) async =>
      const AppLockResult.unsupported();

  @override
  Future<AppLockResult> disable() async => const AppLockResult.unsupported();

  @override
  Future<bool> grantTemporaryUnlock(
    String packageName,
    Duration duration,
  ) async => false;

  @override
  Future<void> goHome() async {}

  @override
  Future<List<AppBlockRequest>> drainBlockRequests() async => const [];

  @override
  Stream<void> get blockRequestsAvailable => const Stream.empty();
}

/// Android gateway over `no_lean/app_lock`. Any channel failure degrades to
/// "nothing blocked", never to a stuck lock.
class MethodChannelAppLockGateway implements AppLockGateway {
  @override
  bool get isSupportedPlatform => true;

  MethodChannelAppLockGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('no_lean/app_lock') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'blocksAvailable') _available.add(null);
    });
  }

  final MethodChannel _channel;
  final _available = StreamController<void>.broadcast();

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<AppLockAvailability> availability() async =>
      (await status()).availability;

  @override
  Future<AppLockStatus> status() async =>
      AppLockStatus.fromMap(await _invoke<Object?>('status'));

  @override
  Future<AppLockResult> requestPermission() async =>
      await _invoke<bool>('openUsageAccessSettings') == true
      ? const AppLockResult.ok()
      : const AppLockResult.unsupported('Could not open Usage access.');

  @override
  Future<AppLockResult> requestOverlayPermission() async =>
      await _invoke<bool>('openOverlaySettings') == true
      ? const AppLockResult.ok()
      : const AppLockResult.unsupported(
          'Could not open "Display over other apps".',
        );

  @override
  Future<List<InstalledAppInfo>> installedApps() async {
    final raw = await _invoke<List<Object?>>('installedApps') ?? const [];
    final apps = <InstalledAppInfo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final packageName = item['packageName'];
      final label = item['label'];
      if (packageName is! String || packageName.isEmpty) continue;
      apps.add(
        InstalledAppInfo(
          packageName: packageName,
          label: label is String && label.isNotEmpty ? label : packageName,
          neverLockable: item['neverLockable'] == true,
        ),
      );
    }
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  @override
  Future<AppLockResult> apply(Map<String, Object?> config) async =>
      await _invoke<bool>('apply', jsonEncode(config)) == true
      ? const AppLockResult.ok()
      : const AppLockResult.unsupported('App lock could not start.');

  @override
  Future<AppLockResult> disable() async =>
      await _invoke<bool>('disable') == true
      ? const AppLockResult.ok()
      : const AppLockResult.unsupported();

  @override
  Future<bool> grantTemporaryUnlock(
    String packageName,
    Duration duration,
  ) async =>
      await _invoke<bool>('grantTemporaryUnlock', {
        'packageName': packageName,
        'millis': duration.inMilliseconds,
      }) ==
      true;

  @override
  Future<void> goHome() async => _invoke<bool>('goHome');

  @override
  Future<List<AppBlockRequest>> drainBlockRequests() async {
    final raw = await _invoke<List<Object?>>('drainBlocks') ?? const [];
    return [for (final item in raw) ?AppBlockRequest.fromMap(item)];
  }

  @override
  Stream<void> get blockRequestsAvailable => _available.stream;
}
