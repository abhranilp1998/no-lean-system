import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import '../domain/app_lock_session.dart';
import '../domain/post_relapse_summary.dart';
import 'post_relapse_lock_body.dart';
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
    this.now,
    super.key,
  });

  final AppLockReason reason;
  final VoidCallback onUnlocked;
  final VoidCallback onOpenSos;
  final VoidCallback onLogCraving;

  /// Test seam for the greeting and the 24-hour mixing window.
  final DateTime Function()? now;

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
    if (!isWindow) return _buildAfterRelapse(recovery);
    final evidence = recovery.riskWindowEvidence;
    final body = [
      'You armed this lock for ${recovery.riskWindow.label}.',
      if (evidence.signalCount > 0)
        '${evidence.signalCount} of your logged risk signals land inside this window.',
      'Unlock with biometrics or your PIN, or open SOS first.',
    ].join(' ');

    return Semantics(
      container: true,
      label: 'NO LEAN is locked',
      child: ListView(
        key: const ValueKey('app-lock-screen'),
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 30),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: 'RISK WINDOW // ${recovery.riskWindow.label}',
              color: magenta,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.lock_outline, color: magenta),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'WINDOW LOCK ACTIVE',
                  style: displayFont(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlassCard(
            accent: magenta,
            child: Text(
              body,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          ),
          ..._errorLine(),
          const SizedBox(height: 22),
          _unlockButton(),
          const SizedBox(height: 12),
          _sosButton(),
          const SizedBox(height: 12),
          _cravingButton(),
        ],
      ),
    );
  }

  /// After a relapse log: a scrolling, personal page with a pinned action bar
  /// so UNLOCK, SOS and LOG CRAVING stay reachable on any screen size.
  Widget _buildAfterRelapse(RecoveryController recovery) {
    final now = (widget.now ?? DateTime.now)();
    final summary = buildPostRelapseSummary(
      events: recovery.events,
      now: now,
      liveStreakDays: recovery.streak,
      longestStreakDays: recovery.longestStreak,
    );
    return Semantics(
      container: true,
      label: 'NO LEAN is locked',
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('app-lock-screen'),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                children: [PostRelapseLockBody(summary: summary, now: now)],
              ),
            ),
            // The bar never takes more than ~45% of the height, so large text
            // on a small screen still leaves room to read; it scrolls instead.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight * .45),
              child: DecoratedBox(
                key: const ValueKey('app-lock-actions'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: cyan.withValues(alpha: .3)),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._errorLine(),
                        _unlockButton(),
                        const SizedBox(height: 10),
                        // Large text: stack instead of squeezing.
                        if (MediaQuery.textScalerOf(context).scale(1) > 1.2)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sosButton(),
                              const SizedBox(height: 8),
                              _cravingButton(),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: _sosButton()),
                              const SizedBox(width: 10),
                              Expanded(child: _cravingButton()),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _errorLine() => [
    if (_error case final error?) ...[
      const SizedBox(height: 12),
      Text(
        error,
        key: const ValueKey('app-lock-error'),
        style: const TextStyle(color: red, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 8),
    ],
  ];

  Widget _unlockButton() => GlowButton(
    key: const ValueKey('app-lock-unlock'),
    label: _busy ? 'VERIFYING…' : 'UNLOCK',
    icon: Icons.fingerprint,
    color: cyan,
    onTap: _unlock,
  );

  Widget _sosButton() => GlowButton(
    key: const ValueKey('app-lock-sos'),
    label: 'OPEN SOS',
    icon: Icons.emergency_outlined,
    color: red,
    onTap: widget.onOpenSos,
  );

  Widget _cravingButton() => OutlinedButton.icon(
    key: const ValueKey('app-lock-craving'),
    onPressed: widget.onLogCraving,
    icon: const Icon(Icons.bolt, color: cyan),
    label: const Text('LOG CRAVING'),
  );
}
