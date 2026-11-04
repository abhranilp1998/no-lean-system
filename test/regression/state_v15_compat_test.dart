import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';

import '../support/recovery_fakes.dart';

/// Regression: 1.5.0 was cut from main (state v13) and showed the
/// "needs a compatible app version" screen on phones carrying state v15
/// from the widgets builds. Every state version up to the current one must
/// open.
void main() {
  Future<RecoveryController> open(String? stored) async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(stored),
      relapseLock: FakeRelapseLock(),
    );
    await c.load();
    return c;
  }

  Future<Map<String, dynamic>> syntheticV15() async {
    final seed = MemoryRecoveryStore();
    final c = RecoveryController(store: seed, relapseLock: FakeRelapseLock());
    await c.load();
    final now = DateTime.now();
    for (var i = 1; i <= 5; i++) {
      await c.recordCraving(
        CravingEntry(
          intensity: 6,
          trigger: 'evening',
          note: 'synthetic',
          createdAt: now.subtract(Duration(days: i, hours: 2)),
        ),
      );
    }
    await c.recordRelapse(
      occurredAt: [now.subtract(const Duration(days: 3))],
      tryBiometrics: false,
    );
    final map = Map<String, dynamic>.from(jsonDecode(seed.value!) as Map);
    // Shape of a real widgets-build (v15) snapshot.
    map.addAll({
      'stateVersion': 15,
      'zones': <Object>[],
      'zoneMonitoring': true,
      'appLockPolicy': <String, Object>{},
      'widgetPrivacy': true,
      'quietHoursEnabled': false,
      'quietHours': {'startMinutes': 1320, 'endMinutes': 420},
      'futureLetters': <Object>[],
      'stretchedWidgetView': 'wave',
    });
    return map;
  }

  test('current build supports state v15 or newer', () {
    expect(RecoveryController.stateVersion, greaterThanOrEqualTo(15));
  });

  for (final v in [13, 14, 15]) {
    test('state v$v snapshot opens without the compatibility screen', () async {
      final map = await syntheticV15()
        ..['stateVersion'] = v;
      final expected = (map['events'] as List).length;
      final c = await open(jsonEncode(map));
      expect(c.loadStatus, RecoveryLoadStatus.ready, reason: c.loadMessage);
      expect(c.events.length, greaterThanOrEqualTo(expected));
    });
  }

  // Local-only check against a real export; the file is never committed.
  final real = Platform.environment['NOLEAN_REAL_EXPORT'];
  test('real exported copies open', () async {
    final d = jsonDecode(File(real!).readAsStringSync()) as Map;
    for (final copy in (d['copies'] as List).cast<Map>()) {
      final c = await open(jsonEncode(copy));
      final n = (copy['events'] as List?)?.length;
      // ignore: avoid_print
      print(
        'copy v${copy['stateVersion']}: ${c.loadStatus.name}, '
        'stored events $n, loaded ${c.events.length}',
      );
      expect(c.loadStatus, RecoveryLoadStatus.ready, reason: c.loadMessage);
      if (n != null) expect(c.events.length, greaterThanOrEqualTo(n));
    }
  }, skip: real == null ? 'set NOLEAN_REAL_EXPORT to run' : false);
}
