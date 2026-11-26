import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/cravings/domain/urge_ride.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/timeline/presentation/widgets/event_tile.dart';

void main() {
  testWidgets('a finished ride shows a human label, not raw metadata', (
    tester,
  ) async {
    final start = RecoveryEvent.create(
      type: RecoveryEventType.craving,
      timestamp: DateTime(2026, 11, 26, 21),
      metadata: {
        'intensity': 6,
        'trigger': 'Ride it out',
        'note': 'Ten-minute ride',
        'urgeRide': true,
      },
    );
    final ride = UrgeRide(
      id: 'x',
      startedAt: start.timestamp,
      endedAt: start.timestamp.add(const Duration(minutes: 10)),
      outcome: UrgeRideOutcome.yes,
      activity: UrgeRideActivity.walk,
      intensityBefore: 6,
    );
    final check = RecoveryEvent.create(
      type: RecoveryEventType.cravingCheck,
      timestamp: ride.endedAt,
      metadata: ride.checkMetadata(start.id),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(body: EventTile(event: check)),
        ),
      ),
    );
    expect(find.text('RIDE IT OUT // WALK // IT PASSED'), findsOneWidget);
    expect(find.text('You stayed with it.'), findsOneWidget);
    expect(find.textContaining('URGERIDE'), findsNothing);
  });
}
