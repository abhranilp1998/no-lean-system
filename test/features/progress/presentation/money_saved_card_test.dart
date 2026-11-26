import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/core/utils/formatters.dart';
import 'package:no_lean/features/progress/presentation/widgets/money_saved_card.dart';
import 'package:no_lean/features/recovery/domain/money_saved.dart';
import 'package:no_lean/features/settings/presentation/money_saved_dialogs.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildNoLeanTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

MoneySavedSnapshot snap({
  double daily = 120,
  Duration clean = const Duration(days: 18),
  SavingsGoal? goal,
  double? other,
  bool subtract = false,
  AppCurrency currency = AppCurrency.inr,
  double? spendPerBottle,
  double? usualDailyMl,
}) => computeMoneySaved(
  dailySpend: daily,
  bottleMl: 100,
  spendPerBottle: spendPerBottle,
  usualDailyMl: usualDailyMl,
  cleanDuration: clean,
  events: const [],
  lastDose: DateTime(2026, 10, 1),
  currency: currency,
  subtractOtherCosts: subtract,
  goal: goal,
);

void main() {
  testWidgets('prompt card asks to set a usual day when spend is unset', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        MoneySavedCard(
          snapshot: snap(daily: 0),
          onSetSpend: () => tapped = true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('money-saved-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('money-saved-prompt-title')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('money-saved-copy')), findsOneWidget);
    expect(
      (tester
                  .widget<Text>(find.byKey(const ValueKey('money-saved-copy')))
                  .data ??
              '')
          .toLowerCase(),
      contains('usual day'),
    );
    await tester.tap(find.byKey(const ValueKey('money-saved-set-spend')));
    expect(tapped, isTrue);
    expect(find.byKey(const ValueKey('goal-jar')), findsNothing);
  });

  testWidgets('set card shows the kept amount, warm copy and a goal jar', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MoneySavedCard(
          snapshot: snap(
            spendPerBottle: 240,
            usualDailyMl: 50,
            goal: const SavingsGoal(name: 'New phone', target: 4000),
          ),
          onSetSpend: () {},
          onSetGoal: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('money-saved-amount')), findsOneWidget);
    expect(find.textContaining('₹2,160'), findsWidgets);
    expect(find.byKey(const ValueKey('goal-jar')), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-jar-name')), findsOneWidget);
    expect(find.text('New phone'), findsOneWidget);
    expect(find.textContaining('54%'), findsWidgets);
    expect(find.text('EDIT TYPICAL SPEND'), findsOneWidget);
    expect(find.text('EDIT GOAL'), findsOneWidget);
  });

  testWidgets('spend setup dialog previews the derived daily rate', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SpendSetupDialog(
          currency: AppCurrency.inr,
          spendPerBottle: 240,
          usualDailyMl: 50,
          dailySpend: 120,
          bottleMl: 100,
          subtractOtherCosts: false,
        ),
      ),
    );
    expect(find.text('TYPICAL SPEND'), findsOneWidget);
    expect(find.byKey(const ValueKey('spend-preview')), findsOneWidget);
    expect(find.textContaining('₹120'), findsWidgets);
    expect(find.text('SAVE TYPICAL SPEND'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal dialog requires a name and target', (tester) async {
    await tester.pumpWidget(
      wrap(const SavingsGoalDialog(currency: AppCurrency.inr)),
    );
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pump();
    expect(find.text('Give the goal a short name.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('goal-name')), 'Trip');
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pump();
    expect(find.text('Enter a target amount above zero.'), findsOneWidget);
  });

  testWidgets('goal jar hides a missing photo file and still shows the name', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MoneySavedCard(
          snapshot: snap(
            goal: const SavingsGoal(
              name: 'Headphones',
              target: 4000,
              photoPath: '/tmp/does-not-exist-goal.jpg',
            ),
          ),
          onSetSpend: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('goal-jar-photo')), findsNothing);
    expect(find.text('Headphones'), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-jar')), findsOneWidget);
  });
}
