import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: cyan.withValues(alpha: .25), blurRadius: 20),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/no_lean_icon.png'),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NO LEAN',
              style: displayFont(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text('PERSONAL OVERRIDE SYSTEM', style: microStyle),
          ],
        ),
        const Spacer(),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: toxic,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: toxic, blurRadius: 12)],
          ),
        ),
      ],
    );
  }
}
