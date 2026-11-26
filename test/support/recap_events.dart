import 'package:no_lean/features/recovery/domain/recovery_event.dart';

RecoveryEvent startAt(DateTime at) =>
    RecoveryEvent.create(type: RecoveryEventType.recoveryStart, timestamp: at);

RecoveryEvent relapseAt(
  DateTime at, {
  String type = 'fullLean',
  Map<String, dynamic> extra = const {},
}) => RecoveryEvent.create(
  type: RecoveryEventType.relapse,
  timestamp: at,
  metadata: {'relapseType': type, ...extra},
);

RecoveryEvent cravingAt(
  DateTime at, {
  int intensity = 6,
  String trigger = 'Evenings',
}) => RecoveryEvent.create(
  type: RecoveryEventType.craving,
  timestamp: at,
  metadata: {'intensity': intensity, 'trigger': trigger},
);

RecoveryEvent recheckAt(DateTime at, String outcome) => RecoveryEvent.create(
  type: RecoveryEventType.cravingCheck,
  timestamp: at,
  metadata: {'cravingId': 'c', 'intensity': 2, 'outcome': outcome},
);

RecoveryEvent sosDoneAt(DateTime at) =>
    RecoveryEvent.create(type: RecoveryEventType.sosComplete, timestamp: at);
