import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
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
}
