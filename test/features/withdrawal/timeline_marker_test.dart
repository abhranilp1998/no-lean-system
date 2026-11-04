import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/withdrawal/domain/withdrawal_personal.dart';
import 'package:no_lean/features/withdrawal/presentation/withdrawal_guide_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const c = Course(8, 24, 72, 168);
  // Weights 1 : 1.5 : 1.5 => boundaries at 0, 0.25, 0.625, 1.
  group('timelineFraction', () {
    test('positions at key hours', () {
      expect(timelineFraction(0, c), 0);
      expect(timelineFraction(12, c), closeTo(0.125, 1e-9));
      expect(timelineFraction(24, c), closeTo(0.25, 1e-9));
      // 47h is 23/48 = 47.9% through Peak.
      final f47 = timelineFraction(47, c);
      expect((f47 - 0.25) / 0.375, closeTo(23 / 48, 1e-9));
      expect(timelineFraction(72, c), closeTo(0.625, 1e-9));
      expect(timelineFraction(120, c), closeTo(0.8125, 1e-9));
      expect(timelineFraction(168, c), 1);
      expect(timelineFraction(500, c), 1);
    });
    test('clamps and relapse reset to 0', () {
      expect(timelineFraction(-5, c), 0);
      expect(timelineFraction(double.nan, c), 0);
      // After a relapse sinceLastUse restarts at 0h.
      expect(timelineFraction(0, c), 0);
    });
    test('monotonic', () {
      var last = -1.0;
      for (var h = 0.0; h <= 200; h += 0.5) {
        final f = timelineFraction(h, c);
        expect(f, greaterThanOrEqualTo(last));
        last = f;
      }
    });
  });

  for (final h in [0, 12, 24, 47, 72, 120, 168, 400]) {
    testWidgets('marker line, triangle and label are centred at ${h}h', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: WithdrawalGuideScreen(cleanOverride: Duration(hours: h)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byKey(const Key('stage-bar')));
      final line = tester.getRect(find.byKey(const Key('you-line')));
      final tri = tester.getRect(find.byKey(const Key('you-triangle')));
      final label = tester.getRect(find.byKey(const Key('you-are-here')));
      expect(tri.center.dx, closeTo(line.center.dx, 0.5));
      expect(line.left, greaterThanOrEqualTo(bar.left - 0.01));
      expect(line.right, lessThanOrEqualTo(bar.right + 0.01));
      expect(label.left, greaterThanOrEqualTo(bar.left - 0.01));
      expect(label.right, lessThanOrEqualTo(bar.right + 0.01));
      final f = timelineFraction(h.toDouble(), c);
      final expected = (bar.left + f * bar.width).clamp(
        bar.left + 1,
        bar.right - 1,
      );
      expect(line.center.dx, closeTo(expected, 0.5));
      if (f > 0.1 && f < 0.9) {
        expect(label.center.dx, closeTo(line.center.dx, 0.5));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
    });
  }
}
