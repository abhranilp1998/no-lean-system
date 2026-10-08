import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/features/code_instead/presentation/code_instead_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';
import 'package:no_lean/features/recovery/services/widget_action_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

void main() {
  final pending = <String>[];
  const channel = MethodChannel('no_lean/widget_actions');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pending.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'drainActions') {
            final actions = List<String>.of(pending);
            pending.clear();
            return actions;
          }
          return null;
        });
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
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
      UncontrolledProviderScope(container: container, child: const NoLeanApp()),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the widget CODE action opens one timer, even when repeated', (
    tester,
  ) async {
    await pumpApp(tester);
    pending.addAll(['code', 'code']);
    await WidgetActionService.instance.initialize();
    await tester.pumpAndSettle();
    expect(find.byType(CodeInsteadScreen), findsOneWidget);
    final screen = tester.widget<CodeInsteadScreen>(
      find.byType(CodeInsteadScreen),
    );
    expect(screen.source, 'widget');
  });

  testWidgets('the notification CODE INSTEAD action opens the timer', (
    tester,
  ) async {
    await pumpApp(tester);
    NotificationService.instance.debugEmitAction('action_code');
    await tester.pumpAndSettle();
    final screen = tester.widget<CodeInsteadScreen>(
      find.byType(CodeInsteadScreen),
    );
    expect(screen.source, 'notification');
  });

  testWidgets('the dashboard tile opens the timer', (tester) async {
    await pumpApp(tester);
    final tile = find.text('CODE INSTEAD');
    await tester.scrollUntilVisible(tile, 300);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final screen = tester.widget<CodeInsteadScreen>(
      find.byType(CodeInsteadScreen),
    );
    expect(screen.source, 'dashboard');
  });
}
