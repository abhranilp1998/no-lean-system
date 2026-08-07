import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_card.dart';

class MilestoneTracker extends StatelessWidget {
  const MilestoneTracker({required this.currentStreak, super.key});

  final int currentStreak;

  static const _milestones = <_MilestoneData>[
    _MilestoneData(days: 3, label: 'BREAK THE LOOP', color: cyan),
    _MilestoneData(days: 7, label: 'FIRST WEEK', color: purple),
    _MilestoneData(days: 14, label: 'HABIT PRESSURE DROPS', color: magenta),
    _MilestoneData(days: 30, label: 'NEW BASELINE', color: toxic),
    _MilestoneData(days: 60, label: 'SYSTEM REBUILT', color: cyan),
    _MilestoneData(days: 90, label: 'LONG GAME', color: purple),
  ];

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final milestone in _milestones)
        _MilestoneRow(milestone: milestone, currentStreak: currentStreak),
    ],
  );
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.milestone, required this.currentStreak});

  final _MilestoneData milestone;
  final int currentStreak;

  @override
  Widget build(BuildContext context) {
    final done = currentStreak >= milestone.days;
    final progress = (currentStreak / milestone.days).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        accent: done ? milestone.color : muted,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? milestone.color : muted,
              size: 19,
            ),
            const SizedBox(width: 11),
            SizedBox(
              width: 42,
              child: Text(
                '${milestone.days}D',
                style: displayFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? milestone.color : Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: panelRaised,
                    color: milestone.color,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              done ? 'CLEARED' : '${(progress * 100).round()}%',
              style: microStyle.copyWith(color: done ? milestone.color : muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneData {
  const _MilestoneData({
    required this.days,
    required this.label,
    required this.color,
  });

  final int days;
  final String label;
  final Color color;
}
