import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/no_lean_visuals.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../recovery/domain/money_saved.dart';

/// Home and progress card for the money-saved counter, including the
/// optional goal jar and a gentle prompt when spend is not set.
class MoneySavedCard extends StatelessWidget {
  const MoneySavedCard({
    required this.snapshot,
    required this.onSetSpend,
    this.onSetGoal,
    this.compact = false,
    super.key,
  });

  final MoneySavedSnapshot snapshot;
  final VoidCallback onSetSpend;
  final VoidCallback? onSetGoal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return GlassCard(
      key: const ValueKey('money-saved-card'),
      accent: toxic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.isSpendSet ? 'MONEY SAVED' : 'MONEY SAVED // NOT SET',
            style: microStyle.copyWith(color: toxic),
          ),
          const SizedBox(height: 10),
          if (snapshot.isSpendSet)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                key: const ValueKey('money-saved-amount'),
                snapshot.format(snapshot.moneySaved),
                style: displayFont(
                  fontSize: compact ? 26 : 32,
                  fontWeight: FontWeight.w700,
                  color: toxic,
                ),
              ),
            )
          else
            Text(
              key: const ValueKey('money-saved-prompt-title'),
              'Set a usual day',
              style: displayFont(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: toxic,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('money-saved-copy'),
            snapshot.warmCopy,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: visuals.secondaryTextColor.withValues(alpha: .95),
            ),
          ),
          if (snapshot.goal != null && snapshot.isSpendSet) ...[
            const SizedBox(height: 14),
            GoalJar(snapshot: snapshot, onTap: onSetGoal),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                key: const ValueKey('money-saved-set-spend'),
                onPressed: onSetSpend,
                child: Text(
                  snapshot.isSpendSet
                      ? 'EDIT TYPICAL SPEND'
                      : 'SET TYPICAL SPEND',
                ),
              ),
              if (onSetGoal != null)
                TextButton(
                  key: const ValueKey('money-saved-set-goal'),
                  onPressed: onSetGoal,
                  child: Text(
                    snapshot.goal == null ? 'ADD A GOAL' : 'EDIT GOAL',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A fillable jar showing progress toward [snapshot.goal].
class GoalJar extends StatelessWidget {
  const GoalJar({required this.snapshot, this.onTap, super.key});

  final MoneySavedSnapshot snapshot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final goal = snapshot.goal;
    if (goal == null) return const SizedBox.shrink();
    final progress = (snapshot.goalProgress ?? 0).clamp(0.0, 1.0);
    final percent = snapshot.goalPercent ?? 0;
    final photo = _photo(goal.photoPath);
    final jar = SizedBox(
      key: const ValueKey('goal-jar'),
      height: 120,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 120,
            child: CustomPaint(
              painter: _JarPainter(
                progress: progress,
                fill: toxic,
                outline: cyan,
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image(
                image: photo,
                key: const ValueKey('goal-jar-photo'),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  key: const ValueKey('goal-jar-name'),
                  goal.name,
                  style: displayFont(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  key: const ValueKey('goal-jar-progress'),
                  '${snapshot.format(snapshot.moneySaved)} of '
                  '${snapshot.format(goal.target)}  ·  '
                  '${percent >= 100 ? 'Done' : '$percent%'}',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return jar;
    return InkWell(
      key: const ValueKey('goal-jar-tap'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: jar,
    );
  }

  static ImageProvider? _photo(String? path) {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }
}

class _JarPainter extends CustomPainter {
  const _JarPainter({
    required this.progress,
    required this.fill,
    required this.outline,
  });

  final double progress;
  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final neck = size.width * 0.28;
    final bodyTop = size.height * 0.18;
    final path = Path()
      ..moveTo(size.width / 2 - neck, 0)
      ..lineTo(size.width / 2 + neck, 0)
      ..lineTo(size.width / 2 + neck, bodyTop * 0.55)
      ..quadraticBezierTo(size.width, bodyTop, size.width - 4, bodyTop + 12)
      ..lineTo(size.width - 4, size.height - 8)
      ..quadraticBezierTo(size.width / 2, size.height + 4, 4, size.height - 8)
      ..lineTo(4, bodyTop + 12)
      ..quadraticBezierTo(0, bodyTop, size.width / 2 - neck, bodyTop * 0.55)
      ..close();

    canvas.save();
    canvas.clipPath(path);
    final fillTop = size.height * (1 - progress);
    canvas.drawRect(
      Rect.fromLTRB(0, fillTop, size.width, size.height),
      Paint()..color = fill.withValues(alpha: 0.85),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Lip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, 3),
          width: neck * 2 + 10,
          height: 6,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = outline,
    );
  }

  @override
  bool shouldRepaint(covariant _JarPainter old) =>
      old.progress != progress || old.fill != fill || old.outline != outline;
}

/// Unused math import guard avoided by referencing [math.min] in tests? Keep.
double jarFillHeight(double progress, double height) =>
    height * math.min(1, math.max(0, progress));
