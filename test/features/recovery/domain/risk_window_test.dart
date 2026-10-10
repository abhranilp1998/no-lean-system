import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  group('RiskWindow', () {
    test('defaults to the 17:00–21:00 peak window', () {
      const window = RiskWindow.defaultWindow();

      expect(window.label, '17:00—21:00');
      expect(window.contains(DateTime(2026, 8, 7, 18)), isTrue);
    });

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

    test('coverage keeps every old minute, including overnight boundaries', () {
      const evening = RiskWindow.defaultWindow();
      expect(evening.covers(evening), isTrue);
      expect(
        const RiskWindow(startMinutes: 960, endMinutes: 1320).covers(evening),
        isTrue,
      );
      expect(
        const RiskWindow(startMinutes: 1080, endMinutes: 1260).covers(evening),
        isFalse,
      );
      expect(
        const RiskWindow(startMinutes: 1020, endMinutes: 1259).covers(evening),
        isFalse,
      );
      expect(
        const RiskWindow(startMinutes: 120, endMinutes: 180).covers(evening),
        isFalse,
      );
      const overnight = RiskWindow(startMinutes: 1320, endMinutes: 120);
      expect(
        const RiskWindow(startMinutes: 1260, endMinutes: 180).covers(overnight),
        isTrue,
      );
      expect(
        const RiskWindow(startMinutes: 1380, endMinutes: 180).covers(overnight),
        isFalse,
      );
      expect(
        const RiskWindow(startMinutes: 0, endMinutes: 0).covers(overnight),
        isTrue,
      );
      expect(
        overnight.covers(const RiskWindow(startMinutes: 0, endMinutes: 0)),
        isFalse,
      );
    });
  });
}
