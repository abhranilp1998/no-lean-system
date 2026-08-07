import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_card.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
    accent: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: microStyle.copyWith(color: color)),
        const SizedBox(height: 9),
        Text(
          value,
          style: displayFont(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          style: TextStyle(fontSize: 10.5, color: muted.withValues(alpha: .9)),
        ),
      ],
    ),
  );
}
