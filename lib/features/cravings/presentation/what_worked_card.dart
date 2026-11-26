import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../companion/presentation/urge_surf_screen.dart';
import '../../recovery/application/recovery_provider.dart';
import '../domain/urge_ride.dart';

/// Home card: the user's own ride-it-out success rate and, once there
/// is enough data, a ranking of what has worked for them.
class WhatWorkedCard extends ConsumerWidget {
  const WhatWorkedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(recoveryProvider).whatWorked;
    if (stats.total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        key: const ValueKey('what-worked-card'),
        accent: cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WHAT WORKS FOR YOU',
              style: eyebrowStyle.copyWith(color: cyan),
            ),
            const SizedBox(height: 8),
            Text(
              stats.homeHeadline,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              stats.homeBody,
              style: const TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
            if (stats.ranked.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final rank in stats.ranked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(rank.activity.label)),
                      Text(
                        rank.scoreLabel,
                        key: ValueKey('what-worked-rank-${rank.activity.name}'),
                        style: const TextStyle(color: toxic),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('what-worked-ride'),
                onPressed: () => UrgeSurfScreen.openRideItOut(context),
                icon: const Icon(Icons.waves, size: 18),
                label: const Text('RIDE ONE OUT'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
