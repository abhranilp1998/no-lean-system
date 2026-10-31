import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/cravings/domain/craving_wave.dart';
import 'package:no_lean/features/cravings/presentation/craving_wave_screen.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

import 'craving_stress_recheck_test.dart' show pumpHost;

RecoveryEvent craving(DateTime at) => RecoveryEvent.create(
  type: RecoveryEventType.craving,
  timestamp: at,
  metadata: {'intensity': 6, 'trigger': 'Other', 'note': ''},
);

RecoveryEvent check(RecoveryEvent c, DateTime at, int intensity) =>
    RecoveryEvent.create(
      type: RecoveryEventType.cravingCheck,
      timestamp: at,
      metadata: {
        'cravingId': c.id,
        'intensity': intensity,
        'outcome': cravingCheckOutcome(6, intensity),
        'originalIntensity': 6,
      },
    );

void main() {
  test('last time it passed comes from the newest "passed" recheck', () {
    final a = craving(DateTime(2026, 10, 1, 18));
    final b = craving(DateTime(2026, 10, 2, 19));
    final events = [
      a,
      check(a, DateTime(2026, 10, 1, 18, 10), 3),
      check(a, DateTime(2026, 10, 1, 18, 22), 0),
      b,
      check(b, DateTime(2026, 10, 2, 19, 14), 0),
      craving(DateTime(2026, 10, 3, 19)), // never passed: ignored.
    ];
    final history = CravingWaveHistory.fromEvents(events);
    expect(history.passedMinutes, [14, 22]);
    expect(history.lastPassedMinutes, 14);
    final points = CravingWaveHistory.pointsFor(events, a.id);
    expect(points.map((p) => p.intensity), [6, 3, 0]);
    expect(points.last.minute, 22);
  });

  test('no history means no claim', () {
    expect(CravingWaveHistory.fromEvents(const []).lastPassedMinutes, isNull);
  });

  testWidgets("It's N, Still N and It passed log real events", (tester) async {
    final c = await pumpHost(
      tester,
      child: (context, ref) => TextButton(
        onPressed: () => CravingWaveScreen.open(context),
        child: const Text('WAVE'),
      ),
    );
    await tester.tap(find.text('WAVE'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.tap(find.byKey(const Key('wave-start')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      c.events.where((e) => e.type == RecoveryEventType.craving),
      hasLength(1),
    );
    await tester.tap(find.byKey(const Key('wave-still')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('wave-passed-button')));
    await tester.pump(const Duration(milliseconds: 200));
    final checks = c.events
        .where((e) => e.type == RecoveryEventType.cravingCheck)
        .map((e) => e.metadata['intensity'])
        .toList();
    expect(checks, [5, 0]);
    expect(find.byKey(const Key('wave-passed')), findsOneWidget);
  });
}
