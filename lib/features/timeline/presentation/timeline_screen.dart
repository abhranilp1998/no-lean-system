import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandHeader(),
                  const SizedBox(height: 24),
                  Text('TIMELINE', style: eyebrowStyle.copyWith(color: cyan)),
                  const SizedBox(height: 7),
                  Text(
                    'Immutable ground truth.',
                    style: displayFont(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          if (events.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No events recorded yet.',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final event = events[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: EventTile(event: event),
                  );
                }, childCount: events.length),
              ),
            ),
        ],
      ),
    );
  }
}
