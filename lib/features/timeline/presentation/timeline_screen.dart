import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/tab_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_header.dart';
import '../../recovery/application/recovery_provider.dart';
import 'widgets/event_tile.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final events = recovery.events.reversed.toList(); // Newest first

    // Row 0 is the header; then one row per event, or the empty state.
    return TabListView.builder(
      itemCount: 1 + (events.isEmpty ? 1 : events.length),
      itemBuilder: (context, index) {
        if (index == 0) return const _TimelineHeader();
        if (events.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                'No events recorded yet.',
                style: TextStyle(color: muted),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: EventTile(event: events[index - 1]),
        );
      },
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const BrandHeader(),
      const SizedBox(height: 24),
      Text('TIMELINE', style: eyebrowStyle.copyWith(color: cyan)),
      const SizedBox(height: 7),
      Text(
        'Immutable ground truth.',
        style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 18),
    ],
  );
}
