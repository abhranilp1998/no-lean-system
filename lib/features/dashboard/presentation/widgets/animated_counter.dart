import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

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
          ),
          const _CounterDivider(),
          _CounterBlock(
            value: hours.toString().padLeft(2, '0'),
            label: 'HRS',
            accent: cyan,
          ),
          const _CounterDivider(),
          _CounterBlock(
            value: minutes.toString().padLeft(2, '0'),
            label: 'MIN',
            accent: purple,
          ),
          const _CounterDivider(),
          _CounterBlock(
            value: seconds.toString().padLeft(2, '0'),
            label: 'SEC',
            accent: magenta,
            compact: true,
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
    this.compact = false,
  });

  final String value;
  final String label;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: displayFont(
          fontSize: compact ? 32 : 38,
          fontWeight: FontWeight.w700,
          color: accent,
          letterSpacing: -2,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: microStyle.copyWith(
          color: accent.withValues(alpha: .75),
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}

class _CounterDivider extends StatelessWidget {
  const _CounterDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
    child: Text(':', style: displayFont(fontSize: 24, color: muted)),
  );
}
