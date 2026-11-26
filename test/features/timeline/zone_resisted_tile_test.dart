import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/timeline/presentation/widgets/event_tile.dart';

Future<void> show(WidgetTester tester, RecoveryEvent event) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(body: EventTile(event: event)),
        ),
      ),
    );

void main() {
  testWidgets('a resisted zone shows in history with the place', (
    tester,
  ) async {
    await show(
      tester,
      RecoveryEvent.create(
        type: RecoveryEventType.cleanCheckIn,
        metadata: {'zoneResisted': true, 'zoneName': 'Old bar'},
      ),
    );
    expect(find.text('ZONE RESISTED // Old bar'), findsOneWidget);
    expect(find.text('Stayed clean after the visit.'), findsOneWidget);
    expect(find.textContaining('ZONERESISTED'), findsNothing);
  });

  testWidgets('a resisted zone without a saved place is still celebrated', (
    tester,
  ) async {
    await show(
      tester,
      RecoveryEvent.create(
        type: RecoveryEventType.cleanCheckIn,
        metadata: {'zoneResisted': true},
      ),
    );
    expect(find.text('ZONE RESISTED'), findsOneWidget);
  });

  testWidgets('an old plain check-in looks exactly as before', (tester) async {
    final old = RecoveryEvent.create(type: RecoveryEventType.cleanCheckIn);
    await show(tester, old);
    expect(find.textContaining('ZONE RESISTED'), findsNothing);
  });
}
