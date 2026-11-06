import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

void main() {
  test('tapping the zone alert body opens the zone SOS; actions win', () {
    expect(
      NotificationService.actionFor(
        null,
        1,
        NotificationService.zoneAlertPayload,
      ),
      'action_zone_open',
    );
    expect(
      NotificationService.actionFor(
        'action_locate',
        1,
        NotificationService.zoneAlertPayload,
      ),
      'action_locate',
    );
    expect(
      NotificationService.actionFor(null, NotificationService.useCheckId),
      NotificationService.useCheckOpenAction,
    );
  });
}
