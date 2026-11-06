import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/zones/domain/zone_entry_recency.dart';

void main() {
  final now = DateTime(2026, 11, 4, 21);
  RecoveryEvent entry(Duration ago, String zoneId) => RecoveryEvent.fromJson({
    'id': 'e-$zoneId',
    'type': RecoveryEventType.zoneEntry.name,
    'timestamp': now.subtract(ago).toIso8601String(),
    'metadata': {'zoneId': zoneId, 'zoneName': 'Zone', 'source': 'app'},
  });

  test('entries older than 30 min are ignored', () {
    expect(
      recentZoneEntry([entry(const Duration(minutes: 31), 'old')], now),
      isNull,
    );
    expect(
      recentZoneEntry([
        entry(const Duration(hours: 5), 'old'),
        entry(const Duration(minutes: 10), 'new'),
      ], now)?.metadata['zoneId'],
      'new',
    );
  });

  test('follow-ups never name the zone, privacy mode on or off', () {
    const hidden = NotificationPrefs(hideSensitive: true);
    expect(zoneFollowUpText(hidden, 0).title, neutralNotificationText.title);
    const open = NotificationPrefs();
    for (final i in [0, 1]) {
      final t = zoneFollowUpText(open, i);
      expect(t.title, 'CHECKING IN');
      expect(t.body, isNot(contains('zone')));
      expect(t.body, isNot(contains('since')));
    }
  });
}
