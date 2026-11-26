import 'package:flutter/material.dart';

import '../services/app_feedback.dart';
import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';
import 'hold_to_act.dart';
import 'glass_card.dart';

class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.onHold,
    this.onHoldStart,
    this.holdDuration,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  /// When set, a ~2 s hold runs this instead of [onTap] (SOS hold-to-text).
  final VoidCallback? onHold;
  final VoidCallback? onHoldStart;
  final Duration? holdDuration;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final tile = InkWell(
      onTap: onHold == null
          ? () {
              AppFeedback.tap();
              onTap();
            }
          : null,
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
    if (onHold == null) return tile;
    return HoldToAct(
      onTap: () {
        AppFeedback.tap();
        onTap();
      },
      onHold: onHold!,
      onHoldStart: onHoldStart,
      duration: holdDuration ?? const Duration(milliseconds: 2000),
      color: color,
      child: tile,
    );
  }
}
