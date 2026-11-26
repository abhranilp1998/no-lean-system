import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/mixing_alert.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

RecoveryEvent slip(
  String id,
  DateTime at, {
  String? type,
  String? note,
  String? quantity,
}) => RecoveryEvent.fromJson({
  'id': id,
  'type': 'relapse',
  'timestamp': at.toIso8601String(),
  'metadata': {'relapseType': ?type, 'note': ?note, 'quantity': ?quantity},
});

void main() {
  final now = DateTime(2026, 11, 26, 22, 30);

  group('what an entry contains', () {
    test('typed lean is codeine; typed benzo is a benzo, not codeine', () {
      expect(substancesOf(slip('a', now, type: 'fullLean')).codeine, isTrue);
      final benzo = substancesOf(slip('b', now, type: 'benzo'));
      expect(benzo.codeine, isFalse);
      expect(benzo.benzo, 'a benzo');
    });

    test('a note names the benzo as the user wrote it', () {
      final s = substancesOf(
        slip('a', now, type: 'other', note: 'took an Alprazolam at 9'),
      );
      expect(s.benzo, 'alprazolam');
      expect(s.codeine, isFalse);
    });

    test('legacy untyped relapse (every old build wrote lean) is codeine', () {
      expect(substancesOf(slip('a', now)).codeine, isTrue);
    });

    test('lean + alcohol type is both; negated notes are not a mix', () {
      final both = substancesOf(slip('a', now, type: 'leanPlusAlcohol'));
      expect(both.codeine, isTrue);
      expect(both.alcohol, isTrue);
      final none = substancesOf(
        slip('b', now, type: 'fullLean', note: 'no alcohol, no xanax today'),
      );
      expect(none.other, isFalse);
    });

    test('everyday words are not alcohol or a benzo', () {
      expect(substancesOf(slip('a', now, note: 'drank tea')).alcohol, isFalse);
      expect(substancesOf(slip('b', now, note: 'felt calm')).benzo, isNull);
      expect(substancesOf(slip('c', now, note: 'a lean night')).other, isFalse);
    });
  });

  group('detectMixingAlert', () {
    test('codeine + alprazolam today quotes the log', () {
      final alert = detectMixingAlert(
        events: [
          slip('a', DateTime(2026, 11, 26, 18), type: 'fullLean'),
          slip('b', DateTime(2026, 11, 26, 21), type: 'benzo', note: 'xanax'),
        ],
        now: now,
      )!;
      expect(alert.substances, ['codeine', 'xanax']);
      expect(alert.quote, 'You logged codeine + xanax today.');
      expect(alert.eventIds, {'a', 'b'});
    });

    test('names alprazolam when logged as alprazolam', () {
      final alert = detectMixingAlert(
        events: [
          slip('a', DateTime(2026, 11, 26, 18), type: 'fullLean'),
          slip('b', DateTime(2026, 11, 26, 21), note: 'alprazolam 0.5'),
        ],
        now: now,
      )!;
      expect(alert.quote, 'You logged codeine + alprazolam today.');
    });

    test('lean + alcohol in one entry is enough', () {
      final alert = detectMixingAlert(
        events: [
          slip('a', DateTime(2026, 11, 26, 20), type: 'leanPlusAlcohol'),
        ],
        now: now,
      );
      expect(alert?.substances, ['codeine', 'alcohol']);
    });

    test('benzo alone or alcohol alone is not a mix', () {
      expect(
        detectMixingAlert(
          events: [
            slip('a', DateTime(2026, 11, 26, 20), type: 'benzo'),
            slip('b', DateTime(2026, 11, 26, 21), type: 'alcohol'),
          ],
          now: now,
        ),
        isNull,
      );
    });

    test('two lean entries are not a mix', () {
      expect(
        detectMixingAlert(
          events: [
            slip('a', DateTime(2026, 11, 26, 19), type: 'fullLean'),
            slip('b', DateTime(2026, 11, 26, 21), type: 'partial'),
          ],
          now: now,
        ),
        isNull,
      );
    });

    test('more than 24 hours apart is not a mix', () {
      expect(
        detectMixingAlert(
          events: [
            slip('a', DateTime(2026, 11, 25, 9), type: 'fullLean'),
            slip('b', DateTime(2026, 11, 26, 21), type: 'benzo'),
          ],
          now: now,
        ),
        isNull,
      );
    });

    test('uses when it happened, not when it was typed in', () {
      // Logged now, but the benzo happened 3 days ago.
      expect(
        detectMixingAlert(
          events: [
            slip('a', DateTime(2026, 11, 26, 21), type: 'fullLean'),
            slip('b', DateTime(2026, 11, 23, 21), type: 'benzo'),
          ],
          now: now,
        ),
        isNull,
      );
      // A backdated pair from last month never alarms today.
      expect(
        detectMixingAlert(
          events: [
            slip('a', DateTime(2026, 10, 1, 21), type: 'fullLean'),
            slip('b', DateTime(2026, 10, 1, 22), type: 'benzo'),
          ],
          now: now,
        ),
        isNull,
      );
    });

    test('earlier day within 24 h says "in the last 24 hours"', () {
      final alert = detectMixingAlert(
        events: [
          slip('a', DateTime(2026, 11, 25, 23), type: 'fullLean'),
          slip(
            'b',
            DateTime(2026, 11, 26, 21),
            type: 'benzo',
            note: 'diazepam',
          ),
        ],
        now: now,
      )!;
      expect(
        alert.quote,
        'You logged codeine + diazepam in the last 24 hours.',
      );
    });

    test('a bulk save of many entries gives exactly one alert', () {
      final events = [
        for (var i = 0; i < 6; i++)
          slip('l$i', DateTime(2026, 11, 26, 8 + i * 2), type: 'fullLean'),
        for (var i = 0; i < 3; i++)
          slip(
            'x$i',
            DateTime(2026, 11, 26, 9 + i * 3),
            type: 'benzo',
            note: 'xanax',
          ),
      ];
      final alert = detectMixingAlert(
        events: events,
        now: now,
        involving: {for (final e in events) e.id},
      )!;
      expect(alert.eventIds.length, 9);
      expect(alert.substances, ['codeine', 'xanax']);
    });

    test('involving: an unrelated new slip does not re-raise an old mix', () {
      final events = [
        slip('a', DateTime(2026, 11, 26, 9), type: 'fullLean'),
        slip('b', DateTime(2026, 11, 26, 10), type: 'benzo'),
      ];
      expect(
        detectMixingAlert(events: events, now: now, involving: {'zzz'}),
        isNull,
      );
      expect(
        detectMixingAlert(events: events, now: now, involving: {'b'}),
        isNotNull,
      );
    });

    test('empty and non-relapse logs are quiet', () {
      expect(detectMixingAlert(events: const [], now: now), isNull);
      expect(
        detectMixingAlert(
          events: [RecoveryEvent.create(type: RecoveryEventType.pledge)],
          now: now,
        ),
        isNull,
      );
    });
  });
}
