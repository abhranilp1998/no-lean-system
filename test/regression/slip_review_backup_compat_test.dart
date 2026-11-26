import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/mixing_alert.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/slip_review.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../support/recovery_fakes.dart';

/// Rule: always backwards compatible. The slip review and mixing alert add
/// only optional relapse metadata keys, so data written by every older build
/// must import, open and re-export without losing anything, and derive the
/// mixing alert from fields those builds already wrote.
void main() {
  const newKeys = ['place', 'zoneId', 'withWho', 'reviewedAt'];

  // A backup exactly as an older build (backup format 8, before the slip
  // review existed) would have written it.
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
        'id': 'lean1',
        'type': 'relapse',
        'timestamp': '2026-11-19T18:00:00.000',
        'metadata': {
          'relapseType': 'fullLean',
          'note': 'Bad day at work, gave in.',
          'attemptedSos': false,
          'contextTags': ['Stress'],
          'someFutureKey': {'keep': true},
        },
      },
      {
        'id': 'xan1',
        'type': 'relapse',
        'timestamp': '2026-11-19T21:30:00.000',
        'metadata': {
          'relapseType': 'other',
          'note': 'took an alprazolam to come down',
          'attemptedSos': false,
        },
      },
      {
        // Oldest builds wrote relapses with no type or note at all.
        'id': 'legacy',
        'type': 'relapse',
        'timestamp': '2026-11-10T20:00:00.000',
        'metadata': <String, dynamic>{},
      },
    ],
    'zones': <Object>[],
    'preferences': {'dailySpend': 250},
  };

  Future<RecoveryController> blank() async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await c.load();
    return c;
  }

  for (final v in [8, 10, 12]) {
    test(
      'backup format $v imports with every event and derives the alert',
      () async {
        final service = BackupService();
        final preview = service.validateBackupJson(jsonEncode(oldBackup(v)));
        expect(preview.eventCount, 4);
        expect(
          preview.events.map((e) => e.id),
          containsAll(['lean1', 'xan1', 'legacy']),
        );

        final c = await blank();
        await c.mergeImportedEvents(
          preview.events,
          preferences: preview.preferences,
        );
        expect(
          c.events.map((e) => e.id),
          containsAll(['start', 'lean1', 'xan1', 'legacy']),
        );

        // The old notes alone are enough: no new field is needed.
        final alert = detectMixingAlert(
          events: c.events,
          now: DateTime(2026, 11, 19, 22),
        )!;
        expect(alert.quote, 'You logged codeine + alprazolam today.');
        expect(alert.eventIds, containsAll(['lean1', 'xan1']));
        expect(
          detectMixingAlert(events: c.events, now: DateTime(2026, 11, 26, 22)),
          isNull,
          reason: 'a week-old mix is history, not an alarm',
        );

        // Nothing was rewritten: old events carry none of the new keys, and
        // their own keys (including unknown ones) are untouched.
        final lean = c.events.firstWhere((e) => e.id == 'lean1');
        expect(lean.metadata['someFutureKey'], {'keep': true});
        expect(lean.metadata['contextTags'], ['Stress']);
        for (final e in c.events) {
          for (final k in newKeys) {
            expect(e.metadata.containsKey(k), isFalse, reason: '${e.id}.$k');
          }
        }

        // Re-export keeps every original key and value, byte for byte.
        final again = service.buildBackupPayload(
          c.events,
          preferences: c.portablePreferences,
        );
        final out = {
          for (final e in (again['events'] as List).cast<Map>())
            e["id"] as String: e,
        };
        // And against the raw file: every original key and value survives.
        for (final raw in (oldBackup(v)['events'] as List).cast<Map>()) {
          final exported = out[raw['id']]!;
          expect(
            exported['timestamp'],
            raw['timestamp'],
            reason: '${raw['id']}',
          );
          final meta = (exported['metadata'] as Map);
          for (final e in (raw['metadata'] as Map).entries) {
            expect(meta[e.key], e.value, reason: '${raw['id']}.${e.key}');
          }
        }
        final original = {for (final e in preview.events) e.id: e.toJson()};
        for (final id in original.keys) {
          // Integration build: #25 derives streakLost on import for a legacy
          // relapse that lacked it. Everything else must match exactly.
          final exported = Map<String, dynamic>.from(out[id]!);
          final meta = Map<String, dynamic>.from(exported['metadata'] as Map);
          final origMeta = (original[id]!['metadata'] as Map);
          for (final k in meta.keys.toList()) {
            if (!origMeta.containsKey(k) && k.startsWith('streakLost')) {
              meta.remove(k);
            }
          }
          exported['metadata'] = meta;
          expect(jsonEncode(exported), jsonEncode(original[id]), reason: id);
        }
      },
    );
  }

  test('an old stateVersion snapshot opens and loses no events', () async {
    final snapshot = {
      'stateVersion': 12,
      'events': oldBackup(8)['events'],
      'zones': <Object>[],
    };
    final c = RecoveryController(
      store: MemoryRecoveryStore(jsonEncode(snapshot)),
      relapseLock: FakeRelapseLock(),
    );
    await c.load();
    expect(c.loadStatus, RecoveryLoadStatus.ready, reason: c.loadMessage);
    expect(c.events.length, 4);
    // Reviewing an old slip adds keys only; it never rewrites the rest.
    final before = c.events.firstWhere((e) => e.id == 'lean1').metadata;
    await c.recordSlipReview({
      'lean1',
    }, const SlipReview(place: 'Work', withWho: 'work'));
    final after = c.events.firstWhere((e) => e.id == 'lean1').metadata;
    expect(after['place'], 'Work');
    for (final entry in before.entries) {
      expect(after[entry.key], entry.value, reason: entry.key);
    }
  });

  test(
    'a backup written WITH reviews round-trips; odd values never reject it',
    () async {
      final service = BackupService();
      final c = await blank();
      final preview = service.validateBackupJson(jsonEncode(oldBackup(12)));
      await c.mergeImportedEvents(preview.events);
      await c.recordSlipReview(
        {'lean1'},
        const SlipReview(
          place: "Friend's place",
          withWho: 'friends',
          triggers: ['Payday'],
        ),
      );
      final payload = service.buildBackupPayload(
        c.events,
        preferences: c.portablePreferences,
      );
      final restored = service.validateBackupJson(jsonEncode(payload));
      final lean = restored.events.firstWhere((e) => e.id == 'lean1');
      expect(lean.metadata['place'], "Friend's place");
      expect(lean.metadata['withWho'], 'friends');
      expect(lean.metadata['contextTags'], ['Stress', 'Payday']);

      // Garbage in the optional keys is dropped, not an import failure.
      final odd = oldBackup(12);
      ((odd['events'] as List)[1] as Map)['metadata'] = {
        'relapseType': 'fullLean',
        'note': 'bad data in the new keys',
        'place': 99,
        'withWho': ['nope'],
        'zoneId': '',
        'reviewedAt': false,
      };
      final p = service.validateBackupJson(jsonEncode(odd));
      final fixed = p.events.firstWhere((e) => e.id == 'lean1').metadata;
      expect(fixed['note'], 'bad data in the new keys');
      for (final k in newKeys) {
        expect(fixed.containsKey(k), isFalse, reason: k);
      }
    },
  );

  test('state and backup versions are unchanged by this feature', () {
    // No version bump: older builds keep reading what this build writes.
    expect(RecoveryController.stateVersion, 18);
    expect(BackupService.currentBackupVersion, 13);
    expect(
      RecoveryEventType.values.map((t) => t.name),
      isNot(contains('slipReview')),
    );
  });
}
