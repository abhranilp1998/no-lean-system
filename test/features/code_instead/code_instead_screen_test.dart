import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/code_instead/domain/code_tasks.dart';
import 'package:no_lean/features/code_instead/presentation/code_instead_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
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

  late DateTime now;

  Future<RecoveryController> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    now = DateTime(2026, 10, 9, 20);
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
          home: CodeInsteadScreen(source: 'dashboard', clock: () => now),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  Iterable<RecoveryEvent> sessions(RecoveryController c) =>
      c.events.where((e) => e.type == RecoveryEventType.codeSession);

  Future<void> advance(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('a full block is logged as completed with its task', (
    tester,
  ) async {
    final controller = await pumpScreen(tester);
    expect(find.text(codeTasks.first.text), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('code-minutes-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('code-start')));
    await tester.pump();
    expect(find.text('05:00'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.text('03:00'), findsOneWidget);
    await advance(tester, const Duration(minutes: 4));
    await tester.pumpAndSettle();

    final event = sessions(controller).single;
    expect(event.metadata['completed'], isTrue);
    expect(event.metadata['durationSeconds'], 300);
    expect(event.metadata['plannedSeconds'], 300);
    expect(event.metadata['taskId'], codeTasks.first.id);
    expect(event.metadata['source'], 'dashboard');
    expect(find.text('BLOCK DONE'), findsOneWidget);

    // The next block rotates to a different task.
    await tester.tap(find.byKey(const ValueKey('code-again')));
    await tester.pump();
    expect(find.text(codeTasks[1].text), findsOneWidget);
  });

  testWidgets('stopping under a minute logs nothing; later stops are logged', (
    tester,
  ) async {
    final controller = await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('code-start')));
    await tester.pump();
    await advance(tester, const Duration(seconds: 30));
    await tester.tap(find.byKey(const ValueKey('code-stop')));
    await tester.pumpAndSettle();
    expect(sessions(controller), isEmpty);
    expect(find.text('STOPPED UNDER A MINUTE // NOT LOGGED.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('code-again')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('code-start')));
    await tester.pump();
    await advance(tester, const Duration(minutes: 3));
    await tester.tap(find.byKey(const ValueKey('code-stop')));
    await tester.pumpAndSettle();
    final event = sessions(controller).single;
    expect(event.metadata['completed'], isFalse);
    expect(event.metadata['durationSeconds'], 180);
  });

  testWidgets('TASK DONE ends early as completed; OTHER TASK rotates', (
    tester,
  ) async {
    final controller = await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('code-skip')));
    await tester.pump();
    expect(find.text(codeTasks[1].text), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('code-start')));
    await tester.pump();
    await advance(tester, const Duration(minutes: 7));
    await tester.tap(find.byKey(const ValueKey('code-done')));
    await tester.pumpAndSettle();
    final event = sessions(controller).single;
    expect(event.metadata['completed'], isTrue);
    expect(event.metadata['taskId'], codeTasks[1].id);
    expect(event.metadata['durationSeconds'], 420);
  });
}
