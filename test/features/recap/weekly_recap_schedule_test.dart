import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recap/domain/weekly_recap_schedule.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to Sunday 6 PM', () {
    final slot = weeklyRecapSlot(const NotificationPrefs());
    expect(slot.weekday, DateTime.sunday);
    expect(slot.minuteOfDay, 18 * 60);
  });

  test('quiet hours that do not cover 6 PM leave the slot alone', () {
    final slot = weeklyRecapSlot(
      const NotificationPrefs(quietHoursEnabled: true),
    );
    expect(slot, const WeeklyRecapSlot(weekday: 7, minuteOfDay: 18 * 60));
  });

  test('quiet hours covering 6 PM push it just after they end', () {
    final slot = weeklyRecapSlot(
      const NotificationPrefs(
        quietHoursEnabled: true,
        quietHours: RiskWindow(startMinutes: 17 * 60, endMinutes: 20 * 60),
      ),
    );
    expect(slot.minuteOfDay, 20 * 60 + 1);
    final at = nextWeeklyOccurrence(DateTime(2026, 11, 27), slot);
    expect(
      const NotificationPrefs(
        quietHoursEnabled: true,
        quietHours: RiskWindow(startMinutes: 17 * 60, endMinutes: 20 * 60),
      ).allows(NotificationKind.weeklyRecap, at),
      isTrue,
    );
  });

  test('quiet hours ending at 23:59 roll to Monday 00:00', () {
    final slot = weeklyRecapSlot(
      const NotificationPrefs(
        quietHoursEnabled: true,
        quietHours: RiskWindow(startMinutes: 12 * 60, endMinutes: 23 * 60 + 59),
      ),
    );
    expect(slot.weekday, DateTime.monday);
    expect(slot.minuteOfDay, 0);
  });

  test('next occurrence is the coming Sunday, strictly in the future', () {
    const slot = WeeklyRecapSlot(weekday: 7, minuteOfDay: 18 * 60);
    // Friday 27 Nov 2026.
    expect(
      nextWeeklyOccurrence(DateTime(2026, 11, 27, 9), slot),
      DateTime(2026, 11, 29, 18),
    );
    // Sunday before 6 PM: today. Sunday after: next week.
    expect(
      nextWeeklyOccurrence(DateTime(2026, 11, 29, 17), slot),
      DateTime(2026, 11, 29, 18),
    );
    expect(
      nextWeeklyOccurrence(DateTime(2026, 11, 29, 18), slot),
      DateTime(2026, 12, 6, 18),
    );
  });

  test(
    'the recap is not critical: muted in quiet hours, delivered outside',
    () {
      expect(NotificationKind.weeklyRecap.isCritical, isFalse);
      const prefs = NotificationPrefs(quietHoursEnabled: true);
      expect(
        prefs.allows(NotificationKind.weeklyRecap, DateTime(2026, 11, 29, 23)),
        isFalse,
      );
      expect(
        prefs.allows(NotificationKind.weeklyRecap, DateTime(2026, 11, 29, 18)),
        isTrue,
      );
    },
  );

  test(
    'text carries no numbers or substance words, and private mode is neutral',
    () {
      const banned = [
        'lean',
        'codeine',
        'benzo',
        'alcohol',
        'craving',
        'slip',
        'relapse',
        'clean',
        'streak',
        'sos',
      ];
      final text = '$weeklyRecapNotificationTitle $weeklyRecapNotificationBody'
          .toLowerCase();
      expect(RegExp(r'\d').hasMatch(text), isFalse);
      for (final word in banned) {
        expect(text, isNot(contains(word)));
      }
      const hidden = NotificationPrefs(hideSensitive: true);
      final shown = hidden.textFor(
        weeklyRecapNotificationTitle,
        weeklyRecapNotificationBody,
      );
      expect(shown, same(neutralNotificationText));
    },
  );

  test('the service refuses to schedule a recap inside quiet hours', () async {
    NotificationService.instance.prefs = const NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
    );
    addTearDown(
      () => NotificationService.instance.prefs = const NotificationPrefs(),
    );
    final scheduled = await NotificationService.instance.scheduleWeeklyRecap(
      const WeeklyRecapSlot(weekday: DateTime.sunday, minuteOfDay: 23 * 60),
    );
    expect(scheduled, isFalse);
  });
}
