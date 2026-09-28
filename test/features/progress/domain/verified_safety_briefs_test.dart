import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/progress/domain/verified_safety_briefs.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';

void main() {
  test('explicit lean and alcohol log elevates the mixing brief', () {
    final insights = verifiedSafetyInsights(
      events: [_relapse(RelapseType.leanPlusAlcohol)],
      cleanStreakDays: 0,
    );

    expect(insights.first.brief.kind, VerifiedSafetyBriefKind.depressantMixing);
    expect(insights.first.logMatched, isTrue);
    expect(insights.first.evidence, contains('explicitly selected'));
  });

  test('cross-log categories do not claim simultaneous use', () {
    final insights = verifiedSafetyInsights(
      events: [_relapse(RelapseType.fullLean), _relapse(RelapseType.benzo)],
      cleanStreakDays: 0,
    );
    final mixing = insights.singleWhere(
      (insight) =>
          insight.brief.kind == VerifiedSafetyBriefKind.depressantMixing,
    );

    expect(mixing.logMatched, isTrue);
    expect(mixing.evidence, contains('across separate entries'));
    expect(mixing.evidence, contains('does not prove simultaneous use'));
  });

  test('clean time elevates tolerance guidance from the live counter', () {
    final insights = verifiedSafetyInsights(
      events: const [],
      cleanStreakDays: 9,
    );

    expect(insights.first.brief.kind, VerifiedSafetyBriefKind.reducedTolerance);
    expect(insights.first.logMatched, isTrue);
    expect(insights.first.evidence, contains('9 days'));
  });

  test('pill language elevates counterfeit pill guidance', () {
    final insights = verifiedSafetyInsights(
      events: [
        _relapse(RelapseType.other, note: 'Bought a pressed pill nearby.'),
      ],
      cleanStreakDays: 0,
    );

    expect(insights.first.brief.kind, VerifiedSafetyBriefKind.counterfeitPills);
    expect(insights.first.logMatched, isTrue);
    expect(insights.first.evidence, contains('cannot determine'));
  });

  test('empty history keeps every brief as unassertive baseline intel', () {
    final insights = verifiedSafetyInsights(
      events: const [],
      cleanStreakDays: 0,
    );

    expect(insights, hasLength(verifiedSafetyBriefs.length));
    expect(insights.every((insight) => !insight.logMatched), isTrue);
  });
}

RecoveryEvent _relapse(RelapseType type, {String? note}) =>
    RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      metadata: {'relapseType': type.name, 'note': ?note},
    );
