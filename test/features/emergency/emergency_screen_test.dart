import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/emergency/presentation/emergency_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';

import '../../support/recovery_fakes.dart';

void main() {
  testWidgets('SOS runs breathe, 5-4-3-2-1, reasons, then re-pledge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
        trustedContactServiceProvider.overrideWithValue(
          const TrustedContactService(FlutterSecureStorage()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final recovery = container.read(recoveryProvider);
    await recovery.load();
    await recovery.updateReasons(['My sister needs me sharp']);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EmergencyScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    String stageTitle() => tester
        .widget<Text>(find.byKey(const ValueKey('sos-stage-title')))
        .data!;
    IconButton close() =>
        tester.widget<IconButton>(find.byKey(const ValueKey('sos-close')));

    expect(stageTitle(), 'STEP 1/4 // SLOW THE BODY DOWN');
    expect(find.text('BREATHE IN'), findsOneWidget);
    expect(close().onPressed, isNull);
    expect(recovery.sosSessions.single.isCompleted, isFalse);

    await tester.pump(const Duration(seconds: 15));
    expect(close().onPressed, isNotNull); // never trapped past 15 s

    await tester.pump(const Duration(seconds: 45));
    await tester.pumpAndSettle();
    expect(stageTitle(), 'STEP 2/4 // GET BACK INTO THE ROOM');

    for (final sense in ['5 // SEE', '4 // TOUCH', '3 // HEAR', '2 // SMELL']) {
      expect(find.text(sense), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sos-ground-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('1 // TASTE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sos-ground-next')));
    await tester.pumpAndSettle();

    expect(stageTitle(), 'STEP 3/4 // REMEMBER WHY');
    expect(find.text('My sister needs me sharp'), findsOneWidget);
    expect(find.textContaining('DAYS CLEAN'), findsOneWidget);
    expect(recovery.sosSessions.single.isCompleted, isFalse);

    await tester.tap(find.byKey(const ValueKey('sos-reasons-next')));
    await tester.pumpAndSettle();
    expect(stageTitle(), 'STEP 4/4 // LOCK IT IN');
    expect(recovery.sosSessions.single.isCompleted, isTrue);

    await tester.tap(find.text('BETTER'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sos-pledge')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sos-screen')), findsNothing);
    expect(recovery.sosSessions.single.debrief, 'down');
    expect(
      recovery.events.where((e) => e.type == RecoveryEventType.pledge),
      hasLength(1),
    );
  });
}
