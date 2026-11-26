import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/post_relapse_summary.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

void main() {
  final now = DateTime(2026, 11, 27, 21, 30);

  RecoveryEvent relapse({
    required Duration ago,
    String? type = 'fullLean',
    Object? lost = 0,
    bool recorded = true,
  }) {
    final at = now.subtract(ago);
    return RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: at,
      metadata: {
        'streakLost': ?lost,
        'relapseType': ?type,
        if (recorded) 'recordedAt': at.toIso8601String(),
      },
    );
  }

  PostRelapseSummary build(
    List<RecoveryEvent> events, {
    int live = 0,
    int best = 0,
  }) => buildPostRelapseSummary(
    events: events,
    now: now,
    liveStreakDays: live,
    longestStreakDays: best,
  );

  test(
    'a lean slip after 81 days shows the real streak and lower tolerance',
    () {
      final s = build([
        relapse(ago: const Duration(minutes: 5), lost: 81),
      ], best: 81);
      expect(s.previousDays, 81);
      expect(s.bestDays, 81);
      expect(s.timerKept, isFalse);
      expect(s.lowerTolerance, isTrue);
      expect(s.hasStreak, isTrue);
    },
  );

  test('best is never below the streak that just ended', () {
    final s = build([relapse(ago: Duration.zero, lost: 12)], best: 3);
    expect(s.bestDays, 12);
  });

  test('lower tolerance starts at exactly 3 clean days, not 2', () {
    expect(
      build([relapse(ago: Duration.zero, lost: 2)]).lowerTolerance,
      isFalse,
    );
    expect(
      build([relapse(ago: Duration.zero, lost: 3)]).lowerTolerance,
      isTrue,
    );
  });

  test('a benzo-only log keeps the timer, shows the live streak, no '
      'tolerance warning, and flags mixing risk', () {
    final s = build(
      [relapse(ago: const Duration(minutes: 2), type: 'benzo')],
      live: 81,
      best: 81,
    );
    expect(s.timerKept, isTrue);
    expect(s.previousDays, 81);
    expect(s.lowerTolerance, isFalse);
    expect(s.mixingRisk, isTrue);
  });

  test('mixing risk covers alcohol and lean+alcohol within 24 hours only', () {
    expect(
      build([
        relapse(ago: const Duration(hours: 23), type: 'alcohol'),
      ]).mixingRisk,
      isTrue,
    );
    expect(
      build([
        relapse(ago: const Duration(hours: 1), type: 'leanPlusAlcohol'),
      ]).mixingRisk,
      isTrue,
    );
    expect(
      build([
        relapse(ago: const Duration(hours: 25), type: 'alcohol'),
      ]).mixingRisk,
      isFalse,
    );
    expect(
      build([
        relapse(ago: const Duration(hours: 1), type: 'fullLean'),
      ]).mixingRisk,
      isFalse,
    );
  });

  test(
    'a lean + benzo save (two events) is both a reset and a mixing risk',
    () {
      final s = build([
        relapse(ago: const Duration(minutes: 1), type: 'fullLean', lost: 79),
        relapse(ago: const Duration(minutes: 1), type: 'benzo', lost: 0),
      ], best: 81);
      expect(s.mixingRisk, isTrue);
      expect(s.previousDays, 79);
      expect(s.lowerTolerance, isTrue);
    },
  );

  test('legacy relapses without type, streakLost or recordedAt are safe', () {
    final s = build([
      relapse(
        ago: const Duration(hours: 2),
        type: null,
        lost: null,
        recorded: false,
      ),
    ], best: 9);
    expect(s.previousDays, 0);
    expect(s.bestDays, 9);
    expect(s.mixingRisk, isFalse);
    expect(s.lowerTolerance, isFalse);
    expect(s.hasStreak, isFalse);
  });

  test('benzo after a lean slip (live streak 0) is not called intact', () {
    final s = build(
      [
        relapse(ago: const Duration(hours: 5), type: 'fullLean', lost: 40),
        relapse(ago: const Duration(minutes: 1), type: 'benzo'),
      ],
      live: 0,
      best: 40,
    );
    expect(s.timerKept, isFalse);
    expect(s.previousDays, 40);
    expect(s.mixingRisk, isTrue);
  });

  test('no relapse events at all still builds a summary', () {
    final s = build(const [], best: 4);
    expect(s.previousDays, 0);
    expect(s.bestDays, 4);
  });

  test('greeting follows the time of day', () {
    String at(int h) => postRelapseGreeting(DateTime(2026, 1, 1, h));
    expect(at(8), 'Good morning.');
    expect(at(14), 'Good afternoon.');
    expect(at(19), 'Good evening.');
    expect(at(2), contains('Still up'));
    expect(at(23), contains('late'));
  });

  test('encouragement rotates through every line and is deterministic', () {
    final seen = {
      for (var i = 0; i < postRelapseEncouragements.length; i++)
        postRelapseEncouragement(i),
    };
    expect(seen.length, postRelapseEncouragements.length);
    expect(postRelapseEncouragement(3), postRelapseEncouragement(3));
    expect(postRelapseEncouragement(-1), isNotEmpty);
  });

  test('copy is warm and private: no substance words, no helplines', () {
    final banned = RegExp(
      r'\blean\b|codeine|benzo|alprazolam|alcohol|sedative|helpline|1800|\b112\b|\b911\b',
      caseSensitive: false,
    );
    for (final mixing in [false, true]) {
      for (final h in [3, 12, 23]) {
        final steps = nextTwentyFourHours(
          now: DateTime(2026, 1, 1, h),
          mixingRisk: mixing,
          contactName: 'Riya',
        );
        expect(steps.length, 3);
        for (final step in steps) {
          expect('${step.title} ${step.body}', isNot(matches(banned)));
          expect(isWarmLine(step.body), isTrue);
        }
      }
    }
    for (final line in postRelapseEncouragements) {
      expect(line, isNot(matches(banned)));
    }
  });

  test('the plan names the user\'s own contact and falls back politely', () {
    final named = nextTwentyFourHours(
      now: now,
      mixingRisk: true,
      contactName: ' Riya ',
    );
    expect(named[1].body, contains('Riya'));
    final anon = nextTwentyFourHours(now: now, mixingRisk: false);
    expect(anon[1].body, contains('someone you trust'));
    expect(anon.first.when, 'NOW');
    expect(
      nextTwentyFourHours(
        now: DateTime(2026, 1, 1, 23),
        mixingRisk: true,
      )[1].when,
      'TONIGHT',
    );
    expect(
      nextTwentyFourHours(
        now: DateTime(2026, 1, 1, 10),
        mixingRisk: false,
      )[1].when,
      'TODAY',
    );
  });
}

bool isWarmLine(String s) => !s.contains('//') && s != s.toUpperCase();
