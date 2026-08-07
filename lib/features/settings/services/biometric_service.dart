import 'package:flutter/material.dart';

import '../../../core/services/app_notice.dart';
import '../../recovery/services/relapse_lock_service.dart';

Future<void> verifyBiometricAuthentication(BuildContext context) async {
  final result = await SecureRelapseLockService.instance
      .authenticateBiometrically(
        reason: 'Verify biometrics for protected NO LEAN actions.',
      );
  if (!context.mounted) return;

  switch (result) {
    case BiometricAuthResult.authenticated:
      AppNotice.show(
        context,
        'BIOMETRIC IDENTITY VERIFIED // RELAPSE LOCK READY.',
        type: AppNoticeType.success,
      );
    case BiometricAuthResult.unavailable:
      AppNotice.show(
        context,
        'NO ENROLLED BIOMETRIC FOUND // ENCRYPTED PIN FALLBACK REMAINS AVAILABLE.',
        type: AppNoticeType.warning,
      );
    case BiometricAuthResult.denied:
      AppNotice.show(
        context,
        'BIOMETRIC VERIFICATION DENIED.',
        type: AppNoticeType.error,
      );
  }
}
