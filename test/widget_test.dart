// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:no_lean/main.dart';

void main() {
  testWidgets('NO LEAN launches into the recovery counter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NoLeanApp()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('NO LEAN'), findsWidgets);
    expect(find.text('THE COUNTER'), findsOneWidget);
    expect(find.text('I WILL NOT BUY LEAN TODAY'), findsOneWidget);
  });
}
