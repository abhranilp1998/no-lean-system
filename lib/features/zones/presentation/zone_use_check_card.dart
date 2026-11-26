import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/use_check.dart';
import '../../recovery/presentation/relapse_log_sheet.dart';
import '../domain/zone_use_check.dart';

/// Warm "Did you use?" question after a danger-zone visit: the headline,
/// the question and three equally easy answers. Shared by the dashboard card
/// and the dialog opened from the notification.
class ZoneUseCheckPanel extends StatelessWidget {
  const ZoneUseCheckPanel({
    required this.check,
    required this.onNo,
    required this.onYes,
    required this.onLater,
    super.key,
  });

  final UseCheck check;
  final VoidCallback onNo;
  final VoidCallback onYes;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.favorite_border, color: cyan, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                zoneCheckHeadline(check).toUpperCase(),
                style: eyebrowStyle.copyWith(color: cyan),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          zoneCheckBody(check),
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('zone-check-no'),
          onPressed: onNo,
          style: FilledButton.styleFrom(
            backgroundColor: toxic,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(46),
          ),
          child: const Text(zoneCheckNoLabel),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton(
                key: const ValueKey('zone-check-yes'),
                onPressed: onYes,
                child: const Text(zoneCheckYesLabel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: OutlinedButton(
                key: const ValueKey('zone-check-later'),
                onPressed: onLater,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(zoneCheckLaterLabel, maxLines: 1),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What each answer does. One place, so the card and the notification tap
/// behave the same.
class ZoneUseCheckActions {
  const ZoneUseCheckActions(this.context, this.recovery);

  final BuildContext context;
  final RecoveryController recovery;

  /// "No, I stayed clean": counted as a zone resisted, then celebrated.
  Future<void> no(UseCheck check) async {
    final count = await recovery.answerUseCheckClean(check);
    await recovery.cancelUseCheck();
    AppFeedback.success();
    if (context.mounted) {
      AppNotice.show(
        context,
        zoneResistedMessage(count),
        type: AppNoticeType.success,
      );
    }
  }

  /// "Yes": opens the logger at the visit time with the place filled in. The
  /// check stays until a relapse is saved, so closing the sheet loses nothing.
  Future<void> yes(UseCheck check) => showRelapseLogSheet(
    context,
    source: 'use_check',
    initialOccurredAt: useCheckPrefill(check, DateTime.now()),
    initialNote: zoneCheckPrefillNote(check),
  );

  /// "Not sure / later": asks again in 30 minutes, at most twice.
  Future<void> later(UseCheck check) async {
    final again = await recovery.snoozeUseCheck(check);
    if (context.mounted) {
      AppNotice.show(
        context,
        again ? zoneCheckSnoozedMessage : zoneCheckDroppedMessage,
      );
    }
  }
}

/// Dashboard card. Shows once a zone check is due and is gone when answered,
/// snoozed or expired. Never shows for other kinds of check.
class ZoneUseCheckCard extends ConsumerWidget {
  const ZoneUseCheckCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final check = recovery.dueZoneUseCheck;
    if (check == null) return const SizedBox.shrink();
    final actions = ZoneUseCheckActions(context, recovery);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const ValueKey('zone-use-check-card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cyan.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cyan.withValues(alpha: .7)),
        ),
        child: ZoneUseCheckPanel(
          check: check,
          onNo: () => actions.no(check),
          onYes: () => actions.yes(check),
          onLater: () => actions.later(check),
        ),
      ),
    );
  }
}

/// The notification body tap: the same question, as a dialog. Returns after
/// the chosen answer has been carried out.
Future<void> showZoneUseCheckDialog(
  BuildContext context,
  RecoveryController recovery,
  UseCheck check,
) async {
  final actions = ZoneUseCheckActions(context, recovery);
  final answer = await showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      key: const ValueKey('zone-use-check-dialog'),
      backgroundColor: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cyan.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ZoneUseCheckPanel(
          check: check,
          onNo: () => Navigator.pop(ctx, 'no'),
          onYes: () => Navigator.pop(ctx, 'yes'),
          onLater: () => Navigator.pop(ctx, 'later'),
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  switch (answer) {
    case 'no':
      await actions.no(check);
    case 'yes':
      await actions.yes(check);
    case 'later':
      await actions.later(check);
  }
}
