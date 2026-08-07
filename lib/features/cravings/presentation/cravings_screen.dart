import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/craving_entry.dart';
import 'craving_dialog.dart';

class CravingsScreen extends ConsumerWidget {
  const CravingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('CRAVING LOG', style: eyebrowStyle.copyWith(color: magenta)),
        const SizedBox(height: 7),
        Text(
          'Name the pattern.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        const Text(
          'A craving is a signal, not an instruction. Log it while it is happening so your future self has evidence.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 18),
        GlowButton(
          label: 'LOG A CRAVING',
          icon: Icons.add,
          color: magenta,
          onTap: () => showCravingDialog(context, ref),
        ),
        const SizedBox(height: 22),
        SectionHeader(
          title: 'RECENT SIGNALS',
          action: '${recovery.cravings.length} TOTAL',
          onTap: () {},
        ),
        if (recovery.cravings.isEmpty)
          GlassCard(
            accent: muted,
            child: const Text(
              'No cravings logged yet. When the next one hits, put it here before you make a move.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ...recovery.cravings.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CravingTile(entry: entry),
          ),
        ),
      ],
    );
  }
}

class _CravingTile extends StatelessWidget {
  const _CravingTile({required this.entry});

  final CravingEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.intensity >= 8
        ? red
        : entry.intensity >= 6
        ? magenta
        : cyan;
    return GlassCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label: entry.trigger.toUpperCase(), color: color),
              const Spacer(),
              Text(
                DateFormat('MMM d  •  HH:mm').format(entry.createdAt),
                style: microStyle,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Text(
                '${entry.intensity}',
                style: displayFont(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text('/ 10 INTENSITY', style: microStyle.copyWith(color: muted)),
            ],
          ),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry.note,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
