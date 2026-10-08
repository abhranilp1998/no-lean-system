import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecoveryController, MemoryRecoveryStore)> loaded({
    String? stored,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    return (controller, store);
  }

  String v9State([Map<String, Object?> extra = const {}]) => jsonEncode({
    'stateVersion': 9,
    'events': [
      RecoveryEvent.create(
        type: RecoveryEventType.recoveryStart,
        timestamp: DateTime(2026, 9, 1),
      ).toJson(),
    ],
    'zones': [],
    ...extra,
  });

  test(
    'v9 migrates to v10 with street tiles on and the v9 copy kept',
    () async {
      final (controller, store) = await loaded(stored: v9State());
      expect(controller.streetTiles, isTrue);
      final saved = jsonDecode(store.value!) as Map;
      expect(saved['stateVersion'], 10);
      expect(saved['streetTiles'], isTrue);
      expect(store.copies.single, contains('"stateVersion":9'));
    },
  );

  test('street tiles toggle persists and needs no authentication', () async {
    final (controller, store) = await loaded();
    await controller.enableRelapseLock('2468');
    await controller.setStreetTiles(false);
    expect(controller.streetTiles, isFalse);

    final reloaded = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await reloaded.load();
    expect(reloaded.streetTiles, isFalse);
  });

  test('a malformed value falls back to the default', () async {
    final (controller, _) = await loaded(
      stored: v9State({'stateVersion': 10, 'streetTiles': 'nope'}),
    );
    expect(controller.streetTiles, isTrue);
  });

  test('imported preferences never change network privacy', () async {
    final (controller, _) = await loaded();
    await controller.setStreetTiles(false);
    await controller.mergeImportedEvents(
      const [],
      preferences: {'streetTiles': true},
      restorePreferences: true,
    );
    expect(controller.streetTiles, isFalse);
  });

  test('states from a newer app version are refused unchanged', () async {
    final newer = v9State({'stateVersion': 11});
    final (controller, store) = await loaded(stored: newer);
    expect(controller.loadStatus, RecoveryLoadStatus.incompatible);
    expect(store.value, newer);
  });

  group('notification privacy', () {
    test('v9 states get quiet hours off and full notification text', () async {
      final (controller, store) = await loaded(stored: v9State());
      expect(controller.notificationPrefs.quietHoursEnabled, isFalse);
      expect(controller.notificationPrefs.hideSensitive, isFalse);
      final saved = jsonDecode(store.value!) as Map;
      expect(saved['quietHoursEnabled'], isFalse);
      expect(saved['quietHours'], {'startMinutes': 1320, 'endMinutes': 420});
      expect(saved['hideSensitiveNotifications'], isFalse);
    });

    test(
      'quiet hours and hide-sensitive persist and reach the service',
      () async {
        final (controller, store) = await loaded();
        await controller.enableRelapseLock('2468');
        const window = RiskWindow(startMinutes: 23 * 60, endMinutes: 6 * 60);
        await controller.setQuietHours(enabled: true, window: window);
        await controller.setHideSensitiveNotifications(true);
        expect(NotificationService.instance.prefs.hideSensitive, isTrue);
        expect(NotificationService.instance.prefs.quietHoursEnabled, isTrue);

        final reloaded = RecoveryController(
          store: store,
          relapseLock: FakeRelapseLock(),
        );
        await reloaded.load();
        expect(reloaded.notificationPrefs.quietHoursEnabled, isTrue);
        expect(reloaded.notificationPrefs.quietHours.startMinutes, 23 * 60);
        expect(reloaded.notificationPrefs.quietHours.endMinutes, 6 * 60);
        expect(reloaded.notificationPrefs.hideSensitive, isTrue);

        await reloaded.setHideSensitiveNotifications(false);
        expect(NotificationService.instance.prefs.hideSensitive, isFalse);
      },
    );

    test(
      'an empty quiet-hours window is refused and nothing changes',
      () async {
        final (controller, _) = await loaded();
        await expectLater(
          controller.setQuietHours(
            enabled: true,
            window: const RiskWindow(startMinutes: 60, endMinutes: 60),
          ),
          throwsArgumentError,
        );
        expect(controller.notificationPrefs.quietHoursEnabled, isFalse);
      },
    );

    test(
      'malformed values fall back; a non-false hide flag stays private',
      () async {
        final (controller, _) = await loaded(
          stored: v9State({
            'stateVersion': 10,
            'quietHoursEnabled': 'yes',
            'quietHours': {'startMinutes': 'x', 'endMinutes': 3},
            'hideSensitiveNotifications': 'on',
          }),
        );
        final prefs = controller.notificationPrefs;
        expect(prefs.quietHoursEnabled, isFalse);
        expect(
          prefs.quietHours.startMinutes,
          NotificationPrefs.defaultQuietHours.startMinutes,
        );
        expect(prefs.hideSensitive, isTrue);
      },
    );

    test('imports never change notification privacy', () async {
      final (controller, _) = await loaded();
      await controller.setHideSensitiveNotifications(true);
      await controller.mergeImportedEvents(
        const [],
        preferences: {
          'hideSensitiveNotifications': false,
          'quietHoursEnabled': true,
        },
        restorePreferences: true,
      );
      expect(controller.notificationPrefs.hideSensitive, isTrue);
      expect(controller.notificationPrefs.quietHoursEnabled, isFalse);
    });
  });
}
