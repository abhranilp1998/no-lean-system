import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/domain/exit_plan.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../support/recovery_fakes.dart';

void main() {
  const chat = LockedApp(packageName: 'com.example.chat', label: 'Chat');
  const policy = AppLockPolicy(
    enabled: true,
    apps: [chat],
    schedule: AppLockSchedule.riskWindow,
  );
  final now = DateTime(2026, 10, 10, 18);

  Future<(RecoveryController, MemoryRecoveryStore, FakeRelapseLock)> load([
    String? stored,
  ]) async {
    final store = MemoryRecoveryStore(stored);
    final lock = FakeRelapseLock();
    final controller = RecoveryController(
      store: store,
      relapseLock: lock,
      now: () => now,
    );
    await controller.load();
    return (controller, store, lock);
  }

  Map<String, Object> unlockMetadata({String method = 'budget'}) => {
    'packageName': 'com.example.chat',
    'appLabel': 'Chat',
    'reason': 'payment',
    'method': method,
    'waitSeconds': 30,
    'unlockMinutes': 5,
    'paymentApp': false,
    'zoneName': 'Corner',
  };

  test('state v12 loads with app lock off and is saved as v13', () async {
    final (controller, store, _) = await load(
      jsonEncode({
        'stateVersion': 12,
        'events': [
          {
            'id': 'p1',
            'type': 'pledge',
            'timestamp': DateTime(2026, 10, 1).toIso8601String(),
            'metadata': <String, dynamic>{},
          },
        ],
      }),
    );
    expect(controller.loadStatus, RecoveryLoadStatus.ready);
    expect(RecoveryController.stateVersion, 13);
    expect(controller.appLockPolicy, const AppLockPolicy());
    expect(controller.appLockPolicy.enabled, isFalse);
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect(saved['stateVersion'], 13);
    expect(saved['appLockPolicy'], isA<Map>());
    expect(store.copies, isNotEmpty, reason: 'pre-migration copy kept');
  });

  test('policy persists and a malformed stored policy fails safe', () async {
    final (controller, store, _) = await load();
    await controller.updateAppLockPolicy(policy);
    final (reloaded, _, _) = await load(store.value);
    expect(reloaded.appLockPolicy, policy);

    final state = jsonDecode(store.value!) as Map<String, dynamic>
      ..['appLockPolicy'] = 'broken';
    final (broken, _, _) = await load(jsonEncode(state));
    expect(broken.loadStatus, RecoveryLoadStatus.ready);
    expect(broken.appLockPolicy.enabled, isFalse);
  });

  test(
    'turning on is free; turning off needs the PIN when one is set',
    () async {
      final (controller, _, lock) = await load();
      await controller.enableRelapseLock('1234');
      expect(
        await controller.updateAppLockPolicy(policy),
        ProtectedActionResult.completed,
      );
      expect(
        await controller.updateAppLockPolicy(policy.copyWith(enabled: false)),
        ProtectedActionResult.authenticationRequired,
      );
      expect(controller.appLockPolicy.enabled, isTrue);
      expect(
        await controller.updateAppLockPolicy(
          policy.copyWith(enabled: false),
          pin: '0000',
          tryBiometrics: false,
        ),
        ProtectedActionResult.denied,
      );
      expect(
        await controller.updateAppLockPolicy(
          policy.copyWith(enabled: false),
          pin: '1234',
          tryBiometrics: false,
        ),
        ProtectedActionResult.completed,
      );
      expect(controller.appLockPolicy.enabled, isFalse);
      expect(lock.pin, '1234');
      expect(
        controller.events.where(
          (e) =>
              e.type == RecoveryEventType.settingsChange &&
              e.metadata['setting'] == 'appLock',
        ),
        hasLength(2),
      );
    },
  );

  test('never-lockable apps are dropped when saving', () async {
    final (controller, _, _) = await load();
    await controller.updateAppLockPolicy(
      policy.copyWith(
        apps: [
          chat,
          const LockedApp(packageName: 'com.google.android.dialer', label: 'P'),
        ],
      ),
    );
    expect(controller.appLockPolicy.apps, [chat]);
  });

  test('unlocks are logged and spend the daily budget', () async {
    final (controller, _, lock) = await load();
    await controller.updateAppLockPolicy(policy);
    expect(controller.appUnlocksLeftToday, 3);
    await controller.recordAppUnlock(unlockMetadata());
    await controller.recordAppUnlock(unlockMetadata(method: 'pin'));
    expect(controller.appUnlocksUsedToday, 1);
    expect(controller.appUnlocksLeftToday, 2);
    final logged = controller.events
        .where((e) => e.type == RecoveryEventType.appUnlock)
        .toList();
    expect(logged, hasLength(2));
    expect(logged.first.metadata['zoneName'], 'Corner');

    // PIN path uses the existing PIN and its lockout.
    expect(controller.appUnlockPinConfigured, isFalse);
    expect(
      await controller.authorizeAppUnlock(),
      ProtectedActionResult.completed,
    );
    await controller.enableRelapseLock('4321');
    expect(controller.appUnlockPinConfigured, isTrue);
    expect(
      await controller.authorizeAppUnlock(pin: '4321', tryBiometrics: false),
      ProtectedActionResult.completed,
    );
    lock.lockedOut = true;
    expect(
      await controller.authorizeAppUnlock(pin: '4321', tryBiometrics: false),
      ProtectedActionResult.lockedOut,
    );
  });

  group('backups', () {
    test('format 8 round-trips appUnlock events; the policy is not exported '
        'and an import never switches the lock on', () async {
      final (controller, _, _) = await load();
      await controller.updateAppLockPolicy(policy);
      await controller.recordAppUnlock(unlockMetadata());
      final service = BackupService();
      expect(BackupService.currentBackupVersion, 8);
      final payload = service.buildBackupPayload(
        controller.events,
        preferences: controller.portablePreferences,
        zones: controller.zones,
      );
      expect(payload['version'], 8);
      expect(
        (payload['preferences'] as Map).containsKey('appLockPolicy'),
        isFalse,
      );
      final preview = service.validateBackupJson(jsonEncode(payload));
      expect(
        preview.events.where((e) => e.type == RecoveryEventType.appUnlock),
        hasLength(1),
      );

      final (fresh, _, _) = await load();
      await fresh.mergeImportedEvents(
        preview.events,
        preferences: {
          ...preview.preferences!,
          'appLockPolicy': policy.toJson(),
        },
        restorePreferences: true,
      );
      expect(fresh.appLockPolicy.enabled, isFalse);
      expect(
        fresh.events.where((e) => e.type == RecoveryEventType.appUnlock),
        hasLength(1),
      );
    });

    test('format 7 backups still import', () {
      final preview = BackupService().validateBackupJson(
        jsonEncode({
          'version': 7,
          'events': [
            {
              'id': 'c1',
              'type': 'craving',
              'timestamp': DateTime(2026, 10, 1).toIso8601String(),
              'metadata': {'intensity': 5, 'trigger': 'Stress'},
            },
          ],
          'preferences': <String, dynamic>{},
        }),
      );
      expect(preview.eventCount, 1);
    });

    test('a raw v13 state file imports without its app lock', () async {
      final (controller, store, _) = await load();
      await controller.updateAppLockPolicy(policy);
      await controller.recordAppUnlock(unlockMetadata());
      final preview = BackupService().validateBackupJson(store.value!);
      final (fresh, _, _) = await load();
      await fresh.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
        restorePreferences: true,
      );
      expect(fresh.appLockPolicy.enabled, isFalse);
      expect(fresh.appUnlocksUsedToday, 1);
    });
  });

  test('unlock reasons cover the user\'s list', () {
    expect(UnlockReason.values.map((r) => r.label), [
      'Payment',
      'Work',
      'Navigation',
      'Urgent',
      'Other',
    ]);
  });
}
