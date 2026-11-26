import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/lower_tolerance.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/presentation/lower_tolerance_card.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';

import '../../../support/recovery_fakes.dart';
import '../../../support/relapse_form.dart';

const contact = TrustedContact(name: 'Riya', phone: '+919876543210');

ToleranceWarning lean18({bool mixed = false}) => ToleranceWarning(
  kind: ToleranceWarningKind.lean,
  cleanDays: 18,
  occurredAt: DateTime(2026, 10, 19, 21),
  mixed: mixed,
);

String storedLeanAt(DateTime at) => jsonEncode({
  'stateVersion': RecoveryController.stateVersion,
  'events': [
    {
      'id': 'prior-lean',
      'type': 'relapse',
      'timestamp': at.toIso8601String(),
      'metadata': {
        'relapseType': 'fullLean',
        'note': 'Starting point for this test.',
      },
    },
  ],
});

void main() {
  final launched = <Uri>[];

  Future<void> show(
    WidgetTester tester, {
    required ToleranceWarning warning,
    TrustedContact? saved = contact,
  }) async {
    launched.clear();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [trustedContactProvider.overrideWith((ref) async => saved)],
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: LowerToleranceCard(
              warning: warning,
              contact: saved,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lean card uses their 18 days and calls the SOS contact', (
    tester,
  ) async {
    await show(tester, warning: lean18());
    expect(find.byKey(const ValueKey('lower-tolerance-card')), findsOneWidget);
    expect(find.text('Your body handles less now'), findsOneWidget);
    expect(
      find.textContaining(
        'You were clean 18 days, so your body handles less now',
      ),
      findsOneWidget,
    );
    expect(find.text('CALL 112'), findsNothing);
    expect(find.textContaining('112'), findsNothing);
    expect(find.text('CALL RIYA'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tolerance-call-sos')));
    await tester.pumpAndSettle();
    expect(launched, [Uri(scheme: 'tel', path: '+919876543210')]);
  });

  testWidgets('benzo-only card is gentler and still has no helpline', (
    tester,
  ) async {
    await show(
      tester,
      warning: ToleranceWarning(
        kind: ToleranceWarningKind.benzo,
        cleanDays: 9,
        occurredAt: DateTime(2026, 10, 10),
      ),
    );
    expect(find.text('Benzos hit harder after a break'), findsOneWidget);
    expect(
      find.textContaining('does not change your lean clean time'),
      findsOneWidget,
    );
    expect(find.textContaining('112'), findsNothing);
    expect(find.text('GOT IT'), findsOneWidget);
  });

  testWidgets('without a saved contact, the call button is disabled', (
    tester,
  ) async {
    await show(tester, warning: lean18(), saved: null);
    expect(find.text('NO SOS CONTACT SAVED'), findsOneWidget);
    expect(find.byKey(const ValueKey('tolerance-no-contact')), findsOneWidget);
    expect(find.textContaining('doctor or hospital'), findsWidgets);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('tolerance-call-sos')),
    );
    expect(button.onPressed, isNull);
    expect(launched, isEmpty);
  });

  testWidgets('GOT IT dismisses the full-screen card', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showLowerToleranceCard(
                  context,
                  warning: lean18(),
                  contact: contact,
                ),
                child: const Text('SHOW'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('SHOW'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lower-tolerance-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tolerance-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lower-tolerance-card')), findsNothing);
    expect(find.text('SHOW'), findsOneWidget);
  });

  testWidgets('saving a lean slip after 18 clean days shows the card once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final prior = now.subtract(const Duration(days: 18));
    final c = RecoveryController(
      store: MemoryRecoveryStore(storedLeanAt(prior)),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(now.year, now.month, now.day, 12),
    );
    await c.load();
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
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRelapseLogSheet(context),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    final note = find.byKey(const ValueKey('relapse-note-0'));
    await revealInRelapseSheet(tester, note);
    await tester.enterText(note, 'I used again after a long clean stretch.');
    tester.testTextInput.hide();
    await tester.tap(find.byKey(const ValueKey('save-relapse-events')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM RESET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('lower-tolerance-card')), findsOneWidget);
    expect(find.textContaining('You were clean 18 days'), findsOneWidget);
    expect(find.text('CALL 112'), findsNothing);
    // Dismiss; the card must not come back.
    await tester.ensureVisible(find.byKey(const ValueKey('tolerance-dismiss')));
    await tester.tap(find.byKey(const ValueKey('tolerance-dismiss')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const ValueKey('lower-tolerance-card')), findsNothing);
    expect(
      c.events.where((e) => e.type == RecoveryEventType.relapse),
      hasLength(2),
    );
  });

  testWidgets('a short streak does not show the card', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final prior = now.subtract(const Duration(days: 2));
    final c = RecoveryController(
      store: MemoryRecoveryStore(storedLeanAt(prior)),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(now.year, now.month, now.day, 12),
    );
    await c.load();
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => c)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRelapseLogSheet(context),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    final note = find.byKey(const ValueKey('relapse-note-0'));
    await revealInRelapseSheet(tester, note);
    await tester.enterText(note, 'Used again only two days later.');
    tester.testTextInput.hide();
    await tester.tap(find.byKey(const ValueKey('save-relapse-events')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM RESET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('lower-tolerance-card')), findsNothing);
  });
}
