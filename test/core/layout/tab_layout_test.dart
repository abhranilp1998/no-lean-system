import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/core/layout/tab_layout.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/cravings/presentation/craving_dialog.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  Future<RecoveryController> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    tester.view.padding = const FakeViewPadding(top: 80, bottom: 60);
    addTearDown(tester.view.reset);
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => controller)],
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

  testWidgets('every tab uses the shared layout and no nested Scaffold', (
    tester,
  ) async {
    await pumpApp(tester);
    final tabs = ['TODAY', 'CRAVINGS', 'PROGRESS', 'TIMELINE', 'SETTINGS'];
    final destinations = find.byType(NavigationDestination);
    expect(destinations, findsNWidgets(tabs.length));
    for (var i = 0; i < tabs.length; i++) {
      await tester.tap(destinations.at(i));
      await tester.pump(const Duration(milliseconds: 300));
      // Exactly one Scaffold (the shell's) and one tab list per tab.
      expect(find.byType(Scaffold), findsOneWidget, reason: 'tab $i');
      final list = tester.widget<ListView>(
        // Inactive IndexedStack tabs are offstage, so this finds the
        // visible tab only.
        find.descendant(
          of: find.byType(TabListView),
          matching: find.byType(ListView),
        ),
      );
      final padding = list.padding!.resolve(TextDirection.ltr);
      expect(padding.left, TabLayout.gutter, reason: 'tab $i');
      expect(padding.top, TabLayout.top, reason: 'tab $i');
      // The shell's Scaffold and SafeArea consume the system insets, so
      // every tab ends with the same clearance above the nav bar.
      expect(padding.bottom, TabLayout.bottomClearance, reason: 'tab $i');
      expect(
        list.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
    }
    expect(
      find.byType(TabListView, skipOffstage: false),
      findsNWidgets(tabs.length),
    );
  });

  testWidgets('the craving dialog stays usable with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => controller)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showCravingDialog(context, ref),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    // Simulate a tall soft keyboard (about 45% of the screen).
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'long day, old route');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final logIt = find.text('LOG IT');
    await tester.ensureVisible(logIt);
    await tester.pumpAndSettle();
    await tester.tap(logIt);
    await tester.pumpAndSettle();
    expect(controller.cravings.single.note, 'long day, old route');
  });
}
