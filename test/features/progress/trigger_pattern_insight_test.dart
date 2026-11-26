import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/progress/domain/recovery_insights.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

void main() {
  final now = DateTime(2026, 11, 26, 20);

  RecoveryEvent craving(int i, Map<String, dynamic> tags) =>
      RecoveryEvent.fromJson({
        'id': 'c$i',
        'type': 'craving',
        'timestamp': now
            .subtract(Duration(days: 1, hours: i))
            .toIso8601String(),
        'metadata': {'intensity': 6, 'trigger': 'Habit', 'note': '', ...tags},
      });

  PatternActionInsight? insight(List<RecoveryEvent> events) =>
      patternActionInsights(
        cravings: const [],
        sosSessions: const [],
        dailySpend: 0,
        moneySaved: 0,
        events: events,
        now: now,
      ).where((i) => i.id == 'trigger-tags').firstOrNull;

  test('no insight until enough cravings are tagged', () {
    final few = [
      for (var i = 0; i < 5; i++)
        craving(i, {'mood': 'bored', 'withWho': 'alone', 'cash': 'plenty'}),
    ];
    expect(insight(few), isNull);
    expect(insight([for (var i = 0; i < 12; i++) craving(i, {})]), isNull);
  });

  test('with enough tags it names the pattern and offers a plan', () {
    final events = [
      for (var i = 0; i < 6; i++)
        craving(i, {'mood': 'bored', 'withWho': 'alone', 'cash': 'plenty'}),
      craving(6, {'mood': 'tired'}),
    ];
    final i = insight(events)!;
    expect(
      i.body,
      contains(
        "Most of your cravings come when you're bored, alone and with cash on you.",
      ),
    );
    expect(i.action, PatternActionKind.writePlan);
    expect(i.actionLabel, 'WRITE AN IF-THEN PLAN');
    expect(i.evidence, '6 OF YOUR 7 TAGGED CRAVINGS MATCH THIS.');
    expect(i.why, contains('at least 6 tagged cravings'));
    expect(i.dismissible, isTrue);
    final govt = RegExp(
      r'\b(112|100|helpline|hotline|police)\b',
      caseSensitive: false,
    );
    expect(govt.hasMatch('${i.title} ${i.body} ${i.why}'), isFalse);
  });

  test('a dismissal holds until the pattern changes', () {
    List<RecoveryEvent> events(int extra) => [
      for (var i = 0; i < 6 + extra; i++)
        craving(i, {'mood': 'bored', 'withWho': 'alone'}),
    ];
    final first = insight(events(0))!;
    final dismissed = {first.id: first.evidenceKey};
    expect(first.isDismissedBy(dismissed), isTrue);
    expect(insight(events(1))!.isDismissedBy(dismissed), isFalse);
  });
}
