import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/timeline/domain/history_projection.dart';

void main() {
  final at = DateTime(2026, 1, 20, 18);
  RecoveryEvent event(
    RecoveryEventType type,
    Map<String, dynamic> metadata, {
    DateTime? time,
  }) => RecoveryEvent.create(
    type: type,
    timestamp: time ?? at,
    metadata: metadata,
  );

  test(
    'recovery/settings/observations separate without cloning or changing events',
    () {
      final use = event(RecoveryEventType.relapse, {});
      final setting = event(RecoveryEventType.settingsChange, {
        'setting': 'scanlines',
        'newValue': 'false',
      });
      final zone = event(RecoveryEventType.zoneEntry, {
        'zoneId': 'z',
        'zoneName': 'Saved place',
        'source': 'app',
      });
      final all = [setting, zone, use];
      final original = all.map((e) => e.toJson()).toList();
      expect(projectHistory(all, HistoryCategory.recovery), [same(use)]);
      expect(projectHistory(all, HistoryCategory.settings), [same(setting)]);
      expect(projectHistory(all, HistoryCategory.location), [same(zone)]);
      expect(all.map((e) => e.toJson()).toList(), original);
    },
  );

  test(
    'explicit located recovery facts share identity; prose/tags/audits do not create presence',
    () {
      final located = event(RecoveryEventType.relapse, {
        'zoneName': 'Saved place',
      });
      final prose = event(RecoveryEventType.craving, {
        'intensity': 5,
        'trigger': 'Habit',
        'note': 'At a saved place',
        'contextTags': ['Location'],
      });
      final audit = event(RecoveryEventType.settingsChange, {
        'setting': 'zoneName',
        'zoneName': 'Edited place',
      });
      expect(
        projectHistory([located, prose, audit], HistoryCategory.location),
        [same(located)],
      );
      expect(
        projectHistory([located], HistoryCategory.recovery).single,
        same(projectHistory([located], HistoryCategory.location).single),
      );
    },
  );

  test('all current recovery event types remain discoverable', () {
    final types = RecoveryEventType.values.toSet()
      ..remove(RecoveryEventType.zoneEntry)
      ..remove(RecoveryEventType.settingsChange);
    final samples = [
      for (final type in RecoveryEventType.values)
        event(type, switch (type) {
          RecoveryEventType.daySummary => {'date': '2026-01-19', 'clean': true},
          RecoveryEventType.craving => {'intensity': 5, 'trigger': 'Habit'},
          RecoveryEventType.cravingCheck => {
            'cravingId': 'sample-urge',
            'intensity': 0,
            'outcome': 'gone',
          },
          RecoveryEventType.codeSession => {
            'taskId': 'sample',
            'plannedSeconds': 300,
            'durationSeconds': 300,
            'completed': true,
          },
          RecoveryEventType.zoneEntry => {'zoneId': 'z', 'zoneName': 'Place'},
          RecoveryEventType.appUnlock => {
            'packageName': 'com.example.app',
            'appLabel': 'Sample app',
            'reason': 'work',
            'method': 'budget',
            'waitSeconds': 30,
            'unlockMinutes': 5,
            'paymentApp': false,
          },
          _ => <String, dynamic>{},
        }),
    ];
    expect(
      projectHistory(samples, HistoryCategory.recovery).map((e) => e.type),
      unorderedEquals(types),
    );
  });

  test(
    'location sources remain distinct, unknown stays unknown, manual pin is not GPS',
    () {
      RecoveryEvent zone(String? source) => event(RecoveryEventType.zoneEntry, {
        'zoneId': 'z',
        'zoneName': 'Place',
        'source': ?source,
      });
      final app = zone('app'),
          background = zone('background'),
          manual = zone('manualPin'),
          missing = zone(null),
          future = zone('future-source');
      final context = event(RecoveryEventType.relapse, {
        'zoneName': 'Place',
        'source': 'app',
      });
      final all = [app, background, manual, missing, future, context];
      for (final (source, expected) in [
        (HistoryLocationSource.foreground, [app]),
        (HistoryLocationSource.background, [background]),
        (HistoryLocationSource.manual, [manual]),
        (HistoryLocationSource.context, [context]),
      ]) {
        expect(
          projectHistory(all, HistoryCategory.location, source: source),
          expected,
        );
      }
      expect(
        projectHistory(
          all,
          HistoryCategory.location,
          source: HistoryLocationSource.unknown,
        ),
        unorderedEquals([missing, future]),
      );
      expect(manual.metadata.containsKey('latitude'), isFalse);
    },
  );

  test(
    'newest-first views are deterministic and linked record lookup stays scoped',
    () {
      final older = event(
        RecoveryEventType.relapse,
        {},
        time: at.subtract(const Duration(days: 1)),
      );
      final newer = event(RecoveryEventType.pledge, {});
      final setting = event(RecoveryEventType.settingsChange, {});
      expect(projectHistory([older, newer], HistoryCategory.recovery), [
        newer,
        older,
      ]);
      expect(
        projectHistory(
          [setting, older],
          HistoryCategory.recovery,
          recordId: setting.id,
        ),
        isEmpty,
      );
      expect(
        projectHistory([older], HistoryCategory.recovery, recordId: older.id),
        [same(older)],
      );
    },
  );

  test(
    'old and current settings fields preserve false, zero and missing values',
    () {
      final legacy = event(RecoveryEventType.settingsChange, {
        'setting': 'highContrast',
        'newValue': 'false',
      });
      expect(settingName(legacy), 'high Contrast');
      expect(settingValue(previousSettingValue(legacy)), 'Not recorded');
      expect(settingValue(nextSettingValue(legacy)), 'Off');
      final current = event(RecoveryEventType.settingsChange, {
        'field': 'dailySpend',
        'from': 0,
        'to': false,
        'source': 'manual',
      });
      expect(settingValue(previousSettingValue(current)), '0');
      expect(settingValue(nextSettingValue(current)), 'Off');
      expect(savedRecordSource(current), 'Manual');
      expect(savedRecordSource(legacy), 'Not recorded');
    },
  );

  test(
    'recorded time preserves original offset/precision and labels unknown timezone',
    () {
      const withoutOffset = '2026-01-20T18:15:01.123456';
      expect(
        recordedAtLabel(
          event(RecoveryEventType.relapse, {'recordedAt': withoutOffset}),
        ),
        '$withoutOffset (timezone not recorded)',
      );
      const offset = '2026-01-20T18:15:01.123456+05:30';
      expect(
        recordedAtLabel(
          event(RecoveryEventType.relapse, {'recordedAt': offset}),
        ),
        offset,
      );
      expect(
        recordedAtLabel(event(RecoveryEventType.relapse, {})),
        'Not recorded',
      );
      expect(
        recordedAtLabel(
          event(RecoveryEventType.relapse, {'recordedAt': 'broken'}),
        ),
        'Not recorded',
      );
    },
  );
}
