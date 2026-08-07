import 'package:flutter/material.dart';

import '../services/app_feedback.dart';
import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';
import 'glass_card.dart';

class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return InkWell(
      onTap: () {
        AppFeedback.tap();
        onTap();
      },
      enableFeedback: false,
      borderRadius: BorderRadius.circular(15),
      child: GlassCard(
        accent: color,
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: color.withValues(alpha: visuals.accentOpacity(.12)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: displayFont(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: visuals.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: visuals.secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}
