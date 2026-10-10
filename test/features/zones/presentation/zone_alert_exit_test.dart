import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/zones/domain/zone_alert_copy.dart';
import 'package:no_lean/features/zones/presentation/zone_alert_screen.dart';

/// Guards the user's rule: the full-screen zone alert never traps. The top
/// close button and "I'M LEAVING" each exit in one tap.
void main() {
  Future<List<ZoneAlertChoice?>> pumpAlert(WidgetTester tester) async {
    final results = <ZoneAlertChoice?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await ZoneAlertScreen.show(
                context,
                const ZoneAlertCopy(title: 'ZONE', body: 'Body'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zone-alert-screen')), findsOneWidget);
    return results;
  }

  for (final key in ['zone-alert-close', 'zone-alert-exit']) {
    testWidgets('$key exits the alert in one tap', (tester) async {
      final results = await pumpAlert(tester);
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('zone-alert-screen')), findsNothing);
      expect(results, [ZoneAlertChoice.exit]);
    });
  }
}
