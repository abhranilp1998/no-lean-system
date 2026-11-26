import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/dates/domain/bundled_dates.dart';
import 'package:no_lean/features/dates/domain/high_risk_dates.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  final now = DateTime(2026, 11, 27, 12, 0); // after 2026 Diwali (8 Nov)

  test('bundled festivals list explicit dates through 2030, no calculator', () {
    final ids = bundledFestivals.map((f) => f.id).toSet();
    expect(
      ids,
      containsAll([
        'durga_puja',
        'diwali',
        'holi',
        'nye',
        'christmas',
        'shivaratri',
        'eid_fitr',
        'eid_adha',
        'raksha_bandhan',
        'ganesh',
        'valentines',
      ]),
    );
    for (final festival in bundledFestivals) {
      expect(festival.dates, isNotEmpty);
      for (final raw in festival.dates) {
        expect(raw, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        final date = parseDateOnly(raw);
        expect(date.year, inInclusiveRange(2026, 2031));
      }
    }
    DateTime diwali(int year) => bundledFestivals
        .firstWhere((f) => f.id == 'diwali')
        .parsedDates
        .firstWhere((d) => d.year == year);
    expect(diwali(2026), DateTime(2026, 11, 8));
    expect(diwali(2027), DateTime(2027, 10, 29));
    expect(diwali(2028), DateTime(2028, 10, 17));
    expect(diwali(2029), DateTime(2029, 11, 5));
    expect(diwali(2030), DateTime(2030, 10, 26));

    DateTime holi(int year) => bundledFestivals
        .firstWhere((f) => f.id == 'holi')
        .parsedDates
        .firstWhere((d) => d.year == year);
    expect(holi(2026), DateTime(2026, 3, 4));
    expect(holi(2027), DateTime(2027, 3, 23));
  });

  test('upcoming lists Christmas and NYE after Diwali 2026 has passed', () {
    final upcoming = upcomingHighRiskDates(
      now: now,
      disabledBundledIds: const {},
      customDates: const [],
    );
    expect(
      upcoming.map((e) => e.title),
      containsAll(["Christmas", "New Year's Eve"]),
    );
    expect(upcoming.map((e) => e.title), isNot(contains('Diwali')));
    final christmas = upcoming.firstWhere((e) => e.title == 'Christmas');
    expect(christmas.date, DateTime(2026, 12, 25));
    expect(christmas.daysUntil, 28);
  });

  test('disabled bundled festivals are omitted', () {
    final upcoming = upcomingHighRiskDates(
      now: now,
      disabledBundledIds: {'christmas', 'nye'},
      customDates: const [],
    );
    expect(upcoming.map((e) => e.sourceId), isNot(contains('christmas')));
    expect(upcoming.map((e) => e.sourceId), isNot(contains('nye')));
  });

  test('annual custom dates roll to next year after they pass', () {
    final custom = CustomHighRiskDate(
      id: 'b1',
      name: "Asha's birthday",
      kind: CustomDateKind.birthday,
      month: 3,
      day: 12,
    );
    final upcoming = upcomingHighRiskDates(
      now: DateTime(2026, 3, 13),
      disabledBundledIds: bundledFestivals.map((f) => f.id).toSet(),
      customDates: [custom],
    );
    expect(upcoming, hasLength(1));
    expect(upcoming.single.date, DateTime(2027, 3, 12));
    expect(upcoming.single.daysUntil, 364);
  });

  test('one-off exam date appears only that day', () {
    final exam = CustomHighRiskDate(
      id: 'e1',
      name: 'GATE result',
      kind: CustomDateKind.exam,
      once: DateTime(2026, 12, 10),
    );
    final upcoming = upcomingHighRiskDates(
      now: DateTime(2026, 12, 1),
      disabledBundledIds: bundledFestivals.map((f) => f.id).toSet(),
      customDates: [exam],
      horizonDays: 40,
    );
    expect(upcoming.single.title, 'GATE result');
    expect(upcoming.single.date, DateTime(2026, 12, 10));
    expect(
      upcomingHighRiskDates(
        now: DateTime(2026, 12, 11),
        disabledBundledIds: bundledFestivals.map((f) => f.id).toSet(),
        customDates: [exam],
      ),
      isEmpty,
    );
  });

  test('payday clamps to the last day of short months', () {
    expect(monthlyOn(2026, 2, 31), DateTime(2026, 2, 28));
    expect(monthlyOn(2028, 2, 31), DateTime(2028, 2, 29));
    expect(monthlyOn(2026, 4, 31), DateTime(2026, 4, 30));
    final upcoming = upcomingHighRiskDates(
      now: DateTime(2026, 1, 30),
      disabledBundledIds: bundledFestivals.map((f) => f.id).toSet(),
      customDates: const [],
      paydayDay: 31,
      horizonDays: 40,
    );
    // Unique by source: only the next payday is listed.
    final paydays = upcoming.where((e) => e.kind == HighRiskKind.payday);
    expect(paydays, hasLength(1));
    expect(paydays.first.date, DateTime(2026, 1, 31));
  });

  test('worst weekday needs a min sample and a clear leader', () {
    RecoveryEvent ev(RecoveryEventType type, DateTime at) =>
        RecoveryEvent.create(
          type: type,
          timestamp: at,
          metadata: type == RecoveryEventType.craving
              ? {'intensity': 4, 'trigger': 'Stress'}
              : null,
        );

    // Four Saturdays — too few.
    final tooFew = [
      for (var i = 0; i < 4; i++)
        ev(RecoveryEventType.relapse, DateTime(2026, 10, 3 + i * 7, 21)),
    ];
    expect(detectWorstWeekday(tooFew, now: now), isNull);

    // 3 Sat, 3 Sun — tie, no leader.
    final tied = [
      ev(RecoveryEventType.relapse, DateTime(2026, 10, 3, 21)),
      ev(RecoveryEventType.relapse, DateTime(2026, 10, 10, 21)),
      ev(RecoveryEventType.craving, DateTime(2026, 10, 17, 21)),
      ev(RecoveryEventType.relapse, DateTime(2026, 10, 4, 21)),
      ev(RecoveryEventType.craving, DateTime(2026, 10, 11, 21)),
      ev(RecoveryEventType.relapse, DateTime(2026, 10, 18, 21)),
    ];
    expect(DateTime(2026, 10, 3).weekday, DateTime.saturday);
    expect(DateTime(2026, 10, 4).weekday, DateTime.sunday);
    expect(detectWorstWeekday(tied, now: now), isNull);

    final clear = [
      ...tied,
      ev(RecoveryEventType.relapse, DateTime(2026, 10, 24, 21)),
    ];
    expect(detectWorstWeekday(clear, now: now), DateTime.saturday);
  });

  test('nudge fires 3 days ahead at 10:30 and defers quiet hours', () {
    const prefs = NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
    );
    final christmas = UpcomingHighRisk(
      key: 'bundled:christmas:2026-12-25',
      title: 'Christmas',
      date: DateTime(2026, 12, 25),
      kind: HighRiskKind.bundled,
      daysUntil: 28,
    );
    final nudges = planHighRiskNudges(
      upcoming: [christmas],
      prefs: prefs,
      now: DateTime(2026, 11, 27, 12),
      remindersEnabled: true,
    );
    expect(nudges, hasLength(1));
    expect(nudges.single.fireAt, DateTime(2026, 12, 22, 10, 30));
    expect(nudges.single.body, contains('Christmas'));
    expect(nudges.single.body, contains('3 days'));
    expect(
      notificationCopyIsClean(
        NotificationText(title: nudges.single.title, body: nudges.single.body),
      ),
      isTrue,
    );

    // If 10:30 is inside quiet hours, defer to 07:01.
    const lateQuiet = NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 9 * 60, endMinutes: 12 * 60),
    );
    final deferred = planHighRiskNudges(
      upcoming: [christmas],
      prefs: lateQuiet,
      now: DateTime(2026, 11, 27, 12),
      remindersEnabled: true,
    );
    expect(deferred.single.fireAt, DateTime(2026, 12, 22, 12, 1));
  });

  test('inside the 3-day window still nudges once when there is no plan', () {
    final item = UpcomingHighRisk(
      key: 'bundled:christmas:2026-12-25',
      title: 'Christmas',
      date: DateTime(2026, 12, 25),
      kind: HighRiskKind.bundled,
      daysUntil: 2,
    );
    final nudges = planHighRiskNudges(
      upcoming: [item],
      prefs: const NotificationPrefs(),
      now: DateTime(2026, 12, 23, 16, 0),
      remindersEnabled: true,
    );
    expect(nudges, hasLength(1));
    expect(nudges.single.fireAt, DateTime(2026, 12, 23, 16, 1));
  });

  test('a saved plan or disabled reminders skip the nudge', () {
    final item = UpcomingHighRisk(
      key: 'k',
      title: 'Christmas',
      date: DateTime(2026, 12, 25),
      kind: HighRiskKind.bundled,
      daysUntil: 28,
      planNote: 'Stay with family',
    );
    expect(
      planHighRiskNudges(
        upcoming: [item],
        prefs: const NotificationPrefs(),
        now: now,
        remindersEnabled: true,
      ),
      isEmpty,
    );
    expect(
      planHighRiskNudges(
        upcoming: [item.copyWithoutPlan()],
        prefs: const NotificationPrefs(),
        now: now,
        remindersEnabled: false,
      ),
      isEmpty,
    );
  });

  test('private wording hides the date name; no copy uses substance words', () {
    final private = highRiskNudgeCopy(
      name: 'Diwali',
      daysUntil: 3,
      hideSensitive: true,
    );
    expect(private.title, neutralNotificationText.title);
    expect(private.body, neutralNotificationText.body);
    expect(private.body.toLowerCase(), isNot(contains('diwali')));
    expect(notificationCopyIsClean(private), isTrue);

    for (final festival in bundledFestivals) {
      final copy = highRiskNudgeCopy(
        name: festival.name,
        daysUntil: 3,
        hideSensitive: false,
      );
      expect(notificationCopyIsClean(copy), isTrue, reason: festival.name);
      expect(copy.body.toLowerCase().contains('lean'), isFalse);
      expect(copy.body.toLowerCase().contains('craving'), isFalse);
      expect(copy.body.toLowerCase().contains('relapse'), isFalse);
    }
    expect(
      notificationCopyIsClean(
        highRiskNudgeCopy(name: 'Payday', daysUntil: 1, hideSensitive: false),
      ),
      isTrue,
    );
  });

  test('high-risk date kind is non-critical so quiet hours mute it', () {
    expect(NotificationKind.highRiskDate.isCritical, isFalse);
    const prefs = NotificationPrefs(quietHoursEnabled: true);
    expect(
      prefs.allows(NotificationKind.highRiskDate, DateTime(2026, 12, 22, 23)),
      isFalse,
    );
    expect(
      prefs.allows(
        NotificationKind.highRiskDate,
        DateTime(2026, 12, 22, 10, 30),
      ),
      isTrue,
    );
  });

  test('plans and custom dates encode and decode', () {
    final custom = CustomHighRiskDate(
      id: 'x',
      name: 'Dad',
      kind: CustomDateKind.lossAnniversary,
      month: 8,
      day: 9,
    );
    final decoded = CustomHighRiskDate.tryParse(custom.toJson());
    expect(decoded, isNotNull);
    expect(decoded!.name, 'Dad');
    expect(decoded.kind, CustomDateKind.lossAnniversary);
    expect(decoded.month, 8);
    expect(decoded.day, 9);
    expect(decodePlans({'k': '  stay home  ', 'empty': '  '}), {
      'k': 'stay home',
    });
    expect(decodePaydayDay(31), 31);
    expect(decodePaydayDay(0), isNull);
    expect(decodePaydayDay('no'), isNull);
  });
}

extension on UpcomingHighRisk {
  UpcomingHighRisk copyWithoutPlan() => UpcomingHighRisk(
    key: key,
    title: title,
    date: date,
    kind: kind,
    daysUntil: daysUntil,
    subtitle: subtitle,
    sourceId: sourceId,
  );
}
