import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/data_fixes_v12.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
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

  test('double-tap twins are dropped; one multi-entry save is kept', () {
    final same = {'relapseType': 'fullLean', 'note': 'x', 'batchId': 'A'};
    final out = dedupeDoubleTaps([
      relapse('1', t, same),
      relapse('2', t.add(const Duration(seconds: 20)), {
        ...same,
        'batchId': 'B',
      }),
      relapse('3', t.add(const Duration(seconds: 30)), same),
      relapse('4', t.add(const Duration(minutes: 5)), {
        ...same,
        'batchId': 'C',
      }),
    ]);
    expect(out.map((e) => e.id), ['1', '3', '4']);
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
