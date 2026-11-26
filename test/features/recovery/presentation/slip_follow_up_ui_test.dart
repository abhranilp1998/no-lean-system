import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/mixing_alert.dart';
import 'package:no_lean/features/recovery/domain/mixing_safety_net.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/slip_review.dart';
import 'package:no_lean/features/recovery/presentation/mixing_alert_screen.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_location.dart';
import '../../../support/recovery_fakes.dart';

void main() {
  // Outside the default 17:00-21:00 risk window.
  final now = DateTime(2026, 10, 8, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  RelapseLogEntry entry(
    DateTime at,
    RelapseType type, [
    String note = 'Rough morning, gave in.',
  ]) => RelapseLogEntry(
    occurredAt: at,
    type: type,
    note: note,
    attemptedSos: false,
  );

  Future<RecoveryController> pumpApp(
    WidgetTester tester, {
    String? pin,
    Map<String, Object> prefs = const {},
    FakeLocationService? location,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await controller.load();
    if (pin != null) await controller.enableRelapseLock(pin);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => controller),
        if (location != null)
          locationServiceProvider.overrideWithValue(location),
        trustedContactProvider.overrideWith(
          (ref) async =>
              const TrustedContact(name: 'Riya', phone: '+919800000000'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NoLeanApp()),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return controller;
  }

  Future<void> saveMix(RecoveryController c, {String? pin}) => c.recordRelapse(
    pin: pin,
    entries: [
      entry(DateTime(2026, 10, 8, 8), RelapseType.fullLean),
      entry(
        DateTime(2026, 10, 8, 10),
        RelapseType.benzo,
        'took one alprazolam to sleep',
      ),
    ],
    tryBiometrics: false,
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets('a mixed save shows the safety card once, then the review', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await saveMix(c);
    await settle(tester);

    expect(find.byKey(const ValueKey('mixing-alert')), findsOneWidget);
    expect(find.text('You logged codeine + alprazolam today.'), findsOneWidget);
    expect(find.byKey(const ValueKey('slip-review')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mixing-alert-close')));
    await settle(tester);
    // One card per save, however many entries: not shown again.
    expect(find.byKey(const ValueKey('mixing-alert')), findsNothing);
    expect(find.byKey(const ValueKey('slip-review')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review-skip')));
    await settle(tester);
    expect(find.byKey(const ValueKey('slip-review')), findsNothing);
    expect(find.byKey(const ValueKey('mixing-alert')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      c.events.where((e) => e.metadata.containsKey('place')),
      isEmpty,
      reason: 'skipping stores nothing',
    );
  });

  testWidgets('a plain slip goes straight to the optional review', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await c.recordRelapse(
      entries: [entry(DateTime(2026, 10, 8, 9), RelapseType.fullLean)],
      tryBiometrics: false,
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('mixing-alert')), findsNothing);
    expect(find.byKey(const ValueKey('slip-review')), findsOneWidget);
  });

  testWidgets('the card waits behind the PIN lock, then appears', (
    tester,
  ) async {
    final c = await pumpApp(tester, pin: '2468');
    await saveMix(c, pin: '2468');
    await settle(tester);
    expect(find.text('LOCKED AFTER RELAPSE LOG'), findsOneWidget);
    expect(find.byKey(const ValueKey('mixing-alert')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2468');
    await tester.tap(find.widgetWithText(FilledButton, 'UNLOCK'));
    await settle(tester);
    expect(find.byKey(const ValueKey('mixing-alert')), findsOneWidget);
  });

  testWidgets('safety net switched off: no card, review still offered', (
    tester,
  ) async {
    final c = await pumpApp(
      tester,
      prefs: {mixingSafetyNetKey: MixingSafetyNet.off.name},
    );
    await saveMix(c);
    await settle(tester);
    expect(find.byKey(const ValueKey('mixing-alert')), findsNothing);
    expect(find.byKey(const ValueKey('slip-review')), findsOneWidget);
  });

  testWidgets('review: three taps are saved onto the slip', (tester) async {
    final c = await pumpApp(tester);
    await c.recordRelapse(
      entries: [entry(DateTime(2026, 10, 8, 9), RelapseType.fullLean)],
      tryBiometrics: false,
    );
    await settle(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey("review-place-Friend's place")),
    );
    await tester.tap(find.byKey(const ValueKey("review-place-Friend's place")));
    await tester.ensureVisible(
      find.byKey(const ValueKey('review-with-friends')),
    );
    await tester.tap(find.byKey(const ValueKey('review-with-friends')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('review-trigger-Boredom')),
    );
    await tester.tap(find.byKey(const ValueKey('review-trigger-Boredom')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('review-save')));
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await settle(tester);

    final slip = c.events.lastWhere((e) => e.metadata.containsKey('place'));
    expect(slip.metadata['place'], "Friend's place");
    expect(slip.metadata['withWho'], 'friends');
    expect(slip.metadata['contextTags'], contains('Boredom'));
    expect(find.byKey(const ValueKey('slip-review')), findsNothing);
  });

  testWidgets(
    'review: save stays off until something is picked; a second tap unpicks',
    (tester) async {
      final c = await pumpApp(tester);
      await c.recordRelapse(
        entries: [entry(DateTime(2026, 10, 8, 9), RelapseType.fullLean)],
        tryBiometrics: false,
      );
      await settle(tester);
      FilledButton save() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('review-save')),
      );
      expect(save().onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('review-with-alone')));
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('review-with-alone')));
      await tester.pump();
      expect(save().onPressed, isNull);
    },
  );

  group('MixingAlertScreen', () {
    final alert = MixingAlert(
      substances: const ['codeine', 'alprazolam'],
      eventIds: const {'a', 'b'},
      latest: now,
      today: true,
    );

    Future<List<Uri>> pump(
      WidgetTester tester, {
      TrustedContact? contact,
    }) async {
      final launched = <Uri>[];
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [trustedContactProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: buildNoLeanTheme(),
            home: MixingAlertScreen(
              alert: alert,
              contact: contact,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      return launched;
    }

    testWidgets('quotes the log, says what to do, shows the illustration', (
      tester,
    ) async {
      await pump(
        tester,
        contact: const TrustedContact(name: 'Riya', phone: '+919800000000'),
      );
      expect(
        find.text('You logged codeine + alprazolam today.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mixing-step-alone')), findsOneWidget);
      expect(find.text("Don't use alone tonight."), findsOneWidget);
      expect(
        find.text("Don't take more of either for the next few hours."),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('recovery-position-image')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining('get them to a hospital now'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('hospital'), findsWidgets);
      expect(find.text('CALL RIYA'), findsOneWidget);
    });

    testWidgets('the big buttons call and text the user’s own contact', (
      tester,
    ) async {
      final launched = await pump(
        tester,
        contact: const TrustedContact(name: 'Riya', phone: '+919800000000'),
      );
      await tester.tap(find.byKey(const ValueKey('mixing-call-contact')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mixing-text-contact')));
      await tester.pump();
      expect(launched.first.toString(), 'tel:+919800000000');
      expect(launched.last.scheme, 'sms');
      expect(launched.last.path, '+919800000000');
      expect(launched.last.queryParameters['body'], mixingPingText);
    });

    testWidgets('no government helplines or emergency numbers anywhere', (
      tester,
    ) async {
      await pump(
        tester,
        contact: const TrustedContact(name: 'Riya', phone: '+919800000000'),
      );
      final texts = [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          w.data ?? w.textSpan?.toPlainText() ?? '',
      ].join('\n');
      expect(
        texts,
        isNot(
          matches(
            RegExp(r'\b(112|911|999|108|102|helpline)\b', caseSensitive: false),
          ),
        ),
      );
    });

    test('the card source names no helpline or emergency number', () {
      final src =
          File('lib/features/recovery/presentation/mixing_alert_screen.dart')
              .readAsLinesSync()
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
      expect(
        src,
        isNot(matches(RegExp(r'(?<![\w.])(112|911|999|108|102)(?![\w.])'))),
      );
      expect(src.toLowerCase(), isNot(contains('helpline')));
    });

    testWidgets('no saved contact: still helps, and says where to add one', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('CALL SOMEONE I TRUST'), findsOneWidget);
      expect(find.textContaining('No SOS contact saved yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('mixing-alert-close')), findsOneWidget);
    });
  });

  testWidgets('SlipReviewSheet shows saved danger zones as place chips', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await c.addZone(
      name: 'The usual pharmacy',
      latitude: 12.9,
      longitude: 77.6,
      radiusMeters: 150,
    );
    await c.recordRelapse(
      entries: [entry(DateTime(2026, 10, 8, 9), RelapseType.fullLean)],
      tryBiometrics: false,
    );
    await settle(tester);
    final zone = c.zones.single;
    await tester.tap(find.byKey(ValueKey('review-zone-${zone.id}')));
    await tester.tap(find.byKey(const ValueKey('review-with-alone')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('review-save')));
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await settle(tester);
    final slip = c.events.lastWhere((e) => e.metadata.containsKey('place'));
    expect(slip.metadata['zoneId'], zone.id);
    expect(slip.metadata['place'], 'The usual pharmacy');
    // A reviewed zone slip never produces a "make it a zone" nudge.
    expect(zoneSuggestions(c.events, c.zones), isEmpty);
    expect(slipsAtPlace(c.events, 'The usual pharmacy'), 1);
  });

  group('make a reviewed place a danger zone', () {
    final fix = LocationFix(
      latitude: 12.9716,
      longitude: 77.5946,
      accuracyMeters: 10,
      at: now,
    );

    Future<RecoveryController> secondSlipHere(
      WidgetTester tester,
      FakeLocationService location, {
      required DateTime at,
    }) async {
      final c = await pumpApp(tester, location: location);
      await c.recordRelapse(
        entries: [entry(DateTime(2026, 10, 7, 20), RelapseType.fullLean)],
        tryBiometrics: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey("review-place-Friend's place")),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review-save')));
      await settle(tester);
      await c.recordRelapse(
        entries: [entry(at, RelapseType.fullLean)],
        tryBiometrics: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey("review-place-Friend's place")),
      );
      await tester.pump();
      return c;
    }

    testWidgets('a fresh slip uses where the phone is now', (tester) async {
      final location = FakeLocationService(fix: fix);
      final c = await secondSlipHere(
        tester,
        location,
        at: DateTime(2026, 10, 8, 11),
      );
      expect(find.byKey(const ValueKey('review-zone-offer')), findsOneWidget);
      expect(find.textContaining('slip 2'), findsOneWidget);

      final before = location.currentFixRequests;
      await tester.tap(find.byKey(const ValueKey('review-mark-zone')));
      await settle(tester);
      expect(location.currentFixRequests - before, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('zone-name')))
            .controller!
            .text,
        "Friend's place",
      );
      await tester.tap(find.byKey(const ValueKey('zone-save')));
      await settle(tester);
      final zone = c.zones.single;
      expect(zone.name, "Friend's place");
      expect(zone.latitude, closeTo(12.9716, 1e-6));
      // Saving the review now links this slip to the zone.
      await tester.tap(find.byKey(const ValueKey('review-save')));
      await settle(tester);
      final linked = c.events.lastWhere((e) => e.metadata['zoneId'] == zone.id);
      expect(linked.metadata['place'], "Friend's place");
    });

    testWidgets('an old slip never borrows today’s location', (tester) async {
      final location = FakeLocationService(fix: fix);
      await secondSlipHere(tester, location, at: DateTime(2026, 10, 8, 6));
      final before = location.currentFixRequests;
      await tester.tap(find.byKey(const ValueKey('review-mark-zone')));
      await settle(tester);
      expect(location.currentFixRequests - before, 0);
      expect(find.byKey(const ValueKey('zone-name')), findsNothing);
    });
  });
}
