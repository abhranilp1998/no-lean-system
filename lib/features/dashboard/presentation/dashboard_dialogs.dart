import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_provider.dart';

Future<void> showPledgeDialog(BuildContext context, WidgetRef ref) async {
  final confirm =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'LOCK TODAY\'S DECISION',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You do not need to feel ready. You need to make one clean decision before the risk window makes it for you.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('NOT YET'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(backgroundColor: magenta),
                    child: const Text('LOCK IT'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (confirm && context.mounted) {
    await ref.read(recoveryProvider).pledge();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PLEDGE LOCKED. KEEP MOVING.'),
        backgroundColor: Color(0xFF42152F),
      ),
    );
  }
}

Future<void> showCheckInDialog(BuildContext context, WidgetRef ref) async {
  final stayedClean = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'EVENING CHECK-IN',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Did you stay clean today?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: GlowButton(
              label: 'YES — I STAYED CLEAN',
              color: toxic,
              icon: Icons.check,
              onTap: () => Navigator.pop(dialogContext, true),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'NO — RECORD A RELAPSE',
              style: TextStyle(color: red),
            ),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (stayedClean == true) {
    await ref.read(recoveryProvider).pledge();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CHECK-IN SAVED. SAME DECISION TOMORROW.'),
          backgroundColor: Color(0xFF223C1B),
        ),
      );
    }
  } else if (stayedClean == false) {
    await showRelapseDialog(context, ref);
  }
}

Future<void> showRelapseDialog(BuildContext context, WidgetRef ref) async {
  final confirm =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'RECORD THE FACTS',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This resets the timer. It does not erase the data. Record it, learn from the chain, and start the next clean minute.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('CANCEL'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(backgroundColor: red),
                    child: const Text('RESET TIMER'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (confirm) {
    await ref.read(recoveryProvider).recordRelapse();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TIMER RESET. NO HIDING. START THE NEXT CLEAN MINUTE.'),
          backgroundColor: Color(0xFF431522),
        ),
      );
    }
  }
}

Future<void> showCodeChallenge(BuildContext context) async {
  const challenges = [
    'Write a function that reverses a string without using built-in reverse helpers.',
    'Build a tiny CLI that prints the current time in three time zones.',
    'Refactor one function you wrote today into two smaller functions.',
    'Solve FizzBuzz, then add a custom rule for multiples of seven.',
  ];
  final task = challenges[DateTime.now().second % challenges.length];
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'CODE INSTEAD',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusPill(label: '10 MINUTE TASK', color: purple),
          const SizedBox(height: 14),
          Text(task, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: const Text('START'),
            ),
          ),
        ],
      ),
    ),
  );
}
