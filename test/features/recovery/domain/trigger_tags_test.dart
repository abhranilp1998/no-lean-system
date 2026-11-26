import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/trigger_pattern.dart';
import 'package:no_lean/features/recovery/domain/trigger_tags.dart';

void main() {
  final now = DateTime(2026, 11, 26, 20);

  RecoveryEvent craving(
    int i, {
    String? place,
    String? withWho,
    String? mood,
    String? cash,
    int daysAgo = 1,
  }) => RecoveryEvent.fromJson({
    'id': 'c$i',
    'type': 'craving',
    'timestamp': now
        .subtract(Duration(days: daysAgo, hours: i))
        .toIso8601String(),
    'metadata': {
      'intensity': 6,
      'trigger': 'Boredom',
      'note': '',
      'place': ?place,
      'withWho': ?withWho,
      'mood': ?mood,
      'cash': ?cash,
    },
  });

  group('applyTriggerTags', () {
    test('adds only the tag keys and leaves every other key alone', () {
      final out = applyTriggerTags(
        {'intensity': 7, 'trigger': 'Habit', 'future': 1},
        const TriggerTags(withWho: 'alone', mood: 'bored', cash: 'plenty'),
        now: now,
      );
      expect(out['intensity'], 7);
      expect(out['future'], 1);
      expect(out['withWho'], 'alone');
      expect(out['mood'], 'bored');
      expect(out['cash'], 'plenty');
      expect(out['taggedAt'], isA<String>());
      expect(out.containsKey('place'), isFalse);
    });

    test('a question left empty is removed, so un-tapping un-tags', () {
      final tagged = applyTriggerTags(
        {'intensity': 5},
        const TriggerTags(mood: 'bored', cash: 'none'),
        now: now,
      );
      final cleared = applyTriggerTags(
        tagged,
        const TriggerTags(mood: 'bored'),
        now: now,
      );
      expect(cleared.containsKey('cash'), isFalse);
      expect(cleared['mood'], 'bored');
      final none = applyTriggerTags(cleared, const TriggerTags(), now: now);
      expect(none.containsKey('mood'), isFalse);
      expect(none.containsKey('taggedAt'), isFalse);
    });

    test('reuses the slip review keys for place and company', () {
      final out = applyTriggerTags(
        {},
        const TriggerTags(place: 'Home', zoneId: 'z1', withWho: 'friends'),
        now: now,
      );
      expect(out['place'], 'Home');
      expect(out['zoneId'], 'z1');
      expect(out['withWho'], 'friends');
    });

    test('an unknown option key is not written', () {
      final out = applyTriggerTags(
        {},
        const TriggerTags(mood: 'nonsense', cash: 'lots'),
        now: now,
      );
      expect(out.containsKey('mood'), isFalse);
      expect(out.containsKey('cash'), isFalse);
    });
  });

  group('normalizeTriggerTagMetadata', () {
    test('drops wrong-typed values and keeps valid and unknown ones', () {
      final m = normalizeTriggerTagMetadata({
        'place': 4,
        'withWho': ['x'],
        'mood': 7,
        'cash': ' some ',
        'taggedAt': false,
        'untouched': 'yes',
      });
      expect(m.containsKey('place'), isFalse);
      expect(m.containsKey('withWho'), isFalse);
      expect(m.containsKey('mood'), isFalse);
      expect(m['cash'], 'some');
      expect(m.containsKey('taggedAt'), isFalse);
      expect(m['untouched'], 'yes');
    });

    test('a value from a newer build is kept, not rejected', () {
      final m = normalizeTriggerTagMetadata({'mood': 'grieving'});
      expect(m['mood'], 'grieving');
    });

    test('a craving with odd tag values still validates', () {
      final v = RecoveryEvent.validateMetadata(RecoveryEventType.craving, {
        'intensity': 5,
        'trigger': 'Habit',
        'mood': 12,
      });
      expect(v['trigger'], 'Habit');
      expect(v.containsKey('mood'), isFalse);
    });
  });

  group('computeTriggerPattern', () {
    test('needs a minimum sample before saying anything', () {
      final events = [
        for (var i = 0; i < 5; i++)
          craving(i, mood: 'bored', withWho: 'alone', cash: 'plenty'),
      ];
      final status = computeTriggerPatternStatus(events, now: now);
      expect(status.pattern, isNull);
      expect(status.tagged, 5);
      expect(status.stillNeeded, 1);
    });

    test('names bored + alone + cash when most cravings share them', () {
      final events = [
        for (var i = 0; i < 6; i++)
          craving(i, mood: 'bored', withWho: 'alone', cash: 'plenty'),
        craving(6, mood: 'stressed', withWho: 'friends', cash: 'none'),
        craving(7, mood: 'tired', place: 'Home'),
      ];
      final p = computeTriggerPattern(events, now: now)!;
      expect(p.matching, 6);
      expect(p.tagged, 8);
      expect(p.isMost, isTrue);
      expect(
        p.sentence,
        "Most of your cravings come when you're bored, alone and with cash on you.",
      );
      expect(p.evidence, '6 of your 8 tagged cravings match this.');
      expect(p.ifSuggestion, "I'm bored, alone and with cash on me");
    });

    test('says "Many" for a third to a half, never "Most"', () {
      final events = [
        for (var i = 0; i < 4; i++) craving(i, mood: 'bored'),
        craving(4, mood: 'angry'),
        craving(5, mood: 'tired'),
        craving(6, mood: 'low'),
        craving(7, mood: 'stressed'),
        craving(8, mood: 'anxious'),
      ];
      final p = computeTriggerPattern(events, now: now)!;
      expect(p.sentence, startsWith('Many of your cravings'));
      expect(p.sentence, contains('bored'));
    });

    test('scattered tags make no claim', () {
      final moods = triggerMoodOptions.keys.toList();
      final events = [for (var i = 0; i < 7; i++) craving(i, mood: moods[i])];
      expect(computeTriggerPattern(events, now: now), isNull);
    });

    test('does not stretch the pattern past what the data supports', () {
      // Bored is common and alone is common, but never together.
      final events = [
        for (var i = 0; i < 3; i++)
          craving(i, mood: 'bored', withWho: 'family'),
        for (var i = 3; i < 6; i++) craving(i, mood: 'tired', withWho: 'alone'),
        craving(6, mood: 'bored', withWho: 'alone'),
      ];
      final p = computeTriggerPattern(events, now: now)!;
      expect(p.factors.length, 1);
      expect(p.matching, greaterThanOrEqualTo(minPatternMatches));
    });

    test('ignores untagged cravings and old tags', () {
      final events = [
        for (var i = 0; i < 10; i++) craving(i),
        for (var i = 10; i < 20; i++) craving(i, mood: 'bored', daysAgo: 200),
      ];
      final status = computeTriggerPatternStatus(events, now: now);
      expect(status.tagged, 0);
      expect(status.pattern, isNull);
    });

    test('place tags speak plainly', () {
      final events = [
        for (var i = 0; i < 6; i++)
          craving(i, place: "Friend's place", withWho: 'friends'),
      ];
      expect(
        computeTriggerPattern(events, now: now)!.sentence,
        "Most of your cravings come when you're with friends and at a friend's place.",
      );
    });
  });
}
