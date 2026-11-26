import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/urge_surf_screen.dart';
import 'package:no_lean/features/cravings/presentation/craving_wave_screen.dart';
import 'package:no_lean/features/letters/presentation/future_letters_screen.dart';
import 'package:no_lean/features/notes/domain/note_invite.dart';
import 'package:no_lean/features/notes/presentation/note_invite_panel.dart';
import 'package:no_lean/features/notes/services/voice_io.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/presentation/relapse_cooldown_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/note_fakes.dart';
import '../../support/recovery_fakes.dart';
import '../../support/voice_fakes.dart';

/// Renders the future-self-notes screens with the Flutter test renderer (no
/// emulator). Does nothing unless NO_LEAN_CAPTURE_DIR is set:
/// `NO_LEAN_CAPTURE_DIR=/workspace/future-self-screens flutter test <file>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();
  final now = DateTime(2026, 11, 26, 18, 30);
  final audio = Uint8List.fromList(List.generate(64, (i) => i));

  setUpAll(() async {
    if (dir == null) return;
    for (final family in ['NoLeanDisplay', 'NoLeanMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    const mono = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf';
    if (File(mono).existsSync()) {
      await (FontLoader('monospace')..addFont(
            Future.value(ByteData.sublistView(File(mono).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function(RecoveryController c) home, {
    FakePhone? phone,
    String? stored,
    Future<void> Function(RecoveryController)? seed,
    Future<void> Function(WidgetTester, RecoveryController)? act,
    FakeVoiceRecorder? recorder,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox()); // drop the previous screen
    final p = phone ?? FakePhone();
    final c = RecoveryController(
      store: MemoryRecoveryStore(stored),
      relapseLock: FakeRelapseLock(),
      futureNotes: p.notes,
      now: () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    await tester.runAsync(() async => seed?.call(c));
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => c),
        voiceRecorderFactoryProvider.overrideWithValue(
          () => recorder ?? FakeVoiceRecorder(),
        ),
        voicePlayerFactoryProvider.overrideWithValue(() => FakeVoicePlayer()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNoLeanTheme(),
          home: RepaintBoundary(key: key, child: home(c)),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await act?.call(tester, c);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir!).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Widget sheetOver(Widget sheet) => Scaffold(
    backgroundColor: Colors.black54,
    body: Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: sheet,
        ),
      ),
    ),
  );

  Future<void> seedNotes(RecoveryController c) async {
    await c.addFutureLetter(
      'Tonight is loud. You have beaten this before. Drink water, text '
      'Dev, and let it pass.',
    );
    await c.addFutureLetter('Remember the morning after the last one.');
  }

  Future<String> lockedState() async {
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
    await c.addFutureLetter('Another sealed one');
    final map = jsonDecode(store.value!) as Map<String, dynamic>;
    map['requirePinAfterRelapse'] = false;
    return jsonEncode(map);
  }

  testWidgets('capture future-self notes screens', (tester) async {
    if (dir == null) return;

    await shoot(
      tester,
      '01_invite_after_milestone',
      (c) => sheetOver(
        const NoteInviteSheet(occasion: NoteInviteOccasion.milestone),
      ),
    );

    await shoot(
      tester,
      '02_invite_write_or_record',
      (c) => sheetOver(
        const NoteInviteSheet(occasion: NoteInviteOccasion.urgePassed),
      ),
      act: (t, c) async {
        await t.tap(find.byKey(const Key('note-invite-open')));
        await t.pump();
      },
      size: const Size(390, 900),
    );

    await shoot(
      tester,
      '03_recording',
      (c) => sheetOver(
        const NoteInviteSheet(occasion: NoteInviteOccasion.cleanCheckIn),
      ),
      act: (t, c) async {
        await t.tap(find.byKey(const Key('note-invite-open')));
        await t.pump();
        await t.tap(find.byKey(const Key('voice-record')));
        await t.pump();
      },
      size: const Size(390, 900),
    );

    await shoot(
      tester,
      '04_review_take',
      (c) => sheetOver(
        const NoteInviteSheet(occasion: NoteInviteOccasion.cleanCheckIn),
      ),
      act: (t, c) async {
        await t.tap(find.byKey(const Key('note-invite-open')));
        await t.pump();
        await t.tap(find.byKey(const Key('voice-record')));
        await t.pump();
        await t.tap(find.byKey(const Key('voice-stop')));
        await t.pump();
      },
      size: const Size(390, 900),
    );

    await shoot(
      tester,
      '05_mic_denied',
      (c) => sheetOver(
        const NoteInviteSheet(occasion: NoteInviteOccasion.cleanCheckIn),
      ),
      recorder: FakeVoiceRecorder()..allow = false,
      act: (t, c) async {
        await t.tap(find.byKey(const Key('note-invite-open')));
        await t.pump();
        await t.tap(find.byKey(const Key('voice-record')));
        await t.pump();
      },
      size: const Size(390, 900),
    );

    await shoot(
      tester,
      '06_ride_the_wave_with_note',
      (c) => const CravingWaveScreen(),
      seed: seedNotes,
      act: (t, c) async {
        await t.tap(find.byKey(const Key('wave-start')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 300));
      },
    );

    await shoot(
      tester,
      '07_ride_the_wave_voice_note',
      (c) => const CravingWaveScreen(),
      seed: (c) async {
        await c.enableRelapseLock('2468');
        await c.addVoiceNote(audio, const Duration(seconds: 23));
      },
      act: (t, c) async {
        await t.tap(find.byKey(const Key('wave-start')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 300));
      },
    );

    await shoot(
      tester,
      '08_wave_passed_invite_link',
      (c) => const CravingWaveScreen(),
      act: (t, c) async {
        await t.tap(find.byKey(const Key('wave-start')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const Key('wave-passed-button')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await t.pump(const Duration(milliseconds: 300));
      },
    );

    await shoot(
      tester,
      '09_urge_timer_with_note',
      (c) => const UrgeSurfScreen(),
      seed: seedNotes,
      act: (t, c) async {
        await t.tap(find.textContaining('minute timer'));
        await t.pump(const Duration(milliseconds: 300));
      },
    );

    await shoot(
      tester,
      '10_after_slip_reset_screen',
      (c) => const RelapseCooldownScreen(),
      seed: seedNotes,
      size: const Size(390, 1100),
    );

    await shoot(
      tester,
      '11_notes_screen_encrypted',
      (c) => const FutureLettersScreen(),
      seed: (c) async {
        await c.enableRelapseLock('2468');
        await seedNotes(c);
        await c.addVoiceNote(audio, const Duration(seconds: 41));
        // Screenshot only: skip the PIN prompt the screen would show.
        c.requirePinAfterRelapse = false;
      },
      size: const Size(390, 1500),
    );

    await shoot(
      tester,
      '12_notes_screen_locked_after_reinstall',
      (c) => const FutureLettersScreen(),
      stored: await lockedState(),
      size: const Size(390, 1500),
    );
  });
}
