import 'package:flutter/material.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/recovery_controller.dart';

enum PeakHourGateResult { proceed, openSos }

Future<PeakHourGateResult?> showPeakHourGateDialog(
  BuildContext context,
  RecoveryController recovery,
) => showDialog<PeakHourGateResult>(
  context: context,
  builder: (_) => _PeakHourGateDialog(recovery: recovery),
);

class _PeakHourGateDialog extends StatefulWidget {
  const _PeakHourGateDialog({required this.recovery});

  final RecoveryController recovery;

  @override
  State<_PeakHourGateDialog> createState() => _PeakHourGateDialogState();
}

class _PeakHourGateDialogState extends State<_PeakHourGateDialog> {
  bool _tapRejected = false;

  @override
  Widget build(BuildContext context) {
    final recovery = widget.recovery;
    final evidence = recovery.riskWindowEvidence;
    final peak = evidence.peakHour == null
        ? null
        : '${evidence.peakHour!.toString().padLeft(2, '0')}:00';
    final evidenceText = evidence.signalCount == 0
        ? 'This is the buy-risk window you configured. Slow the action down before you change your counter.'
        : '${evidence.signalCount} logged risk ${evidence.signalCount == 1 ? 'signal lands' : 'signals land'} inside this window${peak == null ? '.' : '. Peak pressure: $peak.'}';

    return AppDialog(
      title: 'PEAK-HOUR LOCK // ACTIVE',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(label: 'BUY WINDOW DETECTED', color: red),
            ),
            const SizedBox(height: 14),
            Text(
              'YOU ARE INSIDE ${recovery.riskWindow.label}',
              style: displayFont(
                color: red,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              evidenceText,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
            if (evidence.dominantTrigger case final trigger?) ...[
              const SizedBox(height: 8),
              Text(
                'TOP SIGNAL // ${trigger.toUpperCase()}',
                style: microStyle.copyWith(color: magenta),
              ),
            ],
            const SizedBox(height: 18),
            Semantics(
              button: true,
              label: 'Press and hold to open relapse logging',
              child: Material(
                color: red.withValues(alpha: .1),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: red, width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: InkWell(
                  key: const ValueKey('peak-hour-hold-to-proceed'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    AppFeedback.warning();
                    setState(() => _tapRejected = true);
                  },
                  onLongPress: () {
                    AppFeedback.warning();
                    Navigator.pop(context, PeakHourGateResult.proceed);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, color: red),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'PRESS + HOLD TO OPEN RELAPSE LOG',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: red,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _tapRejected
                  ? Padding(
                      key: const ValueKey('peak-hour-tap-rejected'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'TAP REJECTED // HOLD THE CONTROL UNTIL IT UNLOCKS.',
                        textAlign: TextAlign.center,
                        style: microStyle.copyWith(color: red),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, PeakHourGateResult.openSos),
              icon: const Icon(Icons.sos, color: cyan),
              label: const Text('OPEN SOS INSTEAD'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('BACK OUT'),
            ),
          ],
        ),
      ),
    );
  }
}
