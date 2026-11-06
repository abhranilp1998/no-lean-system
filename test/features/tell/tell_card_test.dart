import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/use_check.dart';
import 'package:no_lean/features/tell/data/feedback_store.dart';
import 'package:no_lean/features/tell/presentation/tell_me_anything_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

void main() {
  Future<void> say(WidgetTester t, String s) async {
    await t.enterText(find.byKey(const ValueKey('tell-input')), s);
    await t.tap(find.byKey(const ValueKey('tell-submit')));
    await t.pumpAndSettle();
  }

  testWidgets('offers the matching action; feedback is kept on-device', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final queued = <UseCheck>[];
    final recovery = RecoveryController(
      relapseLock: FakeRelapseLock(),
      scheduleUseCheck: (c) async {
        queued.add(c);
        return true;
      },
      cancelUseCheck: () async {},
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [recoveryProvider.overrideWith((_) => recovery)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TellMeAnythingCard()),
          ),
        ),
      ),
    );
    await say(t, 'I relapsed 2 hours ago');
    expect(find.byKey(const ValueKey('tell-log-relapse')), findsOneWidget);
    await say(t, 'about to buy, craving hard');
    expect(find.byKey(const ValueKey('tell-open-sos')), findsOneWidget);
    // "About to use" queues (A)'s follow-up.
    expect(queued.single.trigger, UseCheckTrigger.aboutToUse);
    await say(t, 'the notification button is broken');
    expect(find.textContaining('Saved for AP'), findsOneWidget);
    final notes = await FeedbackStore().load();
    expect(notes.single.text, 'the notification button is broken');
    expect(notes.single.at.isUtc, isTrue);
  });
}
