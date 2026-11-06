import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_cooldown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 11, 4, 22);

  group('reconcileCooldown (P0-4)', () {
    final relapse = RecoveryEvent.fromJson({
      'id': 'r1',
      'type': RecoveryEventType.relapse.name,
      'timestamp': now.toIso8601String(),
      'metadata': <String, dynamic>{},
    });
    test('expires by time', () {
      expect(
        reconcileCooldown(
          until: now.subtract(const Duration(minutes: 1)),
          eventId: 'r1',
          events: [relapse],
          now: now,
        ).isActive,
        isFalse,
      );
    });
    test('orphaned event id is dropped', () {
      expect(
        reconcileCooldown(
          until: now.add(const Duration(hours: 1)),
          eventId: 'gone',
          events: [relapse],
          now: now,
        ).isActive,
        isFalse,
      );
    });
    test('active cooldown is kept', () {
      final s = reconcileCooldown(
        until: now.add(const Duration(hours: 1)),
        eventId: 'r1',
        events: [relapse],
        now: now,
      );
      expect(s.eventId, 'r1');
    });
  });

  test('a stale Oct 25 cooldown id no longer blocks a new cooldown', () async {
    final store = MemoryRecoveryStore();
    final c = RecoveryController(store: store);
    await c.load();
    await c.recordRelapse();
    // Simulate the real backup: deadline long past, id still set.
    final map = jsonDecode(store.value!) as Map<String, dynamic>;
    map['relapseCooldownUntil'] = DateTime(2026, 10, 25, 23).toIso8601String();
    map['relapseCooldownEventId'] = 'oct-25-relapse';
    store.value = jsonEncode(map);

    final reload = RecoveryController(store: store);
    final writesBefore = store.writes;
    await reload.load();
    // The stale fix is persisted exactly once.
    expect(store.writes, writesBefore + 1);
    expect(jsonDecode(store.value!)['relapseCooldownEventId'], isNull);
    final again = RecoveryController(store: store);
    await again.load();
    expect(store.writes, writesBefore + 1);
    expect(reload.relapseCooldownUntil, isNull);
    expect(reload.relapseCooldownEventId, isNull);
    await reload.recordRelapse();
    expect(reload.relapseCooldownUntil, isNotNull);
    expect(reload.relapseCooldownEventId, isNot('oct-25-relapse'));
  });
}
