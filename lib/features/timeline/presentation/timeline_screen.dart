import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/tab_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/recovery_event.dart';
import '../domain/history_projection.dart';
import 'history_record_screen.dart';
import 'widgets/event_tile.dart';

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({
    this.initialCategory = HistoryCategory.recovery,
    this.recordId,
    super.key,
  });

  final HistoryCategory initialCategory;
  final String? recordId;

  /// Standalone entry points reuse the shell's history views and records.
  /// Only this pushed route owns a Scaffold; the shell tab does not.
  static Future<void> openPage(
    BuildContext context, {
    HistoryCategory category = HistoryCategory.recovery,
    String? recordId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: SafeArea(
          child: TimelineScreen(initialCategory: category, recordId: recordId),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: HistoryCategory.values.length,
    initialIndex: initialCategory.index,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TabLayout.gutter,
            TabLayout.top,
            TabLayout.gutter,
            8,
          ),
          child: Text('TIMELINE', style: eyebrowStyle.copyWith(color: cyan)),
        ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: cyan,
          labelColor: cyan,
          unselectedLabelColor: muted,
          dividerColor: muted.withValues(alpha: .25),
          tabs: [
            for (final category in HistoryCategory.values)
              Tab(
                key: ValueKey('history-tab-${category.name}'),
                text: category.label,
              ),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              for (final category in HistoryCategory.values)
                _HistoryList(
                  key: ValueKey(category),
                  category: category,
                  recordId: category == initialCategory ? recordId : null,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HistoryList extends ConsumerStatefulWidget {
  const _HistoryList({required this.category, this.recordId, super.key});
  final HistoryCategory category;
  final String? recordId;

  @override
  ConsumerState<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<_HistoryList>
    with AutomaticKeepAliveClientMixin {
  HistoryLocationSource? _source;
  late String? _recordId = widget.recordId;

  @override
  bool get wantKeepAlive => true;

  void _details(RecoveryEvent event) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (detailContext) => HistoryRecordScreen(
        recordId: event.id,
        category: widget.category,
        onOpenHistory: (category) => TimelineScreen.openPage(
          detailContext,
          category: category,
          recordId: event.id,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final events = projectHistory(
      ref.watch(recoveryProvider).events,
      widget.category,
      source: _source,
      recordId: _recordId,
    );

    return TabListView.builder(
      key: PageStorageKey('history-list-${widget.category.name}'),
      itemCount: 1 + (events.isEmpty ? 1 : events.length),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.category.title,
                  style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.category.description,
                  style: const TextStyle(color: muted, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  '${events.length} ${events.length == 1 ? 'record' : 'records'}',
                  style: microStyle,
                ),
                if (_recordId != null)
                  InputChip(
                    label: const Text('Linked record'),
                    deleteButtonTooltipMessage: 'Show all records',
                    onDeleted: () => setState(() => _recordId = null),
                  ),
                if (widget.category == HistoryCategory.location) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('All sources'),
                        selected: _source == null,
                        onSelected: (_) => setState(() => _source = null),
                      ),
                      for (final source in HistoryLocationSource.values)
                        ChoiceChip(
                          label: Text(source.label),
                          selected: _source == source,
                          onSelected: (_) => setState(() => _source = source),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }
        if (events.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              _recordId != null
                  ? 'This record is no longer available in this history. Clear Linked record to see all records.'
                  : _source != null
                  ? 'No location records match this source.'
                  : widget.category.emptyMessage,
              style: const TextStyle(color: muted, height: 1.4),
            ),
          );
        }
        final event = events[index - 1];
        return Padding(
          key: ValueKey('history-record-${event.id}'),
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EventTile(event: event),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: ValueKey('history-details-${event.id}'),
                    onPressed: () => _details(event),
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text('Details'),
                  ),
                  if (widget.category == HistoryCategory.recovery &&
                      hasLocationContext(event))
                    TextButton.icon(
                      key: ValueKey('history-location-link-${event.id}'),
                      onPressed: () => TimelineScreen.openPage(
                        context,
                        category: HistoryCategory.location,
                        recordId: event.id,
                      ),
                      icon: const Icon(Icons.place_outlined, size: 16),
                      label: const Text('Location history'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
