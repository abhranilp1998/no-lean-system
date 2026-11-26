import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/domain/use_check.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';
import 'package:no_lean/features/zones/domain/zone_entry.dart';
import 'package:no_lean/features/zones/domain/zone_use_check.dart';
import 'package:no_lean/features/zones/presentation/zone_use_check_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  late RecoveryController c;
  late DateTime now;
  UseCheck? stored;

  Future<void> pump(WidgetTester tester, {bool dialog = false}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    now = DateTime.now();
    stored = null;
    c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (check) async {
        stored = check;
        return true;
      },
      cancelUseCheck: () async => stored = null,
      peekUseCheck: () async => stored,
      takeUseCheck: () async {
        final s = stored;
        stored = null;
        return s;
      },
      readZoneLedger: () async => null,
      writeZoneLedger: (_) async {},
    );
    await c.load();
    await c.setZoneHistory(true);
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
              builder: (context) => dialog
                  ? Center(
                      child: TextButton(
                        onPressed: () => showZoneUseCheckDialog(
                          context,
                          c,
                          c.pendingUseCheck!,
                        ),
                        child: const Text('OPEN'),
                      ),
                    )
                  : ListView(children: const [ZoneUseCheckCard()]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> visitedHoursAgo(WidgetTester tester, double hours) async {
    final at = now.subtract(Duration(minutes: (hours * 60).round()));
    await c.maybeQueueZoneUseCheck(
      ZoneEntry(zoneId: 'z1', zoneName: 'Old bar', at: at, source: 'app'),
    );
    await tester.pump();
  }

  testWidgets('no card before the check is due, or when nothing is pending', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('zone-use-check-card')), findsNothing);
    await visitedHoursAgo(tester, .2);
    expect(find.byKey(const ValueKey('zone-use-check-card')), findsNothing);
  });

  testWidgets('a due check shows the warm card with three answers', (
    tester,
  ) async {
    await pump(tester);
    await visitedHoursAgo(tester, 2);
    expect(find.byKey(const ValueKey('zone-use-check-card')), findsOneWidget);
    expect(find.text('CHECKING IN, NO PRESSURE'), findsOneWidget);
    expect(find.textContaining('Old bar'), findsOneWidget);
    expect(find.text(zoneCheckNoLabel), findsOneWidget);
    expect(find.text(zoneCheckYesLabel), findsOneWidget);
    expect(find.text(zoneCheckLaterLabel), findsOneWidget);
  });

  testWidgets('NO celebrates, counts a zone resisted and removes the card', (
    tester,
  ) async {
    await pump(tester);
    await visitedHoursAgo(tester, 2);
    await tester.tap(find.byKey(const ValueKey('zone-check-no')));
    await tester.pumpAndSettle();
    expect(c.zonesResisted, 1);
    expect(find.byKey(const ValueKey('zone-use-check-card')), findsNothing);
    expect(stored, isNull);
    final e = c.events.lastWhere(
      (e) => e.type == RecoveryEventType.cleanCheckIn,
    );
    expect(e.metadata['zoneResisted'], isTrue);
  });

  testWidgets('NOT SURE / LATER hides the card and keeps the check', (
    tester,
  ) async {
    await pump(tester);
    await visitedHoursAgo(tester, 2);
    await tester.tap(find.byKey(const ValueKey('zone-check-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zone-use-check-card')), findsNothing);
    expect(c.pendingUseCheck?.snoozes, 1);
    expect(stored?.snoozedUntil, now.add(useCheckSnooze));
    expect(c.zonesResisted, 0);
  });

  testWidgets(
    'YES opens the logger at the visit time with the place filled in',
    (tester) async {
      await pump(tester);
      await visitedHoursAgo(tester, 3);
      final visitAt = c.pendingUseCheck!.triggeredAt;
      await tester.tap(find.byKey(const ValueKey('zone-check-yes')));
      await tester.pumpAndSettle();
      expect(find.byType(RelapseLogSheet), findsOneWidget);
      expect(find.text('After a visit to Old bar.'), findsOneWidget);
      // The date and time buttons show the visit, not "now".
      expect(
        find.textContaining(DateFormat.yMMMd().format(visitAt)),
        findsWidgets,
      );
      // Closing the sheet without saving keeps the question.
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(c.pendingUseCheck, isNotNull);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        isEmpty,
      );
    },
  );

  testWidgets('the notification tap opens the same question as a dialog', (
    tester,
  ) async {
    await pump(tester, dialog: true);
    await visitedHoursAgo(tester, 2);
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zone-use-check-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('zone-check-no')));
    await tester.pumpAndSettle();
    expect(c.zonesResisted, 1);
    expect(find.byKey(const ValueKey('zone-use-check-dialog')), findsNothing);
  });

  group('notification', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    final saved = NotificationService.instance.prefs;
    tearDown(() => NotificationService.instance.prefs = saved);

    test(
      'quiet hours mute the notification but keep the check for the card',
      () async {
        NotificationService.instance.prefs = const NotificationPrefs(
          quietHoursEnabled: true,
          quietHours: RiskWindow(startMinutes: 0, endMinutes: 23 * 60 + 59),
        );
        final check = UseCheck(
          trigger: UseCheckTrigger.zoneVisit,
          triggeredAt: DateTime.now().subtract(const Duration(minutes: 5)),
          zoneName: 'Old bar',
        );
        expect(
          await NotificationService.instance.scheduleUseCheck(check),
          isFalse,
        );
        final kept = await NotificationService.instance.peekPendingUseCheck();
        expect(kept?.trigger, UseCheckTrigger.zoneVisit);
        expect(kept?.zoneName, 'Old bar');
      },
    );
  });
}
