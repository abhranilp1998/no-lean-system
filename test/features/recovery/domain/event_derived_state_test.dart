import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';

void main() {
  group('Event Derived State Computations', () {
    test('computeLastDose finds the most recent relapse', () {
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: DateTime(2023, 1, 1),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: DateTime(2023, 2, 1),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: DateTime(2023, 3, 1),
        ),
      ];
      final lastDose = computeLastDose(events);
      expect(lastDose, DateTime(2023, 2, 1));
    });

    test('computeLastDose uses the earliest event if no baseline exists', () {
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: DateTime(2023, 1, 1),
        ),
      ];
      final lastDose = computeLastDose(events);
      expect(lastDose, DateTime(2023, 1, 1));
    });

    test('recovery start is a neutral counter baseline', () {
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: DateTime(2023, 1, 1),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: DateTime(2023, 2, 1),
        ),
      ];

      expect(computeLastDose(events), DateTime(2023, 2, 1));
    });

    test('historical milestone survives without daily pledge records', () {
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.milestone,
          timestamp: DateTime(2023, 1, 1),
          metadata: {'days': 42},
        ),
      ];

      expect(computeLongestStreak(events), 42);
    });

    test('relapse keeps the clean duration that was lost', () {
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          metadata: {'streakLost': 18},
        ),
      ];

      expect(computeLongestStreak(events), 18);
    });

    test('computeCurrentStreak calculates correctly backwards from today', () {
      final today = DateTime.now();
      final events = [
        RecoveryEvent.create(type: RecoveryEventType.pledge, timestamp: today),
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: today.subtract(const Duration(days: 1)),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: today.subtract(const Duration(days: 2)),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: today.subtract(const Duration(days: 3)),
        ),
        // Pledge on the same day as relapse is overridden by the relapse for that day
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: today.subtract(const Duration(days: 3)),
        ),
      ];

      final streak = computeCurrentStreak(events);
      expect(streak, 3);
    });

    test('computePostSosHoldRate calculates held vs total', () {
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.sosComplete,
          timestamp: DateTime(2023, 1, 1, 10, 0),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: DateTime(2023, 1, 1, 11, 0),
        ), // 60 mins later, broken
        RecoveryEvent.create(
          type: RecoveryEventType.sosComplete,
          timestamp: DateTime(2023, 1, 2, 10, 0),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: DateTime(2023, 1, 2, 13, 0),
        ), // 180 mins later, held
      ];

      final rate = computePostSosHoldRate(events, 120);
      expect(rate.total, 2);
      expect(rate.held, 1);
    });
  });
}
