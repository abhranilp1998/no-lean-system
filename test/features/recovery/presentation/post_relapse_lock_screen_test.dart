import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/app_lock_session.dart';
import 'package:no_lean/features/recovery/domain/post_relapse_summary.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/presentation/app_lock_screen.dart';
import 'package:no_lean/features/recovery/presentation/post_relapse_lock_body.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Yesterday evening on the real clock: always in the past (the controller
  // validates relapse dates against the real clock) with a fixed hour.
  final today = DateTime.now();
  final now = DateTime(today.year, today.month, today.day - 1, 21, 30);

  /// A controller whose clean run began [cleanDays] days ago, then logs
  /// [types] as relapses [ago] before now.
  Future<RecoveryController> seeded({
    required int cleanDays,
    List<RelapseType> types = const [RelapseType.fullLean],
    Duration ago = const Duration(minutes: 3),
  }) async {
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': RecoveryController.stateVersion,
        'events': [
          RecoveryEvent.create(
            type: RecoveryEventType.recoveryStart,
            timestamp: now.subtract(Duration(days: cleanDays, hours: 1)),
          ).toJson(),
        ],
      }),
    );
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    if (types.isNotEmpty) {
      await c.recordRelapse(
        tryBiometrics: false,
        entries: [
          for (final t in types)
            RelapseLogEntry(
              occurredAt: now.subtract(ago),
              type: t,
              note: 'Rough evening, gave in.',
              attemptedSos: false,
            ),
        ],
      );
    }
    return c;
  }

  Future<void> pump(
    WidgetTester tester,
    RecoveryController c, {
    bool highContrast = false,
    bool reduceMotion = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    VoidCallback? onSos,
    VoidCallback? onCraving,
    TrustedContact? contact,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => c),
        trustedContactProvider.overrideWith((ref) async => contact),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(
            highContrast: highContrast,
            reduceMotion: reduceMotion,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: AppLockScreen(
                reason: AppLockReason.relapseLogged,
                onUnlocked: () {},
                onOpenSos: onSos ?? () {},
                onLogCraving: onCraving ?? () {},
                now: () => now,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> showBreathing(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('breath-toggle')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('app-lock-screen')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('app-lock-screen')),
      const Offset(0, -4000),
    );
    await tester.pump();
  }

  testWidgets('after 81 clean days: greeting, honesty line, real streak, plan, '
      'encouragement', (tester) async {
    final c = await seeded(cleanDays: 81);
    await pump(tester, c);

    expect(find.text('LOCKED AFTER RELAPSE LOG'), findsOneWidget);
    expect(find.text('RELAPSE LOGGED // ENTRY SAVED'), findsOneWidget);
    expect(find.text('Good evening.'), findsOneWidget);
    expect(find.text('That took honesty.'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-relapse-days')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('post-relapse-days'))).data,
      '81',
    );
    expect(find.textContaining('81 days still count'), findsOneWidget);
    expect(find.text('BEST: 81D'), findsOneWidget);
    expect(find.text('THIS WAS YOUR BEST RUN'), findsOneWidget);
    expect(find.text('THE NEXT 24 HOURS'), findsOneWidget);
    expect(find.text('Water, then something to eat'), findsOneWidget);
    expect(find.text('Do not be alone with it'), findsOneWidget);
    expect(find.text('Sleep, then check in'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('post-relapse-encouragement')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('post-relapse-tolerance')),
      findsOneWidget,
    );
    expect(find.text('LOWER TOLERANCE NOW'), findsOneWidget);
    expect(find.textContaining('After 81 clean days'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-relapse-mixing')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short streak (2 days) has no lower-tolerance reminder', (
    tester,
  ) async {
    final c = await seeded(cleanDays: 2);
    await pump(tester, c);
    expect(find.textContaining('2 days still count'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-relapse-tolerance')), findsNothing);
  });

  testWidgets('a 3-day streak gets the lower-tolerance reminder', (
    tester,
  ) async {
    final c = await seeded(cleanDays: 3);
    await pump(tester, c);
    expect(
      find.byKey(const ValueKey('post-relapse-tolerance')),
      findsOneWidget,
    );
  });

  testWidgets('mixed lean + benzo: mixing-risk card with the safety net, and '
      'the streak that ended', (tester) async {
    final c = await seeded(
      cleanDays: 81,
      types: [RelapseType.fullLean, RelapseType.benzo],
    );
    await pump(
      tester,
      c,
      contact: const TrustedContact(name: 'Riya', phone: '+919800000000'),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('post-relapse-mixing')), findsOneWidget);
    expect(find.text('MIXING RISK // NEXT 24 HOURS'), findsOneWidget);
    expect(find.byKey(const ValueKey('mixing-ping-contact')), findsOneWidget);
    expect(find.textContaining('81 days still count'), findsOneWidget);
    expect(find.textContaining('Stay near Riya'), findsOneWidget);
    // Unwinding the safety net's second tap still does not name a helpline
    // anywhere on this screen except the existing, opt-in 112 reveal.
    expect(find.textContaining('helpline'), findsNothing);
  });

  testWidgets('benzo-only: streak intact, timer kept, mixing risk, no '
      'tolerance card', (tester) async {
    final c = await seeded(cleanDays: 81, types: [RelapseType.benzo]);
    await pump(tester, c);
    expect(find.text('YOUR STREAK IS INTACT'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('post-relapse-days'))).data,
      '81',
    );
    expect(find.textContaining('not reset'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-relapse-mixing')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-relapse-tolerance')), findsNothing);
  });

  testWidgets('no streak to show: day-one copy, still warm', (tester) async {
    final c = await seeded(cleanDays: 0);
    await pump(tester, c);
    expect(find.text('DAY ONE, AGAIN'), findsOneWidget);
    expect(find.textContaining('still count'), findsNothing);
    expect(find.byKey(const ValueKey('post-relapse-tolerance')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SOS and LOG CRAVING work without unlocking; UNLOCK is pinned', (
    tester,
  ) async {
    var sos = 0;
    var craving = 0;
    final c = await seeded(cleanDays: 81);
    await pump(
      tester,
      c,
      onSos: () => sos++,
      onCraving: () => craving++,
      size: const Size(320, 480),
    );
    // Scrolled to the bottom of a long page, the actions are still on screen.
    await scrollToEnd(tester);
    await tester.tap(find.byKey(const ValueKey('app-lock-sos')));
    await tester.tap(find.byKey(const ValueKey('app-lock-craving')));
    expect(sos, 1);
    expect(craving, 1);
    final unlock = find.byKey(const ValueKey('app-lock-unlock'));
    expect(unlock, findsOneWidget);
    expect(find.text('UNLOCK'), findsOneWidget);
    expect(
      tester.getRect(unlock).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    expect(tester.getRect(unlock).width, greaterThan(250));
  });

  testWidgets('points to the user\'s own contact, a doctor or a hospital, '
      'never a helpline', (tester) async {
    final c = await seeded(cleanDays: 81);
    await pump(tester, c);
    await scrollToEnd(tester);
    final note = tester.widget<Text>(
      find.byKey(const ValueKey('post-relapse-footnote')),
    );
    final text = note.data!;
    expect(text, contains('SOS contact'));
    expect(text, contains('doctor'));
    expect(text, contains('hospital'));
    expect(text, isNot(contains('112')));
    expect(find.textContaining(RegExp(r'1800|helpline')), findsNothing);
  });

  testWidgets('small screen, big text, high contrast: scrolls, no overflow', (
    tester,
  ) async {
    final c = await seeded(
      cleanDays: 81,
      types: [RelapseType.fullLean, RelapseType.benzo],
    );
    await pump(
      tester,
      c,
      size: const Size(320, 568),
      textScale: 1.6,
      highContrast: true,
      reduceMotion: true,
    );
    expect(tester.takeException(), isNull);
    await scrollToEnd(tester);
    expect(find.byKey(const ValueKey('post-relapse-footnote')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-unlock')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathing guide runs a minute and finishes', (tester) async {
    final c = await seeded(cleanDays: 81);
    await pump(tester, c);
    await showBreathing(tester);
    String phase() =>
        tester.widget<Text>(find.byKey(const ValueKey('breath-phase'))).data!;
    expect(phase(), contains('In for 4, out for 6'));
    await tester.tap(find.byKey(const ValueKey('breath-toggle')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(phase(), startsWith('BREATHE IN'));
    expect(phase(), contains('ROUND 1 OF 6'));
    await tester.pump(const Duration(seconds: 5));
    expect(phase(), startsWith('BREATHE OUT'));
    await tester.pump(const Duration(seconds: 10));
    expect(phase(), contains('ROUND 2 OF 6'));
    await tester.pump(const Duration(seconds: 60));
    expect(phase(), startsWith('DONE'));
    expect(find.text('AGAIN'), findsOneWidget);
  });

  Future<List<double>> circleSizes(
    WidgetTester tester, {
    required bool reduce,
  }) async {
    final c = await seeded(cleanDays: 81);
    await pump(tester, c, reduceMotion: reduce);
    await showBreathing(tester);
    await tester.tap(find.byKey(const ValueKey('breath-toggle')));
    final out = <double>[];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
      out.add(
        tester.getSize(find.byKey(const ValueKey('breath-circle'))).width,
      );
    }
    await tester.tap(find.byKey(const ValueKey('breath-toggle')));
    await tester.pump();
    return out;
  }

  testWidgets('reduce motion keeps the breathing circle still', (tester) async {
    expect((await circleSizes(tester, reduce: true)).toSet().length, 1);
  });

  testWidgets('without reduce motion the circle follows the breath', (
    tester,
  ) async {
    expect(
      (await circleSizes(tester, reduce: false)).toSet().length,
      greaterThan(1),
    );
  });

  testWidgets('the body works on its own with an empty log', (tester) async {
    final c = await seeded(cleanDays: 0, types: const []);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => c),
        trustedContactProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PostRelapseLockBody(
                now: now,
                summary: buildPostRelapseSummary(
                  events: c.events,
                  now: now,
                  liveStreakDays: c.streak,
                  longestStreakDays: c.longestStreak,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('That took honesty.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
