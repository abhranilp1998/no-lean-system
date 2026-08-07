import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/utils/formatters.dart';

void main() {
  group('formatDuration', () {
    test('formats a duration for the app', () {
      const duration = Duration(days: 3, hours: 4, minutes: 5, seconds: 6);

      expect(formatDuration(duration), '3 days, 04:05:06');
    });

    test('formats a compact duration for the Android widget', () {
      const duration = Duration(days: 3, hours: 4, minutes: 5, seconds: 6);

      expect(formatDuration(duration, compact: true), '3d 04h 05m');
    });
  });

  test('dateKey uses a stable local calendar representation', () {
    expect(dateKey(DateTime(2026, 8, 7, 23, 59)), '2026-08-07');
  });
}
