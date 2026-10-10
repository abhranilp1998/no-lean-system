import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/dose_safety_cards.dart'
    show emergencyNumber;
import '../../recovery/presentation/relapse_auth_dialog.dart';
import '../application/app_lock_providers.dart';
import '../domain/exit_plan.dart';
import '../domain/locked_app.dart';
import '../services/app_lock_gateway.dart';

enum _Stage { locked, reason, waiting, ready }

/// Shown over a locked app. The user is never trapped: SOS, Call 112 and
/// Go home are always on screen, Back goes home, and "I need this app"
/// always leads to a way in (budget wait, PIN, or the long wait).
class AppBlockScreen extends ConsumerStatefulWidget {
  const AppBlockScreen({required this.request, this.dialer, super.key});

  final AppBlockRequest request;

  /// Test hook for the 112 call.
  final Future<bool> Function(Uri uri)? dialer;

  static Future<void> open(BuildContext context, AppBlockRequest request) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AppBlockScreen(request: request),
        ),
      );

  @override
  ConsumerState<AppBlockScreen> createState() => _AppBlockScreenState();
}

class _AppBlockScreenState extends ConsumerState<AppBlockScreen> {
  _Stage _stage = _Stage.locked;
  UnlockReason? _reason;
  ExitStep? _step;
  int _remaining = 0;
  Timer? _timer;
  bool _busy = false;
  String? _error;

  AppBlockRequest get _request => widget.request;

  LockedApp? get _app =>
      ref.read(recoveryProvider).appLockPolicy.appFor(_request.packageName);

  bool get _paymentApp => _app?.paymentApp ?? false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _goHome() async {
    _timer?.cancel();
    await ref.read(appLockGatewayProvider).goHome();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openSos() async {
    _timer?.cancel();
    if (_stage == _Stage.waiting) setState(() => _stage = _Stage.locked);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
  }

  Future<void> _call112() async {
    final uri = Uri(scheme: 'tel', path: emergencyNumber);
    try {
      final opened =
          await (widget.dialer ??
              (uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication))(uri);
      if (!opened && mounted) {
        AppNotice.show(
          context,
          'NO DIALER AVAILABLE // CALL $emergencyNumber MANUALLY.',
          type: AppNoticeType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'COULD NOT OPEN DIALER // CALL $emergencyNumber MANUALLY.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _chooseReason(UnlockReason reason) async {
    final recovery = ref.read(recoveryProvider);
    final step = planUnlock(
      paymentApp: _paymentApp,
      usedToday: recovery.appUnlocksUsedToday,
      dailyBudget: recovery.appLockPolicy.dailyUnlockBudget,
      pinConfigured: recovery.appUnlockPinConfigured,
    );
    _reason = reason;
    if (step.needsPin) {
      await _verifyPin(step);
    } else {
      _startWait(step);
    }
  }

  Future<void> _verifyPin(ExitStep step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final recovery = ref.read(recoveryProvider);
    var result = await recovery.authorizeAppUnlock();
    if (result == ProtectedActionResult.authenticationRequired && mounted) {
      final pin = await showRelapsePinDialog(context, actionLabel: 'UNLOCK');
      if (pin == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      result = await recovery.authorizeAppUnlock(
        pin: pin,
        tryBiometrics: false,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case ProtectedActionResult.completed:
        setState(() {
          _step = step;
          _stage = _Stage.ready;
        });
      case ProtectedActionResult.lockedOut:
        // Never a dead end: PIN entry is paused, so take the long wait.
        _error =
            'PIN entry is paused after too many attempts. You can still open the app after a longer wait.';
        _startWait(
          planUnlock(
            paymentApp: _paymentApp,
            usedToday: recovery.appUnlocksUsedToday,
            dailyBudget: recovery.appLockPolicy.dailyUnlockBudget,
            pinConfigured: true,
            pinLockedOut: true,
          ),
        );
      case ProtectedActionResult.denied:
      case ProtectedActionResult.authenticationRequired:
        setState(() => _error = result.failureMessage);
    }
  }

  void _startWait(ExitStep step) {
    _timer?.cancel();
    setState(() {
      _step = step;
      _remaining = step.wait.inSeconds;
      _stage = _remaining <= 0 ? _Stage.ready : _Stage.waiting;
    });
    if (_remaining <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        setState(() => _stage = _Stage.ready);
      }
    });
  }

  void _cancelWait() {
    _timer?.cancel();
    setState(() {
      _stage = _Stage.locked;
      _step = null;
      _reason = null;
      _error = null;
    });
  }

  Future<void> _open() async {
    final step = _step;
    final reason = _reason;
    if (step == null || reason == null || _busy) return;
    setState(() => _busy = true);
    final recovery = ref.read(recoveryProvider);
    try {
      await recovery.recordAppUnlock(
        appUnlockMetadata(
          packageName: _request.packageName,
          appLabel: _app?.label ?? _request.label,
          reason: reason,
          step: step,
          paymentApp: _paymentApp,
          zoneName: _request.zoneName,
        ),
      );
    } catch (_) {
      // Logging failed: still let the user in (never a dead end).
    }
    final opened = await ref
        .read(appLockGatewayProvider)
        .grantTemporaryUnlock(_request.packageName, step.unlockFor);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      AppNotice.show(
        context,
        '${_request.label.toUpperCase()} IS UNLOCKED FOR 5 MIN // open it from your home screen.',
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final policy = recovery.appLockPolicy;
    final left = recovery.appUnlocksLeftToday;
    final why = _request.cause == 'zone' && _request.zoneName != null
        ? 'You are inside ${_request.zoneName}.'
        : '${policy.schedule.label} lock is on'
              '${policy.schedule == AppLockSchedule.riskWindow ? ' (${recovery.riskWindow.label})' : ''}.';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_goHome());
      },
      child: Scaffold(
        key: const ValueKey('app-block-screen'),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: 'APP LOCKED // ${_request.label.toUpperCase()}',
                  color: magenta,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'NOT RIGHT NOW.',
                style: displayFont(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '$why You chose to lock ${_request.label}.',
                style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              ..._stageContent(left),
              if (_error case final error?) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  key: const ValueKey('app-block-error'),
                  style: const TextStyle(color: red, fontSize: 12, height: 1.4),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GlowButton(
                      key: const ValueKey('app-block-sos'),
                      label: 'SOS',
                      icon: Icons.emergency_outlined,
                      color: red,
                      onTap: () => unawaited(_openSos()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('app-block-call-112'),
                      onPressed: () => unawaited(_call112()),
                      style: FilledButton.styleFrom(
                        backgroundColor: red,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.call),
                      label: const Text('CALL $emergencyNumber'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('app-block-home'),
                onPressed: () => unawaited(_goHome()),
                icon: const Icon(Icons.home_outlined, color: cyan),
                label: const Text('GO HOME'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageContent(int left) {
    final recovery = ref.read(recoveryProvider);
    switch (_stage) {
      case _Stage.locked:
        final budgetText = left > 0
            ? '$left of ${recovery.appLockPolicy.dailyUnlockBudget} unlocks left today.'
            : recovery.appUnlockPinConfigured
            ? 'Today\'s unlocks are used. Your PIN opens it.'
            : 'Today\'s unlocks are used. A longer wait still opens it.';
        return [
          GlowButton(
            key: const ValueKey('app-block-need'),
            label: 'I NEED THIS APP',
            icon: Icons.lock_open_outlined,
            color: cyan,
            onTap: () => setState(() {
              _stage = _Stage.reason;
              _error = null;
            }),
          ),
          const SizedBox(height: 6),
          Text(
            '${_paymentApp ? 'Payment app: 10 s wait. ' : ''}$budgetText',
            key: const ValueKey('app-block-budget'),
            style: microStyle,
          ),
        ];
      case _Stage.reason:
        return [
          Text('WHAT DO YOU NEED IT FOR?', style: eyebrowStyle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in UnlockReason.values)
                ActionChip(
                  key: ValueKey('app-block-reason-${reason.name}'),
                  label: Text(reason.label.toUpperCase()),
                  onPressed: _busy ? null : () => _chooseReason(reason),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('app-block-reason-cancel'),
            onPressed: _cancelWait,
            child: const Text('BACK'),
          ),
        ];
      case _Stage.waiting:
        final reasons = recovery.reasons;
        return [
          GlassCard(
            accent: purple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BREATHE // $_remaining s',
                  key: const ValueKey('app-block-countdown'),
                  style: eyebrowStyle.copyWith(color: purple),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your own reasons, before you go in:',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                if (reasons.isEmpty)
                  const Text('You are doing this for a reason. Remember it.')
                else
                  for (final reason in reasons)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $reason',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('app-block-wait-cancel'),
            onPressed: _cancelWait,
            child: const Text('I DON\'T NEED IT AFTER ALL'),
          ),
        ];
      case _Stage.ready:
        return [
          GlowButton(
            key: const ValueKey('app-block-open'),
            label: _busy
                ? 'OPENING…'
                : 'OPEN ${_request.label.toUpperCase()} FOR '
                      '${(_step?.unlockFor ?? ExitPlanTimings.unlockFor).inMinutes} MIN',
            icon: Icons.open_in_new,
            color: toxic,
            onTap: () => unawaited(_open()),
          ),
          const SizedBox(height: 6),
          const Text(
            'Only this app opens. It locks again when the time is up. This unlock goes on your timeline.',
            style: microStyle,
          ),
        ];
    }
  }
}
