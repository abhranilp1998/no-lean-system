import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/companion/domain/companion_state.dart';
import 'package:no_lean/features/companion/domain/substance_safety.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

final now = DateTime(2026, 11, 4, 20);
RecoveryEvent slip(Duration ago, {String? type, String? note}) =>
    RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: now.subtract(ago),
      metadata: {'relapseType': ?type, 'note': ?note},
    );

void main() {
  const none = CompanionState();

  test('no logs, no picks: no taper, no check-in', () {
    expect(
      safetyNotesFor(
        none,
        events: [slip(const Duration(hours: 5), type: 'fullLean')],
        now: now,
      ),
      isEmpty,
    );
  });

  test('logged benzo relapse triggers taper warning', () {
    final e = [slip(const Duration(days: 20), type: 'benzo')];
    expect(needsTaperWarning(none, e, now), isTrue);
    expect(safetyNotesFor(none, events: e, now: now), contains(taperWarning));
  });

  test('benzo named in a note triggers taper warning', () {
    final e = [
      slip(
        const Duration(days: 3),
        type: 'other',
        note: 'took 2 alprax at night',
      ),
    ];
    expect(needsTaperWarning(none, e, now), isTrue);
  });

  test('old benzo (>90d) does not trigger', () {
    expect(
      needsTaperWarning(none, [
        slip(const Duration(days: 120), type: 'benzo'),
      ], now),
      isFalse,
    );
  });

  test('alcohol on 3 separate days in 14 = heavy; 1 day is not', () {
    final one = [slip(const Duration(days: 2), type: 'alcohol')];
    expect(needsTaperWarning(none, one, now), isFalse);
    final three = [
      for (final d in [1, 4, 8]) slip(Duration(days: d), type: 'alcohol'),
    ];
    expect(needsTaperWarning(none, three, now), isTrue);
  });

  test('lean+alcohol slip in last 72h shows mixing check-in first', () {
    final notes = safetyNotesFor(
      none,
      recentSlip: true,
      events: [slip(const Duration(hours: 10), type: 'leanPlusAlcohol')],
      now: now,
    );
    expect(notes.first, mixingCheckIn);
    expect(notes, isNot(contains(toleranceNote)));
  });

  test('codeine + benzo logged within 24h of each other = mixed', () {
    final e = [
      slip(const Duration(hours: 30), type: 'fullLean'),
      slip(const Duration(hours: 20), type: 'benzo'),
    ];
    expect(loggedUse(e, now).mixedSlip, isTrue);
  });

  test('codeine and alcohol days apart, or old, is not mixed', () {
    expect(
      loggedUse([
        slip(const Duration(hours: 10), type: 'fullLean'),
        slip(const Duration(days: 3, hours: 1), type: 'alcohol'),
      ], now).mixedSlip,
      isFalse,
    );
    expect(
      loggedUse([
        slip(const Duration(days: 5), type: 'leanPlusAlcohol'),
      ], now).mixedSlip,
      isFalse,
    );
  });

  test('note naming lean and daru = mixed', () {
    expect(
      loggedUse([
        slip(const Duration(hours: 2), type: 'other', note: 'lean then daru'),
      ], now).mixedSlip,
      isTrue,
    );
  });

  test('slip note substances count and round-trip json', () {
    final n = SlipNote(
      at: now.subtract(const Duration(hours: 1)),
      substances: {Substance.codeine, Substance.benzo},
    );
    final back = SlipNote.fromJson(n.toJson())!;
    expect(back.substances, {Substance.codeine, Substance.benzo});
    final s = none.copyWith(slips: [back]);
    final notes = safetyNotesFor(s, now: now);
    expect(notes, containsAll([mixingCheckIn, taperWarning]));
  });

  test('no government helplines in safety copy', () {
    for (final n in [taperWarning, redFlagNote, toleranceNote, mixingCheckIn]) {
      expect(
        n.body,
        isNot(
          matches(
            RegExp(r'helpline|tele-?manas|\b1\d{2,4}\b', caseSensitive: false),
          ),
        ),
      );
    }
  });
}
