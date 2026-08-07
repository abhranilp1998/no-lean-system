import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

Future<void> testBiometricAvailability(BuildContext context) async {
  try {
    final auth = LocalAuthentication();
    final available =
        await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          available
              ? 'BIOMETRIC HARDWARE DETECTED.'
              : 'NO BIOMETRIC AUTHENTICATOR AVAILABLE ON THIS DEVICE.',
        ),
        backgroundColor: available
            ? const Color(0xFF223C1B)
            : const Color(0xFF431522),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BIOMETRIC CHECK UNAVAILABLE.')),
      );
    }
  }
}
