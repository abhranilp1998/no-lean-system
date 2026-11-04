import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/companion/domain/companion_engine.dart' as eng;
import 'package:no_lean/features/companion/domain/companion_engine.dart'
    hide matches;
import 'package:no_lean/features/companion/domain/companion_messages.dart';
import 'package:no_lean/features/companion/domain/companion_state.dart';
import 'package:no_lean/features/companion/domain/idea_cards.dart';
import 'package:no_lean/features/companion/domain/substance_safety.dart';

void main() {
  final now = DateTime(2026, 11, 4, 20);
  CompanionContext ctx({
    int hours = 40,
    int craving = 0,
    bool slip = false,
    Set<String> symptoms = const {},
    String? mood,
    DateTime? at,
  }) => CompanionContext(
    since: Duration(hours: hours),
    now: at ?? now,
    craving: craving,
    recentSlip: slip,
    symptoms: symptoms,
    mood: mood,
    name: 'Sam',
    bestDays: 12,
    saved: '₹1,200',
    contact: 'Abhi',
    easeInHours: 32,
  );

  group('content lint', () {
    test('library is large and ids are unique', () {
      expect(companionMessages.length, greaterThanOrEqualTo(200));
      final ids = companionMessages.map((m) => m.id).toSet();
      expect(ids.length, companionMessages.length);
      expect(ideaCards.map((i) => i.id).toSet().length, ideaCards.length);
    });

    test('tags are valid', () {
      for (final m in companionMessages) {
        expect(bandIds.containsAll(m.bands), isTrue, reason: m.id);
        expect(todIds.containsAll(m.tods), isTrue, reason: m.id);
        expect(symptomIds.containsAll(m.symptoms), isTrue, reason: m.id);
        expect(moodIds.containsAll(m.moods), isTrue, reason: m.id);
        expect(m.minCraving, inInclusiveRange(0, 3));
      }
    });

    test('every kind has messages and no banned phrases', () {
      for (final k in MsgKind.values) {
        expect(companionMessages.where((m) => m.kind == k), isNotEmpty);
      }
      final banned = RegExp(
        r"helpline|hotline|failure|\bweak\b|you've got this|stay positive|"
        r'streak broken|\bjunkie|\baddict\b|\d{3,}[- ]?\d{3,}|!!',
        caseSensitive: false,
      );
      for (final m in companionMessages) {
        expect(banned.hasMatch(m.text), isFalse, reason: '${m.id}: ${m.text}');
        expect(m.text.length, lessThan(220), reason: m.id);
      }
    });

    test('placeholders are known', () {
      final known = {
        'name',
        'hours',
        'days',
        'easeIn',
        'best',
        'saved',
        'contact',
      };
      for (final m in companionMessages) {
        for (final x in RegExp(r'\{(\w+)\}').allMatches(m.text)) {
          expect(known, contains(x[1]), reason: m.id);
        }
      }
    });

    test('no dosing advice for benzos or alcohol', () {
      final all = [
        ...companionMessages.map((m) => m.text),
        taperWarning.body,
        redFlagNote.body,
        toleranceNote.body,
      ].join(' ');
      expect(RegExp(r'\d+\s?mg', caseSensitive: false).hasMatch(all), isFalse);
    });

    test('every band has greeting or praise, and peak bands have plenty', () {
      for (final b in bandIds) {
        final n = companionMessages.where(
          (m) =>
              (m.kind == MsgKind.greet || m.kind == MsgKind.praise) &&
              (m.bands.isEmpty || m.bands.contains(b)),
        );
        expect(n.length, greaterThanOrEqualTo(8), reason: b);
      }
    });
  });

  group('bands and time of day', () {
    test('band boundaries', () {
      expect(bandFor(const Duration(hours: 11, minutes: 59)), 'h0_12');
      expect(bandFor(const Duration(hours: 12)), 'h12_24');
      expect(bandFor(const Duration(hours: 47)), 'h24_48');
      expect(bandFor(const Duration(hours: 48)), 'h48_72');
      expect(bandFor(const Duration(days: 3)), 'd3_5');
      expect(bandFor(const Duration(days: 13)), 'd7_14');
      expect(bandFor(const Duration(days: 14)), 'w2_4');
      expect(bandFor(const Duration(days: 30)), 'm1_3');
      expect(bandFor(const Duration(days: 90)), 'm3plus');
    });
    test('time of day', () {
      expect(todFor(DateTime(2026, 1, 1, 4, 59)), 'night');
      expect(todFor(DateTime(2026, 1, 1, 5)), 'morning');
      expect(todFor(DateTime(2026, 1, 1, 11)), 'afternoon');
      expect(todFor(DateTime(2026, 1, 1, 17)), 'evening');
      expect(todFor(DateTime(2026, 1, 1, 22)), 'night');
    });
  });

  group('engine', () {
    test('renders with no leftover placeholders across many contexts', () {
      for (final h in [3, 18, 40, 60, 100, 150, 250, 500, 1500, 3000]) {
        for (final hour in [3, 8, 14, 19, 23]) {
          for (final slip in [false, true]) {
            final c = ctx(
              hours: h,
              slip: slip,
              craving: h % 4,
              at: DateTime(2026, 11, 4, hour),
            );
            final v = CompanionEngine(const CompanionState(), seed: h).build(c);
            for (final m in [v.greeting, ...v.messages]) {
              expect(render(m, c), isNot(contains('{')), reason: m.id);
            }
            expect(v.ideas, hasLength(4));
          }
        }
      }
    });

    test('missing name is dropped gracefully', () {
      final c = CompanionContext(
        since: const Duration(hours: 40),
        now: DateTime(2026, 11, 4, 19),
      );
      final m = companionMessages.firstWhere((m) => m.id == 'g03');
      expect(render(m, c), startsWith('Evening. '));
    });

    test('contact-only messages need a contact', () {
      final c = CompanionContext(since: const Duration(hours: 40), now: now);
      final t02 = companionMessages.firstWhere((m) => m.id == 't02');
      expect(eng.matches(t02, c, 'h24_48', 'evening'), isFalse);
    });

    test('lapse messages only after a slip; slip leads with lapse', () {
      final clean = CompanionEngine(
        const CompanionState(),
        seed: 1,
      ).build(ctx());
      expect(
        [clean.greeting, ...clean.messages].any((m) => m.kind == MsgKind.lapse),
        isFalse,
      );
      final slip = CompanionEngine(
        const CompanionState(),
        seed: 1,
      ).build(ctx(slip: true));
      expect(slip.messages.first.kind, MsgKind.lapse);
    });

    test('strong craving puts urge surfing first among ideas', () {
      final v = CompanionEngine(
        const CompanionState(),
        seed: 3,
      ).build(ctx(craving: 3));
      expect(v.messages.first.kind, MsgKind.craving);
      expect(v.ideas.first.action, 'surf');
    });

    test('symptoms steer ideas', () {
      final v = CompanionEngine(
        const CompanionState(),
        seed: 5,
      ).build(ctx(symptoms: {'gut'}));
      expect(v.ideas.first.symptoms, contains('gut'));
    });

    test('no repeats within 7 days', () {
      var state = const CompanionState();
      final seen = <String>{};
      for (var i = 0; i < 6; i++) {
        final at = now.add(Duration(hours: i));
        final c = ctx(at: at);
        final m = CompanionEngine(state, seed: i).pick(MsgKind.praise, c)!;
        expect(seen.add(m.id), isTrue, reason: 'repeat ${m.id} at $i');
        state = state.markShown([m.id], at);
      }
    });

    test('helpful taps raise weight, not-for-me lowers it', () {
      final ids = companionMessages
          .where((m) => m.kind == MsgKind.together)
          .map((m) => m.id)
          .toList();
      var state = const CompanionState();
      for (final id in ids.skip(1)) {
        state = state.rate(id, wasHelpful: false).rate(id, wasHelpful: false);
      }
      for (var i = 0; i < 5; i++) {
        state = state.rate(ids.first, wasHelpful: true);
      }
      var hits = 0;
      for (var s = 0; s < 100; s++) {
        if (CompanionEngine(state, seed: s).pick(MsgKind.together, ctx())!.id ==
            ids.first) {
          hits++;
        }
      }
      expect(hits, greaterThan(30));
    });
  });

  group('state', () {
    test('round-trips and taper warning', () {
      final s = const CompanionState()
          .copyWith(
            substances: {Substance.codeine, Substance.alcohol},
            heavyAlcohol: true,
            triggers: ['Evenings', 'Alone'],
            triggersAsked: true,
            slips: [
              SlipNote(
                at: DateTime.utc(2026, 11, 1),
                trigger: 'Alone',
                ifThen: 'call',
              ),
            ],
          )
          .rate('p01', wasHelpful: true)
          .markShown(['g01'], now);
      final back = CompanionState.fromJson(s.toJson());
      expect(back.substances, s.substances);
      expect(back.needsTaperWarning, isTrue);
      expect(back.triggers, ['Evenings', 'Alone']);
      expect(back.helpful['p01'], 1);
      expect(back.shown.containsKey('g01'), isTrue);
      expect(back.slips.single.ifThen, 'call');
      expect(safetyNotesFor(back), contains(taperWarning));
    });

    test('codeine and weed alone need no taper warning; benzos do', () {
      expect(
        const CompanionState(
          substances: {Substance.codeine, Substance.weed},
        ).needsTaperWarning,
        isFalse,
      );
      expect(
        const CompanionState(substances: {Substance.alcohol}).needsTaperWarning,
        isFalse,
      );
      expect(
        const CompanionState(substances: {Substance.benzo}).needsTaperWarning,
        isTrue,
      );
      expect(safetyNotesFor(const CompanionState(), recentSlip: true), [
        toleranceNote,
      ]);
    });

    test('garbage json gives defaults', () {
      final s = CompanionState.fromJson({'substances': 5, 'shown': 'x'});
      expect(s.substances, isEmpty);
      expect(s.reachOutTexts, defaultReachOutTexts);
      expect(CompanionState.fromJson(null).triggersAsked, isFalse);
    });

    test('merge keeps local answers and unions slips', () {
      final local = CompanionState(
        triggers: const ['Stress'],
        triggersAsked: true,
        slips: [SlipNote(at: DateTime.utc(2026, 11, 2))],
      );
      final other = CompanionState(
        triggers: const ['Bored'],
        triggersAsked: true,
        substances: const {Substance.benzo},
        slips: [
          SlipNote(at: DateTime.utc(2026, 11, 2)),
          SlipNote(at: DateTime.utc(2026, 10, 2)),
        ],
      );
      final m = local.mergeImported(other);
      expect(m.triggers, ['Stress']);
      expect(m.substances, {Substance.benzo});
      expect(m.slips, hasLength(2));
    });
  });
}
