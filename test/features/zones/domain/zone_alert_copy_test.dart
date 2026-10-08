import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_alert_copy.dart';

void main() {
  final zone = DangerZone(
    id: 'z1',
    name: 'Corner pharmacy',
    latitude: 22.57,
    longitude: 88.36,
    radiusMeters: 200,
    createdAt: DateTime(2026, 10, 2),
  );

  test('zone copy states only recorded facts and the next move', () {
    final copy = buildZoneAlertCopy(
      zone: zone,
      now: DateTime(2026, 10, 8, 18, 30),
      cleanSince: DateTime(2026, 10, 3),
      riskWindow: const RiskWindow.defaultWindow(),
    );
    expect(copy.title, 'DANGER ZONE // CORNER PHARMACY');
    expect(copy.body, contains('on 2 Oct'));
    expect(copy.body, contains('Clean since 3 Oct.'));
    expect(copy.body, contains('inside your 17:00—21:00 risk window'));
    expect(copy.body, contains('open SOS'));
    for (final word in ['weak', 'shame', 'failure', 'pathetic']) {
      expect(copy.body.toLowerCase(), isNot(contains(word)));
    }
  });

  test('risk-window line only appears inside the window', () {
    final copy = buildZoneAlertCopy(
      zone: zone,
      now: DateTime(2026, 10, 8, 11),
      riskWindow: const RiskWindow.defaultWindow(),
    );
    expect(copy.body, isNot(contains('risk window')));
  });
}
