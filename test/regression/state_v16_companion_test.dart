import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/companion/domain/companion_state.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../support/recovery_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 4, 20);

  Future<(RecoveryController, MemoryRecoveryStore)> load([String? s]) async {
    final store = MemoryRecoveryStore(s);
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    return (c, store);
  }

  Map<String, dynamic> legacy(int v) => {
    'stateVersion': v,
    'events': [
      {
        'id': 'r1',
        'type': 'relapse',
        'timestamp': DateTime(2026, 10, 20).toIso8601String(),
        'metadata': <String, dynamic>{},
      },
      {
        'id': 'c1',
        'type': 'craving',
        'timestamp': DateTime(2026, 10, 30).toIso8601String(),
        'metadata': {'intensity': 4, 'trigger': 'Stress'},
      },
    ],
    'futureLetters': [
      {
        'id': 'l1',
        'text': 'Keep going.',
        'createdAt': DateTime(2026, 10, 1).toIso8601String(),
      },
    ],
    'someFutureKey': {'keep': true},
  };

  for (final v in [13, 14, 15]) {
    test(
      'state v$v loads with default companion, keeps data, saves v16',
      () async {
        final (c, store) = await load(jsonEncode(legacy(v)));
        expect(c.events, hasLength(2));
        expect(c.companion.triggersAsked, isFalse);
        expect(c.companion.substances, isEmpty);
        await c.updateCompanion(
          (s) => s.copyWith(
            substances: {Substance.benzo, Substance.codeine},
            triggers: ['Evenings'],
            triggersAsked: true,
          ),
        );
        final saved = jsonDecode(store.value!) as Map<String, dynamic>;
        expect(saved['stateVersion'], RecoveryController.stateVersion);
        expect(saved['someFutureKey'], {'keep': true});
        expect((saved['events'] as List), hasLength(2));
        if (v >= 15 || saved.containsKey('futureLetters')) {
          expect(saved['futureLetters'], isNotNull);
        }
        final (again, _) = await load(store.value);
        expect(again.companion.needsTaperWarning, isTrue);
        expect(again.companion.triggers, ['Evenings']);
        expect(again.events, hasLength(2));
      },
    );
  }

  test(
    'backup format 11 round-trips companion; format 10 still imports',
    () async {
      final (c, _) = await load(jsonEncode(legacy(15)));
      await c.updateCompanion(
        (s) => s.copyWith(
          substances: {Substance.alcohol},
          heavyAlcohol: true,
          triggers: ['Alone'],
          triggersAsked: true,
          slips: [SlipNote(at: DateTime.utc(2026, 11, 1), ifThen: 'walk')],
        ),
      );
      final service = BackupService();
      final payload = service.buildBackupPayload(
        c.events,
        preferences: c.portablePreferences,
        zones: c.zones,
        companion: c.companion,
      );
      expect(payload['version'], BackupService.currentBackupVersion);
      final preview = service.validateBackupJson(jsonEncode(payload));
      expect(preview.companion, isNotNull);

      final (fresh, _) = await load();
      await fresh.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
        importedCompanion: preview.companion,
      );
      expect(fresh.companion.needsTaperWarning, isTrue);
      expect(fresh.companion.slips.single.ifThen, 'walk');
      expect(fresh.events.map((e) => e.id), containsAll(['r1', 'c1']));

      final old = Map<String, dynamic>.from(payload)
        ..['version'] = 10
        ..remove('companion');
      final p10 = service.validateBackupJson(jsonEncode(old));
      expect(p10.eventCount, 2);
      expect(p10.companion, isNull);
    },
  );

  test('best clean hours survives a relapse', () async {
    final (c, _) = await load(jsonEncode(legacy(15)));
    expect(c.bestCleanHours, greaterThan(24 * 14));
  });
}
