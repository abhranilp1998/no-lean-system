import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_provider.dart';
import '../domain/high_risk_dates.dart';

/// Simple plan note. If-then plans are not on main; this is the hook a
/// later branch can replace with a structured if-then editor.
Future<void> showHighRiskPlanSheet(
  BuildContext context,
  WidgetRef ref,
  UpcomingHighRisk item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: panelRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: HighRiskPlanSheet(item: item),
    ),
  );
}

class HighRiskPlanSheet extends ConsumerStatefulWidget {
  const HighRiskPlanSheet({required this.item, super.key});

  final UpcomingHighRisk item;

  @override
  ConsumerState<HighRiskPlanSheet> createState() => _HighRiskPlanSheetState();
}

class _HighRiskPlanSheetState extends ConsumerState<HighRiskPlanSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.planNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _when {
    final days = widget.item.daysUntil;
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          key: const Key('high-risk-plan-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WHAT\'S YOUR PLAN?',
              style: eyebrowStyle.copyWith(color: cyan),
            ),
            const SizedBox(height: 6),
            Text(
              '${item.title} · $_when',
              style: displayFont(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (item.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                item.subtitle!,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'If things get hard, I will…',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('high-risk-plan-note'),
              controller: _controller,
              maxLines: 4,
              maxLength: 400,
              decoration: const InputDecoration(
                hintText: 'Call a friend, leave early, stay with family…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.hasPlan)
                  TextButton(
                    key: const Key('high-risk-plan-clear'),
                    onPressed: () async {
                      await saveAction(
                        context,
                        () => ref
                            .read(recoveryProvider)
                            .clearHighRiskPlan(item.key),
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('CLEAR'),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('high-risk-plan-save'),
                  onPressed: () async {
                    await saveAction(
                      context,
                      () => ref
                          .read(recoveryProvider)
                          .setHighRiskPlan(item.key, _controller.text),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('SAVE PLAN'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
