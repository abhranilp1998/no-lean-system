import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../domain/sos_flow.dart';

class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  Timer? _timer;
  late final DateTime _startedAt;
  late final RecoveryController _recovery;
  late final String _sessionId;
  late final Future<void> _startFuture;
  final _flow = SosFlow();
  bool _startSaved = false;
  int _ticks = 0;
  String? _selectedDebrief;
  DateTime? _completedAt;
  TrustedContact? _trustedContact;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _recovery = ref.read(recoveryProvider);
    _sessionId = const Uuid().v4();
    _startFuture = _saveStart();
    unawaited(_loadTrustedContact());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _ticks++;
        if (_flow.tick()) {
          _timer?.cancel();
          AppFeedback.success();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_completedAt != null) {
      unawaited(_recordCompletion(debrief: _selectedDebrief));
    }
    super.dispose();
  }

  void _completeGroundingStep() {
    AppFeedback.selection();
    setState(_flow.completeGroundingStep);
  }

  void _finishReasons() {
    if (!_flow.finishReasons()) return;
    AppFeedback.success();
    setState(() => _completedAt = DateTime.now());
    unawaited(_recordCompletion());
  }

  Future<void> _saveStart() async {
    try {
      await _recovery.startSosSession(id: _sessionId, startedAt: _startedAt);
      _startSaved = true;
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'SOS is available, but this session could not be saved. Keep going; you can retry when it finishes.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<bool> _recordCompletion({String? debrief}) async {
    final completedAt = _completedAt;
    if (completedAt == null) return false;
    await _startFuture;
    if (!_startSaved) await _saveStart();
    if (!_startSaved) return false;
    try {
      await _recovery.completeSosSession(
        startId: _sessionId,
        completedAt: completedAt,
        debrief: debrief,
      );
      return true;
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'Session completion could not be saved. Please retry before leaving.',
          type: AppNoticeType.error,
        );
      }
      return false;
    }
  }

  Future<void> _loadTrustedContact() async {
    try {
      final contact = await ref
          .read(trustedContactServiceProvider)
          .getContact();
      if (mounted) setState(() => _trustedContact = contact);
    } catch (_) {
      // SOS remains fully usable if encrypted contact storage is unavailable.
    }
  }

  Future<void> _callTrustedContact() async {
    final contact = _trustedContact;
    if (contact == null) return;
    try {
      final opened = await launchUrl(
        Uri(scheme: 'tel', path: contact.phone),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        AppNotice.show(
          context,
          'NO DIALER AVAILABLE // CALL ${contact.phone} MANUALLY.',
          type: AppNoticeType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'COULD NOT OPEN DIALER // CALL ${contact.phone} MANUALLY.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  Widget _stageBody(RecoveryController recovery) => switch (_flow.stage) {
    SosStage.breathe => _BreatheStage(flow: _flow),
    SosStage.ground => _GroundStage(
      flow: _flow,
      onDone: _completeGroundingStep,
    ),
    SosStage.reasons => _ReasonsStage(
      reasons: recovery.reasons,
      streak: recovery.streak,
      moneySaved: recovery.moneySaved,
      onDone: _finishReasons,
    ),
    SosStage.pledge => _PledgeStage(
      selectedDebrief: _selectedDebrief,
      onDebrief: (value) => setState(() => _selectedDebrief = value),
      onPledge: () async {
        if (!await _recordCompletion(debrief: _selectedDebrief)) return;
        if (!mounted) return;
        if (!await saveAction(
          context,
          () => ref.read(recoveryProvider).pledge(),
        )) {
          return;
        }
        if (mounted) Navigator.pop(context);
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final visuals = NoLeanVisuals.of(context);
    final canExit = _flow.canExit;
    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Breathe for ${_flow.minSecondsBeforeExit} seconds before leaving.',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor: red.withValues(alpha: .8),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        key: const ValueKey('sos-screen'),
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SosPainter(
                    _ticks,
                    effectScale: visuals.effectScale,
                    reduceMotion: visuals.reduceMotion,
                  ),
                ),
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 48),
                      const Spacer(),
                      const StatusPill(label: 'SYSTEM OVERRIDE', color: red),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey('sos-close'),
                        tooltip: canExit ? 'Leave SOS' : null,
                        onPressed: canExit
                            ? () => Navigator.pop(context)
                            : null,
                        icon: Icon(
                          Icons.close,
                          color: canExit ? red : red.withValues(alpha: .3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SOS MODE',
                    textAlign: TextAlign.center,
                    style: displayFont(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: red,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'DO NOT BUY. DO NOT DRIVE. STAY HERE.',
                    textAlign: TextAlign.center,
                    style: microStyle.copyWith(
                      color: Colors.white70,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _StageProgress(flow: _flow),
                  const SizedBox(height: 22),
                  Text(
                    'STEP ${_flow.stage.index + 1}/${SosStage.values.length} // ${_flow.stage.headline}',
                    key: const ValueKey('sos-stage-title'),
                    textAlign: TextAlign.center,
                    style: displayFont(
                      fontSize: 15,
                      color: red,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: visuals.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(_flow.stage),
                      child: _stageBody(recovery),
                    ),
                  ),
                  if (_trustedContact != null) ...[
                    const SizedBox(height: 22),
                    OutlinedButton.icon(
                      onPressed: _callTrustedContact,
                      icon: const Icon(Icons.phone),
                      label: Text(
                        'CALL ${_trustedContact!.name.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cyan,
                        side: const BorderSide(color: cyan),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageProgress extends StatelessWidget {
  const _StageProgress({required this.flow});

  final SosFlow flow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'SOS step ${flow.stage.index + 1} of ${SosStage.values.length}, ${flow.stage.label}',
      child: Column(
        key: const ValueKey('sos-progress'),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: flow.progress,
              minHeight: 5,
              color: red,
              backgroundColor: red.withValues(alpha: .14),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final stage in SosStage.values)
                Expanded(
                  child: Text(
                    '${stage.index + 1} ${stage.label}',
                    textAlign: TextAlign.center,
                    style: microStyle.copyWith(
                      fontSize: 8.5,
                      color: stage == flow.stage
                          ? red
                          : stage.index < flow.stage.index
                          ? toxic
                          : muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreatheStage extends StatelessWidget {
  const _BreatheStage({required this.flow});

  final SosFlow flow;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.square(
                dimension: 220,
                child: CircularProgressIndicator(
                  value: flow.remaining / flow.breathSeconds,
                  strokeWidth: 7,
                  color: red,
                  backgroundColor: red.withValues(alpha: .12),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${flow.remaining}',
                    key: const ValueKey('sos-seconds'),
                    style: displayFont(
                      fontSize: 64,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text('SECONDS', style: microStyle.copyWith(color: red)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          flow.breathPhase,
          textAlign: TextAlign.center,
          style: displayFont(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Four seconds in, four hold, four out, four hold. The urge peaks, then drops. Give it the full minute.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11.5, height: 1.45),
        ),
      ],
    );
  }
}

class _GroundStage extends StatelessWidget {
  const _GroundStage({required this.flow, required this.onDone});

  final SosFlow flow;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final step = flow.groundingStep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < groundingSteps.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < flow.groundIndex
                      ? toxic.withValues(alpha: .2)
                      : Colors.transparent,
                  border: Border.all(
                    color: i == flow.groundIndex
                        ? red
                        : i < flow.groundIndex
                        ? toxic
                        : muted,
                  ),
                ),
                child: Text(
                  '${groundingSteps[i].count}',
                  style: displayFont(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        GlassCard(
          accent: red,
          child: Column(
            children: [
              Text(
                '${step.count} // ${step.sense}',
                key: const ValueKey('sos-ground-sense'),
                style: displayFont(
                  fontSize: 30,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                step.prompt,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GlowButton(
          key: const ValueKey('sos-ground-next'),
          label: 'DONE // ${step.count} ${step.sense}',
          icon: Icons.check,
          color: red,
          onTap: onDone,
        ),
      ],
    );
  }
}

class _ReasonsStage extends StatelessWidget {
  const _ReasonsStage({
    required this.reasons,
    required this.streak,
    required this.moneySaved,
    required this.onDone,
  });

  final List<String> reasons;
  final int streak;
  final double moneySaved;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          accent: red,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WHY YOU ARE DONE WITH THIS',
                style: microStyle.copyWith(color: red),
              ),
              const SizedBox(height: 12),
              if (reasons.isEmpty)
                const Text(
                  'No reasons saved yet. Say one out loud now, then add it in Settings before the next risk window.',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.35),
                )
              else
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '—',
                          style: TextStyle(
                            color: red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reason,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ON THE LINE // $streak DAY${streak == 1 ? '' : 'S'} CLEAN'
          '${moneySaved > 0 ? ' // ${moneySaved.toStringAsFixed(0)} KEPT' : ''}',
          key: const ValueKey('sos-on-the-line'),
          textAlign: TextAlign.center,
          style: microStyle.copyWith(color: toxic),
        ),
        const SizedBox(height: 18),
        GlowButton(
          key: const ValueKey('sos-reasons-next'),
          label: 'I READ THEM',
          icon: Icons.arrow_forward,
          color: red,
          onTap: onDone,
        ),
      ],
    );
  }
}

class _PledgeStage extends StatelessWidget {
  const _PledgeStage({
    required this.selectedDebrief,
    required this.onDebrief,
    required this.onPledge,
  });

  final String? selectedDebrief;
  final ValueChanged<String> onDebrief;
  final Future<void> Function() onPledge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'You rode it out. Check in, then lock today.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: toxic,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DebriefButton(
              label: 'BETTER',
              icon: Icons.arrow_downward,
              selected: selectedDebrief == 'down',
              onTap: () => onDebrief('down'),
            ),
            const SizedBox(width: 8),
            _DebriefButton(
              label: 'SAME',
              icon: Icons.compare_arrows,
              selected: selectedDebrief == 'same',
              onTap: () => onDebrief('same'),
            ),
            const SizedBox(width: 8),
            _DebriefButton(
              label: 'WORSE',
              icon: Icons.arrow_upward,
              selected: selectedDebrief == 'worse',
              onTap: () => onDebrief('worse'),
            ),
          ],
        ),
        if (selectedDebrief == 'worse' || selectedDebrief == 'same') ...[
          const SizedBox(height: 12),
          const Text(
            'Still there? Stay put and run it again, or call someone before you move.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11.5, height: 1.4),
          ),
        ],
        const SizedBox(height: 22),
        GlowButton(
          key: const ValueKey('sos-pledge'),
          label: 'I WILL NOT BUY LEAN TODAY',
          icon: Icons.lock_outline,
          color: toxic,
          onTap: onPledge,
        ),
      ],
    );
  }
}

class _SosPainter extends CustomPainter {
  _SosPainter(
    this.ticks, {
    required this.effectScale,
    required this.reduceMotion,
  });

  final int ticks;
  final double effectScale;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = reduceMotion
        ? .065 * effectScale
        : (.06 + (ticks % 2) * .03) * effectScale;
    final paint = Paint()
      ..color = red.withValues(alpha: pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(Offset(size.width / 2, 260), 160, paint);
    final line = Paint()
      ..color = red.withValues(alpha: (.08 * effectScale).clamp(0, .18))
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _SosPainter oldDelegate) =>
      oldDelegate.ticks != ticks ||
      oldDelegate.effectScale != effectScale ||
      oldDelegate.reduceMotion != reduceMotion;
}

class _DebriefButton extends StatelessWidget {
  const _DebriefButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? toxic.withValues(alpha: .2)
              : Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? toxic : Colors.white.withValues(alpha: .1),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? toxic : Colors.white54, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? toxic : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
