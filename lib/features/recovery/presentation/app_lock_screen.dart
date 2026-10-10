import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import '../domain/app_lock_session.dart';
import 'relapse_auth_dialog.dart';

/// Full-shell PIN/biometric wall. SOS and craving logging stay one tap away
/// without unlocking, per the product rule that emergency actions are never
/// hidden behind authentication.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({
    required this.reason,
    required this.onUnlocked,
    required this.onOpenSos,
    required this.onLogCraving,
    super.key,
  });

  final AppLockReason reason;
  final VoidCallback onUnlocked;
  final VoidCallback onOpenSos;
  final VoidCallback onLogCraving;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final recovery = ref.read(recoveryProvider);
    try {
      var result = await recovery.unlockApp();
      if (result == ProtectedActionResult.authenticationRequired && mounted) {
        final pin = await showRelapsePinDialog(context, actionLabel: 'UNLOCK');
        if (pin == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        result = await recovery.unlockApp(pin: pin, tryBiometrics: false);
      }
      if (!mounted) return;
      if (result == ProtectedActionResult.completed) {
        setState(() => _busy = false);
        widget.onUnlocked();
        return;
      }
      setState(() {
        _busy = false;
        _error = result.failureMessage;
      });
    } on RecoverySaveException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final isWindow = widget.reason == AppLockReason.riskWindow;
    final evidence = recovery.riskWindowEvidence;
    final pill = isWindow
        ? 'RISK WINDOW // ${recovery.riskWindow.label}'
        : 'RELAPSE LOGGED // ENTRY SAVED';
    final title = isWindow ? 'WINDOW LOCK ACTIVE' : 'LOCKED AFTER RELAPSE LOG';
    final body = isWindow
        ? [
            'You armed this lock for ${recovery.riskWindow.label}.',
            if (evidence.signalCount > 0)
              '${evidence.signalCount} of your logged risk signals land inside this window.',
            'Unlock with biometrics or your PIN, or open SOS first.',
          ].join(' ')
        : 'Your entry is saved. The app re-locks after a relapse log so the next step is deliberate. SOS and craving logging stay open without unlocking.';

    return Semantics(
      container: true,
      label: 'NO LEAN is locked',
      child: ListView(
        key: const ValueKey('app-lock-screen'),
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 30),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(label: pill, color: isWindow ? magenta : red),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.lock_outline, color: isWindow ? magenta : red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: displayFont(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlassCard(
            accent: isWindow ? magenta : red,
            child: Text(
              body,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              key: const ValueKey('app-lock-error'),
              style: const TextStyle(color: red, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 22),
          GlowButton(
            key: const ValueKey('app-lock-unlock'),
            label: _busy ? 'VERIFYING…' : 'UNLOCK',
            icon: Icons.fingerprint,
            color: cyan,
            onTap: _unlock,
          ),
          const SizedBox(height: 12),
          GlowButton(
            key: const ValueKey('app-lock-sos'),
            label: 'OPEN SOS',
            icon: Icons.emergency_outlined,
            color: red,
            onTap: widget.onOpenSos,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('app-lock-craving'),
            onPressed: widget.onLogCraving,
            icon: const Icon(Icons.bolt, color: cyan),
            label: const Text('LOG CRAVING'),
          ),
        ],
      ),
    );
  }
}
