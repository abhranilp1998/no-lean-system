import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/timeline/presentation/widgets/event_tile.dart';

void main() {
  testWidgets('rich relapse is unmistakable and uses human-readable facts', (
    tester,
  ) async {
    final event = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      metadata: {
        'relapseType': RelapseType.leanPlusAlcohol.name,
        'note': 'After work I ignored the exit plan.',
        'attemptedSos': true,
        'quantity': 'half a cup',
        'contextTags': ['After Work', 'Office Stress'],
        'streakLost': 8,
        'batchId': 'hidden',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(body: EventTile(event: event)),
        ),
      ),
    );

    expect(find.text('RELAPSE'), findsOneWidget);
    expect(find.text('LEAN + ALCOHOL'), findsOneWidget);
    expect(find.text('SOS ATTEMPTED'), findsOneWidget);
    expect(find.text('half a cup'), findsOneWidget);
    expect(find.text('After Work'), findsOneWidget);
    expect(find.text('Office Stress'), findsOneWidget);
    expect(find.text('8-DAY STREAK INTERRUPTED'), findsOneWidget);
    expect(find.textContaining('BATCHID'), findsNothing);
    expect(find.textContaining('RELAPSETYPE'), findsNothing);
  });

  testWidgets('legacy relapse remains readable after the visual upgrade', (
    tester,
  ) async {
    final event = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      metadata: {'postSos': false, 'streakLost': 3},
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(body: EventTile(event: event)),
        ),
      ),
    );

    expect(find.text('RELAPSE'), findsOneWidget);
    expect(find.text('LEGACY RELAPSE RECORD'), findsOneWidget);
    expect(find.text('3-DAY STREAK INTERRUPTED'), findsOneWidget);
  });

  testWidgets('relapse entry options menu is reachable by accessibility', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final event = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      metadata: {'relapseType': RelapseType.fullLean.name, 'streakLost': 2},
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(body: EventTile(event: event)),
        ),
      ),
    );

    // Before the fix the tile excluded the menu from semantics, so the
    // nearest node was the tile summary with no tap action.
    final node = tester.getSemantics(find.byTooltip('Entry options'));
    final data = node.getSemanticsData();
    expect(data.tooltip, 'Entry options');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.label, isNot(contains('Relapse recorded')));
    handle.dispose();
  });
}
