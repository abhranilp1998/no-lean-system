import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/utils/formatters.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/recovery/services/recovery_state_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> legacy() => {
    'stateVersion': 5,
    'lastDose': DateTime(2025, 2, 3, 18).toIso8601String(),
    'lastPledge': DateTime(2025, 2, 4, 8, 17).toIso8601String(),
    'cleanDays': {'2025-02-03': false, '2025-02-04': true},
    'cravings': [
      {
        'createdAt': DateTime(2025, 2, 3, 17).toIso8601String(),
        'intensity': 7,
        'trigger': 'Stress',
        'note': 'Keep me',
      },
    ],
    'sosSessions': [
      {
        'startedAt': DateTime(2025, 2, 3, 16).toIso8601String(),
        'completedAt': DateTime(2025, 2, 3, 16, 1).toIso8601String(),
        'debrief': 'down',
      },
    ],
    'reasons': ['My family'],
    'dailySpend': 25,
    'longestStreak': 900,
  };

  test(
    'v5 upgrade retains date-only relapse facts, exact pledge, history and preferences',
    () async {
      final source = jsonEncode(legacy());
      final store = MemoryRecoveryStore(source);
      final c = RecoveryController(store: store);
      await c.load();
      expect(c.isLoaded, isTrue);
      expect(c.cleanDays, {'2025-02-03': false, '2025-02-04': true});
      expect(c.lastPledge, DateTime(2025, 2, 4, 8, 17));
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        isEmpty,
      );
      expect(c.cravings.single.note, 'Keep me');
      expect(c.sosSessions.single.debrief, 'down');
      expect(c.longestStreak, 900);
      expect(c.reasons, ['My family']);
      expect(store.copies.single, source);
      final reopened = RecoveryController(store: store);
      await reopened.load();
      expect(
        reopened.events.map((e) => e.toJson()).toList(),
        c.events.map((e) => e.toJson()).toList(),
      );
      expect(store.writes, 1);
    },
  );

  test(
    'v6 repairs lost legacy days from preserved backup without removing events',
    () async {
      final event = RecoveryEvent.create(type: RecoveryEventType.pledge);
      final store = MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 6,
          'events': [event.toJson()],
        }),
      )..copies.add(jsonEncode(legacy()));
      final c = RecoveryController(store: store);
      await c.load();
      expect(c.events.any((e) => e.id == event.id), isTrue);
      expect(c.cleanDays['2025-02-03'], isFalse);
      expect(
        c.events.any((e) => e.timestamp == DateTime(2025, 2, 4, 8, 17)),
        isTrue,
      );
    },
  );

  test('optional setting corruption does not erase valid events', () async {
    final event = RecoveryEvent.create(type: RecoveryEventType.pledge);
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': 7,
        'events': [event.toJson()],
        'dailySpend': 'broken',
        'riskWindow': 'broken',
        'cooldownMinutes': [],
        'intensity': {},
      }),
    );
    final c = RecoveryController(store: store);
    await c.load();
    expect(c.isLoaded, isTrue);
    expect(c.events.any((e) => e.id == event.id), isTrue);
    expect(c.cooldownMinutes, 15);
    expect(store.writes, 0);
  });

  for (final source in [
    'broken JSON',
    jsonEncode({'stateVersion': 999, 'events': []}),
    jsonEncode({
      'stateVersion': 7,
      'events': [42],
    }),
  ]) {
    test(
      'unreadable or future state stays unchanged and refuses writes: $source',
      () async {
        final store = MemoryRecoveryStore(source);
        final c = RecoveryController(store: store);
        await c.load();
        expect(c.isLoaded, isFalse);
        expect(c.loadStatus, isNot(RecoveryLoadStatus.loading));
        await expectLater(c.recordRelapse(), throwsStateError);
        expect(store.value, source);
        expect(store.writes, 0);
      },
    );
  }

  test('startup read failure is retryable', () async {
    final store = MemoryRecoveryStore()..failRead = true;
    final c = RecoveryController(store: store);
    await c.load();
    expect(c.loadStatus, RecoveryLoadStatus.error);
    store.failRead = false;
    await c.retryLoad();
    expect(c.isLoaded, isTrue);
  });

  test(
    'failed batch rolls back all events and supports retry with stable identities',
    () async {
      final store = MemoryRecoveryStore();
      final c = RecoveryController(store: store);
      await c.load();
      final before = store.value;
      final dates = [
        DateTime.now().subtract(const Duration(days: 2)),
        DateTime.now().subtract(const Duration(days: 1)),
      ];
      store.failWrite = true;
      await expectLater(
        c.recordRelapse(occurredAt: dates, operationId: 'batch'),
        throwsA(isA<RecoverySaveException>()),
      );
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        isEmpty,
      );
      expect(store.value, before);
      expect(c.saveMessage, isNotNull);
      store.failWrite = false;
      await c.recordRelapse(occurredAt: dates, operationId: 'batch');
      await c.recordRelapse(occurredAt: dates, operationId: 'batch');
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(2),
      );
      expect(c.lastDose, dates.last);
      expect(c.relapseCooldownUntil, isNull);
      expect(c.saveMessage, isNull);
      final reload = RecoveryController(store: store);
      await reload.load();
      expect(reload.lastDose, dates.last);
    },
  );

  test(
    'same-minute separate events persist and a recent event does not extend an existing cooldown',
    () async {
      final c = RecoveryController(store: MemoryRecoveryStore());
      await c.load();
      await c.recordRelapse();
      final owner = c.relapseCooldownEventId;
      final deadline = c.relapseCooldownUntil;
      final at = DateTime.now();
      await c.recordRelapse(occurredAt: [at, at], source: 'widget');
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(3),
      );
      expect(c.relapseCooldownEventId, owner);
      expect(c.relapseCooldownUntil, deadline);
      await c.clearRelapseCooldown('stress');
      await c.clearRelapseCooldown('second tap');
      expect(
        c.events.firstWhere((e) => e.id == owner).metadata['debrief'],
        'stress',
      );
    },
  );

  test('batch validates all dates before changing history', () async {
    final c = RecoveryController(store: MemoryRecoveryStore());
    await c.load();
    for (final dates in <List<DateTime>>[
      [],
      [DateTime(1999)],
      [DateTime.now().add(const Duration(days: 1))],
      List.filled(51, DateTime(2025)),
    ]) {
      await expectLater(
        c.recordRelapse(occurredAt: dates),
        throwsArgumentError,
      );
    }
    expect(c.events, hasLength(1));
  });

  test(
    'batch and import enforce PIN authorization, and imports cannot disable it',
    () async {
      final c = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
      );
      await c.load();
      await c.enableRelapseLock('2468');
      final dates = [DateTime(2025, 2), DateTime(2025, 2, 2)];
      expect(
        await c.recordRelapse(occurredAt: dates, pin: '0000'),
        ProtectedActionResult.denied,
      );
      expect(
        await c.recordRelapse(occurredAt: dates, pin: '2468'),
        ProtectedActionResult.completed,
      );
      final imported = RecoveryEvent.create(type: RecoveryEventType.relapse);
      expect(
        await c.mergeImportedEvents([imported]),
        ProtectedActionResult.authenticationRequired,
      );
      expect(
        await c.mergeImportedEvents(
          [imported],
          pin: '2468',
          restorePreferences: true,
          preferences: {'requirePinAfterRelapse': false},
        ),
        ProtectedActionResult.completed,
      );
      expect(c.requirePinAfterRelapse, isTrue);
      await expectLater(
        c.appendEvent(RecoveryEvent.create(type: RecoveryEventType.relapse)),
        throwsStateError,
      );
    },
  );

  test(
    'concurrent writes serialize and preserve each committed event',
    () async {
      final store = MemoryRecoveryStore()
        ..delay = const Duration(milliseconds: 5);
      final c = RecoveryController(store: store);
      await c.load();
      await Future.wait(List.generate(10, (_) => c.pledge()));
      expect(store.maxConcurrentWrites, 1);
      final reopened = RecoveryController(store: store);
      await reopened.load();
      expect(
        reopened.events.where((e) => e.type == RecoveryEventType.pledge),
        hasLength(10),
      );
    },
  );

  test(
    'legacy exports and backup v3 round-trip without duplicate legacy facts',
    () async {
      final source = legacy()
        ..['settings'] = {
          'soundEffectsEnabled': true,
          'vibrationEnabled': false,
          'effectIntensity': 'ultra',
        };
      final service = BackupService();
      final preview = service.validateBackupJson(jsonEncode(source));
      expect(preview.preferences!['soundscape'], isTrue);
      final c = RecoveryController(store: MemoryRecoveryStore());
      await c.load();
      await c.mergeImportedEvents(preview.events);
      final count = c.events.length;
      await c.mergeImportedEvents(
        service.validateBackupJson(jsonEncode(source)).events,
      );
      expect(c.events.length, count);
      final roundTrip = service.validateBackupJson(
        jsonEncode({
          'version': 3,
          'events': c.events.map((e) => e.toJson()).toList(),
          'preferences': c.portablePreferences,
        }),
      );
      expect(roundTrip.eventCount, count);
      expect(
        roundTrip.events.where((e) => e.type == RecoveryEventType.daySummary),
        hasLength(2),
      );
    },
  );

  test('absence shows welcome-back without assigning missing days', () async {
    final earlier = DateTime.now().subtract(const Duration(days: 4));
    final c = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 7,
          'events': [],
          'lastOpenedAt': earlier.toIso8601String(),
        }),
      ),
    );
    await c.load();
    expect(c.welcomeBackSince, earlier);
    await c.markOpened();
    expect(c.cleanDays[dateKey(earlier)], isNull);
    expect(c.events.where((e) => e.type == RecoveryEventType.relapse), isEmpty);
  });

  test(
    'file store migrates preferences once, retains copies and reopens latest committed history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nolean-store-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final old = MemoryRecoveryStore(jsonEncode(legacy()));
      final store = FileRecoveryStateStore(directory: directory, legacy: old);
      final c = RecoveryController(store: store);
      await c.load();
      expect(c.isLoaded, isTrue);
      await c.recordRelapse(occurredAt: [DateTime(2025, 3)]);
      expect(await File('${directory.path}/previous.json').exists(), isTrue);
      expect(old.value, jsonEncode(legacy()));
      expect(await store.recoveryCopies(), isNotEmpty);
      final reload = RecoveryController(
        store: FileRecoveryStateStore(directory: directory, legacy: old),
      );
      await reload.load();
      expect(reload.lastDose, DateTime(2025, 3));
      final file = File('${directory.path}/current.json');
      await file.writeAsString('damaged');
      final damaged = RecoveryController(store: store);
      await damaged.load();
      expect(damaged.isLoaded, isFalse);
      expect(await file.readAsString(), 'damaged');
    },
  );
}
