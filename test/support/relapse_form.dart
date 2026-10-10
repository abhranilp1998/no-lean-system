import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';

/// Scrolls the relapse sheet's list (either direction) until [finder] is
/// built, then brings it on screen. The list is lazy, so off-screen entries
/// may not exist until scrolled to.
Future<void> revealInRelapseSheet(WidgetTester tester, Finder finder) async {
  final list = find
      .descendant(
        of: find.byType(RelapseLogSheet),
        matching: find.byType(ListView),
      )
      .first;
  ScrollPosition position() => tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      )
      .position;
  for (final dy in [-300.0, 300.0]) {
    var last = double.nan;
    while (finder.evaluate().isEmpty && position().pixels != last) {
      last = position().pixels;
      await tester.drag(list, Offset(0, dy));
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isNotEmpty) break;
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
