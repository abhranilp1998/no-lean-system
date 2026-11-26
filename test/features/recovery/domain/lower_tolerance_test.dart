import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/lower_tolerance.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 10, 1, 10);

  RecoveryEvent ev(
    DateTime at, {
    RelapseType? type,
    RecoveryEventType kind = RecoveryEventType.relapse,
    String id = 'e',
  }) => RecoveryEvent.fromJson({
    'id': '$id-${at.toIso8601String()}',
    'type': kind.name,
    'timestamp': at.toIso8601String(),
    'metadata': {if (type != null) 'relapseType': type.name},
  });

  RelapseLogEntry entry(DateTime at, RelapseType type) => RelapseLogEntry(
    occurredAt: at,
    type: type,
    note: 'Logging what happened that day.',
    attemptedSos: false,
  );

  ToleranceWarning? warn(
    List<RecoveryEvent> history,
    List<RelapseLogEntry> entries,
  ) => lowerToleranceWarning(existingEvents: history, entries: entries);

  test('no warning at or under 5 clean days', () {
    final history = [ev(start, type: RelapseType.fullLean)];
    expect(
      warn(history, [
        entry(start.add(const Duration(days: 5)), RelapseType.fullLean),
      ]),
      isNull,
    );
    expect(
      warn(history, [
        entry(start.add(const Duration(days: 3)), RelapseType.fullLean),
      ]),
      isNull,
    );
    expect(warn(history, [entry(start, RelapseType.fullLean)]), isNull);
  });

  test('lean slip after more than 5 days uses their number', () {
    final at = start.add(const Duration(days: 18));
    final warning = warn(
      [ev(start, kind: RecoveryEventType.recoveryStart, id: 'start')],
      [entry(at, RelapseType.fullLean)],
    );
    expect(warning, isNotNull);
    expect(warning!.kind, ToleranceWarningKind.lean);
    expect(warning.cleanDays, 18);
    expect(warning.mixed, isFalse);
    expect(warning.isBenzoOnly, isFalse);
    expect(
      warning.body,
      'You were clean 18 days, so your body handles less now. '
      'Your old amount hits much harder, especially with benzos or alcohol.',
    );
    expect(warning.title, 'Your body handles less now');
    expect(warning.footer, contains('doctor or hospital'));
    expect(warning.footer.toLowerCase(), isNot(contains('112')));
  });

  test('a 6-day gap is the first day that qualifies', () {
    final warning = warn(
      [ev(start, type: RelapseType.fullLean)],
      [entry(start.add(const Duration(days: 6)), RelapseType.partial)],
    );
    expect(warning!.cleanDays, 6);
    expect(warning.body, contains('6 days'));
  });

  test('partial and lean+alcohol slips qualify the same as full lean', () {
    final history = [ev(start, type: RelapseType.fullLean)];
    final at = start.add(const Duration(days: 10));
    expect(
      warn(history, [entry(at, RelapseType.partial)])!.kind,
      ToleranceWarningKind.lean,
    );
    expect(
      warn(history, [entry(at, RelapseType.leanPlusAlcohol)])!.mixed,
      isTrue,
    );
  });

  test('mixed lean + benzo in one save uses the lean card and mixed copy', () {
    final at = start.add(const Duration(days: 12));
    final warning = warn(
      [ev(start, type: RelapseType.fullLean)],
      [
        entry(at, RelapseType.fullLean),
        entry(at.add(const Duration(hours: 2)), RelapseType.benzo),
      ],
    );
    expect(warning!.kind, ToleranceWarningKind.lean);
    expect(warning.mixed, isTrue);
    expect(warning.cleanDays, 12);
    expect(
      warning.body,
      'You were clean 12 days, so your body handles less now. '
      'Your old amount hits much harder, and mixing with benzos or '
      'alcohol makes that even more dangerous.',
    );
  });

  test('benzo-only after a benzo gap gets the gentler note', () {
    final warning = warn(
      [ev(start, type: RelapseType.benzo)],
      [entry(start.add(const Duration(days: 9)), RelapseType.benzo)],
    );
    expect(warning!.kind, ToleranceWarningKind.benzo);
    expect(warning.isBenzoOnly, isTrue);
    expect(warning.cleanDays, 9);
    expect(
      warning.body,
      'You had 9 days without benzos, so they hit harder now. '
      'A smaller amount than before can be enough. '
      'This does not change your lean clean time.',
    );
    expect(warning.title, 'Benzos hit harder after a break');
  });

  test('benzo-only with no benzo history uses the lean clean gap', () {
    final warning = warn(
      [ev(start, kind: RecoveryEventType.recoveryStart, id: 'start')],
      [entry(start.add(const Duration(days: 20)), RelapseType.benzo)],
    );
    expect(warning!.kind, ToleranceWarningKind.benzo);
    expect(warning.cleanDays, 20);
  });

  test(
    'a recent benzo means a benzo-only slip does not warn, even after a long lean gap',
    () {
      final history = [
        ev(start, type: RelapseType.fullLean),
        ev(start.add(const Duration(days: 16)), type: RelapseType.benzo),
      ];
      expect(
        warn(history, [
          entry(start.add(const Duration(days: 17)), RelapseType.benzo),
        ]),
        isNull,
      );
    },
  );

  test('alcohol-only after a long gap does not warn', () {
    expect(
      warn(
        [ev(start, type: RelapseType.fullLean)],
        [entry(start.add(const Duration(days: 20)), RelapseType.alcohol)],
      ),
      isNull,
    );
  });

  test('an OTHER log that names a lean brand is treated as lean', () {
    final warning = warn(
      [ev(start, type: RelapseType.fullLean)],
      [
        RelapseLogEntry(
          occurredAt: start.add(const Duration(days: 11)),
          type: RelapseType.other,
          note: 'I drank a bottle of Phensedyl tonight.',
          attemptedSos: false,
        ),
      ],
    );
    expect(warning!.kind, ToleranceWarningKind.lean);
    expect(warning.cleanDays, 11);
  });

  test('a typeless quick-log is treated as lean', () {
    expect(containsLean(null), isTrue);
  });

  test('multi-day bulk: shown once for the first qualifying dose', () {
    final history = [ev(start, type: RelapseType.fullLean)];
    final warning = warn(history, [
      entry(start.add(const Duration(days: 2)), RelapseType.fullLean),
      entry(start.add(const Duration(days: 18)), RelapseType.fullLean),
      entry(start.add(const Duration(days: 19)), RelapseType.fullLean),
    ]);
    // Day 2 is too soon; day 18 is the first that qualifies (18 days after
    // the original lean, and the day-2 dose does not close that gap because
    // it is only 2 days after — wait, day 2 IS added as extraLean, so day 18
    // is 16 days after day 2. Recheck.
    // Order: day 2 added as lean reset; day 18 is 16 days after day 2 — still
    // > 5, so first qualifying is day 18, cleanDays = 16.
    expect(warning!.kind, ToleranceWarningKind.lean);
    expect(warning.cleanDays, 16);
    expect(warning.occurredAt, start.add(const Duration(days: 18)));
  });

  test(
    'multi-day bulk: only the first of several qualifying doses is used',
    () {
      final history = [ev(start, type: RelapseType.fullLean)];
      final warning = warn(history, [
        entry(start.add(const Duration(days: 8)), RelapseType.fullLean),
        entry(start.add(const Duration(days: 9)), RelapseType.fullLean),
      ]);
      // Day 8 qualifies (8 days). Day 9 is only 1 day after day 8, so it would
      // not qualify on its own; we still report the first (day 8).
      expect(warning!.cleanDays, 8);
      expect(warning.occurredAt, start.add(const Duration(days: 8)));
    },
  );

  test('multi-day bulk of benzo-only days warns once', () {
    final history = [ev(start, type: RelapseType.benzo)];
    final warning = warn(history, [
      entry(start.add(const Duration(days: 10)), RelapseType.benzo),
      entry(start.add(const Duration(days: 11, hours: 3)), RelapseType.benzo),
    ]);
    expect(warning!.kind, ToleranceWarningKind.benzo);
    expect(warning.cleanDays, 10);
  });

  test(
    'mixed multi-day save prefers the lean card even if a benzo comes first',
    () {
      final history = [ev(start, type: RelapseType.fullLean)];
      final warning = warn(history, [
        entry(start.add(const Duration(days: 9)), RelapseType.benzo),
        entry(start.add(const Duration(days: 10)), RelapseType.fullLean),
      ]);
      expect(warning!.kind, ToleranceWarningKind.lean);
      expect(warning.mixed, isTrue);
      expect(warning.cleanDays, 10);
    },
  );

  test(
    'gap is measured from occurredAt, not from now, so late logs still qualify',
    () {
      final happened = start.add(const Duration(days: 18));
      // "Now" is weeks later; the late-logged slip still happened 18 days after
      // the previous lean reset.
      final warning = warn(
        [ev(start, type: RelapseType.fullLean)],
        [entry(happened, RelapseType.fullLean)],
      );
      expect(warning!.cleanDays, 18);
    },
  );

  test('a backdated slip inside a short gap does not warn', () {
    final history = [
      ev(start, type: RelapseType.fullLean),
      ev(start.add(const Duration(days: 20)), type: RelapseType.fullLean),
    ];
    // Logging a missed day only 3 days after the first relapse.
    expect(
      warn(history, [
        entry(start.add(const Duration(days: 3)), RelapseType.fullLean),
      ]),
      isNull,
    );
  });

  test('an empty history does not warn', () {
    expect(
      warn(const [], [
        entry(start.add(const Duration(days: 20)), RelapseType.fullLean),
      ]),
      isNull,
    );
  });

  test(
    'saving does not change the lean timer for a benzo-only warning',
    () async {
      final store = MemoryRecoveryStore();
      final c = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await c.load();
      await c.recordRelapse(entries: [entry(start, RelapseType.fullLean)]);
      final before = c.lastDose;
      final beforeStreakBasis = c.lastDose;
      final slip = entry(
        start.add(const Duration(days: 14)),
        RelapseType.benzo,
      );
      expect(
        lowerToleranceWarning(existingEvents: c.events, entries: [slip])!.kind,
        ToleranceWarningKind.benzo,
      );
      await c.recordRelapse(entries: [slip]);
      expect(c.lastDose, before);
      expect(c.lastDose, beforeStreakBasis);
    },
  );

  test(
    'an old-format backup still imports, and a later long-gap slip warns',
    () async {
      final old = {
        'version': 5,
        'events': [
          {
            'id': 'old-start',
            'type': 'recoveryStart',
            'timestamp': start.toIso8601String(),
            'metadata': <String, dynamic>{},
          },
          {
            'id': 'old-lean',
            'type': 'relapse',
            'timestamp': start.add(const Duration(days: 2)).toIso8601String(),
            'metadata': <String, dynamic>{'streakLost': 2},
          },
        ],
        'preferences': <String, dynamic>{},
      };
      final preview = BackupService().validateBackupJson(jsonEncode(old));
      expect(preview.eventCount, 2);
      final fresh = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
      );
      await fresh.load();
      await fresh.mergeImportedEvents(preview.events);
      expect(
        fresh.events.map((e) => e.id),
        containsAll(['old-start', 'old-lean']),
      );
      final slip = entry(
        start.add(const Duration(days: 2 + 18)),
        RelapseType.fullLean,
      );
      final warning = lowerToleranceWarning(
        existingEvents: fresh.events,
        entries: [slip],
      );
      expect(warning!.cleanDays, 18);
      expect(
        await fresh.recordRelapse(entries: [slip]),
        ProtectedActionResult.completed,
      );
      expect(
        fresh.events.map((e) => e.id),
        containsAll(['old-start', 'old-lean']),
      );
    },
  );
}
