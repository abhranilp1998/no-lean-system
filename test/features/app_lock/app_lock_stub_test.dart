import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/application/app_lock_providers.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  test('the stub gateway reports app lock as not available yet', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final gateway = container.read(appLockGatewayProvider);
    expect(gateway, isA<UnsupportedAppLockGateway>());
    expect(
      await container.read(appLockAvailabilityProvider.future),
      AppLockAvailability.notImplemented,
    );
    const policy = AppLockPolicy(
      apps: [LockedApp(packageName: 'com.example.chat', label: 'Chat')],
      schedule: AppLockSchedule.always,
    );
    for (final result in [
      await gateway.apply(policy),
      await gateway.requestPermission(),
      await gateway.disable(),
    ]) {
      expect(result.supported, isFalse);
      expect(result.message, 'App lock is not available yet.');
    }
    expect(await gateway.installedApps(), isEmpty);
  });

  test('policy schedule hooks', () {
    final window = const RiskWindow(startMinutes: 22 * 60, endMinutes: 2 * 60);
    final night = DateTime(2026, 10, 10, 23);
    final noon = DateTime(2026, 10, 10, 12);
    const chat = LockedApp(packageName: 'com.example.chat', label: 'Chat');
    const paused = LockedApp(
      packageName: 'com.example.pay',
      label: 'Pay',
      enabled: false,
    );

    const risk = AppLockPolicy(
      apps: [chat, paused],
      schedule: AppLockSchedule.riskWindow,
    );
    expect(risk.blocks('com.example.chat', night, riskWindow: window), isTrue);
    expect(risk.blocks('com.example.chat', noon, riskWindow: window), isFalse);
    expect(risk.blocks('com.example.pay', night, riskWindow: window), isFalse);

    const zones = AppLockPolicy(apps: [chat], lockInsideDangerZones: true);
    expect(
      zones.isActiveAt(noon, riskWindow: window, insideDangerZone: true),
      isTrue,
    );
    expect(zones.isActiveAt(noon, riskWindow: window), isFalse);
    expect(
      const AppLockPolicy(
        schedule: AppLockSchedule.always,
      ).isActiveAt(noon, riskWindow: window),
      isFalse,
    );

    final roundTrip = LockedApp.fromJson(chat.toJson());
    expect(roundTrip, chat);
    expect(() => LockedApp.fromJson({'label': 'x'}), throwsFormatException);
  });
}
