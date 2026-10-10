import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:no_lean/features/zones/domain/zone_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(recoveryProvider).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('hide sensitive content toggles neutral notifications', (
    tester,
  ) async {
    final container = await pumpSettings(tester);
    final toggle = find.byKey(const ValueKey('settings-hide-sensitive'));
    await tester.scrollUntilVisible(toggle, 300);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      container.read(recoveryProvider).notificationPrefs.hideSensitive,
      isTrue,
    );
    expect(
      find.textContaining('Notifications read "Reminder"'),
      findsOneWidget,
    );
  });

  testWidgets('quiet hours dialog saves an enabled window', (tester) async {
    final container = await pumpSettings(tester);
    final action = find.byKey(const ValueKey('settings-quiet-hours'));
    await tester.scrollUntilVisible(action, 300);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('QUIET HOURS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quiet-hours-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quiet-hours-save')));
    await tester.pumpAndSettle();
    final prefs = container.read(recoveryProvider).notificationPrefs;
    expect(prefs.quietHoursEnabled, isTrue);
    expect(find.textContaining('risk + zone alerts still on'), findsOneWidget);
  });

  testWidgets('private home widget toggle saves the setting', (tester) async {
    final container = await pumpSettings(tester);
    final toggle = find.byKey(const ValueKey('settings-widget-privacy'));
    await tester.scrollUntilVisible(toggle, 300);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).widgetPrivacy, isTrue);
    expect(find.textContaining('no counter, streak'), findsOneWidget);
  });

  testWidgets('zone history: opt in, then clear with confirmation', (
    tester,
  ) async {
    final container = await pumpSettings(tester);
    final recovery = container.read(recoveryProvider);
    final toggle = find.byKey(const ValueKey('settings-zone-history'));
    await tester.scrollUntilVisible(toggle, 300);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-clear-zone-history')),
      findsNothing,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(recovery.zoneHistory, isTrue);

    final zone = await recovery.addZone(
      name: 'Old bar',
      latitude: 22.57,
      longitude: 88.36,
    );
    await recovery.recordZoneEntry(
      ZoneEntry.of(zone, DateTime(2026, 10, 9, 21), 'app'),
    );
    await tester.pumpAndSettle();
    final clear = find.byKey(const ValueKey('settings-clear-zone-history'));
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 recorded entry'), findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-clear-zone-history')));
    await tester.pumpAndSettle();
    expect(recovery.zoneEntryCount, 0);
    expect(
      find.byKey(const ValueKey('settings-clear-zone-history')),
      findsNothing,
    );
  });

  testWidgets('position notification toggle is on by default and turns off', (
    tester,
  ) async {
    final container = await pumpSettings(tester);
    expect(container.read(recoveryProvider).positionNotification, isTrue);
    final toggle = find.byKey(const ValueKey('settings-position-notification'));
    await tester.scrollUntilVisible(toggle, 300);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('always-on position status'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).positionNotification, isFalse);
    expect(find.textContaining('zone alerts still work'), findsOneWidget);
  });

  testWidgets('app lock is a disabled "coming soon" placeholder', (
    tester,
  ) async {
    await pumpSettings(tester);
    final tile = find.byKey(const ValueKey('settings-app-lock'));
    await tester.scrollUntilVisible(tile, 300);
    await tester.pumpAndSettle();
    expect(find.text('App lock (coming soon)'), findsOneWidget);
    expect(find.textContaining('not available yet'), findsOneWidget);
    final ink = tester.widget<InkWell>(
      find.descendant(of: tile, matching: find.byType(InkWell)),
    );
    expect(ink.onTap, isNull);
  });
}
