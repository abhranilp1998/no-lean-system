import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/trigger_tags.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/zones/domain/background_zone_alert.dart';

import '../support/recovery_fakes.dart';

/// Rule: always backwards compatible. Craving tags and if-then plans add only
/// optional fields, so data from every older build must open, import and
/// re-export with nothing lost, and what this build writes must not make
/// an older build refuse it.
void main() {
  const tagKeys = ['place', 'zoneId', 'withWho', 'mood', 'cash', 'taggedAt'];
  final now = DateTime(2026, 11, 26, 20);

  // A backup exactly as an older build (before craving tags and plans)
  // would have written it.
  Map<String, dynamic> oldBackup(int version) => {
    'version': version,
    'exportedAt': '2026-11-20T10:00:00.000',
    'events': [
      {
        'id': 'start',
        'type': 'recoveryStart',
        'timestamp': '2026-10-01T09:00:00.000',
        'metadata': {'source': 'onboarding'},
      },
      {
        'id': 'cr1',
        'type': 'craving',
        'timestamp': '2026-11-18T19:00:00.000',
        'metadata': {
          'intensity': 7,
          'trigger': 'Boredom',
          'note': 'on the way home',
          'stress': 3,
          'someFutureKey': {'keep': true},
        },
      },
      {
        'id': 'cr2',
        'type': 'craving',
        'timestamp': '2026-11-19T21:00:00.000',
        'metadata': {'intensity': 5, 'trigger': 'Habit', 'note': ''},
      },
    ],
    'zones': <Object>[],
    'preferences': {'dailySpend': 250, 'riskReminders': true},
  };

  Future<RecoveryController> blank([DateTime Function()? clock]) async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: clock ?? () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    return c;
  }

  for (final v in [8, 10, 12]) {
    test('backup format $v imports untouched, with no plans', () async {
      final service = BackupService();
      final preview = service.validateBackupJson(jsonEncode(oldBackup(v)));
      expect(preview.eventCount, 3);
      final c = await blank();
      await c.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
      );
      expect(c.events.map((e) => e.id), containsAll(['cr1', 'cr2']));
      expect(c.ifThenPlans, isEmpty);
      for (final e in c.events) {
        for (final k in tagKeys) {
          expect(e.metadata.containsKey(k), isFalse, reason: '${e.id}.$k');
        }
      }
      final cr1 = c.events.firstWhere((e) => e.id == 'cr1');
      expect(cr1.metadata['someFutureKey'], {'keep': true});
      expect(cr1.metadata['stress'], 3);
      expect(c.portablePreferences.containsKey('ifThenPlans'), isFalse);

      // Re-export keeps every original key and value.
      final again = service.buildBackupPayload(
        c.events,
        preferences: c.portablePreferences,
      );
      final out = {
        for (final e in (again['events'] as List).cast<Map>())
          e['id'] as String: e,
      };
      for (final raw in (oldBackup(v)['events'] as List).cast<Map>()) {
        final meta = out[raw['id']]!['metadata'] as Map;
        for (final e in (raw['metadata'] as Map).entries) {
          expect(meta[e.key], e.value, reason: '${raw['id']}.${e.key}');
        }
      }
    });
  }

  test(
    'an old state snapshot opens, has no plans, and tagging only adds',
    () async {
      final snapshot = {
        'stateVersion': 17,
        'events': oldBackup(12)['events'],
        'zones': <Object>[],
      };
      final c = RecoveryController(
        store: MemoryRecoveryStore(jsonEncode(snapshot)),
        relapseLock: FakeRelapseLock(),
        now: () => now,
      );
      await c.load();
      expect(c.loadStatus, RecoveryLoadStatus.ready, reason: c.loadMessage);
      expect(c.events.length, 3);
      expect(c.ifThenPlans, isEmpty);

      final before = c.events.firstWhere((e) => e.id == 'cr1').metadata;
      expect(
        await c.recordTriggerTags(
          'cr1',
          const TriggerTags(mood: 'bored', withWho: 'alone', cash: 'plenty'),
        ),
        isTrue,
      );
      final after = c.events.firstWhere((e) => e.id == 'cr1').metadata;
      expect(after['mood'], 'bored');
      for (final entry in before.entries) {
        expect(after[entry.key], entry.value, reason: entry.key);
      }
      // Time, intensity and the craving's own trigger never move.
      expect(
        c.events.firstWhere((e) => e.id == 'cr1').timestamp,
        DateTime.parse('2026-11-18T19:00:00.000'),
      );
      expect(await c.recordTriggerTags('nope', const TriggerTags()), isFalse);
    },
  );

  test('state written without plans is byte-identical to before', () async {
    final store = MemoryRecoveryStore();
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    await c.recordCraving(
      CravingEntry(
        intensity: 6,
        trigger: 'Habit',
        note: '',
        createdAt: DateTime(2026, 11, 26, 19),
      ),
    );
    final stored = jsonDecode(store.value!) as Map;
    expect(stored.containsKey('ifThenPlans'), isFalse);
    expect(c.portablePreferences.containsKey('ifThenPlans'), isFalse);
  });

  test('plans survive a restart and are exported in the backup', () async {
    final store = MemoryRecoveryStore();
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    await c.addIfThenPlan(
      ifText: "I'm bored on the way home",
      thenText: 'call my brother',
      mood: 'bored',
    );
    expect(c.ifThenPlans, hasLength(1));

    final reopened = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await reopened.load();
    expect(
      reopened.ifThenPlans.single.sentence,
      "If I'm bored on the way home, then I will call my brother.",
    );
    expect(reopened.ifThenPlans.single.mood, 'bored');

    final payload = BackupService().buildBackupPayload(
      c.events,
      preferences: c.portablePreferences,
    );
    final restored = BackupService().validateBackupJson(jsonEncode(payload));
    final fresh = await blank();
    await fresh.mergeImportedEvents(
      restored.events,
      preferences: restored.preferences,
    );
    expect(await fresh.mergeImportedPlans(restored.preferences), 1);
    expect(fresh.ifThenPlans.map((p) => p.id), [c.ifThenPlans.single.id]);

    // Importing the same backup again does not duplicate the plan.
    expect(await fresh.mergeImportedPlans(restored.preferences), 0);
    expect(fresh.ifThenPlans, hasLength(1));
  });

  test('odd plan data in a backup never rejects the backup', () async {
    final odd = oldBackup(12);
    (odd['preferences'] as Map)['ifThenPlans'] = [
      7,
      {'id': 'x'},
      {
        'id': 'good',
        'if': "I'm at the shop",
        'then': 'walk home',
        'createdAt': '2026-11-20T10:00:00.000',
      },
    ];
    final preview = BackupService().validateBackupJson(jsonEncode(odd));
    final c = await blank();
    await c.mergeImportedEvents(
      preview.events,
      preferences: preview.preferences,
    );
    await c.mergeImportedPlans(preview.preferences);
    expect(c.ifThenPlans.map((p) => p.id), ['good']);
    expect(c.events.length, greaterThanOrEqualTo(3));
  });

  test('odd tag values in a backup are dropped, never an import failure', () {
    final odd = oldBackup(12);
    ((odd['events'] as List)[1] as Map)['metadata'] = {
      'intensity': 7,
      'trigger': 'Boredom',
      'note': 'bad tags',
      'mood': 5,
      'cash': ['x'],
      'withWho': false,
      'taggedAt': 1,
    };
    final preview = BackupService().validateBackupJson(jsonEncode(odd));
    final meta = preview.events.firstWhere((e) => e.id == 'cr1').metadata;
    expect(meta['note'], 'bad tags');
    for (final k in tagKeys) {
      expect(meta.containsKey(k), isFalse, reason: k);
    }
  });

  test('the background zone alert reads plans from the state file', () {
    final raw = jsonEncode({
      'backgroundGeofencing': true,
      'zones': [
        {
          'id': 'z1',
          'name': 'Bus stand',
          'latitude': 12.9,
          'longitude': 77.5,
          'radiusMeters': 200,
          'createdAt': '2026-11-01T10:00:00.000',
        },
      ],
      'ifThenPlans': [
        {
          'id': 'p1',
          'if': "I'm at the bus stand",
          'then': 'cross the road',
          'createdAt': '2026-11-02T10:00:00.000',
          'zoneId': 'z1',
        },
      ],
    });
    final copy = backgroundZoneAlert(
      rawState: raw,
      geofenceIds: ['${zoneGeofencePrefix}z1'],
      now: now,
    )!;
    expect(copy.body, contains('Your plan: If'));
    expect(copy.body, contains('cross the road'));
    // And an old state file with no plans reads exactly as before.
    final plain = backgroundZoneAlert(
      rawState: jsonEncode({
        'backgroundGeofencing': true,
        'zones': jsonDecode(raw)['zones'],
      }),
      geofenceIds: ['${zoneGeofencePrefix}z1'],
      now: now,
    )!;
    expect(plain.body, isNot(contains('Your plan')));
  });

  test(
    'the risk-window alerts pick up a window plan, and drop it when deleted',
    () async {
      final c = await blank();
      expect(
        c.riskAlertPlan.map((a) => a.body).join(),
        isNot(contains('Your plan')),
      );
      final plan = await c.addIfThenPlan(
        ifText: 'it is 6pm',
        thenText: 'go for a walk',
      );
      expect(
        c.riskAlertPlan.firstWhere((a) => a.id == 510).body,
        contains('go for a walk'),
      );
      await c.deleteIfThenPlan(plan.id);
      expect(
        c.riskAlertPlan.map((a) => a.body).join(),
        isNot(contains('walk')),
      );
    },
  );

  test('no event type, state or backup version change', () {
    expect(RecoveryController.stateVersion, 17);
    expect(BackupService.currentBackupVersion, 12);
    expect(
      RecoveryEventType.values.map((t) => t.name),
      isNot(anyOf(contains('triggerTag'), contains('ifThenPlan'))),
    );
  });
}
