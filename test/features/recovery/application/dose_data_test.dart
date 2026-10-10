import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/dose_units.dart';
import 'package:no_lean/features/recovery/domain/events_csv.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

import '../../../support/recovery_fakes.dart';

Map<String, dynamic> relapseJson(
  String id,
  DateTime at,
  Map<String, dynamic> metadata,
) => {
  'id': id,
  'type': 'relapse',
  'timestamp': at.toIso8601String(),
  'metadata': {'relapseType': 'fullLean', ...metadata},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('relapse dose metadata validation', () {
    Map<String, dynamic> validate(Map<String, dynamic> metadata) =>
        RecoveryEvent.validateMetadata(RecoveryEventType.relapse, metadata);

    test('ml and L derive amountMl; bottle keeps its stored ml', () {
      expect(validate({'amount': 250, 'unit': 'ml'})['amountMl'], 250);
      expect(validate({'amount': 1.5, 'unit': 'litre'})['amountMl'], 1500);
      // A bottle dose logged at 100 ml stays 200 ml even if bottleMl says 250.
      final bottle = validate({
        'amount': 2,
        'unit': 'bottle',
        'amountMl': 200,
        'bottleMl': 100,
      });
      expect(bottle['amountMl'], 200);
      expect(
        validate({'amount': 2, 'unit': 'bottle', 'bottleMl': 120})['amountMl'],
        240,
      );
    });

    test('counts never carry ml', () {
      final tablets = validate({
        'amount': 2,
        'unit': 'tablet',
        'amountMl': 999,
        'bottleMl': 100,
      });
      expect(tablets.containsKey('amountMl'), isFalse);
      expect(tablets.containsKey('bottleMl'), isFalse);
    });

    test('bad doses, costs and stress are rejected', () {
      for (final bad in <Map<String, dynamic>>[
        {'amount': 0, 'unit': 'ml'},
        {'amount': -1, 'unit': 'ml'},
        {'amount': 2, 'unit': 'cups'},
        {'amount': 2},
        {'unit': 'ml'},
        {'amount': '2', 'unit': 'ml'},
        {'amount': 2, 'unit': 'bottle'}, // no ml and no bottle size
        {'amount': 2, 'unit': 'bottle', 'bottleMl': 5},
        {'cost': -10},
        {'cost': 'free'},
        {'stress': 0},
        {'stress': 6},
      ]) {
        expect(() => validate(bad), throwsFormatException, reason: '$bad');
      }
    });

    test('cost 0 is valid; stress rounds', () {
      expect(validate({'cost': 0})['cost'], 0);
      expect(validate({'stress': 4.2})['stress'], 4);
    });

    test('craving stress and craving checks validate', () {
      expect(
        RecoveryEvent.validateMetadata(RecoveryEventType.craving, {
          'intensity': 7,
          'trigger': 'Boredom',
          'stress': 5,
        })['stress'],
        5,
      );
      expect(
        () => RecoveryEvent.validateMetadata(RecoveryEventType.cravingCheck, {
          'cravingId': 'c',
          'intensity': 11,
          'outcome': 'eased',
        }),
        throwsFormatException,
      );
      expect(
        () => RecoveryEvent.validateMetadata(RecoveryEventType.cravingCheck, {
          'cravingId': 'c',
          'intensity': 3,
          'outcome': 'meh',
        }),
        throwsFormatException,
      );
      expect(cravingCheckOutcome(7, 0), 'gone');
      expect(cravingCheckOutcome(7, 4), 'eased');
      expect(cravingCheckOutcome(7, 7), 'same');
      expect(cravingCheckOutcome(7, 9), 'stronger');
    });
  });

  group('state v12 migration', () {
    final day = DateTime(2026, 9, 1, 21);
    String v11State({Map<String, dynamic> extra = const {}}) => jsonEncode({
      'stateVersion': 11,
      'events': [
        relapseJson('a', day, {'quantity': '250ml'}),
        relapseJson('b', day.add(const Duration(days: 1)), {
          'quantity': '2.5 bottles',
        }),
        relapseJson('c', day.add(const Duration(days: 2)), {
          'quantity': 'half a cup',
        }),
        relapseJson('d', day.add(const Duration(days: 3)), {
          'quantity': '2 tablets',
        }),
      ],
      ...extra,
    });

    test('exact quantities gain structured fields; text is kept', () async {
      final store = MemoryRecoveryStore(v11State());
      final controller = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await controller.load();
      Map<String, dynamic> meta(String id) =>
          controller.events.firstWhere((e) => e.id == id).metadata;
      expect(controller.bottleMl, defaultBottleMl);
      expect(meta('a')['amountMl'], 250);
      expect(meta('a')['quantity'], '250ml');
      expect(meta('a')['amountSource'], 'parsed');
      expect(meta('b').containsKey('amountMl'), isFalse);
      expect(meta('b').containsKey('unit'), isFalse);
      expect(meta('b')['quantity'], '2.5 bottles');
      expect(meta('c').containsKey('unit'), isFalse);
      expect(meta('c')['quantity'], 'half a cup');
      expect(meta('d')['unit'], 'tablet');
      expect(meta('d').containsKey('amountMl'), isFalse);

      final saved = jsonDecode(store.value!) as Map;
      expect(saved['stateVersion'], RecoveryController.stateVersion);
      expect(saved['bottleMl'], 100);
      expect(saved['insightPreferences'], {'dismissed': {}});
      // The original v11 state is preserved untouched.
      expect(store.copies.single, contains('"stateVersion":11'));
    });

    test('current bottle preference cannot supply a historical size', () async {
      final store = MemoryRecoveryStore(v11State(extra: {'bottleMl': 250}));
      final controller = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await controller.load();
      expect(controller.bottleMl, 250);
      final originalIds = controller.events.map((event) => event.id).toList();
      final reloaded = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await reloaded.load();
      expect(reloaded.events.map((event) => event.id), originalIds);
      final metadata = reloaded.events.firstWhere((e) => e.id == 'b').metadata;
      expect(metadata['quantity'], '2.5 bottles');
      expect(metadata.containsKey('amountMl'), isFalse);
      expect(metadata.containsKey('bottleMl'), isFalse);
    });

    test('a newer state version is refused, not rewritten', () async {
      final raw = jsonEncode({
        'stateVersion': RecoveryController.stateVersion + 1,
        'events': [],
      });
      final store = MemoryRecoveryStore(raw);
      final controller = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await controller.load();
      expect(controller.loadStatus, RecoveryLoadStatus.incompatible);
      expect(store.value, raw);
    });
  });

  group('bottle size setting', () {
    test('changes new entries only and persists', () async {
      final store = MemoryRecoveryStore();
      final controller = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await controller.load();
      final at = DateTime.now().subtract(const Duration(hours: 2));
      await controller.recordRelapse(
        entries: [
          RelapseLogEntry(
            occurredAt: at,
            type: RelapseType.fullLean,
            note: 'two bottles after work',
            attemptedSos: false,
            dose: DoseAmount.entered(
              2,
              DoseUnit.bottle,
              bottleMl: controller.bottleMl,
            ),
            cost: 600,
            stress: 4,
          ),
        ],
      );
      await controller.updateBottleMl(250);
      final relapse = controller.events.firstWhere(
        (e) => e.type == RecoveryEventType.relapse,
      );
      expect(relapse.metadata['amountMl'], 200);
      expect(relapse.metadata['bottleMl'], 100);
      expect(relapse.metadata['cost'], 600);
      expect(relapse.metadata['stress'], 4);
      expect(() => controller.updateBottleMl(0), throwsA(isA<ArgumentError>()));

      final reloaded = RecoveryController(
        store: MemoryRecoveryStore(store.value),
        relapseLock: FakeRelapseLock(),
      );
      await reloaded.load();
      expect(reloaded.bottleMl, 250);
      expect(reloaded.portablePreferences['bottleMl'], 250);
      expect(
        reloaded.events
            .firstWhere((e) => e.type == RecoveryEventType.relapse)
            .metadata['amountMl'],
        200,
      );
    });
  });

  group('backup format 7', () {
    final service = BackupService();
    final day = DateTime(2026, 9, 1, 21);

    test('format 6 imports retain bottle notes without inventing ml', () {
      final preview = service.validateBackupJson(
        jsonEncode({
          'version': 6,
          'events': [
            relapseJson('a', day, {'quantity': '3 bottles'}),
            relapseJson('b', day, {'quantity': 'a lot'}),
          ],
        }),
      );
      final a = preview.events.firstWhere((e) => e.id == 'a').metadata;
      expect(a.containsKey('amountMl'), isFalse);
      expect(a.containsKey('unit'), isFalse);
      expect(a['quantity'], '3 bottles');
      final b = preview.events.firstWhere((e) => e.id == 'b').metadata;
      expect(b.containsKey('amount'), isFalse);
    });

    test(
      'raw v11 state keeps bottle preference apart from historical notes',
      () {
        final preview = service.validateBackupJson(
          jsonEncode({
            'stateVersion': 11,
            'bottleMl': 120,
            'events': [
              relapseJson('a', day, {'quantity': '2 bottles'}),
            ],
          }),
        );
        expect(preview.events.single.metadata.containsKey('amountMl'), isFalse);
        expect(preview.events.single.metadata['quantity'], '2 bottles');
        expect(preview.preferences!['bottleMl'], 120);
      },
    );

    test(
      'all old backup formats preserve unknown bottle size on re-export',
      () {
        for (var version = 1; version <= 6; version++) {
          final preview = service.validateBackupJson(
            jsonEncode({
              'version': version,
              'events': [
                relapseJson('bottle', day, {'quantity': '2 bottles'}),
                relapseJson('volume', day, {'quantity': '0.5 L'}),
                relapseJson('known', day, {
                  'quantity': '2 bottles',
                  'amount': 2,
                  'unit': 'bottle',
                  'amountMl': 240,
                  'bottleMl': 120,
                }),
              ],
              'preferences': {'bottleMl': 250},
            }),
          );
          final reExport = service.validateBackupJson(
            jsonEncode(
              service.buildBackupPayload(preview.events, preferences: {}),
            ),
          );
          Map<String, dynamic> metadata(String id) =>
              reExport.events.firstWhere((event) => event.id == id).metadata;
          expect(
            metadata('bottle')['quantity'],
            '2 bottles',
            reason: 'v$version',
          );
          expect(metadata('bottle').containsKey('amountMl'), isFalse);
          expect(metadata('volume')['amountMl'], 500);
          expect(metadata('known')['amountMl'], 240);
          expect(metadata('known')['bottleMl'], 120);
          expect(reExport.events.map((event) => event.id).toSet(), {
            'bottle',
            'volume',
            'known',
          });
        }
      },
    );

    test('format 7 round-trips doses, checks and bottle size', () async {
      final controller = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
        scheduleCravingCheck: (_) async => true,
        cancelCravingCheck: () async {},
      );
      await controller.load();
      await controller.updateBottleMl(120);
      final cravingId = await controller.recordCraving(
        CravingEntry(
          intensity: 8,
          trigger: 'Boredom',
          note: '',
          createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
          stress: 5,
        ),
      );
      await controller.recordCravingCheck(cravingId: cravingId, intensity: 3);
      final payload = service.buildBackupPayload(
        controller.events,
        preferences: controller.portablePreferences,
      );
      expect(payload['version'], BackupService.currentBackupVersion);
      final preview = service.validateBackupJson(jsonEncode(payload));
      expect(preview.preferences!['bottleMl'], 120);
      final check = preview.events.firstWhere(
        (e) => e.type == RecoveryEventType.cravingCheck,
      );
      expect(check.metadata['outcome'], 'eased');
      expect(
        preview.events
            .firstWhere((e) => e.type == RecoveryEventType.craving)
            .metadata['stress'],
        5,
      );
    });

    test('a newer format and bad bottle sizes are refused', () {
      expect(
        () => service.validateBackupJson(
          jsonEncode({
            'version': BackupService.currentBackupVersion + 1,
            'events': [],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => service.validateBackupJson(
          jsonEncode({
            'version': 7,
            'events': [],
            'preferences': {'bottleMl': 0},
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('craving recheck', () {
    test(
      'schedules at +15 min, is due later, and records an outcome',
      () async {
        final now = DateTime(2026, 10, 9, 18);
        var clock = now;
        final scheduled = <DateTime>[];
        var cancels = 0;
        final controller = RecoveryController(
          store: MemoryRecoveryStore(),
          relapseLock: FakeRelapseLock(),
          now: () => clock,
          scheduleCravingCheck: (at) async {
            scheduled.add(at);
            return true;
          },
          cancelCravingCheck: () async => cancels++,
        );
        await controller.load();
        final id = await controller.recordCraving(
          CravingEntry(
            intensity: 6,
            trigger: 'Habit',
            note: '',
            createdAt: now,
          ),
        );
        expect(scheduled, [now.add(const Duration(minutes: 15))]);
        expect(controller.pendingCravingCheck, isNull); // not due yet
        clock = now.add(const Duration(minutes: 16));
        expect(controller.pendingCravingCheck?.id, id);
        await controller.recordCravingCheck(cravingId: id, intensity: 8);
        expect(controller.pendingCravingCheck, isNull);
        expect(cancels, 1);
        final check = controller.events.firstWhere(
          (e) => e.type == RecoveryEventType.cravingCheck,
        );
        expect(check.metadata['outcome'], 'stronger');
        expect(check.metadata['originalIntensity'], 6);
      },
    );

    test('stale cravings are not nagged about', () async {
      final now = DateTime(2026, 10, 9, 18);
      final controller = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
        now: () => now.add(const Duration(hours: 7)),
        scheduleCravingCheck: (_) async => true,
      );
      await controller.load();
      await controller.recordCraving(
        CravingEntry(intensity: 6, trigger: 'Habit', note: '', createdAt: now),
      );
      expect(controller.pendingCravingCheck, isNull);
    });

    test('quiet hours mute the recheck notification', () async {
      const prefs = NotificationPrefs(quietHoursEnabled: true); // 22:00-07:00
      expect(NotificationKind.cravingCheck.isCritical, isFalse);
      final inQuiet = DateTime(2026, 10, 9, 23, 30);
      expect(prefs.allows(NotificationKind.cravingCheck, inQuiet), isFalse);
      expect(
        prefs.allows(NotificationKind.cravingCheck, DateTime(2026, 10, 9, 18)),
        isTrue,
      );
      final service = NotificationService.instance;
      final previous = service.prefs;
      service.prefs = prefs;
      addTearDown(() => service.prefs = previous);
      expect(await service.scheduleCravingCheck(at: inQuiet), isFalse);
    });
  });

  test('dismissed insights persist with their evidence key', () async {
    final store = MemoryRecoveryStore();
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    await controller.dismissInsight('trigger-pattern', 'Boredom|5');
    final reloaded = RecoveryController(
      store: MemoryRecoveryStore(store.value),
      relapseLock: FakeRelapseLock(),
    );
    await reloaded.load();
    expect(reloaded.dismissedInsights, {'trigger-pattern': 'Boredom|5'});
    await reloaded.restoreDismissedInsights();
    expect(reloaded.dismissedInsights, isEmpty);
  });

  test('CSV carries amount, unit, ml, bottle size, cost and stress', () {
    final event = RecoveryEvent.fromJson(
      relapseJson('a', DateTime(2026, 9, 1, 21), {
        'quantity': '2.5 bottles',
        'amount': 2.5,
        'unit': 'bottle',
        'amountMl': 250,
        'bottleMl': 100,
        'amountSource': 'parsed',
        'cost': 450,
        'stress': 4,
      }),
    );
    final row = eventCsvRow(event);
    String col(String name) => row[eventsCsvColumns.indexOf(name)];
    expect(col('amount'), '2.5');
    expect(col('unit'), 'bottle');
    expect(col('amount_ml'), '250');
    expect(col('bottle_ml'), '100');
    expect(col('amount_source'), 'parsed');
    expect(col('cost_inr'), '450');
    expect(col('stress'), '4');
    expect(col('relapse_type'), 'fullLean');
    expect(col('quantity'), '2.5 bottles');
    expect(col('details'), isEmpty);
  });
}
