import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recovery_controller.dart';
import '../services/recovery_state_store.dart';
import '../../zones/services/native_geofence_gateway.dart';
import '../../zones/services/zone_entry_inbox.dart';

final recoveryProvider = ChangeNotifierProvider<RecoveryController>((ref) {
  return RecoveryController(
    store: FileRecoveryStateStore(),
    geofences: NativeGeofenceGateway(),
    zoneInbox: FileZoneEntryInbox(),
  )..load();
});
