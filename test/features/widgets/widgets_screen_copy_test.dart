import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/widgets/presentation/widgets_screen.dart';
import 'package:no_lean/features/widgets/services/widget_choice_service.dart';

import '../cravings/craving_stress_recheck_test.dart' show pumpHost;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String stored({required int daysAgo}) => jsonEncode({
    'stateVersion': RecoveryController.stateVersion,
    'events': [
      {
        'id': 'base',
        'type': 'recoveryStart',
        'timestamp': DateTime.now()
            .subtract(Duration(days: daysAgo, hours: 1))
            .toIso8601String(),
      },
    ],
  });

  Future<void> openPreview(WidgetTester tester, {required int daysAgo}) async {
    await pumpHost(
      tester,
      stored: stored(daysAgo: daysAgo),
      child: (context, ref) =>
          WidgetsScreen(service: WidgetChoiceService(enabled: false)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('widget preview says 1 DAY CLEAN, not 1 DAYS CLEAN', (
    tester,
  ) async {
    await openPreview(tester, daysAgo: 1);
    expect(find.text('1 DAY CLEAN'), findsWidgets);
    expect(find.text('1 DAYS CLEAN'), findsNothing);
  });

  testWidgets('widget preview keeps the plural for other counts', (
    tester,
  ) async {
    await openPreview(tester, daysAgo: 0);
    expect(find.text('0 DAYS CLEAN'), findsWidgets);
    await openPreview(tester, daysAgo: 2);
    expect(find.text('2 DAYS CLEAN'), findsWidgets);
  });
}
