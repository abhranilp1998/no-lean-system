// PLACEHOLDER: app locking is not implemented yet.
//
// TODO(app-lock): real Android implementation (native side, Kotlin, behind a
// MethodChannel such as `no_lean/app_lock`). Two known approaches:
//
// 1. UsageStatsManager polling
//    - Permission: android.permission.PACKAGE_USAGE_STATS (protected; the
//      user grants it manually in Settings > Usage access, opened with
//      Settings.ACTION_USAGE_ACCESS_SETTINGS). Check with AppOpsManager
//      OPSTR_GET_USAGE_STATS.
//    - A foreground service (needs FOREGROUND_SERVICE + a typed
//      FOREGROUND_SERVICE_* permission on Android 14+) queries
//      UsageStatsManager.queryEvents() every ~1 s for ACTIVITY_RESUMED /
//      MOVE_TO_FOREGROUND and compares the package with the policy.
//    - Battery cost from polling; may lag by up to the poll interval.
//
// 2. AccessibilityService
//    - Reacts to TYPE_WINDOW_STATE_CHANGED instantly, no polling.
//    - Requires the user to enable the service in Accessibility settings and
//      a BIND_ACCESSIBILITY_SERVICE <service> with an accessibility config XML.
//
// Blocking UI (either approach): when a locked app comes to the foreground,
// launch a full-screen NO LEAN blocking activity (FLAG_ACTIVITY_NEW_TASK,
// excluded from recents) or draw a SYSTEM_ALERT_WINDOW overlay
// (Settings.canDrawOverlays / ACTION_MANAGE_OVERLAY_PERMISSION). It must
// always offer SOS and a way home, mirroring the zone alert's one-tap exit.
//
// Google Play policy note: AccessibilityService use must match the
// Accessibility API policy (non-accessibility tools need a prominent
// disclosure, consent and Play Console declaration, and are often rejected);
// PACKAGE_USAGE_STATS needs a declared core use case; overlays and
// foreground services have their own declarations. Prefer UsageStats +
// blocking activity, with an in-app disclosure screen like the background
// geofence one, and document the use case for Play review.
//
// No permissions are declared in AndroidManifest.xml for this yet.

import '../domain/locked_app.dart';

/// Why app locking cannot run right now.
enum AppLockAvailability {
  /// Placeholder build: the feature does not exist yet.
  notImplemented,

  /// TODO(app-lock): the OS permission (usage access / accessibility) is
  /// missing.
  permissionRequired,

  /// TODO(app-lock): enforcement is possible.
  available,
}

/// An app the user could pick to lock.
class InstalledAppInfo {
  const InstalledAppInfo({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

/// Result of an app-lock call.
class AppLockResult {
  const AppLockResult.unsupported([this.message = notAvailableYetMessage])
    : supported = false;

  const AppLockResult.ok() : supported = true, message = null;

  static const notAvailableYetMessage = 'App lock is not available yet.';

  final bool supported;
  final String? message;
}

/// Platform boundary for locking specific apps. Everything above this line
/// (policy, settings, UI) can be built and tested without native code.
abstract interface class AppLockGateway {
  Future<AppLockAvailability> availability();

  /// TODO(app-lock): open the usage-access / accessibility settings screen.
  Future<AppLockResult> requestPermission();

  /// TODO(app-lock): list launchable apps (PackageManager.queryIntentActivities
  /// with ACTION_MAIN/CATEGORY_LAUNCHER; Android 11+ package visibility needs
  /// a `<queries>` entry rather than QUERY_ALL_PACKAGES).
  Future<List<InstalledAppInfo>> installedApps();

  /// TODO(app-lock): push the policy to the native enforcement service.
  Future<AppLockResult> apply(AppLockPolicy policy);

  /// TODO(app-lock): stop enforcement and clear native state.
  Future<AppLockResult> disable();
}

/// Default gateway until the native side exists: everything reports
/// "not available yet" and nothing is blocked.
class UnsupportedAppLockGateway implements AppLockGateway {
  const UnsupportedAppLockGateway();

  @override
  Future<AppLockAvailability> availability() async =>
      AppLockAvailability.notImplemented;

  @override
  Future<AppLockResult> requestPermission() async =>
      const AppLockResult.unsupported();

  @override
  Future<List<InstalledAppInfo>> installedApps() async => const [];

  @override
  Future<AppLockResult> apply(AppLockPolicy policy) async =>
      const AppLockResult.unsupported();

  @override
  Future<AppLockResult> disable() async => const AppLockResult.unsupported();
}
