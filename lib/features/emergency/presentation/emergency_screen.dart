import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/sos_session.dart';

class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  Timer? _timer;
  late final DateTime _startedAt;
  late final RecoveryController _recovery;
  int _remaining = 60;
  bool _finished = false;
  bool _sessionRecorded = false;
  String? _selectedDebrief;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _recovery = ref.read(recoveryProvider);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() {
          _remaining = 0;
          _finished = true;
        });
        unawaited(_recordSession(completedAt: DateTime.now()));
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_sessionRecorded) {
      unawaited(_recordSession());
    }
    super.dispose();
  }

  Future<void> _recordSession({DateTime? completedAt, String? debrief}) async {
    if (_sessionRecorded) return;
    _sessionRecorded = true;
    if (completedAt != null) AppFeedback.success();
    await _recovery.recordSosSession(
      SosSession(startedAt: _startedAt, completedAt: completedAt, debrief: debrief),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final visuals = NoLeanVisuals.of(context);
    final phase = _remaining > 45
        ? 'BREATHE IN'
        : _remaining > 30
        ? 'HOLD THE LINE'
        : _remaining > 15
        ? 'BREATHE OUT'
        : 'LET THE WAVE PASS';
    return PopScope(
      canPop: _remaining <= 45,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Breathe for at least 15 seconds before leaving.',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor: red.withValues(alpha: .8),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SosPainter(
                    _remaining,
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
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.close, color: Colors.transparent),
                      ),
                      const Spacer(),
                      const StatusPill(label: 'SYSTEM OVERRIDE', color: red),
                      const Spacer(),
                      IconButton(
                        onPressed: _remaining <= 45 ? () => Navigator.pop(context) : null,
                        icon: Icon(
                          Icons.close,
                          color: _remaining <= 45 ? red : red.withValues(alpha: .3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                const SizedBox(height: 36),
                SizedBox(
                  height: 246,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _remaining / 60,
                          strokeWidth: 7,
                          color: red,
                          backgroundColor: red.withValues(alpha: .12),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$_remaining',
                            style: displayFont(
                              fontSize: 70,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'SECONDS',
                            style: microStyle.copyWith(color: red),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  phase,
                  textAlign: TextAlign.center,
                  style: displayFont(
                    fontSize: 15,
                    color: red,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 30),
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
                      if (recovery.reasons.isEmpty)
                        const Text(
                          'No reasons saved yet. Add them in Settings before the next risk window.',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.35,
                          ),
                        )
                      else
                        ...recovery.reasons.map(
                          (reason) => Padding(
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (!_finished)
                  const Text(
                    'The urge peaks, then drops. Give it the minute it is asking for.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 11, height: 1.4),
                  ),
                if (_finished) ...[
                  const Text(
                    'You stayed for the wave. How are you feeling?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: toxic,
                      fontSize: 12,
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
                        selected: _selectedDebrief == 'down',
                        onTap: () => setState(() => _selectedDebrief = 'down'),
                      ),
                      const SizedBox(width: 8),
                      _DebriefButton(
                        label: 'SAME',
                        icon: Icons.compare_arrows,
                        selected: _selectedDebrief == 'same',
                        onTap: () => setState(() => _selectedDebrief = 'same'),
                      ),
                      const SizedBox(width: 8),
                      _DebriefButton(
                        label: 'WORSE',
                        icon: Icons.arrow_upward,
                        selected: _selectedDebrief == 'worse',
                        onTap: () => setState(() => _selectedDebrief = 'worse'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GlowButton(
                    label: 'I WILL NOT BUY LEAN TODAY',
                    icon: Icons.lock_outline,
                    color: toxic,
                    onTap: () async {
                      if (_selectedDebrief != null && !_sessionRecorded) {
                        unawaited(_recordSession(completedAt: DateTime.now(), debrief: _selectedDebrief));
                      }
                      await ref.read(recoveryProvider).pledge();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ));
  }
}

class _SosPainter extends CustomPainter {
  _SosPainter(
    this.remaining, {
    required this.effectScale,
    required this.reduceMotion,
  });

  final int remaining;
  final double effectScale;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = reduceMotion
        ? .065 * effectScale
        : (.06 + (remaining % 2) * .03) * effectScale;
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
      oldDelegate.remaining != remaining ||
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
          color: selected ? toxic.withValues(alpha: .2) : Colors.white.withValues(alpha: .05),
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
