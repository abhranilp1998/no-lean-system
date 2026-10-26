import 'dart:async';

import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';

/// Records every call; tests choose the status and installed apps.
class FakeAppLockGateway implements AppLockGateway {
  @override
  bool get isSupportedPlatform => true;

  FakeAppLockGateway({
    this.currentStatus = const AppLockStatus(
      supported: true,
      usageAccess: true,
      overlay: true,
      serviceRunning: true,
    ),
    this.apps = const [],
  });

  AppLockStatus currentStatus;
  List<InstalledAppInfo> apps;
  final applied = <Map<String, Object?>>[];
  final grants = <(String, Duration)>[];
  final pending = <AppBlockRequest>[];
  int disables = 0;
  int homes = 0;
  int usageRequests = 0;
  int overlayRequests = 0;
  final _available = StreamController<void>.broadcast();

  void pushBlock(AppBlockRequest request) {
    pending.add(request);
    _available.add(null);
  }

  @override
  Future<AppLockAvailability> availability() async =>
      currentStatus.availability;

  @override
  Future<AppLockStatus> status() async => currentStatus;

  @override
  Future<AppLockResult> requestPermission() async {
    usageRequests++;
    return const AppLockResult.ok();
  }

  @override
  Future<AppLockResult> requestOverlayPermission() async {
    overlayRequests++;
    return const AppLockResult.ok();
  }

  @override
  Future<List<InstalledAppInfo>> installedApps() async => apps;

  @override
  Future<AppLockResult> apply(Map<String, Object?> config) async {
    applied.add(config);
    return const AppLockResult.ok();
  }

  @override
  Future<AppLockResult> disable() async {
    disables++;
    return const AppLockResult.ok();
  }

  @override
  Future<bool> grantTemporaryUnlock(
    String packageName,
    Duration duration,
  ) async {
    grants.add((packageName, duration));
    return true;
  }

  @override
  Future<void> goHome() async => homes++;

  @override
  Future<List<AppBlockRequest>> drainBlockRequests() async {
    final out = List.of(pending);
    pending.clear();
    return out;
  }

  @override
  Stream<void> get blockRequestsAvailable => _available.stream;
}
