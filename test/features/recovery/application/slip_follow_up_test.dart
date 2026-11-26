import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';
import 'package:no_lean/features/recovery/domain/mixing_alert.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/slip_review.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 26, 22, 30);

  Future<(RecoveryController, MemoryRecoveryStore)> open([
    String? stored,
    DateTime Function()? clock,
  ]) async {
    final store = MemoryRecoveryStore(stored);
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: clock ?? () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    return (c, store);
  }

  RelapseLogEntry entry(
    DateTime at,
    RelapseType type, {
    String note = 'Rough evening, gave in.',
    String? quantity,
  }) => RelapseLogEntry(
    occurredAt: at,
    type: type,
    note: note,
    attemptedSos: false,
    quantity: quantity,
  );

  test('codeine then alprazolam raises one alert naming both', () async {
    final (c, _) = await open();
    await c.recordRelapse(
      entries: [entry(DateTime(2026, 11, 26, 18), RelapseType.fullLean)],
      tryBiometrics: false,
    );
    expect(c.pendingMixingAlert, isNull);
    expect(c.takeSlipReview(), isNotNull);

    await c.recordRelapse(
      entries: [
        entry(
          DateTime(2026, 11, 26, 21),
          RelapseType.benzo,
          note: 'took one alprazolam to sleep',
        ),
      ],
      tryBiometrics: false,
    );
    final alert = c.takeMixingAlert()!;
    expect(alert.quote, 'You logged codeine + alprazolam today.');
    expect(c.takeMixingAlert(), isNull, reason: 'taken once');
  });

  test('a multi-entry save shows one alert and one review request', () async {
    final (c, _) = await open();
    await c.recordRelapse(
      entries: [
        for (var i = 0; i < 4; i++)
          entry(DateTime(2026, 11, 26, 9 + i * 2), RelapseType.fullLean),
        for (var i = 0; i < 3; i++)
          entry(
            DateTime(2026, 11, 26, 10 + i * 3),
            RelapseType.benzo,
            note: 'xanax again today',
          ),
      ],
      tryBiometrics: false,
    );
    expect(c.takeMixingAlert()!.eventIds.length, 7);
    expect(c.takeMixingAlert(), isNull);
    expect(c.takeSlipReview()!.eventIds.length, 7);
    expect(c.takeSlipReview(), isNull);
  });

  test('a multi-day catch-up gets no automatic review prompt', () async {
    final (c, _) = await open();
    await c.recordRelapse(
      entries: [
        entry(DateTime(2026, 11, 20, 20), RelapseType.fullLean),
        entry(DateTime(2026, 11, 24, 20), RelapseType.fullLean),
      ],
      tryBiometrics: false,
    );
    expect(c.pendingSlipReview, isNull);
    expect(c.pendingMixingAlert, isNull);
  });

  test('backdating a mix to last month never alarms tonight', () async {
    final (c, _) = await open();
    await c.recordRelapse(
      entries: [
        entry(DateTime(2026, 10, 3, 21), RelapseType.fullLean),
        entry(DateTime(2026, 10, 3, 22), RelapseType.alcohol),
      ],
      tryBiometrics: false,
    );
    expect(c.pendingMixingAlert, isNull);
  });

  test(
    'one-tap Used raises the alert too (widget / notification path)',
    () async {
      final (c, _) = await open(null, DateTime.now);
      await c.recordRelapse(
        entries: [
          entry(
            DateTime.now().subtract(const Duration(hours: 2)),
            RelapseType.benzo,
            note: 'diazepam, couldn\'t sleep',
          ),
        ],
        tryBiometrics: false,
      );
      c.takeMixingAlert();
      await c.quickLogUsed(tryBiometrics: false);
      expect(c.pendingMixingAlert?.substances, ['codeine', 'diazepam']);
    },
  );

  test('benzo alone: no alert, and it does not reset the lean timer', () async {
    final (c, _) = await open();
    final before = c.cleanDuration;
    await c.recordRelapse(
      entries: [entry(DateTime(2026, 11, 26, 20), RelapseType.benzo)],
      tryBiometrics: false,
    );
    expect(c.pendingMixingAlert, isNull);
    final benzo = c.events.lastWhere(
      (e) => e.type == RecoveryEventType.relapse,
    );
    expect(resetsLeanCleanTimer(benzo), isFalse);
    expect(c.cleanDuration >= before, isTrue);
  });

  test('pending alert and review are not saved to disk', () async {
    final (c, store) = await open();
    await c.recordRelapse(
      entries: [entry(DateTime(2026, 11, 26, 20), RelapseType.leanPlusAlcohol)],
      tryBiometrics: false,
    );
    expect(c.pendingMixingAlert, isNotNull);
    final (again, _) = await open(store.value);
    expect(again.pendingMixingAlert, isNull);
    expect(again.pendingSlipReview, isNull);
    expect(
      detectMixingAlert(events: again.events, now: now),
      isNotNull,
      reason: 'the mix is re-derivable from the saved log',
    );
  });

  group('recordSlipReview', () {
    test(
      'saves without a PIN, only on relapses, and survives reload',
      () async {
        final (c, store) = await open();
        await c.enableRelapseLock('4321');
        await c.recordRelapse(
          pin: '4321',
          entries: [
            entry(
              DateTime(2026, 11, 26, 20),
              RelapseType.fullLean,
            ).withTags(['Stress']),
          ],
          tryBiometrics: false,
        );
        final request = c.takeSlipReview()!;
        final updated = await c.recordSlipReview(
          request.eventIds,
          const SlipReview(
            place: "Friend's place",
            withWho: 'friends',
            triggers: ['Payday'],
          ),
        );
        expect(updated, 1);
        final slip = c.events.singleWhere(
          (e) => e.id == request.eventIds.single,
        );
        expect(slip.metadata['place'], "Friend's place");
        expect(slip.metadata['withWho'], 'friends');
        expect(slip.metadata['contextTags'], ['Stress', 'Payday']);
        expect(slip.timestamp, DateTime(2026, 11, 26, 20), reason: 'time kept');

        final (again, _) = await open(store.value);
        final reloaded = again.events.singleWhere((e) => e.id == slip.id);
        expect(reloaded.metadata['place'], "Friend's place");
      },
    );

    test('empty review and non-relapse ids change nothing', () async {
      final (c, store) = await open();
      final starts = c.events.first.id;
      final writes = store.writes;
      expect(
        await c.recordSlipReview({starts}, const SlipReview(place: 'Home')),
        0,
      );
      expect(await c.recordSlipReview({starts}, const SlipReview()), 0);
      expect(store.writes, writes);
    });
  });

  test('reviewed-era slips before the window lengthen the warning', () async {
    final (c, _) = await open();
    expect(
      c.riskAlertPlan.any((a) => a.title.contains('IN 15 MIN')),
      isTrue,
      reason: 'default lead is unchanged with no pattern',
    );
    await c.recordRelapse(
      entries: [
        entry(DateTime(2026, 11, 20, 15, 40), RelapseType.fullLean),
        entry(DateTime(2026, 11, 23, 16, 10), RelapseType.fullLean),
      ],
      tryBiometrics: false,
    );
    expect(c.riskAlertPlan.any((a) => a.title.contains('IN 90 MIN')), isTrue);
  });
}

extension on RelapseLogEntry {
  RelapseLogEntry withTags(List<String> tags) => RelapseLogEntry(
    occurredAt: occurredAt,
    type: type,
    note: note,
    attemptedSos: attemptedSos,
    contextTags: tags,
  );
}
