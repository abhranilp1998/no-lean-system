import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/utils/formatters.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/money_saved.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

Map<String, dynamic> state({
  required DateTime lastDose,
  double dailySpend = 0,
  Map<String, dynamic> extra = const {},
  List<Map<String, dynamic>> events = const [],
}) => {
  'stateVersion': RecoveryController.stateVersion,
  'dailySpend': dailySpend,
  'events': [
    {
      'id': 'start',
      'type': 'recoveryStart',
      'timestamp': lastDose.toIso8601String(),
    },
    ...events,
  ],
  ...extra,
};

void main() {
  final lastDose = DateTime(2026, 10, 1, 12);
  final now = DateTime(2026, 10, 19, 12);

  Future<RecoveryController> load(Map<String, dynamic> raw) async {
    final controller = RecoveryController(
      store: MemoryRecoveryStore(jsonEncode(raw)),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await controller.load();
    expect(controller.loadStatus, RecoveryLoadStatus.ready);
    return controller;
  }

  test(
    'existing dailySpend still drives moneySaved after 18 clean days',
    () async {
      final c = await load(state(lastDose: lastDose, dailySpend: 120));
      expect(c.currency, AppCurrency.inr);
      expect(c.moneySaved, 18 * 120);
      expect(c.savingsGoal, isNull);
      expect(c.subtractOtherCosts, isFalse);
    },
  );

  test('per-bottle settings persist through the store', () async {
    final store = MemoryRecoveryStore(jsonEncode(state(lastDose: lastDose)));
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    await c.updateMoneySavedSettings(
      currency: AppCurrency.eur,
      spendPerBottle: 200,
      usualDailyMl: 100,
      subtractOtherCosts: true,
    );
    await c.updateSavingsGoal(
      const SavingsGoal(name: 'Train ticket', target: 2500),
    );
    expect(c.dailySpend, 200);

    final reloaded = RecoveryController(
      store: MemoryRecoveryStore(store.value),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await reloaded.load();
    expect(reloaded.currency, AppCurrency.eur);
    expect(reloaded.spendPerBottle, 200);
    expect(reloaded.usualDailyMl, 100);
    expect(reloaded.subtractOtherCosts, isTrue);
    expect(reloaded.savingsGoal?.name, 'Train ticket');
    expect(reloaded.savingsGoal?.target, 2500);
    expect(reloaded.dailySpend, 200);
    expect(reloaded.portablePreferences['currencyCode'], 'EUR');
    expect(reloaded.portablePreferences['savingsGoal']['name'], 'Train ticket');
  });

  test(
    'changing bottle size recomputes dailySpend from the breakdown',
    () async {
      final c = await load(
        state(
          lastDose: lastDose,
          extra: {
            'spendPerBottle': 200,
            'usualDailyMl': 100,
            'dailySpend': 200,
            'bottleMl': 100,
          },
        ),
      );
      expect(c.dailySpend, 200);
      await c.updateBottleMl(200);
      // Same 100 ml/day, now a 200 ml bottle at ₹200 → ₹100/day
      expect(c.dailySpend, 100);
      expect(c.moneySaved, 18 * 100);
    },
  );

  test(
    'benzo-only use does not reset the counter; optional cost subtracts',
    () async {
      final c = await load(
        state(
          lastDose: lastDose,
          dailySpend: 120,
          extra: {'subtractOtherCosts': true},
          events: [
            {
              'id': 'benzo',
              'type': 'relapse',
              'timestamp': lastDose
                  .add(const Duration(days: 4))
                  .toIso8601String(),
              'metadata': {'relapseType': 'benzo', 'cost': 300},
            },
          ],
        ),
      );
      expect(c.lastDose, lastDose);
      expect(c.moneySaved, 18 * 120 - 300);
    },
  );

  test('an old-format backup with only dailySpend still imports', () async {
    final service = BackupService();
    final preview = service.validateBackupJson(
      jsonEncode({
        'version': 5,
        'events': [
          {
            'id': 'start',
            'type': 'recoveryStart',
            'timestamp': lastDose.toIso8601String(),
            'metadata': <String, dynamic>{},
          },
          {
            'id': 'pledge-1',
            'type': 'pledge',
            'timestamp': lastDose
                .add(const Duration(days: 2))
                .toIso8601String(),
            'metadata': <String, dynamic>{},
          },
        ],
        'preferences': {'dailySpend': 450, 'cooldownMinutes': 15},
      }),
    );
    expect(preview.eventCount, 2);
    expect(preview.preferences!['dailySpend'], 450);
    expect(preview.preferences!.containsKey('currencyCode'), isFalse);
    expect(preview.preferences!.containsKey('savingsGoal'), isFalse);

    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    expect(c.loadStatus, RecoveryLoadStatus.ready);
    final baseline = c.events.length;
    final result = await c.mergeImportedEvents(
      preview.events,
      preferences: preview.preferences,
      restorePreferences: true,
    );
    expect(result, ProtectedActionResult.completed);
    expect(c.dailySpend, 450);
    expect(c.currency, AppCurrency.inr);
    expect(c.spendPerBottle, isNull);
    expect(c.savingsGoal, isNull);
    expect(c.events.map((e) => e.id), containsAll(['start', 'pledge-1']));
    expect(c.events.length, greaterThanOrEqualTo(baseline));
    // 18 days at the imported 450/day, timer from the imported start.
    expect(c.lastDose, lastDose);
    expect(c.moneySaved, 18 * 450);
  });

  test('new money fields round-trip in a current backup', () async {
    final service = BackupService();
    final preview = service.validateBackupJson(
      jsonEncode({
        'version': BackupService.currentBackupVersion,
        'events': [
          {
            'id': 'start',
            'type': 'recoveryStart',
            'timestamp': lastDose.toIso8601String(),
          },
        ],
        'preferences': {
          'dailySpend': 120,
          'bottleMl': 100,
          'currencyCode': 'GBP',
          'spendPerBottle': 240,
          'usualDailyMl': 50,
          'subtractOtherCosts': true,
          'savingsGoal': {
            'name': 'Headphones',
            'target': 8000,
            'photoPath': '/data/savings_goal.jpg',
          },
        },
      }),
    );
    expect(preview.preferences!['currencyCode'], 'GBP');
    expect(preview.preferences!['savingsGoal']['name'], 'Headphones');
    final c = await load(state(lastDose: lastDose));
    await c.mergeImportedEvents(
      preview.events,
      preferences: preview.preferences,
      restorePreferences: true,
    );
    expect(c.currency, AppCurrency.gbp);
    expect(c.spendPerBottle, 240);
    expect(c.usualDailyMl, 50);
    expect(c.subtractOtherCosts, isTrue);
    expect(c.savingsGoal?.name, 'Headphones');
    expect(c.savingsGoal?.photoPath, '/data/savings_goal.jpg');
    expect(c.dailySpend, 120);
  });

  test('malformed new money fields do not throw on state load', () async {
    final c = await load(
      state(
        lastDose: lastDose,
        dailySpend: 80,
        extra: {
          'currencyCode': 12,
          'spendPerBottle': 'nope',
          'usualDailyMl': -4,
          'subtractOtherCosts': 'yes',
          'savingsGoal': {'name': '', 'target': 0},
        },
      ),
    );
    expect(c.currency, AppCurrency.inr);
    expect(c.spendPerBottle, isNull);
    expect(c.usualDailyMl, isNull);
    expect(c.subtractOtherCosts, isFalse);
    expect(c.savingsGoal, isNull);
    expect(c.dailySpend, 80);
  });

  test('privacy widget payload never includes money or substance words', () {
    final payload = {
      // checked in home_widget_payload_test; this guards the copy itself.
    };
    expect(payload, isEmpty);
    final snap = computeMoneySaved(
      dailySpend: 120,
      bottleMl: 100,
      cleanDuration: const Duration(days: 18),
      events: const [],
      lastDose: lastDose,
      goal: const SavingsGoal(name: 'Trip', target: 4000),
    );
    expect(isPrivacySafeMoneyCopy(snap.widgetKept), isTrue);
    expect(isPrivacySafeMoneyCopy(snap.notificationText), isTrue);
  });
}
