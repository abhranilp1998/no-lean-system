import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: cyan.withValues(alpha: visuals.glowOpacity(.25)),
                blurRadius: 20 * visuals.glowRadiusScale,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/no_lean_icon.png'),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BrandWordmark(ultra: visuals.ultraMode && !visuals.reduceMotion),
            const SizedBox(height: 2),
            Text(
              'PERSONAL OVERRIDE SYSTEM',
              style: microStyle.copyWith(color: visuals.secondaryTextColor),
            ),
          ],
        ),
        const Spacer(),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: toxic,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: toxic.withValues(
                  alpha: visuals.glowOpacity(1, minimum: .24),
                ),
                blurRadius: 12 * visuals.glowRadiusScale,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark({required this.ultra});

  final bool ultra;

  @override
  Widget build(BuildContext context) {
    final mainStyle = displayFont(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
    );
    if (!ultra) return Text('NO LEAN', style: mainStyle);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -1.5,
          top: .8,
          child: Text(
            'NO LEAN',
            style: mainStyle.copyWith(color: magenta.withValues(alpha: .7)),
          ),
        ),
        Positioned(
          left: 1.5,
          top: -.8,
          child: Text(
            'NO LEAN',
            style: mainStyle.copyWith(color: cyan.withValues(alpha: .72)),
          ),
        ),
        Text('NO LEAN', style: mainStyle),
      ],
    );
  }
}
