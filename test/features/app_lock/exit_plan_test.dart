import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/domain/exit_plan.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

void main() {
  group('planUnlock', () {
    test('within budget: 30 s mindful wait, 5 minute unlock', () {
      final step = planUnlock(
        paymentApp: false,
        usedToday: 0,
        dailyBudget: 3,
        pinConfigured: true,
      );
      expect(step.method, UnlockMethod.budget);
      expect(step.wait, const Duration(seconds: 30));
      expect(step.unlockFor, const Duration(minutes: 5));
      expect(step.needsPin, isFalse);
    });

    test('payment apps take the 10 s quick path', () {
      final step = planUnlock(
        paymentApp: true,
        usedToday: 2,
        dailyBudget: 3,
        pinConfigured: false,
      );
      expect(step.method, UnlockMethod.budget);
      expect(step.wait, const Duration(seconds: 10));
      expect(step.unlockFor, const Duration(minutes: 5));
    });

    test('budget used up: the PIN is required, no extra wait', () {
      final step = planUnlock(
        paymentApp: true,
        usedToday: 3,
        dailyBudget: 3,
        pinConfigured: true,
      );
      expect(step.method, UnlockMethod.pin);
      expect(step.needsPin, isTrue);
      expect(step.wait, Duration.zero);
      expect(step.unlockFor, const Duration(minutes: 5));
    });

    test('never a dead end: no PIN or a locked-out PIN gets the long wait', () {
      for (final step in [
        planUnlock(
          paymentApp: false,
          usedToday: 5,
          dailyBudget: 3,
          pinConfigured: false,
        ),
        planUnlock(
          paymentApp: false,
          usedToday: 5,
          dailyBudget: 3,
          pinConfigured: true,
          pinLockedOut: true,
        ),
        planUnlock(
          paymentApp: true,
          usedToday: 0,
          dailyBudget: 0,
          pinConfigured: false,
        ),
      ]) {
        expect(step.method, UnlockMethod.longWait);
        expect(step.wait, const Duration(seconds: 120));
        expect(step.unlockFor, const Duration(minutes: 5));
      }
    });
  });

  group('daily budget counting', () {
    RecoveryEvent unlock(DateTime at, String method) => RecoveryEvent.create(
      type: RecoveryEventType.appUnlock,
      timestamp: at,
      metadata: {
        'packageName': 'com.example.chat',
        'appLabel': 'Chat',
        'reason': 'work',
        'method': method,
        'unlockMinutes': 5,
      },
    );

    test('counts budget unlocks on the local day only', () {
      final now = DateTime(2026, 10, 10, 19);
      final events = [
        unlock(DateTime(2026, 10, 9, 23, 59), 'budget'),
        unlock(DateTime(2026, 10, 10, 0, 1), 'budget'),
        unlock(DateTime(2026, 10, 10, 18), 'budget'),
        unlock(DateTime(2026, 10, 10, 18, 30), 'pin'),
        unlock(DateTime(2026, 10, 10, 18, 40), 'longWait'),
        RecoveryEvent.create(type: RecoveryEventType.pledge, timestamp: now),
      ];
      expect(unlocksUsedOn(events, now), 2);
      expect(unlocksUsedOn(events, DateTime(2026, 10, 11, 8)), 0);
    });
  });

  group('appUnlock event', () {
    test('metadata carries reason, app, zone and the method', () {
      final metadata = appUnlockMetadata(
        packageName: 'com.phonepe.app',
        appLabel: 'PhonePe',
        reason: UnlockReason.payment,
        step: planUnlock(
          paymentApp: true,
          usedToday: 0,
          dailyBudget: 3,
          pinConfigured: false,
        ),
        paymentApp: true,
        zoneName: '  Station corner ',
      );
      final event = RecoveryEvent.create(
        type: RecoveryEventType.appUnlock,
        metadata: metadata,
      );
      expect(event.metadata, {
        'packageName': 'com.phonepe.app',
        'appLabel': 'PhonePe',
        'reason': 'payment',
        'method': 'budget',
        'waitSeconds': 10,
        'unlockMinutes': 5,
        'paymentApp': true,
        'zoneName': 'Station corner',
      });
      final restored = RecoveryEvent.fromJson(event.toJson());
      expect(restored.metadata, event.metadata);
    });

    test('validation rejects bad data and strips coordinates', () {
      Map<String, dynamic> base() => {
        'packageName': 'com.example.chat',
        'reason': 'urgent',
        'method': 'pin',
        'unlockMinutes': 5,
      };
      for (final bad in [
        {...base(), 'packageName': ''},
        {...base(), 'reason': 'boredom'},
        {...base(), 'method': 'magic'},
        {...base(), 'unlockMinutes': 0},
        {...base(), 'unlockMinutes': 600},
        {...base(), 'zoneName': 7},
      ]) {
        expect(
          () => RecoveryEvent.create(
            type: RecoveryEventType.appUnlock,
            metadata: bad,
          ),
          throwsFormatException,
          reason: '$bad',
        );
      }
      final event = RecoveryEvent.create(
        type: RecoveryEventType.appUnlock,
        metadata: {...base(), 'latitude': 22.5, 'longitude': 88.3},
      );
      expect(event.metadata.containsKey('latitude'), isFalse);
      expect(event.metadata.containsKey('longitude'), isFalse);
      expect(event.metadata['appLabel'], 'com.example.chat');
      for (final reason in UnlockReason.values) {
        expect(appUnlockReasons, contains(reason.name));
      }
      for (final method in UnlockMethod.values) {
        expect(appUnlockMethods, contains(method.name));
      }
    });
  });
}
