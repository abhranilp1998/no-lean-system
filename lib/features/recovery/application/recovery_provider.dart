import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recovery_controller.dart';
import '../services/recovery_state_store.dart';

final recoveryProvider = ChangeNotifierProvider<RecoveryController>((ref) {
  return RecoveryController(store: FileRecoveryStateStore())..load();
});
