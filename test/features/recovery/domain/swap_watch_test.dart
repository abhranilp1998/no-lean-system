import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/swap_watch.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fixed "today" so windows are deterministic: recent = Nov 13–26,
  // previous = Oct 30–Nov 12.
  final now = DateTime(2026, 11, 26, 23, 30);

  RecoveryEvent ev(
    DateTime at, {
    RelapseType? type,
    String note = '',
    String id = 'e',
  }) => RecoveryEvent.fromJson({
    'id': '$id-${at.toIso8601String()}-$note',
    'type': 'relapse',
    'timestamp': at.toIso8601String(),
    'metadata': {
      if (type != null) 'relapseType': type.name,
      if (note.isNotEmpty) 'note': note,
    },
  });

  DateTime d(int month, int day, [int hour = 21]) =>
      DateTime(2026, month, day, hour);

  List<RecoveryEvent> days(RelapseType type, List<(int, int)> md) => [
    for (final (m, day) in md) ev(d(m, day), type: type, id: '$type-$m-$day'),
  ];

  test('unique days, not doses, and windows use occurredAt', () {
    final events = [
      // Two doses on one previous lean day still count as one day.
      ev(d(11, 1, 10), type: RelapseType.fullLean, id: 'a'),
      ev(d(11, 1, 22), type: RelapseType.fullLean, id: 'b'),
      ev(d(11, 5), type: RelapseType.fullLean, id: 'c'),
      ev(d(11, 14), type: RelapseType.fullLean, id: 'd'), // recent
      // A late-logged event whose occurredAt is in the previous window.
      ev(d(11, 8), type: RelapseType.alcohol, id: 'late'),
      ev(d(11, 20), type: RelapseType.alcohol, id: 'alc-recent-1'),
      ev(d(11, 22), type: RelapseType.alcohol, id: 'alc-recent-2'),
      ev(d(11, 24), type: RelapseType.alcohol, id: 'alc-recent-3'),
      ev(d(11, 26), type: RelapseType.alcohol, id: 'alc-recent-4'),
      // Future events are ignored.
      ev(DateTime(2026, 11, 27), type: RelapseType.fullLean, id: 'future'),
      // Too old.
      ev(d(10, 10), type: RelapseType.fullLean, id: 'old'),
    ];
    final counts = substanceDayCounts(events: events, now: now);
    expect(counts[WatchedSubstance.lean]!.previous, 2); // Nov 1, 5
    expect(counts[WatchedSubstance.lean]!.recent, 1); // Nov 14
    expect(counts[WatchedSubstance.alcohol]!.previous, 1); // Nov 8
    expect(counts[WatchedSubstance.alcohol]!.recent, 4);
  });

  test('lean+alcohol counts for both substances on that day', () {
    final counts = substanceDayCounts(
      events: [ev(d(11, 20), type: RelapseType.leanPlusAlcohol)],
      now: now,
    );
    expect(counts[WatchedSubstance.lean]!.recent, 1);
    expect(counts[WatchedSubstance.alcohol]!.recent, 1);
  });

  test('benzo-only is a benzo day, never a lean day', () {
    final counts = substanceDayCounts(
      events: [
        ev(d(11, 2), type: RelapseType.benzo),
        ev(d(11, 20), type: RelapseType.benzo),
      ],
      now: now,
    );
    expect(counts[WatchedSubstance.benzo]!.previous, 1);
    expect(counts[WatchedSubstance.benzo]!.recent, 1);
    expect(counts[WatchedSubstance.lean]!.previous, 0);
    expect(counts[WatchedSubstance.lean]!.recent, 0);
  });

  test('a typeless log counts as lean; a lean brand in OTHER does too', () {
    final typeless = ev(d(11, 20), id: 'quick');
    final branded = ev(
      d(11, 21),
      type: RelapseType.other,
      note: 'Drank a bottle of Phensedyl tonight.',
      id: 'brand',
    );
    expect(substancesOn(typeless), {WatchedSubstance.lean});
    expect(substancesOn(branded), {WatchedSubstance.lean});
  });

  test('weed, alcohol and benzos can be read from the note', () {
    expect(
      substancesOn(ev(d(11, 20), type: RelapseType.other, note: 'smoked weed')),
      {WatchedSubstance.weed},
    );
    expect(
      substancesOn(ev(d(11, 20), type: RelapseType.other, note: 'two beers')),
      {WatchedSubstance.alcohol},
    );
    expect(
      substancesOn(
        ev(d(11, 20), type: RelapseType.other, note: 'took alprazolam'),
      ),
      {WatchedSubstance.benzo},
    );
    expect(
      substancesOn(
        ev(d(11, 20), type: RelapseType.other, note: 'no beer today'),
      ),
      {WatchedSubstance.other},
    );
  });

  test('the example copy: lean down 70%, alcohol 1 to 4 days a week', () {
    // Previous (Oct 30–Nov 12): 10 lean days, 2 alcohol days (= 1/week).
    // Recent (Nov 13–26): 3 lean days, 8 alcohol days (= 4/week).
    final leanPrev = [
      for (final day in [30, 31]) ev(d(10, day), type: RelapseType.fullLean),
      for (final day in [1, 2, 3, 4, 5, 6, 7, 8])
        ev(d(11, day), type: RelapseType.fullLean),
    ];
    final leanRecent = [
      for (final day in [14, 16, 18])
        ev(d(11, day), type: RelapseType.fullLean),
    ];
    final alcPrev = [
      ev(d(11, 2), type: RelapseType.alcohol),
      ev(d(11, 9), type: RelapseType.alcohol),
    ];
    final alcRecent = [
      for (final day in [13, 15, 16, 18, 20, 22, 24, 26])
        ev(d(11, day), type: RelapseType.alcohol),
    ];
    final insight = detectSwapWatch(
      events: [...leanPrev, ...leanRecent, ...alcPrev, ...alcRecent],
      now: now,
    );
    expect(insight, isNotNull);
    expect(insight!.lean.previous, 10);
    expect(insight.lean.recent, 3);
    expect(insight.leanDropPercent, 70);
    expect(insight.risen, WatchedSubstance.alcohol);
    expect(insight.other.previous, 2);
    expect(insight.other.recent, 8);
    expect(
      insight.body,
      'Lean is down 70%, nice work. Alcohol went from 1 day a week '
      'to 4 days a week, worth keeping an eye on.',
    );
    expect(insight.footer, contains('SOS contact'));
    expect(insight.footer.toLowerCase(), isNot(contains('112')));
  });

  test('a 1-day lean drop under 30% does not warn', () {
    // 4 previous lean days, 3 recent: 25% and 1 day.
    final events = [
      ...days(RelapseType.fullLean, [(11, 1), (11, 3), (11, 5), (11, 7)]),
      ...days(RelapseType.fullLean, [(11, 14), (11, 16), (11, 18)]),
      ...days(RelapseType.alcohol, [(11, 2)]),
      ...days(RelapseType.alcohol, [(11, 14), (11, 20), (11, 22)]),
    ];
    expect(detectSwapWatch(events: events, now: now), isNull);
  });

  test(
    'a 30% one-day lean drop does warn when the other rise is meaningful',
    () {
      // 3 previous lean → 2 recent = 33% and 1 day. Alcohol 0 → 2 days.
      final events = [
        ...days(RelapseType.fullLean, [(11, 1), (11, 5), (11, 9)]),
        ...days(RelapseType.fullLean, [(11, 14), (11, 20)]),
        ...days(RelapseType.alcohol, [(11, 20), (11, 24)]),
      ];
      final insight = detectSwapWatch(events: events, now: now);
      expect(insight, isNotNull);
      expect(insight!.leanDropPercent, 33);
      expect(insight.risen, WatchedSubstance.alcohol);
    },
  );

  test('a one-day rise in the other substance is not enough', () {
    final events = [
      ...days(RelapseType.fullLean, [(11, 1), (11, 3), (11, 5), (11, 7)]),
      ...days(RelapseType.fullLean, [(11, 14)]),
      ...days(RelapseType.alcohol, [(11, 20)]), // 0 → 1
    ];
    expect(detectSwapWatch(events: events, now: now), isNull);
  });

  test(
    'lean going up or staying flat does not warn, even if alcohol rises',
    () {
      final events = [
        ...days(RelapseType.fullLean, [(11, 1), (11, 5)]),
        ...days(RelapseType.fullLean, [(11, 14), (11, 16), (11, 20)]),
        ...days(RelapseType.alcohol, [(11, 14), (11, 16), (11, 20), (11, 22)]),
      ];
      expect(detectSwapWatch(events: events, now: now), isNull);
    },
  );

  test('the largest meaningful rise wins when several substances go up', () {
    final events = [
      ...days(RelapseType.fullLean, [
        (11, 1),
        (11, 3),
        (11, 5),
        (11, 7),
        (11, 9),
      ]),
      ...days(RelapseType.fullLean, [(11, 14)]),
      ...days(RelapseType.alcohol, [(11, 20), (11, 22)]), // 0 → 2
      ...days(RelapseType.benzo, [
        (10, 30),
        (11, 14),
        (11, 16),
        (11, 18),
        (11, 20),
        (11, 22),
      ]), // 1 → 5
    ];
    final insight = detectSwapWatch(events: events, now: now);
    expect(insight!.risen, WatchedSubstance.benzo);
    expect(insight.other.previous, 1);
    expect(insight.other.recent, 5);
  });

  test('weed days are watched the same way', () {
    final events = [
      ...days(RelapseType.fullLean, [(11, 1), (11, 3), (11, 5), (11, 8)]),
      ...days(RelapseType.fullLean, [(11, 14)]),
      ev(d(11, 18), type: RelapseType.other, note: 'smoked a joint'),
      ev(d(11, 20), type: RelapseType.other, note: 'weed after work'),
      ev(d(11, 24), type: RelapseType.other, note: 'ganja'),
    ];
    final insight = detectSwapWatch(events: events, now: now);
    expect(insight!.risen, WatchedSubstance.weed);
    expect(insight.other.recent, 3);
    expect(
      insight.body,
      contains('Weed went from 0 days a week to 1.5 days a week'),
    );
  });

  test('visibility: stays up until dismissed, then hidden for a week', () {
    final insight = SwapWatchInsight(
      lean: const SubstanceDayCounts(previous: 10, recent: 3),
      risen: WatchedSubstance.alcohol,
      other: const SubstanceDayCounts(previous: 2, recent: 8),
      recentStart: DateTime(2026, 11, 13),
      previousStart: DateTime(2026, 10, 30),
    );
    expect(
      swapWatchIsVisible(
        insight: insight,
        enabled: true,
        dismissedAt: null,
        now: now,
      ),
      isTrue,
    );
    expect(
      swapWatchIsVisible(
        insight: insight,
        enabled: false,
        dismissedAt: null,
        now: now,
      ),
      isFalse,
    );
    expect(
      swapWatchIsVisible(
        insight: insight,
        enabled: true,
        dismissedAt: now.subtract(const Duration(days: 3)),
        now: now,
      ),
      isFalse,
    );
    expect(
      swapWatchIsVisible(
        insight: insight,
        enabled: true,
        dismissedAt: now.subtract(const Duration(days: 7)),
        now: now,
      ),
      isTrue,
    );
    expect(
      swapWatchIsVisible(
        insight: null,
        enabled: true,
        dismissedAt: null,
        now: now,
      ),
      isFalse,
    );
  });

  test('notification is at most once a week and is muted in quiet hours', () {
    expect(
      shouldNotifySwapWatch(
        visible: true,
        notifiedAt: null,
        now: now,
        quietHoursBlocked: false,
      ),
      isTrue,
    );
    expect(
      shouldNotifySwapWatch(
        visible: true,
        notifiedAt: now.subtract(const Duration(days: 3)),
        now: now,
        quietHoursBlocked: false,
      ),
      isFalse,
    );
    expect(
      shouldNotifySwapWatch(
        visible: true,
        notifiedAt: null,
        now: now,
        quietHoursBlocked: true,
      ),
      isFalse,
    );
    expect(NotificationKind.swapWatch.isCritical, isFalse);
    final quiet = const NotificationPrefs(quietHoursEnabled: true);
    expect(
      quiet.allows(NotificationKind.swapWatch, DateTime(2026, 11, 26, 23)),
      isFalse,
    );
    final hidden = const NotificationPrefs(
      hideSensitive: true,
    ).textFor(swapWatchNotificationTitle, swapWatchNotificationBody);
    expect(hidden.title, 'Reminder');
    expect(hidden.body, 'Open the app when you have a moment.');
    expect(swapWatchNotificationTitle.toLowerCase(), isNot(contains('lean')));
    expect(swapWatchNotificationBody.toLowerCase(), isNot(contains('alcohol')));
  });

  test(
    'detecting a swap never moves the lean timer, even with benzo days',
    () async {
      final c = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
        now: () => now,
      );
      await c.load();
      await c.recordRelapse(
        entries: [
          RelapseLogEntry(
            occurredAt: d(10, 20),
            type: RelapseType.fullLean,
            note: 'Starting point for this test.',
            attemptedSos: false,
          ),
        ],
      );
      final before = c.lastDose;
      await c.recordRelapse(
        entries: [
          RelapseLogEntry(
            occurredAt: d(11, 20),
            type: RelapseType.benzo,
            note: 'A benzo-only night, nothing else.',
            attemptedSos: false,
          ),
        ],
      );
      expect(c.lastDose, before);
      detectSwapWatch(events: c.events, now: now);
      expect(c.lastDose, before);
      await c.setSwapWatchEnabled(false);
      await c.setSwapWatchEnabled(true);
      await c.dismissSwapWatch();
      expect(c.lastDose, before);
    },
  );

  test(
    'an old backup still imports; new swap-watch keys are optional',
    () async {
      final old = {
        'version': 5,
        'events': [
          {
            'id': 'old-lean',
            'type': 'relapse',
            'timestamp': d(11, 1).toIso8601String(),
            'metadata': <String, dynamic>{'streakLost': 2},
          },
        ],
        'preferences': <String, dynamic>{},
      };
      final preview = BackupService().validateBackupJson(jsonEncode(old));
      expect(preview.eventCount, 1);
      expect(preview.preferences ?? {}, isNot(contains('swapWatchEnabled')));
      final fresh = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
        now: () => now,
      );
      await fresh.load();
      await fresh.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
        restorePreferences: true,
      );
      expect(fresh.events.map((e) => e.id), contains('old-lean'));
      expect(fresh.swapWatchEnabled, isTrue); // default on
      expect(fresh.swapWatchDismissedAt, isNull);

      // A newer backup with the optional keys still imports, and garbage in
      // those keys does not reject the file.
      final newer = {
        'version': 12,
        'events': old['events'],
        'preferences': {
          'swapWatchEnabled': true,
          'swapWatchDismissedAt': now
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'swapWatchNotifiedAt': 'not-a-date',
          'swapWatchEnabledExtra': 'ignored',
        },
      };
      final ok = BackupService().validateBackupJson(jsonEncode(newer));
      expect(ok.preferences!['swapWatchEnabled'], isTrue);
      expect(ok.preferences!['swapWatchDismissedAt'], isNotNull);
      expect(ok.preferences!.containsKey('swapWatchNotifiedAt'), isFalse);
    },
  );
}
