import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/companion/presentation/companion_hub_screen.dart';
import 'package:no_lean/features/companion/presentation/struggling_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester t, Widget w) async {
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 4, 20),
    );
    await t.runAsync(controller.load);
    t.view.physicalSize = const Size(1200, 8000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryProvider.overrideWith((ref) => controller),
          trustedContactProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(home: w),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('struggling: answer then see ideas and red flags', (t) async {
    await pump(
      t,
      StrugglingScreen(nowOverride: DateTime(2026, 11, 4, 20), seed: 1),
    );
    expect(find.text('Show me what helps'), findsOneWidget);
    await t.tap(find.text('Show me what helps'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('TRY ONE NOW'), findsOneWidget);
    expect(find.text('Ride the wave'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
    expect(find.textContaining('helpline'), findsNothing);
    for (final b in find.byType(IconButton).evaluate()) {
      final size = t.getSize(find.byWidget(b.widget));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('hub renders milestones and struggling button', (t) async {
    await pump(
      t,
      CompanionHubScreen(nowOverride: DateTime(2026, 11, 4, 20), seed: 2),
    );
    await t.pump(const Duration(seconds: 1));
    // First open asks about triggers; dismiss it.
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      Navigator.of(t.element(find.byType(BottomSheet))).pop();
      await t.pump(const Duration(milliseconds: 500));
    }
    expect(find.text("I'M STRUGGLING"), findsOneWidget);
    expect(find.text('MILESTONES (YOURS TO KEEP)'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
  });
}
