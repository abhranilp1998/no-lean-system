import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/dashboard/domain/rough_day.dart';
import 'package:no_lean/features/dashboard/presentation/dashboard_screen.dart';
import 'package:no_lean/features/dashboard/presentation/rough_day_home.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';

import '../../../support/recovery_fakes.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(finder, 400, scrollable: scrollable);
}

void main() {
  late RecoveryController c;
  late List<Uri> dialed;
  late List<DateTime> reminders;
  var rideOpened = false;
  var logNowOpened = false;

  Future<void> pumpDash(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    dialed = [];
    reminders = [];
    rideOpened = false;
    logNowOpened = false;
    c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (_) async => true,
      cancelUseCheck: () async {},
      scheduleLogLater: (at) async {
        reminders.add(at);
        return true;
      },
      cancelLogLater: () async {},
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
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpHome(WidgetTester tester, {TrustedContact? contact}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    dialed = [];
    reminders = [];
    rideOpened = false;
    logNowOpened = false;
    c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (_) async => true,
      cancelUseCheck: () async {},
      scheduleLogLater: (at) async {
        reminders.add(at);
        return true;
      },
      cancelLogLater: () async {},
    );
    await c.load();
    await c.enterRoughDay(source: RoughDaySource.struggling);
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
            body: RoughDayHome(
              key: const ValueKey('rough-day-home'),
              contactOverride: contact,
              lookupContact: false,
              launchUri: (uri) async {
                dialed.add(uri);
                return true;
              },
              onRideItOut: () => rideOpened = true,
              onLogNow: () => logNowOpened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('I am struggling switches the home to the calm layout', (
    tester,
  ) async {
    await pumpDash(tester);
    expect(find.byKey(const ValueKey('rough-day-home')), findsNothing);
    await reveal(tester, find.byKey(const ValueKey('dashboard-im-struggling')));
    await tester.tap(find.byKey(const ValueKey('dashboard-im-struggling')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.isRoughDay, isTrue);
    expect(find.byKey(const ValueKey('rough-day-home')), findsOneWidget);
    expect(find.text(roughDayCallLabel), findsOneWidget);
    expect(find.text(roughDayRideLabel), findsOneWidget);
    expect(find.text(roughDayLogLaterLabel), findsOneWidget);
    expect(find.text(roughDayBackLabel), findsOneWidget);
  });

  testWidgets('a logged slip also switches the home', (tester) async {
    await pumpDash(tester);
    await c.recordRelapse(
      entries: [
        RelapseLogEntry(
          occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
          type: RelapseType.fullLean,
          note: 'Writing this down honestly.',
          attemptedSos: false,
        ),
      ],
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('rough-day-home')), findsOneWidget);
    expect(find.text(roughDayCallLabel), findsOneWidget);
  });

  testWidgets('the three buttons do what they say', (tester) async {
    await pumpHome(
      tester,
      contact: const TrustedContact(name: 'Sam', phone: '9876543210'),
    );
    await tester.tap(find.byKey(const ValueKey('rough-day-call')));
    await tester.pump();
    expect(dialed.single.scheme, 'tel');
    expect(dialed.single.path, '9876543210');

    await tester.tap(find.byKey(const ValueKey('rough-day-ride')));
    await tester.pump();
    expect(rideOpened, isTrue);

    await tester.tap(find.byKey(const ValueKey('rough-day-log-later')));
    await tester.pumpAndSettle();
    expect(find.text(roughDayRemindLabel), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('rough-day-log-remind')),
    );
    await tester.tap(find.byKey(const ValueKey('rough-day-log-remind')));
    await tester.pumpAndSettle();
    expect(reminders, hasLength(1));
    expect(find.textContaining('I will nudge you'), findsOneWidget);
  });

  testWidgets('Log it later can open the logger now', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('rough-day-log-later')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rough-day-log-now')));
    await tester.tap(find.byKey(const ValueKey('rough-day-log-now')));
    await tester.pumpAndSettle();
    expect(logNowOpened, isTrue);
  });

  testWidgets('with no person saved, Call my person never dials a helpline', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('rough-day-call')));
    await tester.pumpAndSettle();
    expect(dialed, isEmpty);
    expect(find.textContaining('Add someone you trust first'), findsOneWidget);
    // The trusted-contact dialog may or may not open (secure storage is
    // mocked-unfriendly); the important part is we did not dial 112 / 911.
  });

  testWidgets('Back to normal view restores the usual home', (tester) async {
    await pumpDash(tester);
    await reveal(tester, find.byKey(const ValueKey('dashboard-im-struggling')));
    await tester.tap(find.byKey(const ValueKey('dashboard-im-struggling')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('rough-day-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.isRoughDay, isFalse);
    expect(find.byKey(const ValueKey('rough-day-home')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-used-now')), findsOneWidget);
  });
}
