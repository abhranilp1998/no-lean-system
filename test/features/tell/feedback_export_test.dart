import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/tell/data/feedback_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('export text holds only notes and timestamps', () {
    final out = formatFeedbackExport([
      FeedbackNote(at: DateTime(2026, 11, 4, 10), text: 'timer\nis slow'),
    ], now: DateTime(2026, 11, 4, 12));
    expect(out, contains('NO LEAN feedback for AP'));
    expect(out, contains('1 note\n'));
    expect(out, contains('timer is slow'));
  });

  test('export shares saved notes, skips when empty', () async {
    final store = FeedbackStore();
    String? sent;
    Future<void> fake(String t, String s) async => sent = t;
    expect(await exportFeedbackToAp(store, share: fake), isFalse);
    expect(sent, isNull);
    await store.add('add dark mode');
    await store.add('love the widget');
    expect(await exportFeedbackToAp(store, share: fake), isTrue);
    expect(sent, contains('2 notes'));
    expect(sent, contains('love the widget'));
  });
}
