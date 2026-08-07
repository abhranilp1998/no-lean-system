import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recovery_controller.dart';

final recoveryProvider = ChangeNotifierProvider<RecoveryController>((ref) {
  return RecoveryController()..load();
});
