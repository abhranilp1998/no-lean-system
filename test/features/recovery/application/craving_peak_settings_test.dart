import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/craving_peak.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RecoveryEvent craving(DateTime at) => RecoveryEvent.create(
    type: RecoveryEventType.craving,
    timestamp: at,
    metadata: const {'intensity': 6, 'trigger': 'evening'},
  );

  List<Map<String, dynamic>> eveningEvents() => [
    for (var i = 0; i < 5; i++)
      craving(DateTime(2026, 11, 20 + i, 19, 10)).toJson(),
  ];

  String state({
    int version = 17,
    List<Map<String, dynamic>>? events,
    Map<String, Object?> extra = const {},
  }) => jsonEncode({
    'stateVersion': version,
    'events':
        events ??
        [
          RecoveryEvent.create(
            type: RecoveryEventType.recoveryStart,
            timestamp: DateTime(2026, 9, 1),
          ).toJson(),
        ],
    'zones': [],
    ...extra,
  });

  Future<(RecoveryController, MemoryRecoveryStore)> loaded({
    String? stored,
    DateTime Function()? now,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: now ?? () => DateTime(2026, 11, 26, 12),
    );
    await controller.load();
    return (controller, store);
  }

  test(
    'toggle defaults on, including a v17 state that lacks the key',
    () async {
      final (fresh, _) = await loaded();
      expect(fresh.cravingPeakHeadsUp, isTrue);
      expect(RecoveryController.stateVersion, 18);
      expect(BackupService.currentBackupVersion, 13);

      final (legacy, store) = await loaded(stored: state());
      expect(legacy.cravingPeakHeadsUp, isTrue);
      final saved = jsonDecode(store.value!) as Map;
      expect(saved['stateVersion'], 18);
      expect(saved['cravingPeakHeadsUp'], isTrue);
    },
  );

  test('an explicit false stays off after reload', () async {
    final (controller, store) = await loaded();
    await controller.setSetting('cravingPeakHeadsUp', false);
    expect(controller.cravingPeakHeadsUp, isFalse);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['cravingPeakHeadsUp'], isFalse);

    final reloaded = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 26, 12),
    );
    await reloaded.load();
    expect(reloaded.cravingPeakHeadsUp, isFalse);
  });

  test(
    'plan is derived from occurredAt and skipped inside the risk window',
    () async {
      const morning = RiskWindow(startMinutes: 8 * 60, endMinutes: 11 * 60);
      final (armed, _) = await loaded(
        stored: state(
          events: eveningEvents(),
          extra: {'riskWindow': morning.toJson()},
        ),
      );
      expect(armed.cravingPeakPlan?.peakHour, 19);
      expect(armed.cravingPeakInsight.skip, isNull);

      final (overlap, _) = await loaded(stored: state(events: eveningEvents()));
      expect(overlap.cravingPeakPlan, isNull);
      expect(
        overlap.cravingPeakInsight.skip,
        CravingPeakSkip.overlapsRiskWindow,
      );
    },
  );

  test(
    'backup format 13 carries the toggle; format 12 stays valid without it',
    () {
      final service = BackupService();
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: DateTime(2026, 1, 1),
        ).toJson(),
      ];
      final v13 = service.validateBackupJson(
        jsonEncode({
          'version': 13,
          'events': events,
          'preferences': {'cravingPeakHeadsUp': false, 'riskReminders': true},
        }),
      );
      expect(v13.preferences!['cravingPeakHeadsUp'], isFalse);
      expect(v13.preferences!['riskReminders'], isTrue);

      final v12 = service.validateBackupJson(
        jsonEncode({
          'version': 12,
          'events': events,
          'preferences': {'riskReminders': false},
        }),
      );
      expect(v12.preferences, isNot(contains('cravingPeakHeadsUp')));
      expect(v12.eventCount, 1);
    },
  );
}
