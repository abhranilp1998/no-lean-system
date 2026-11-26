import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/letters/domain/future_letter.dart';
import 'package:no_lean/features/cravings/presentation/craving_wave_screen.dart';
import 'package:no_lean/features/letters/presentation/future_letters_screen.dart';
import 'package:no_lean/features/recovery/presentation/relapse_cooldown_screen.dart';
import 'package:no_lean/features/notes/application/note_invite_store.dart';
import 'package:no_lean/features/notes/domain/note_invite.dart';
import 'package:no_lean/features/notes/presentation/future_note_card.dart';
import 'package:no_lean/features/notes/presentation/note_composer.dart';
import 'package:no_lean/features/notes/presentation/note_invite_panel.dart';
import 'package:no_lean/features/notes/presentation/voice_note_recorder.dart';
import 'package:no_lean/features/notes/services/voice_io.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/note_fakes.dart';
import '../../support/recovery_fakes.dart';
import '../../support/voice_fakes.dart';

void main() {
  final audio = Uint8List.fromList(List.generate(64, (i) => i));
  late FakePhone phone;
  late FakeVoiceRecorder recorder;
  late FakeVoicePlayer player;
  late RecoveryController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    phone = FakePhone();
    recorder = FakeVoiceRecorder();
    player = FakeVoicePlayer();
  });

  Future<RecoveryController> pump(
    WidgetTester tester,
    Widget child, {
    String? stored,
    FakePhone? on,
    bool scroll = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller = RecoveryController(
      store: MemoryRecoveryStore(stored),
      relapseLock: FakeRelapseLock(),
      futureNotes: (on ?? phone).notes,
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      cancelUseCheck: () async {},
      now: () => DateTime(2026, 11, 26, 20),
    );
    await controller.load();
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => controller),
        voiceRecorderFactoryProvider.overrideWithValue(() => recorder),
        voicePlayerFactoryProvider.overrideWithValue(() => player),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: scroll
              ? Scaffold(body: SingleChildScrollView(child: child))
              : child,
        ),
      ),
    );
    return controller;
  }

  group('FutureNoteCard', () {
    testWidgets('shows nothing without notes', (tester) async {
      await pump(tester, const FutureNoteCard(moment: NoteMoment.urge));
      expect(find.byKey(const Key('future-note-card')), findsNothing);
    });

    testWidgets('plays a text note, and ANOTHER cycles', (tester) async {
      await pump(
        tester,
        const FutureNoteCard(moment: NoteMoment.urge, seed: 0),
      );
      await tester.runAsync(() async {
        await controller.addFutureLetter('first');
        await controller.addFutureLetter('second');
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('FROM YOU, FOR RIGHT NOW'), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      await tester.tap(find.byKey(const Key('future-note-another')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('a voice note plays decrypted bytes only when tapped', (
      tester,
    ) async {
      await pump(
        tester,
        const FutureNoteCard(moment: NoteMoment.afterSlip, seed: 0),
      );
      await tester.runAsync(() async {
        await controller.enableRelapseLock('2468');
        await controller.addVoiceNote(audio, const Duration(seconds: 12));
      });
      await tester.pump();
      expect(find.text('YOU LEFT THIS FOR A DAY LIKE TODAY'), findsOneWidget);
      expect(player.played, isEmpty); // never auto-plays
      expect(find.textContaining('0:12'), findsOneWidget);
      await tester.tap(find.byKey(const Key('future-note-play')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(player.played.single, audio);
      expect(find.text('STOP'), findsOneWidget);
      player.finish();
      await tester.pump();
      expect(find.textContaining('PLAY YOUR VOICE NOTE'), findsOneWidget);
    });

    testWidgets('locked notes are skipped; all-locked says so', (tester) async {
      final stored = await _lockedState();
      await pump(
        tester,
        const FutureNoteCard(moment: NoteMoment.roughDay),
        stored: stored,
        on: FakePhone(),
      );
      await tester.pump();
      expect(find.byKey(const Key('future-note-locked')), findsOneWidget);
      expect(find.byKey(const Key('future-note-card')), findsNothing);
    });
  });

  group('composer and voice recording', () {
    testWidgets('the microphone is never asked for until RECORD is tapped', (
      tester,
    ) async {
      await pump(tester, const FutureNoteComposer());
      await tester.pump(const Duration(seconds: 2));
      expect(recorder.permissionAsks, 0);
      expect(find.byKey(const Key('voice-record')), findsOneWidget);
    });

    testWidgets('text note saves', (tester) async {
      await pump(tester, const FutureNoteComposer());
      await tester.enterText(
        find.byKey(const Key('future-letter-draft')),
        'Hold on',
      );
      await tester.tap(find.byKey(const Key('future-letter-save')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(controller.futureLetters.single.text, 'Hold on');
    });

    testWidgets('record, listen, keep: saves a voice note', (tester) async {
      await pump(tester, const FutureNoteComposer());
      await tester.tap(find.byKey(const Key('voice-record')));
      await tester.pump();
      expect(recorder.permissionAsks, 1);
      expect(recorder.recording, isTrue);
      expect(find.byKey(const Key('voice-stop')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-stop')));
      await tester.pump();
      expect(find.byKey(const Key('voice-review')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-listen')));
      await tester.pump();
      expect(player.played.single, recorder.bytes);
      await tester.tap(find.byKey(const Key('voice-save')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final note = controller.futureLetters.single;
      expect(note.isVoice, isTrue);
      expect(note.audio!.durationMs, 7000);
      expect(phone.voice.files, isNotEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'permission refused: warm message, nothing recorded, text still works',
      (tester) async {
        recorder.allow = false;
        await pump(tester, const FutureNoteComposer());
        await tester.tap(find.byKey(const Key('voice-record')));
        await tester.pump();
        expect(find.byKey(const Key('voice-denied')), findsOneWidget);
        expect(recorder.recording, isFalse);
        expect(find.byKey(const Key('future-letter-save')), findsOneWidget);
      },
    );

    testWidgets('recording stops by itself at 60 seconds', (tester) async {
      recorder.length = const Duration(seconds: 75); // recorder over-reports
      await pump(tester, const _CappedComposer());
      await tester.tap(find.byKey(const Key('voice-record')));
      await tester.pump();
      _cappedNow = _cappedNow.add(const Duration(seconds: 30));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('voice-stop')), findsOneWidget);
      _cappedNow = _cappedNow.add(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(recorder.stops, 1);
      expect(find.byKey(const Key('voice-review')), findsOneWidget);
      expect(find.textContaining('Recorded 0:60'), findsOneWidget);
    });

    testWidgets('an empty recording says so and saves nothing', (tester) async {
      recorder.emptyTake = true;
      await pump(tester, const FutureNoteComposer());
      await tester.tap(find.byKey(const Key('voice-record')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-stop')));
      await tester.pump();
      expect(find.text('Nothing was recorded. Try again.'), findsOneWidget);
      expect(controller.futureLetters, isEmpty);
    });
  });

  group('invitations', () {
    test('policy: quiet, snoozable, switch-off-able', () {
      final t = DateTime(2026, 11, 26, 20);
      expect(
        shouldInviteNote(state: const NoteInviteState(), now: t, noteCount: 0),
        isTrue,
      );
      expect(
        shouldInviteNote(
          state: NoteInviteState(
            lastShownAt: t.subtract(const Duration(hours: 5)),
          ),
          now: t,
          noteCount: 0,
        ),
        isFalse,
      );
      expect(
        shouldInviteNote(
          state: NoteInviteState(
            lastShownAt: t.subtract(const Duration(days: 3)),
          ),
          now: t,
          noteCount: 1,
        ),
        isTrue,
      );
      // A few notes in: only about every two weeks.
      expect(
        shouldInviteNote(
          state: NoteInviteState(
            lastShownAt: t.subtract(const Duration(days: 3)),
          ),
          now: t,
          noteCount: 5,
        ),
        isFalse,
      );
      expect(
        shouldInviteNote(
          state: NoteInviteState(snoozedUntil: t.add(const Duration(days: 1))),
          now: t,
          noteCount: 0,
        ),
        isFalse,
      );
      expect(
        shouldInviteNote(
          state: const NoteInviteState(never: true),
          now: t,
          noteCount: 0,
        ),
        isFalse,
      );
      expect(
        shouldInviteNote(
          state: const NoteInviteState(),
          now: t,
          noteCount: 100,
        ),
        isFalse,
      );
    });

    test('note picking skips locked notes and cycles', () {
      final a = FutureLetter.create('a');
      final b = FutureLetter.create('b');
      final c = FutureLetter.create('c');
      expect(pickNoteToPlay([a, b, c], locked: {b.id}, seed: 0)!.text, 'a');
      expect(
        pickNoteToPlay([a, b, c], locked: {b.id}, seed: 0, step: 1)!.text,
        'c',
      );
      expect(
        pickNoteToPlay([a, b, c], locked: {a.id, b.id, c.id}, seed: 3),
        isNull,
      );
      expect(pickNoteToPlay(const [], locked: {}, seed: 1), isNull);
    });

    testWidgets('the link shows when due, opens the sheet, and a saved note '
        'thanks the user', (tester) async {
      await pump(
        tester,
        const FutureNoteInviteLink(occasion: NoteInviteOccasion.urgePassed),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.byKey(const Key('note-invite-link')), findsOneWidget);
      await tester.tap(find.byKey(const Key('note-invite-link')));
      await tester.pumpAndSettle();
      expect(find.text('YOU RODE IT OUT'), findsOneWidget);
      expect(find.textContaining('Totally optional'), findsOneWidget);
      await tester.tap(find.byKey(const Key('note-invite-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('future-letter-draft')),
        'It passes.',
      );
      await tester.tap(find.byKey(const Key('future-letter-save')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-invite-saved')), findsOneWidget);
      expect(controller.futureLetters.single.text, 'It passes.');
    });

    testWidgets('NOT NOW snoozes: no second invitation for days', (
      tester,
    ) async {
      await pump(
        tester,
        const FutureNoteInviteLink(occasion: NoteInviteOccasion.milestone),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('note-invite-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-invite-later')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final state = await tester.runAsync(NoteInviteStore().read);
      expect(state!.snoozedUntil, isNotNull);
      expect(
        shouldInviteNote(
          state: state,
          now: DateTime.now().add(const Duration(days: 1)),
          noteCount: 0,
        ),
        isFalse,
      );
    });

    testWidgets("DON'T SUGGEST THIS switches invitations off for good", (
      tester,
    ) async {
      await pump(
        tester,
        const FutureNoteInviteLink(occasion: NoteInviteOccasion.cleanCheckIn),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('note-invite-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-invite-never')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final state = await tester.runAsync(NoteInviteStore().read);
      expect(state!.never, isTrue);
    });

    testWidgets('after a snooze the link stays hidden', (tester) async {
      SharedPreferences.setMockInitialValues({
        'future_note_invite_v1':
            '{"snooze":"${DateTime.now().add(const Duration(days: 2)).toIso8601String()}"}',
      });
      await pump(
        tester,
        const FutureNoteInviteLink(occasion: NoteInviteOccasion.milestone),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.byKey(const Key('note-invite-link')), findsNothing);
    });
  });

  group('where notes show up', () {
    testWidgets('Ride the wave: a note while riding, an invitation after it '
        'passes', (tester) async {
      await pump(tester, const CravingWaveScreen(), scroll: false);
      await tester.runAsync(() => controller.addFutureLetter('This ends.'));
      await tester.pump();
      expect(find.byKey(const Key('future-note-card')), findsNothing);
      await tester.tap(find.byKey(const Key('wave-start')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('FROM YOU, FOR RIGHT NOW'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wave-passed-button')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('wave-passed')), findsOneWidget);
      expect(find.byKey(const Key('future-note-card')), findsNothing);
      expect(find.byKey(const Key('note-invite-link')), findsOneWidget);
    });

    testWidgets('after a slip: the reset screen shows a note', (tester) async {
      await pump(tester, const RelapseCooldownScreen(), scroll: false);
      await tester.runAsync(() => controller.addFutureLetter('Start again.'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('future-note-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('YOU LEFT THIS FOR A DAY LIKE TODAY'), findsOneWidget);
    });
  });

  group('Notes screen', () {
    testWidgets('explains how notes are kept; locked notes can be unlocked '
        'with the old PIN', (tester) async {
      final stored = await _lockedState();
      await pump(
        tester,
        const FutureLettersScreen(),
        stored: stored,
        on: FakePhone(),
        scroll: false,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('future-notes-locked-explainer')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('future-notes-unlock')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note-pin-field')), '0000');
      await tester.tap(find.byKey(const Key('note-pin-submit')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('future-notes-locked-explainer')),
        findsOneWidget,
      );
      expect(controller.lockedNoteIds, isNotEmpty);
      await tester.tap(find.byKey(const Key('future-notes-unlock')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note-pin-field')), '2468');
      await tester.tap(find.byKey(const Key('note-pin-submit')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(controller.lockedNoteIds, isEmpty);
      expect(
        find.byKey(const Key('future-notes-locked-explainer')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('future-notes-security')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Nothing is uploaded'), findsOneWidget);
    });
  });
}

var _cappedNow = DateTime(2026, 11, 26, 20);

class _CappedComposer extends ConsumerWidget {
  const _CappedComposer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _cappedNow = DateTime(2026, 11, 26, 20);
    return Column(
      children: [
        // The recorder under test, with a controllable clock.
        _CappedRecorder(),
      ],
    );
  }
}

class _CappedRecorder extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      VoiceNoteRecorder(now: () => _cappedNow, onSave: (_) async {});
}

/// State with one note sealed under PIN 2468 on another phone.
Future<String> _lockedState() async {
  final other = FakePhone();
  final store = MemoryRecoveryStore();
  final c = RecoveryController(
    store: store,
    relapseLock: FakeRelapseLock(),
    futureNotes: other.notes,
  );
  await c.load();
  await c.enableRelapseLock('2468');
  await c.addFutureLetter('Sealed elsewhere');
  final map = jsonDecode(store.value!) as Map<String, dynamic>;
  // A reinstall: app data came back, the PIN and the Keystore did not.
  map['requirePinAfterRelapse'] = false;
  return jsonEncode(map);
}
