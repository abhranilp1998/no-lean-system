import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/emergency/presentation/emergency_screen.dart';
import 'package:no_lean/features/withdrawal/domain/withdrawal_guide.dart';
import 'package:no_lean/features/withdrawal/presentation/withdrawal_guide_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stage boundaries', () {
    expect(stageFor(const Duration(hours: 5)).id, 'early');
    expect(stageFor(const Duration(hours: 36)).id, 'peak');
    expect(stageFor(const Duration(days: 4)).id, 'easing');
    expect(stageFor(const Duration(days: 20)).id, 'post_acute');
    expect(easesText(const Duration(hours: 36)), contains('36 hours'));
  });

  test('red flags and json round trip', () {
    final c = SymptomCheckIn(
      at: DateTime(2026, 11, 4),
      severities: {Symptom.cramps: 2, Symptom.chestPain: 1},
    );
    expect(c.hasRedFlag, isTrue);
    final back = SymptomCheckIn.fromJson(c.toJson())!;
    expect(back.severities, c.severities);
    expect(SymptomCheckIn.fromJson({'at': 'x'}), isNull);
    expect(
      SymptomCheckIn(
        at: DateTime(2026),
        severities: {Symptom.aches: 3},
      ).hasRedFlag,
      isFalse,
    );
  });

  test('relief tips carry cautions', () {
    final tips = reliefFor({Symptom.diarrhoea});
    expect(tips.map((t) => t.title), contains('Loperamide for diarrhoea'));
    expect(
      tips.firstWhere((t) => t.title.startsWith('Loperamide')).body,
      contains('12 mg'),
    );
    expect(generalDonts.first, contains('overdose'));
  });

  testWidgets('screen shows stage and red flag after check-in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: WithdrawalGuideScreen(cleanOverride: Duration(hours: 36)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('The peak'), findsWidgets);
    expect(find.byKey(const Key('you-are-here')), findsOneWidget);
    expect(find.byKey(const Key('comfort-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sym-chestPain')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('save-checkin')));
    await tester.tap(find.byKey(const Key('save-checkin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('red-flag-card')), findsOneWidget);
    expect(find.text('See a doctor today'), findsOneWidget);
    await tester.tap(find.byKey(const Key('doctor-yes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('doctor-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('support-no')));
    await tester.pumpAndSettle();
    expect(find.text('Your way'), findsOneWidget);
    expect(find.textContaining('Call '), findsNothing);
    expect(find.byKey(const Key('open-sos')), findsWidgets);
    expect(find.textContaining('14416'), findsNothing);
    await tester.tap(find.byKey(const Key('open-sos')).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EmergencyScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 10));
  });
}
