import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/dates/domain/high_risk_dates.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../support/recovery_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 27, 12);

  Future<(RecoveryController, MemoryRecoveryStore, List<List<HighRiskNudge>>)>
  load({String? stored, DateTime? clock}) async {
    final store = MemoryRecoveryStore(stored);
    final scheduled = <List<HighRiskNudge>>[];
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => clock ?? now,
      scheduleHighRiskDateReminders: (nudges) async {
        scheduled.add(List.of(nudges));
      },
      cancelHighRiskDateReminders: () async {
        scheduled.add(const []);
      },
    );
    await controller.load();
    return (controller, store, scheduled);
  }

  test('toggle defaults on and older state without the key stays on', () async {
    expect(RecoveryController.stateVersion, 18);
    expect(BackupService.currentBackupVersion, 13);
    final (fresh, _, scheduled) = await load();
    expect(fresh.highRiskDateReminders, isTrue);
    expect(fresh.paydayDay, isNull);
    expect(fresh.customHighRiskDates, isEmpty);
    expect(fresh.highRiskPlans, isEmpty);
    // load() must not schedule reminders (that hung export tests).
    expect(scheduled, isEmpty);

    await fresh.setHighRiskDateReminders(false);
    expect(fresh.highRiskDateReminders, isFalse);
    expect(scheduled, isNotEmpty);

    final (reloaded, store, _) = await load(
      stored: jsonEncode({
        'stateVersion': 17,
        'events': [
          {
            'id': 'p1',
            'type': 'pledge',
            'timestamp': DateTime(2026, 10, 1).toIso8601String(),
            'metadata': <String, dynamic>{},
          },
        ],
      }),
    );
    expect(reloaded.loadStatus, RecoveryLoadStatus.ready);
    expect(reloaded.highRiskDateReminders, isTrue);
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    // Saving after load may write defaults, but version stays 17.
    expect(saved['stateVersion'], 18);
  });

  test('custom dates, payday and plans persist across reload', () async {
    final (controller, store, scheduled) = await load();
    await controller.setPaydayDay(31);
    await controller.addCustomHighRiskDate(
      name: "Asha's birthday",
      kind: CustomDateKind.birthday,
      month: 3,
      day: 12,
    );
    expect(controller.customHighRiskDates, hasLength(1));
    final key = controller
        .upcomingHighRiskDates(limit: 16)
        .firstWhere((e) => e.title == "Asha's birthday")
        .key;
    await controller.setHighRiskPlan(key, 'Call Asha in the morning.');
    expect(controller.highRiskPlans[key], 'Call Asha in the morning.');

    final (reloaded, _, _) = await load(stored: store.value);
    expect(reloaded.paydayDay, 31);
    expect(reloaded.customHighRiskDates.single.name, "Asha's birthday");
    expect(reloaded.customHighRiskDates.single.month, 3);
    expect(reloaded.highRiskPlans[key], 'Call Asha in the morning.');
    expect(scheduled, isNotEmpty, reason: 'changes reschedule reminders');
  });

  test(
    'resync schedules a Christmas nudge and cancel when toggled off',
    () async {
      final (controller, _, scheduled) = await load();
      scheduled.clear();
      await controller.resyncHighRiskDateReminders();
      expect(scheduled, isNotEmpty);
      final last = scheduled.last;
      expect(
        last.any((n) => n.title == 'Coming up' && n.body.contains('Christmas')),
        isTrue,
      );
      for (final nudge in last) {
        expect(
          notificationCopyIsClean(
            NotificationText(title: nudge.title, body: nudge.body),
          ),
          isTrue,
        );
      }
      scheduled.clear();
      await controller.setHighRiskDateReminders(false);
      expect(scheduled.last, isEmpty);
    },
  );

  test(
    'worst weekday surfaces on upcoming when the sample is enough',
    () async {
      Map<String, dynamic> ev(
        String id,
        String type,
        DateTime at, [
        Map<String, dynamic>? meta,
      ]) => {
        'id': id,
        'type': type,
        'timestamp': at.toIso8601String(),
        'metadata': meta ?? <String, dynamic>{},
      };
      final (controller, _, _) = await load(
        stored: jsonEncode({
          'stateVersion': 17,
          'events': [
            ev('p1', 'pledge', DateTime(2026, 9, 1)),
            for (final day in [3, 10, 17, 24])
              ev('r$day', 'relapse', DateTime(2026, 10, day, 21)),
            ev('c1', 'craving', DateTime(2026, 10, 31, 21), {
              'intensity': 4,
              'trigger': 'Stress',
            }),
            ev('c2', 'craving', DateTime(2026, 10, 30, 21), {
              'intensity': 3,
              'trigger': 'Stress',
            }),
          ],
        }),
      );
      expect(DateTime(2026, 10, 3).weekday, DateTime.saturday);
      expect(DateTime(2026, 10, 31).weekday, DateTime.saturday);
      expect(controller.worstWeekday, DateTime.saturday);
      expect(
        controller.upcomingHighRiskDates().any(
          (e) => e.kind == HighRiskKind.weekday,
        ),
        isTrue,
      );
      await controller.setWeekdayNudges(false);
      expect(
        controller.upcomingHighRiskDates().any(
          (e) => e.kind == HighRiskKind.weekday,
        ),
        isFalse,
      );
    },
  );
}
