import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/if_then_plan.dart';

/// The user's own words, shown calmly at the moment they matter. Never a
/// command: it is a note from a steadier moment.
class PlanCard extends StatelessWidget {
  const PlanCard({
    required this.plans,
    this.heading = 'YOUR PLAN',
    this.maxShown = 2,
    super.key,
  });

  final List<IfThenPlan> plans;
  final String heading;
  final int maxShown;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const SizedBox.shrink();
    final shown = plans.take(maxShown).toList();
    return GlassCard(
      accent: toxic,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, color: toxic, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  heading,
                  style: eyebrowStyle.copyWith(color: toxic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Text(
              shown[i].sentence,
              key: ValueKey('plan-card-${shown[i].id}'),
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'You wrote this on a steadier day. Just the next small step.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// On the home screen: shows the user's plan only while it is useful, inside
/// their risk window or around their usual craving peak. Takes no space the
/// rest of the time.
class PlanNowCard extends ConsumerWidget {
  const PlanNowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(recoveryProvider).plansDueNow;
    if (plans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PlanCard(
        key: const ValueKey('plan-now-card'),
        plans: plans,
        heading: 'YOUR PLAN FOR RIGHT NOW',
      ),
    );
  }
}
