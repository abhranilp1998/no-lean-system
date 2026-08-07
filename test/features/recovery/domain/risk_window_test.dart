import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  group('RiskWindow', () {
    test('detects times inside a daytime window', () {
      const window = RiskWindow(
        startMinutes: 17 * 60 + 30,
        endMinutes: 20 * 60,
      );

      expect(window.contains(DateTime(2026, 8, 7, 17, 29)), isFalse);
      expect(window.contains(DateTime(2026, 8, 7, 17, 30)), isTrue);
      expect(window.contains(DateTime(2026, 8, 7, 19, 15)), isTrue);
      expect(window.contains(DateTime(2026, 8, 7, 20)), isTrue);
      expect(window.contains(DateTime(2026, 8, 7, 20, 1)), isFalse);
    });

    test('supports windows that cross midnight', () {
      const window = RiskWindow(startMinutes: 22 * 60, endMinutes: 2 * 60);

      expect(window.contains(DateTime(2026, 8, 7, 23)), isTrue);
      expect(window.contains(DateTime(2026, 8, 8, 1, 30)), isTrue);
      expect(window.contains(DateTime(2026, 8, 8, 12)), isFalse);
    });

    test('distributes four reminders within the configured range', () {
      const window = RiskWindow(
        startMinutes: 17 * 60 + 30,
        endMinutes: 20 * 60,
      );

      expect(window.reminderMinutes(), [1050, 1087, 1125, 1162]);
      expect(window.label, '17:30—20:00');
    });

    test('round-trips through JSON', () {
      const window = RiskWindow(startMinutes: 23 * 60, endMinutes: 90);

      final restored = RiskWindow.fromJson(window.toJson());

      expect(restored.startMinutes, window.startMinutes);
      expect(restored.endMinutes, window.endMinutes);
    });
  });
}
