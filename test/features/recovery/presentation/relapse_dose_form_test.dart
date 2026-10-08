import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/presentation/dose_safety_cards.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';

import '../../../support/recovery_fakes.dart';
import '../../../support/relapse_form.dart';

Future<RecoveryController> pumpSheet(
  WidgetTester tester, {
  String? stored,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = RecoveryController(
    store: MemoryRecoveryStore(stored),
    relapseLock: FakeRelapseLock(),
    // Outside the default risk window so the peak-hour gate stays closed.
    now: () => DateTime(2026, 9, 19, 12),
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRelapseLogSheet(context),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  return c;
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await revealInRelapseSheet(tester, field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await revealInRelapseSheet(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.tap(find.byKey(const ValueKey('save-relapse-events')));
  await tester.pumpAndSettle();
}

RecoveryEvent onlyRelapse(RecoveryController c) =>
    c.events.singleWhere((e) => e.type == RecoveryEventType.relapse);

void main() {
  testWidgets('comma-decimal bottles, rupee cost and stress are stored', (
    tester,
  ) async {
    final c = await pumpSheet(tester);
    await enter(tester, 'relapse-note-0', 'Bought two and a half after work.');
    await enter(tester, 'relapse-amount-0', '2,5');
    expect(find.text('= 250 ml at 100 ml per bottle'), findsOneWidget);
    await enter(tester, 'relapse-cost-0', '₹1,200');
    await tapKey(tester, 'relapse-stress-0-4');
    await save(tester);
    await tester.tap(find.text('CONFIRM RESET'));
    await tester.pumpAndSettle();
    final meta = onlyRelapse(c).metadata;
    expect(meta['amount'], 2.5);
    expect(meta['unit'], 'bottle');
    expect(meta['amountMl'], 250);
    expect(meta['bottleMl'], 100);
    expect(meta['cost'], 1200);
    expect(meta['stress'], 4);
    expect(meta.containsKey('amountSource'), isFalse);
  });

  testWidgets('250 with bottles asks "Did you mean 250 ml?" and switches', (
    tester,
  ) async {
    final c = await pumpSheet(tester);
    await enter(tester, 'relapse-note-0', 'Drank it straight from the bottle.');
    await enter(tester, 'relapse-amount-0', '250');
    await save(tester);
    expect(find.byKey(const ValueKey('dose-sanity-dialog')), findsOneWidget);
    expect(find.textContaining('Did you mean 250 ml?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dose-sanity-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM RESET'));
    await tester.pumpAndSettle();
    final meta = onlyRelapse(c).metadata;
    expect(meta['unit'], 'ml');
    expect(meta['amountMl'], 250);
  });

  testWidgets('EDIT on the sanity prompt saves nothing', (tester) async {
    final c = await pumpSheet(tester);
    await enter(tester, 'relapse-note-0', 'Typed the wrong unit by mistake.');
    await enter(tester, 'relapse-amount-0', '0.25');
    await tapKey(tester, 'relapse-unit-0-ml');
    await save(tester);
    expect(find.textContaining('Did you mean 0.25 L'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dose-sanity-edit')));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRM RELAPSE'), findsNothing);
    expect(c.events.where((e) => e.type == RecoveryEventType.relapse), isEmpty);
  });

  testWidgets('zero and junk amounts are rejected inline', (tester) async {
    final c = await pumpSheet(tester);
    await enter(tester, 'relapse-note-0', 'Checking the amount validation.');
    await enter(tester, 'relapse-amount-0', '0');
    await save(tester);
    await revealInRelapseSheet(
      tester,
      find.textContaining('Enter a number above 0'),
    );
    expect(find.textContaining('Enter a number above 0'), findsOneWidget);
    expect(c.events.where((e) => e.type == RecoveryEventType.relapse), isEmpty);
  });

  testWidgets('tablets keep out of ml; exact quantity text is parsed', (
    tester,
  ) async {
    final c = await pumpSheet(tester);
    await enter(tester, 'relapse-note-0', 'Took pills when I could not sleep.');
    await enter(tester, 'relapse-quantity-0', '250ml');
    await save(tester);
    await tester.tap(find.text('CONFIRM RESET'));
    await tester.pumpAndSettle();
    final meta = onlyRelapse(c).metadata;
    expect(meta['quantity'], '250ml');
    expect(meta['amountMl'], 250);
    expect(meta['amountSource'], 'parsed');
  });

  testWidgets('mixing warning and the overdose card appear while logging', (
    tester,
  ) async {
    final earlier = DateTime.now().subtract(const Duration(hours: 3));
    final state = jsonEncode({
      'stateVersion': 12,
      'events': [
        {
          'id': 'base',
          'type': 'recoveryStart',
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
          'metadata': {},
        },
        {
          'id': 'a1',
          'type': 'relapse',
          'timestamp': earlier.toIso8601String(),
          'metadata': {'relapseType': 'alcohol'},
        },
      ],
    });
    await pumpSheet(tester, stored: state);
    final mixing = find.byKey(const ValueKey('dose-warning-mixing'));
    await revealInRelapseSheet(tester, mixing);
    expect(mixing, findsOneWidget);
    expect(find.textContaining('codeine/lean + alcohol'), findsOneWidget);
    expect(find.byKey(const ValueKey('overdose-signs-card')), findsOneWidget);
    // Same calendar day as the earlier relapse (unless run just after
    // midnight), so the repeat-dose warning shows too.
    if (earlier.day == DateTime.now().day) {
      expect(
        find.byKey(const ValueKey('dose-warning-repeatDose')),
        findsOneWidget,
      );
    }
  });

  testWidgets('CALL 112 dials 112', (tester) async {
    Uri? dialed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OverdoseSignsCard(
              launcher: (uri) async {
                dialed = uri;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('call-112')));
    await tester.pump();
    expect(dialed, Uri(scheme: 'tel', path: '112'));
  });
}
