import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/cravings/presentation/craving_dialog.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/settings/presentation/settings_dialogs.dart';

import '../../support/recovery_fakes.dart';

Future<RecoveryController> pumpHost(
  WidgetTester tester, {
  String? stored,
  required Widget Function(BuildContext context, WidgetRef ref) child,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = RecoveryController(
    store: MemoryRecoveryStore(stored),
    relapseLock: FakeRelapseLock(),
    scheduleCravingCheck: (_) async => true,
    cancelCravingCheck: () async {},
  );
  await c.load();
  final container = ProviderContainer(
    overrides: [recoveryProvider.overrideWith((ref) => c)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) => child(context, ref)),
        ),
      ),
    ),
  );
  return c;
}

void main() {
  testWidgets('craving dialog stores the stress rating', (tester) async {
    final c = await pumpHost(
      tester,
      child: (context, ref) => TextButton(
        onPressed: () => showCravingDialog(context, ref),
        child: const Text('CRAVE'),
      ),
    );
    await tester.tap(find.text('CRAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('craving-stress-5')));
    await tester.pump();
    expect(find.text('STRESS (OPTIONAL) // MAX'), findsOneWidget);
    await tester.tap(find.text('LOG IT'));
    await tester.pumpAndSettle();
    final craving = c.events.singleWhere(
      (e) => e.type == RecoveryEventType.craving,
    );
    expect(craving.metadata['stress'], 5);
    expect(find.text('CRAVING LOGGED // RECHECK IN 15 MIN.'), findsOneWidget);
  });

  testWidgets('RECHECK DUE card records the 15-minute outcome', (tester) async {
    final at = DateTime.now().subtract(const Duration(minutes: 20));
    final stored = jsonEncode({
      'stateVersion': 12,
      'events': [
        {
          'id': 'base',
          'type': 'recoveryStart',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
          'metadata': {},
        },
        {
          'id': 'crave-1',
          'type': 'craving',
          'timestamp': at.toIso8601String(),
          'metadata': {'intensity': 7, 'trigger': 'Habit'},
        },
      ],
    });
    final c = await pumpHost(
      tester,
      stored: stored,
      child: (context, ref) => const CravingRecheckCard(),
    );
    await tester.pump();
    expect(find.text('RECHECK DUE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('craving-recheck-card')));
    await tester.pumpAndSettle();
    expect(find.text('It was 7/10. How strong is it now?'), findsOneWidget);
    // Drag the slider fully left: the craving is gone.
    await tester.drag(
      find.byKey(const ValueKey('recheck-intensity')),
      const Offset(-1000, 0),
    );
    await tester.pump();
    expect(find.text('GONE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recheck-save')));
    await tester.pumpAndSettle();
    final check = c.events.singleWhere(
      (e) => e.type == RecoveryEventType.cravingCheck,
    );
    expect(check.metadata['cravingId'], 'crave-1');
    expect(check.metadata['outcome'], 'gone');
    expect(find.text('RECHECK DUE'), findsNothing);
  });

  testWidgets('bottle size dialog saves a preset and a custom size', (
    tester,
  ) async {
    final c = await pumpHost(
      tester,
      child: (context, ref) => TextButton(
        onPressed: () => showBottleSizeDialog(context, ref),
        child: const Text('BOTTLE'),
      ),
    );
    await tester.tap(find.text('BOTTLE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bottle-size-250')));
    await tester.tap(find.byKey(const ValueKey('bottle-size-save')));
    await tester.pumpAndSettle();
    expect(c.bottleMl, 250);

    await tester.tap(find.text('BOTTLE'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bottle-size-custom')),
      '5',
    );
    await tester.tap(find.byKey(const ValueKey('bottle-size-save')));
    await tester.pump();
    expect(find.text('Enter a size from 10 to 2000 ml.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('bottle-size-custom')),
      '180',
    );
    await tester.tap(find.byKey(const ValueKey('bottle-size-save')));
    await tester.pumpAndSettle();
    expect(c.bottleMl, 180);
  });
}
