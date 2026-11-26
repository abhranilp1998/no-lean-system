import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/progress/presentation/widgets/swap_watch_card.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/swap_watch.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';

import '../../../support/recovery_fakes.dart';

const contact = TrustedContact(name: 'Riya', phone: '+919876543210');

final sample = SwapWatchInsight(
  lean: const SubstanceDayCounts(previous: 10, recent: 3),
  risen: WatchedSubstance.alcohol,
  other: const SubstanceDayCounts(previous: 2, recent: 8),
  recentStart: DateTime(2026, 11, 13),
  previousStart: DateTime(2026, 10, 30),
);

void main() {
  final launched = <Uri>[];

  Future<void> show(
    WidgetTester tester, {
    SwapWatchInsight? insight,
    TrustedContact? saved = contact,
    VoidCallback? onDismiss,
  }) async {
    launched.clear();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 26, 18),
    );
    await c.load();
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => c),
        trustedContactProvider.overrideWith((ref) async => saved),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SwapWatchCard(
              insight: insight ?? sample,
              contact: saved,
              onDismiss: onDismiss,
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

  testWidgets('uses their numbers and calls the SOS contact, never 112', (
    tester,
  ) async {
    var dismissed = false;
    await show(tester, onDismiss: () => dismissed = true);
    expect(find.byKey(const ValueKey('swap-watch-card')), findsOneWidget);
    expect(find.text('A quiet heads-up'), findsOneWidget);
    expect(find.textContaining('Lean is down 70%, nice work.'), findsOneWidget);
    expect(
      find.textContaining('Alcohol went from 1 day a week to 4 days a week'),
      findsOneWidget,
    );
    expect(find.text('CALL 112'), findsNothing);
    expect(find.textContaining('112'), findsNothing);
    expect(find.text('CALL RIYA'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swap-watch-call-sos')));
    await tester.pumpAndSettle();
    expect(launched, [Uri(scheme: 'tel', path: '+919876543210')]);
    await tester.tap(find.byKey(const ValueKey('swap-watch-dismiss')));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets(
    'without a contact, there is no call button and a doctor is offered',
    (tester) async {
      await show(tester, saved: null);
      expect(find.byKey(const ValueKey('swap-watch-call-sos')), findsNothing);
      expect(
        find.byKey(const ValueKey('swap-watch-no-contact')),
        findsOneWidget,
      );
      expect(find.textContaining('doctor'), findsWidgets);
      expect(find.textContaining('112'), findsNothing);
    },
  );
}
