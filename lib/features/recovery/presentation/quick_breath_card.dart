import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../../core/widgets/glass_card.dart';

/// A one-minute paced-breathing guide that runs fully offline and needs no
/// unlock: breathe in for 4, out for 6, six times. With reduce-motion on the
/// circle stays still and only the words and the counter change.
class QuickBreathCard extends StatefulWidget {
  const QuickBreathCard({super.key});

  static const inSeconds = 4;
  static const outSeconds = 6;
  static const rounds = 6;

  @override
  State<QuickBreathCard> createState() => _QuickBreathCardState();
}

class _QuickBreathCardState extends State<QuickBreathCard>
    with SingleTickerProviderStateMixin {
  static const _cycle = QuickBreathCard.inSeconds + QuickBreathCard.outSeconds;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _cycle * QuickBreathCard.rounds),
  );
  bool _started = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.value = 0;
        _started = false;
      } else {
        _started = true;
        _controller.forward(from: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return GlassCard(
      accent: cyan,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final seconds = _controller.value * _cycle * QuickBreathCard.rounds;
          final done = _started && _controller.isCompleted;
          final running = _controller.isAnimating;
          final inCycle = seconds % _cycle;
          final breathingIn = inCycle < QuickBreathCard.inSeconds;
          final round = (seconds ~/ _cycle + 1).clamp(
            1,
            QuickBreathCard.rounds,
          );
          final phase = !_started
              ? 'READY'
              : done
              ? 'DONE'
              : breathingIn
              ? 'BREATHE IN'
              : 'BREATHE OUT';
          // 0..1 circle fill: grows over the in-breath, shrinks over the out.
          final fill = !running
              ? 0.0
              : breathingIn
              ? inCycle / QuickBreathCard.inSeconds
              : 1 -
                    (inCycle - QuickBreathCard.inSeconds) /
                        QuickBreathCard.outSeconds;
          final size = visuals.reduceMotion ? 64.0 : 52 + 28 * fill;
          return Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Center(
                  child: Container(
                    key: const ValueKey('breath-circle'),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cyan.withValues(
                        alpha: visuals.reduceMotion || !running
                            ? .14
                            : .1 + .2 * fill,
                      ),
                      border: Border.all(
                        color: cyan,
                        width: visuals.highContrast ? 2 : 1.2,
                      ),
                    ),
                    child: Icon(
                      done ? Icons.check : Icons.air,
                      color: cyan,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BREATHE FOR ONE MINUTE',
                      style: eyebrowStyle.copyWith(color: cyan),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _started && !done
                            ? '$phase  ·  ROUND $round OF ${QuickBreathCard.rounds}'
                            : done
                            ? 'DONE. Notice how your shoulders feel.'
                            : 'In for ${QuickBreathCard.inSeconds}, out for '
                                  '${QuickBreathCard.outSeconds}, six times. '
                                  'Slow out-breaths calm the body down.',
                        key: const ValueKey('breath-phase'),
                        style: TextStyle(
                          color: _started && !done
                              ? Colors.white
                              : visuals.secondaryTextColor,
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: _started && !done
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      key: const ValueKey('breath-toggle'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 40),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: _toggle,
                      child: Text(
                        running
                            ? 'STOP'
                            : done
                            ? 'AGAIN'
                            : 'START',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
