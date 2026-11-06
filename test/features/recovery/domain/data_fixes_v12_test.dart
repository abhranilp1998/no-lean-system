import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/data_fixes_v12.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

RecoveryEvent relapse(String id, DateTime at, Map<String, dynamic> meta) =>
    RecoveryEvent.fromJson({
      'id': id,
      'type': RecoveryEventType.relapse.name,
      'timestamp': at.toIso8601String(),
      'metadata': meta,
    });

void main() {
  final t = DateTime(2026, 10, 30, 19, 39);

  group('dose consistency', () {
    test('typed 120ml beats the untouched 1-bottle default', () {
      final e = fixDoseConsistency(
        relapse('a', t, {
          'quantity': '120ml',
          'amount': 1.0,
          'unit': 'bottle',
          'amountMl': 100.0,
          'bottleMl': 100.0,
        }),
        bottleMl: 100,
      );
      expect(e.metadata['unit'], 'ml');
      expect(e.metadata['amount'], 120.0);
      expect(e.metadata['amountMl'], 120.0);
      expect(e.metadata.containsKey('bottleMl'), isFalse);
      expect(e.metadata['doseFixedFrom'], isNotNull);
    });

    test('real disagreement is flagged, not guessed', () {
      final e = fixDoseConsistency(
        relapse('b', t, {
          'quantity': '1X100 ml',
          'amount': 2.0,
          'unit': 'bottle',
          'amountMl': 200.0,
          'bottleMl': 100.0,
        }),
        bottleMl: 100,
      );
      expect(e.metadata['doseConflict'], isTrue);
      expect(e.metadata['amount'], 2.0);
    });

    test('agreeing text and fields are left alone; idempotent', () {
      final raw = relapse('c', t, {
        'quantity': '2 bottles',
        'amount': 200.0,
        'unit': 'ml',
        'amountMl': 200.0,
      });
      final once = fixDoseConsistency(raw, bottleMl: 100);
      expect(once.metadata, raw.metadata);
      final twice = fixDoseConsistency(
        fixDoseConsistency(
          relapse('d', t, {
            'quantity': '120ml',
            'amount': 1.0,
            'unit': 'bottle',
            'amountMl': 100.0,
            'bottleMl': 100.0,
          }),
          bottleMl: 100,
        ),
        bottleMl: 100,
      );
      expect(twice.metadata['amount'], 120.0);
    });

    test('ml is recomputed when it disagrees with amount × bottle', () {
      final e = fixDoseConsistency(
        relapse('e', t, {'amount': 2.0, 'unit': 'bottle', 'bottleMl': 100.0}),
        bottleMl: 100,
      );
      expect(e.metadata['amountMl'], 200.0);
    });

    test('"2 x 100 ml" parses to 200 ml', () {
      expect(parseQuantityTextV12('2 x 100 ml', bottleMl: 100)!.amountMl, 200);
    });
  });

  test('Ascoril C / Phensedyl logged as OTHER become lean', () {
    final e = fixLeanBrand(
      relapse('f', t, {'relapseType': 'other', 'note': 'one ascoril c / 2'}),
    );
    expect(e.metadata['relapseType'], 'fullLean');
    expect(e.metadata['relapseTypeFrom'], 'other');
    final p = fixLeanBrand(
      relapse('g', t, {'relapseType': 'other', 'note': 'Phensedyl'}),
    );
    expect(p.metadata['relapseType'], 'fullLean');
    final keep = fixLeanBrand(
      relapse('h', t, {'relapseType': 'benzo', 'note': 'phensedyl too'}),
    );
    expect(keep.metadata['relapseType'], 'benzo');
    expect(
      RelapseLogEntry(
        occurredAt: t,
        type: RelapseType.other,
        note: 'ascoril-c bottle again',
        attemptedSos: false,
      ).toMetadata()['relapseType'],
      'fullLean',
    );
  });

  group('non-destructive double-tap dedupe (shared rule)', () {
    Map<String, dynamic> m(String batch, Duration after, [String note = 'x']) =>
        {
          'relapseType': 'fullLean',
          'note': note,
          'batchId': batch,
          'recordedAt': t.add(after).toIso8601String(),
        };

    test('twins are hidden with duplicateOf, never deleted', () {
      final out = dedupeDoubleTaps([
        relapse('1', t, m('A', Duration.zero)),
        relapse(
          '2',
          t.add(const Duration(seconds: 20)),
          m('B', const Duration(seconds: 20)),
        ),
        relapse(
          '3',
          t.add(const Duration(seconds: 30)),
          m('A', const Duration(seconds: 30)),
        ),
        relapse(
          '4',
          t.add(const Duration(minutes: 5)),
          m('C', const Duration(minutes: 5)),
        ),
      ]);
      expect(out.events.map((e) => e.id), ['1', '3', '4']);
      expect(out.hidden.single.id, '2');
      expect(out.hidden.single.metadata['duplicateOf'], '1');
      expect(out.hidden.single.metadata['hidden'], isTrue);
    });

    test('dedupe keys on recordedAt, not the logged time', () {
      final out = dedupeDoubleTaps([
        relapse('1', t, m('A', const Duration(hours: 1))),
        relapse('2', t, m('B', const Duration(hours: 3))),
      ]);
      expect(out.hidden, isEmpty);
    });

    test('blank-note backfills and pledges are never touched', () {
      final backfill = {
        'relapseType': 'fullLean',
        'recordedAt': t.add(const Duration(days: 1)).toIso8601String(),
      };
      final pledge = RecoveryEvent.fromJson({
        'id': 'p1',
        'type': RecoveryEventType.pledge.name,
        'timestamp': t.toIso8601String(),
        'metadata': <String, dynamic>{},
      });
      final out = dedupeDoubleTaps([
        relapse('1', t, {...backfill, 'batchId': 'A'}),
        relapse('2', t, {...backfill, 'batchId': 'B'}),
        pledge,
        RecoveryEvent.fromJson({...pledge.toJson(), 'id': 'p2'}),
      ]);
      expect(out.hidden, isEmpty);
      expect(out.events, hasLength(4));
    });
  });

  test('brand regex: no broad lean/syrup, negation respected', () {
    expect(mentionsLeanBrand('leaning on my brother'), isFalse);
    expect(mentionsLeanBrand('maple syrup pancakes'), isFalse);
    expect(mentionsLeanBrand('had lean again'), isFalse);
    expect(mentionsLeanBrand('no corex today, just beer'), isFalse);
    expect(mentionsLeanBrand("didn't buy the phensedyl"), isFalse);
    expect(mentionsLeanBrand('skipped the Ascoril C'), isFalse);
    expect(mentionsLeanBrand('Phensedyl'), isTrue);
    expect(mentionsLeanBrand('no beer, two corex'), isTrue);
    final e = fixLeanBrand(
      relapse('n', t, {'relapseType': 'other', 'note': 'no codeine, weed'}),
    );
    expect(e.metadata['relapseType'], 'other');
  });

  test('applyDataFixesV12 is idempotent', () {
    final input = [
      relapse('1', t, {
        'relapseType': 'other',
        'note': 'ascoril c',
        'quantity': '120ml',
        'amount': 1.0,
        'unit': 'bottle',
        'amountMl': 100.0,
        'bottleMl': 100.0,
        'batchId': 'A',
        'recordedAt': t.toIso8601String(),
      }),
      relapse('2', t.add(const Duration(seconds: 10)), {
        'relapseType': 'other',
        'note': 'ascoril c',
        'quantity': '120ml',
        'amount': 1.0,
        'unit': 'bottle',
        'amountMl': 100.0,
        'bottleMl': 100.0,
        'batchId': 'B',
        'recordedAt': t.add(const Duration(seconds: 10)).toIso8601String(),
      }),
    ];
    final once = applyDataFixesV12(input, bottleMl: 100);
    final twice = applyDataFixesV12(once.events, bottleMl: 100);
    expect(once.hidden.single.id, '2');
    expect(twice.hidden, isEmpty);
    expect(
      jsonEncode(twice.events.map((e) => e.toJson()).toList()),
      jsonEncode(once.events.map((e) => e.toJson()).toList()),
    );
  });

  for (final legacy in [10, 11]) {
    test('backup v$legacy → v12 round-trip keeps hidden copies', () {
      final service = BackupService();
      final dup = {
        'relapseType': 'fullLean',
        'note': 'x',
        'recordedAt': t.toIso8601String(),
      };
      final v = service.validateBackupJson(
        jsonEncode({
          'version': legacy,
          'events': [
            relapse('1', t, {...dup, 'batchId': 'A'}).toJson(),
            relapse('2', t, {...dup, 'batchId': 'B'}).toJson(),
            relapse('3', t.add(const Duration(days: 1)), {
              'relapseType': 'fullLean',
            }).toJson(),
          ],
          'preferences': <String, dynamic>{},
        }),
      );
      expect(v.events.map((e) => e.id), ['1', '3']);
      expect(v.hiddenDuplicates.single.metadata['duplicateOf'], '1');

      final v12 = jsonEncode(
        service.buildBackupPayload(
          v.events,
          preferences: const {},
          hiddenDuplicates: v.hiddenDuplicates,
          feedbackNotes: [
            {'at': '2026-10-30T14:09:00.000Z', 'text': 'more dark mode'},
          ],
        ),
      );
      expect(jsonDecode(v12)['version'], 12);
      final again = service.validateBackupJson(v12);
      expect(again.events.map((e) => e.id), ['1', '3']);
      expect(again.hiddenDuplicates.map((e) => e.id), ['2']);
      expect((again.feedbackNotes as List).single['text'], 'more dark mode');
    });
  }

  test('controller keeps hidden duplicates in state and merges them', () async {
    SharedPreferences.setMockInitialValues({});
    final dup = {
      'relapseType': 'fullLean',
      'note': 'x',
      'recordedAt': t.toIso8601String(),
    };
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': 16,
        'events': [
          relapse('1', t, {...dup, 'batchId': 'A'}).toJson(),
          relapse('2', t, {...dup, 'batchId': 'B'}).toJson(),
        ],
      }),
    );
    final c = RecoveryController(relapseLock: FakeRelapseLock(), store: store);
    await c.load();
    expect(c.events.map((e) => e.id), ['1']);
    expect(c.hiddenDuplicates.single.id, '2');
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect((saved['hiddenDuplicates'] as List).single['id'], '2');
    // Reloading (now v17) neither re-hides nor resurfaces anything.
    final c2 = RecoveryController(relapseLock: FakeRelapseLock(), store: store);
    await c2.load();
    expect(c2.events.map((e) => e.id), ['1']);
    expect(c2.hiddenDuplicates.map((e) => e.id), ['2']);
    // Merging a backup that still has the copy visible does not resurface it.
    await c2.mergeImportedEvents([
      relapse('2', t, {...dup, 'batchId': 'B'}),
    ]);
    expect(c2.events.map((e) => e.id), ['1']);
  });

  test('state v16 is fixed on load and saved as v17', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': 16,
        'bottleMl': 100.0,
        'events': [
          relapse('r1', t, {
            'relapseType': 'other',
            'note': 'one ascoril c / 2',
            'quantity': '120ml',
            'amount': 1.0,
            'unit': 'bottle',
            'amountMl': 100.0,
            'bottleMl': 100.0,
            'batchId': 'A',
          }).toJson(),
        ],
      }),
    );
    final c = RecoveryController(relapseLock: FakeRelapseLock(), store: store);
    await c.load();
    final r = c.events.firstWhere((e) => e.id == 'r1');
    expect(r.metadata['relapseType'], 'fullLean');
    expect(r.metadata['amountMl'], 120.0);
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect(saved['stateVersion'], 17);
  });
}
