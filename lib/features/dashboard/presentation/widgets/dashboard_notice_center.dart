import 'package:flutter/material.dart';

import '../../../../core/services/app_feedback.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/no_lean_visuals.dart';
import '../../domain/dashboard_notice_style.dart';

class DashboardNoticeCenter extends StatefulWidget {
  const DashboardNoticeCenter({
    required this.style,
    required this.showWelcomeBack,
    required this.showResetSupport,
    required this.onLogMissedRelapses,
    required this.onOpenResetSupport,
    required this.onLogMoreEvents,
    super.key,
  });

  final DashboardNoticeStyle style;
  final bool showWelcomeBack;
  final bool showResetSupport;
  final VoidCallback onLogMissedRelapses;
  final VoidCallback onOpenResetSupport;
  final VoidCallback onLogMoreEvents;

  @override
  State<DashboardNoticeCenter> createState() => _DashboardNoticeCenterState();
}

class _DashboardNoticeCenterState extends State<DashboardNoticeCenter> {
  int? _expandedIndex;

  List<_DashboardNotice> get _notices => [
    if (widget.showWelcomeBack)
      _DashboardNotice(
        title: 'WELCOME BACK',
        compactLabel: 'HISTORY SYNC',
        compactStatus: 'HISTORY INTACT',
        body:
            'Your history is still here. Add anything you missed, at your own pace. Unopened days are left unrecorded.',
        icon: Icons.playlist_add_check_circle_outlined,
        color: cyan,
        actions: [
          _NoticeAction(
            label: 'LOG MISSED RELAPSES',
            icon: Icons.playlist_add,
            onTap: widget.onLogMissedRelapses,
          ),
        ],
      ),
    if (widget.showResetSupport)
      _DashboardNotice(
        title: 'TAKE A MOMENT',
        compactLabel: 'RESET SUPPORT',
        compactStatus: 'LOG SAVED',
        body:
            'Your log is saved. Breathing, your reasons, and a short reflection are here when you need them.',
        icon: Icons.support_outlined,
        color: purple,
        actions: [
          _NoticeAction(
            label: 'OPEN RESET SUPPORT',
            icon: Icons.self_improvement_outlined,
            onTap: widget.onOpenResetSupport,
          ),
          _NoticeAction(
            label: 'LOG MORE EVENTS',
            icon: Icons.add_circle_outline,
            onTap: widget.onLogMoreEvents,
          ),
        ],
      ),
  ];

  @override
  void didUpdateWidget(covariant DashboardNoticeCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) _expandedIndex = null;
    if (_expandedIndex != null && _expandedIndex! >= _notices.length) {
      _expandedIndex = null;
    }
  }

  void _toggle(int index) {
    AppFeedback.selection();
    setState(() => _expandedIndex = _expandedIndex == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    final notices = _notices;
    if (notices.isEmpty) return const SizedBox.shrink();
    return switch (widget.style) {
      DashboardNoticeStyle.edgeRail => _buildEdgeRail(context, notices),
      DashboardNoticeStyle.statusStack => _buildStatusStack(context, notices),
      DashboardNoticeStyle.systemInbox => _buildSystemInbox(context, notices),
    };
  }

  Widget _buildEdgeRail(BuildContext context, List<_DashboardNotice> notices) {
    final visuals = NoLeanVisuals.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 7,
            runSpacing: 7,
            children: [
              for (var index = 0; index < notices.length; index++)
                _EdgeSignalPill(
                  notice: notices[index],
                  expanded: _expandedIndex == index,
                  onTap: () => _toggle(index),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: visuals.motionDuration(const Duration(milliseconds: 220)),
          curve: Curves.easeOutCubic,
          child: _expandedIndex == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _NoticeDetailPanel(
                    notice: notices[_expandedIndex!],
                    onCollapse: () => _toggle(_expandedIndex!),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStatusStack(
    BuildContext context,
    List<_DashboardNotice> notices,
  ) {
    final visuals = NoLeanVisuals.of(context);
    return Column(
      children: [
        Row(
          children: [
            for (var index = 0; index < notices.length; index++) ...[
              Expanded(
                child: _StatusSegment(
                  notice: notices[index],
                  expanded: _expandedIndex == index,
                  onTap: () => _toggle(index),
                ),
              ),
              if (index != notices.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        AnimatedSize(
          duration: visuals.motionDuration(const Duration(milliseconds: 220)),
          curve: Curves.easeOutCubic,
          child: _expandedIndex == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _NoticeDetailPanel(
                    notice: notices[_expandedIndex!],
                    onCollapse: () => _toggle(_expandedIndex!),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSystemInbox(
    BuildContext context,
    List<_DashboardNotice> notices,
  ) => Semantics(
    button: true,
    label: '${notices.length} system messages',
    child: InkWell(
      onTap: () {
        AppFeedback.tap();
        _showInbox(context, notices);
      },
      borderRadius: BorderRadius.circular(13),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: cyan.withValues(alpha: .78)),
          boxShadow: [
            BoxShadow(color: cyan.withValues(alpha: .08), blurRadius: 14),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.mark_email_unread_outlined, color: cyan, size: 21),
            const SizedBox(width: 11),
            for (final notice in notices) ...[
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: notice.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: notice.color.withValues(alpha: .45),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '${notices.length} SYSTEM MESSAGE${notices.length == 1 ? '' : 'S'}',
                style: microStyle.copyWith(
                  color: cyan,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .9,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: cyan),
          ],
        ),
      ),
    ),
  );

  Future<void> _showInbox(
    BuildContext context,
    List<_DashboardNotice> notices,
  ) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: cyan),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .54,
      minChildSize: .36,
      maxChildSize: .78,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 3,
              decoration: BoxDecoration(
                color: cyan.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'SYSTEM INBOX',
                style: displayFont(
                  color: cyan,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text('${notices.length} ACTIVE', style: microStyle),
              IconButton(
                tooltip: 'Close system inbox',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final notice in notices) ...[
            _NoticeDetailPanel(notice: notice),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}

class _EdgeSignalPill extends StatelessWidget {
  const _EdgeSignalPill({
    required this.notice,
    required this.expanded,
    required this.onTap,
  });

  final _DashboardNotice notice;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: expanded,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: NoLeanVisuals.of(
          context,
        ).motionDuration(const Duration(milliseconds: 180)),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: notice.color.withValues(alpha: expanded ? .15 : .065),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notice.color.withValues(alpha: expanded ? .95 : .48),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(notice.icon, color: notice.color, size: 17),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  notice.compactLabel,
                  style: microStyle.copyWith(
                    color: notice.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  notice.compactStatus,
                  style: microStyle.copyWith(fontSize: 8),
                ),
              ],
            ),
            const SizedBox(width: 7),
            Icon(
              expanded ? Icons.expand_less : Icons.chevron_left,
              color: notice.color,
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
    required this.notice,
    required this.expanded,
    required this.onTap,
  });

  final _DashboardNotice notice;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: expanded,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: NoLeanVisuals.of(
          context,
        ).motionDuration(const Duration(milliseconds: 180)),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: notice.color.withValues(alpha: expanded ? .16 : .055),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notice.color.withValues(alpha: expanded ? .88 : .35),
          ),
        ),
        child: Row(
          children: [
            Icon(notice.icon, color: notice.color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notice.compactLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: microStyle.copyWith(
                      color: notice.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    notice.compactStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: microStyle.copyWith(fontSize: 8),
                  ),
                ],
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: notice.color,
              size: 17,
            ),
          ],
        ),
      ),
    ),
  );
}

class _NoticeDetailPanel extends StatelessWidget {
  const _NoticeDetailPanel({required this.notice, this.onCollapse});

  final _DashboardNotice notice;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: notice.color.withValues(alpha: .72)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(notice.icon, color: notice.color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice.title,
                style: microStyle.copyWith(
                  color: notice.color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            if (onCollapse != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Collapse ${notice.title}',
                onPressed: onCollapse,
                icon: Icon(Icons.close, color: notice.color, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Text(notice.body, style: const TextStyle(fontSize: 11.5, height: 1.42)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final action in notice.actions)
              TextButton.icon(
                onPressed: action.onTap,
                icon: Icon(action.icon, size: 16),
                label: Text(action.label),
                style: TextButton.styleFrom(foregroundColor: notice.color),
              ),
          ],
        ),
      ],
    ),
  );
}

class _DashboardNotice {
  const _DashboardNotice({
    required this.title,
    required this.compactLabel,
    required this.compactStatus,
    required this.body,
    required this.icon,
    required this.color,
    required this.actions,
  });

  final String title;
  final String compactLabel;
  final String compactStatus;
  final String body;
  final IconData icon;
  final Color color;
  final List<_NoticeAction> actions;
}

class _NoticeAction {
  const _NoticeAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}
