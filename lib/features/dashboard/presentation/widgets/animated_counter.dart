import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/no_lean_visuals.dart';

class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    required this.duration,
    required this.reduceMotion,
    super.key,
  });

  final Duration duration;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final motionReduced = reduceMotion || visuals.reduceMotion;
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _CounterBlock(
            value: days.toString().padLeft(2, '0'),
            label: 'DAYS',
            accent: cyan,
            reduceMotion: motionReduced,
          ),
          const _CounterDivider(),
          _CounterBlock(
            value: hours.toString().padLeft(2, '0'),
            label: 'HRS',
            accent: cyan,
            reduceMotion: motionReduced,
          ),
          const _CounterDivider(),
          _CounterBlock(
            value: minutes.toString().padLeft(2, '0'),
            label: 'MIN',
            accent: purple,
            reduceMotion: motionReduced,
          ),
          const _CounterDivider(),
          _CounterBlock(
            value: seconds.toString().padLeft(2, '0'),
            label: 'SEC',
            accent: magenta,
            compact: true,
            reduceMotion: motionReduced,
          ),
        ],
      ),
    );
  }
}

class _CounterBlock extends StatelessWidget {
  const _CounterBlock({
    required this.value,
    required this.label,
    required this.accent,
    required this.reduceMotion,
    this.compact = false,
  });

  final String value;
  final String label;
  final Color accent;
  final bool compact;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final valueText = Text(
      value,
      key: ValueKey('$label-$value'),
      style:
          displayFont(
            fontSize: compact ? 32 : 38,
            fontWeight: FontWeight.w700,
            color: accent,
            letterSpacing: -2,
          ).copyWith(
            shadows: [
              Shadow(
                color: accent.withValues(alpha: visuals.glowOpacity(.42)),
                blurRadius: 11 * visuals.glowRadiusScale,
              ),
            ],
          ),
    );

    return Column(
      children: [
        if (reduceMotion)
          valueText
        else
          AnimatedSwitcher(
            duration: visuals.motionDuration(const Duration(milliseconds: 180)),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.center,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -.16),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: valueText,
          ),
        const SizedBox(height: 4),
        Text(
          label,
          style: microStyle.copyWith(
            color: accent.withValues(
              alpha: visuals.accentOpacity(.75, minimum: .58),
            ),
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _CounterDivider extends StatelessWidget {
  const _CounterDivider();

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      child: Text(
        ':',
        style: displayFont(fontSize: 24, color: visuals.secondaryTextColor),
      ),
    );
  }
}
