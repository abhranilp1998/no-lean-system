import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/withdrawal/data/symptom_checkin_store.dart';
import 'package:no_lean/features/withdrawal/domain/companion.dart';
import 'package:no_lean/features/withdrawal/domain/withdrawal_guide.dart';
import 'package:no_lean/features/withdrawal/domain/withdrawal_personal.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecoveryEvent relapse(DateTime at, double ml) => RecoveryEvent.create(
  type: RecoveryEventType.relapse,
  timestamp: at,
  metadata: {'relapseType': 'fullLean', 'amount': ml, 'unit': 'ml'},
);

RecoveryEvent craving(DateTime at) => RecoveryEvent.create(
  type: RecoveryEventType.craving,
  timestamp: at,
  metadata: {'intensity': 7, 'trigger': 'evening'},
);

void main() {
  final now = DateTime(2026, 11, 4, 10);
  const window = RiskWindow.defaultWindow();

  test('no data uses clean timer and typical course', () {
    final p = buildPlan(
      events: const [],
      cleanSince: now.subtract(const Duration(hours: 36)),
      now: now,
      riskWindow: window,
    );
    expect(p.noData, isTrue);
    expect(p.dose.level, DoseLevel.unknown);
    expect(p.stage.id, 'peak');
    expect(p.forecast.map((f) => f.label), [
      'Next 6 hours',
      'Tonight',
      'Tomorrow',
      'When it ends',
    ]);
  });

  test(
    'high dose stretches course; last relapse anchors clock; craving peak',
    () {
      final events = [
        for (var d = 30; d >= 3; d--)
          relapse(
            now.subtract(Duration(days: d, hours: 0)).copyWithHour(19),
            300,
          ),
        for (var d = 1; d <= 4; d++)
          craving(now.subtract(Duration(days: d)).copyWithHour(19)),
      ];
      final p = buildPlan(
        events: events,
        cleanSince: now.subtract(const Duration(days: 30)),
        now: now,
        riskWindow: window,
      );
      expect(p.dose.level, DoseLevel.high);
      expect(p.course.acuteEndH, 240);
      expect(p.anchorSource, 'your last logged use');
      expect(p.riskTonight, contains('7 PM'));
      expect(p.reasons.join(' '), contains('300 ml'));
    },
  );

  test('recent relapse puts plan in relapse mode with gentle copy', () {
    final p = buildPlan(
      events: [relapse(now.subtract(const Duration(hours: 2)), 50)],
      cleanSince: now.subtract(const Duration(days: 5)),
      now: now,
      riskWindow: window,
    );
    expect(p.inRelapse, isTrue);
    expect(acknowledgement(p, now), isNot(contains('fail')));
    expect(nextMove(p, null, now).title, 'Ride out the craving wave');
  });

  test('trend compares last two check-ins', () {
    SymptomCheckIn c(int v) => SymptomCheckIn(
      at: now,
      severities: {Symptom.aches: v, Symptom.cramps: v},
    );
    expect(checkInTrend([c(1), c(3)]), Trend.better);
    expect(checkInTrend([c(3), c(1)]), Trend.worse);
    expect(checkInTrend([c(2)]), Trend.none);
  });

  test('red flags are on/off', () {
    final back = SymptomCheckIn.fromJson({
      'at': now.toIso8601String(),
      's': {'chestPain': 3},
    })!;
    expect(back.severities[Symptom.chestPain], 1);
  });

  test('companion greeting, prefs and next moves', () {
    expect(greeting(DateTime(2026, 1, 1, 8), 'Abhi'), 'Good morning, Abhi.');
    expect(greeting(DateTime(2026, 1, 1, 20), ''), 'Good evening.');
    final p = const CompanionPrefs(
      doctor: Comfort.yes,
      supportLine: Comfort.no,
    );
    expect(p.asked, isTrue);
    expect(p.showSupportLine, isFalse);
    expect(CompanionPrefs.fromJson(p.toJson()).doctor, Comfort.yes);
    expect(const CompanionPrefs().supportNumber, isEmpty);
    final plan = buildPlan(
      events: const [],
      cleanSince: now.subtract(const Duration(hours: 36)),
      now: now,
      riskWindow: window,
    );
    final diarrhoea = SymptomCheckIn(
      at: now,
      severities: {Symptom.diarrhoea: 2},
    );
    expect(nextMove(plan, diarrhoea, now).title, 'Drink ORS now');
    expect(acknowledgement(plan, now), contains('36 hours'));
    expect(doctorBrief(plan, diarrhoea).join(' '), contains('36 hours ago'));
  });

  test('backup section round trip merges without duplicates', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SymptomCheckInStore();
    await store.add(SymptomCheckIn(at: now, severities: {Symptom.aches: 2}));
    await store.savePrefs(
      const CompanionPrefs(
        name: 'A',
        doctor: Comfort.yes,
        supportLine: Comfort.later,
      ),
    );
    final section = await store.exportSection();
    SharedPreferences.setMockInitialValues({});
    expect(await store.importSection(section), 1);
    expect(await store.importSection(section), 0);
    expect((await store.loadPrefs()).name, 'A');
    expect(await store.importSection('garbage'), 0);
  });

  test('backup carries withdrawal section and stays compatible', () {
    final service = BackupService();
    final without = service.buildBackupPayload(const [], preferences: const {});
    expect(without.containsKey('withdrawal'), isFalse);
    expect(service.validateBackupJson(jsonEncode(without)).withdrawal, isNull);
    final withSection = service.buildBackupPayload(
      const [],
      preferences: const {},
      withdrawal: {'checkIns': <Object>[]},
    );
    expect(withSection['version'], BackupService.currentBackupVersion);
    expect(
      service.validateBackupJson(jsonEncode(withSection)).withdrawal,
      isA<Map>(),
    );
  });

  test('guide copy has no helpline numbers', () {
    final all = [
      redFlagText,
      ...generalDos,
      ...generalDonts,
      for (final s in [...infoSections, ...detailedStages]) ...s.items,
      for (final s in guideSources) s.name,
    ].join(' ');
    for (final n in ['14416', '14446', '112', 'Tele-MANAS', 'helpline']) {
      expect(all.contains(n), isFalse, reason: n);
    }
  });
}

extension on DateTime {
  DateTime copyWithHour(int h) => DateTime(year, month, day, h);
}
