import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(RecoveryController, MemoryRecoveryStore, FakeRelapseLock)>
  load() async {
    final store = MemoryRecoveryStore();
    final lock = FakeRelapseLock();
    final controller = RecoveryController(
      store: store,
      relapseLock: lock,
      now: () => DateTime(2026, 10, 10, 18),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.enableRelapseLock('1234');
    return (controller, store, lock);
  }

  const moved = RiskWindow(startMinutes: 120, endMinutes: 180);
  const apps = AppLockPolicy(
    enabled: true,
    apps: [LockedApp(packageName: 'com.example.chat', label: 'Chat')],
    schedule: AppLockSchedule.riskWindow,
    lockInsideDangerZones: false,
  );

  test(
    'moving the evening wall requires auth and denied edits keep history',
    () async {
      final (controller, store, lock) = await load();
      final before = store.value;
      expect(
        await controller.updateRiskWindow(moved, tryBiometrics: false),
        ProtectedActionResult.authenticationRequired,
      );
      expect(
        await controller.updateRiskWindow(moved, pin: '0000'),
        ProtectedActionResult.denied,
      );
      lock.lockedOut = true;
      expect(
        await controller.updateRiskWindow(moved, pin: '1234'),
        ProtectedActionResult.lockedOut,
      );
      expect(controller.isRiskWindow, isTrue);
      expect(store.value, before);
    },
  );

  test(
    'app schedule is protected even with the evening wall turned off',
    () async {
      final (controller, _, _) = await load();
      await controller.setRiskWindowLock(false, pin: '1234');
      await controller.updateAppLockPolicy(apps);
      expect(
        await controller.updateRiskWindow(moved, tryBiometrics: false),
        ProtectedActionResult.authenticationRequired,
      );
      expect(
        controller.appLockPolicy.blocks(
          'com.example.chat',
          DateTime(2026, 10, 10, 18),
          riskWindow: controller.riskWindow,
        ),
        isTrue,
      );
    },
  );

  test(
    'shrinking hours requires auth even when the current minute stays inside',
    () async {
      final (controller, _, _) = await load();
      expect(
        await controller.updateRiskWindow(
          const RiskWindow(startMinutes: 17 * 60, endMinutes: 20 * 60),
          tryBiometrics: false,
        ),
        ProtectedActionResult.authenticationRequired,
      );
      expect(controller.riskWindow.endMinutes, 21 * 60);
    },
  );

  test(
    'expanding protection and unchanged times require no challenge',
    () async {
      final (controller, _, lock) = await load();
      final eventCount = controller.events.length;
      expect(
        await controller.updateRiskWindow(const RiskWindow.defaultWindow()),
        ProtectedActionResult.completed,
      );
      expect(controller.events.length, eventCount);
      expect(
        await controller.updateRiskWindow(
          const RiskWindow(startMinutes: 16 * 60, endMinutes: 22 * 60),
        ),
        ProtectedActionResult.completed,
      );
      expect(lock.challenges, 0);
      expect(controller.isRiskWindow, isTrue);
    },
  );

  test('verified edit is saved, logged, and survives reload', () async {
    final (controller, store, lock) = await load();
    expect(
      await controller.updateRiskWindow(moved, pin: '1234'),
      ProtectedActionResult.completed,
    );
    expect(controller.isRiskWindow, isFalse);
    final change = controller.events
        .where(
          (e) =>
              e.type == RecoveryEventType.settingsChange &&
              e.metadata['setting'] == 'riskWindow',
        )
        .single;
    expect(change.metadata['from'], const RiskWindow.defaultWindow().label);
    expect(change.metadata['newValue'], moved.label);
    final reloaded = RecoveryController(store: store, relapseLock: lock);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.riskWindow.toJson(), moved.toJson());
  });

  test('unprotected reminder hours stay editable', () async {
    final (controller, _, lock) = await load();
    await controller.setRiskWindowLock(false, pin: '1234');
    await controller.updateAppLockPolicy(
      apps.copyWith(schedule: AppLockSchedule.always),
    );
    expect(
      await controller.updateRiskWindow(moved),
      ProtectedActionResult.completed,
    );
    expect(lock.challenges, 0);
  });

  test(
    'save failure rolls back the approved window and its timeline event',
    () async {
      final (controller, store, _) = await load();
      final before = store.value;
      final eventCount = controller.events.length;
      store.failWrite = true;
      await expectLater(
        controller.updateRiskWindow(moved, pin: '1234'),
        throwsA(isA<RecoverySaveException>()),
      );
      expect(controller.isRiskWindow, isTrue);
      expect(controller.events.length, eventCount);
      expect(store.value, before);
    },
  );

  test(
    'a risk window restored from a backup is logged on the timeline',
    () async {
      final (controller, store, lock) = await load();
      final result = await controller.mergeImportedEvents(
        const [],
        preferences: {'riskWindow': moved.toJson()},
        restorePreferences: true,
        pin: '1234',
      );
      expect(result, ProtectedActionResult.completed);
      expect(controller.riskWindow.startMinutes, moved.startMinutes);
      final logged = controller.events.where(
        (e) =>
            e.type == RecoveryEventType.settingsChange &&
            e.metadata['setting'] == 'riskWindow' &&
            e.metadata['source'] == 'import',
      );
      expect(logged, hasLength(1));
      expect(
        logged.single.metadata['from'],
        const RiskWindow.defaultWindow().label,
      );
      expect(logged.single.metadata['newValue'], moved.label);
      expect(logged.single.timestamp, DateTime(2026, 10, 10, 18));
      final audit = logged.single.toJson();
      final reloaded = RecoveryController(store: store, relapseLock: lock);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.riskWindow.toJson(), moved.toJson());
      expect(
        reloaded.events
            .singleWhere((event) => event.id == audit['id'])
            .toJson(),
        audit,
      );
    },
  );

  test('importing the same risk window adds no timeline entry', () async {
    final (controller, _, _) = await load();
    final count = controller.events.length;
    await controller.mergeImportedEvents(
      const [],
      preferences: {'riskWindow': controller.riskWindow.toJson()},
      restorePreferences: true,
      pin: '1234',
    );
    expect(controller.events.length, count);
  });

  test('declined imports cannot change the window or add its audit', () async {
    final (controller, store, lock) = await load();
    final before = store.value;
    final events = controller.events.map((event) => event.toJson()).toList();
    expect(
      await controller.mergeImportedEvents(
        const [],
        preferences: {'riskWindow': moved.toJson()},
        restorePreferences: true,
        tryBiometrics: false,
      ),
      ProtectedActionResult.authenticationRequired,
    );
    expect(
      await controller.mergeImportedEvents(
        const [],
        preferences: {'riskWindow': moved.toJson()},
        restorePreferences: true,
        pin: '0000',
        tryBiometrics: false,
      ),
      ProtectedActionResult.denied,
    );
    lock.lockedOut = true;
    expect(
      await controller.mergeImportedEvents(
        const [],
        preferences: {'riskWindow': moved.toJson()},
        restorePreferences: true,
        pin: '1234',
      ),
      ProtectedActionResult.lockedOut,
    );
    expect(
      controller.riskWindow.toJson(),
      const RiskWindow.defaultWindow().toJson(),
    );
    expect(controller.events.map((event) => event.toJson()).toList(), events);
    expect(store.value, before);
  });

  test(
    'without preference restoration imports add no settings audit',
    () async {
      final (controller, store, _) = await load();
      final before = store.value;
      await controller.mergeImportedEvents(
        const [],
        preferences: {'riskWindow': moved.toJson()},
        restorePreferences: false,
        pin: '1234',
      );
      await controller.mergeImportedEvents(
        const [],
        restorePreferences: true,
        pin: '1234',
      );
      expect(
        controller.riskWindow.toJson(),
        const RiskWindow.defaultWindow().toJson(),
      );
      expect(store.value, before);
    },
  );

  test(
    'failed import save rolls back records, window and audit together',
    () async {
      final (controller, store, _) = await load();
      final before = store.value;
      final events = controller.events.map((event) => event.toJson()).toList();
      final incoming = RecoveryEvent.create(
        type: RecoveryEventType.pledge,
        timestamp: DateTime(2026, 10, 9, 19),
      );
      store.failWrite = true;
      await expectLater(
        controller.mergeImportedEvents(
          [incoming],
          preferences: {'riskWindow': moved.toJson()},
          restorePreferences: true,
          pin: '1234',
        ),
        throwsA(isA<RecoverySaveException>()),
      );
      expect(
        controller.riskWindow.toJson(),
        const RiskWindow.defaultWindow().toJson(),
      );
      expect(controller.events.map((event) => event.toJson()).toList(), events);
      expect(store.value, before);
    },
  );

  test(
    'legacy import and re-export preserve unknown bottle facts and audit IDs',
    () async {
      final (controller, store, lock) = await load();
      final service = BackupService();
      const note = 'before\uFEFFafter // বাংলা // 🟢';
      final legacy = RecoveryEvent.create(
        type: RecoveryEventType.relapse,
        timestamp: DateTime(2026, 10, 8, 19),
        metadata: {'quantity': '2 bottles', 'note': note},
      );
      final preview = service.validateBackupJson(
        jsonEncode({
          'version': 6,
          'events': [legacy.toJson()],
          'preferences': {'riskWindow': moved.toJson()},
        }),
      );
      expect(preview.events.single.metadata.containsKey('amountMl'), isFalse);
      final original = preview.events.single.toJson();
      await controller.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
        restorePreferences: true,
        pin: '1234',
      );
      final audit = controller.events.singleWhere(
        (event) =>
            event.type == RecoveryEventType.settingsChange &&
            event.metadata['source'] == 'import',
      );
      final reloaded = RecoveryController(store: store, relapseLock: lock);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      final exported = service.validateBackupJson(
        jsonEncode(
          service.buildBackupPayload(
            reloaded.events,
            preferences: reloaded.portablePreferences,
          ),
        ),
      );
      expect(
        exported.events.singleWhere((event) => event.id == legacy.id).toJson(),
        original,
      );
      expect(
        exported.events.singleWhere((event) => event.id == audit.id).toJson(),
        audit.toJson(),
      );
      expect(
        exported.events
            .singleWhere((event) => event.id == legacy.id)
            .metadata['note'],
        note,
      );
      expect(
        exported.events
            .singleWhere((event) => event.id == legacy.id)
            .metadata
            .containsKey('amountMl'),
        isFalse,
      );
    },
  );
}
