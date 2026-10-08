import 'package:intl/intl.dart';

import 'event_derived_state.dart';
import 'recovery_event.dart';
import 'risk_window.dart';

enum RiskAlertKind { preWindow, windowOpen, followUp }

/// One daily risk-window notification: when it fires and what it says.
class RiskAlert {
  const RiskAlert({
    required this.id,
    required this.kind,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final RiskAlertKind kind;
  final int minuteOfDay;
  final String title;
  final String body;
}

/// Observed facts the alerts are allowed to claim. Nothing here is invented:
/// every number comes from the user's own logged events.
class RiskAlertFacts {
  const RiskAlertFacts({
    required this.totalCravings,
    required this.cravingsInWindow,
    required this.cleanSince,
    this.topTrigger,
    this.topTriggerCount = 0,
    this.peakHour,
  });

  final int totalCravings;
  final int cravingsInWindow;
  final DateTime cleanSince;
  final String? topTrigger;
  final int topTriggerCount;
  final int? peakHour;

  int? get windowSharePercent => totalCravings == 0
      ? null
      : (cravingsInWindow * 100 / totalCravings).round();
}

RiskAlertFacts computeRiskAlertFacts({
  required List<RecoveryEvent> events,
  required RiskWindow window,
  required DateTime cleanSince,
}) {
  final cravings = events
      .where((event) => event.type == RecoveryEventType.craving)
      .toList();
  final inWindow = cravings
      .where((event) => window.contains(event.timestamp.toLocal()))
      .length;
  final evidence = computeRiskWindowEvidence(events, window);
  return RiskAlertFacts(
    totalCravings: cravings.length,
    cravingsInWindow: inWindow,
    cleanSince: cleanSince,
    topTrigger: evidence.dominantTrigger,
    topTriggerCount: evidence.dominantTriggerCount,
    peakHour: evidence.peakHour,
  );
}

/// Notification IDs 500–503 are the in-window alerts (kept from earlier
/// releases so upgrades replace them); 510 is the pre-window warning.
const riskAlertFirstId = 500;
const riskAlertPreWindowId = 510;
const riskAlertLastId = 511;

/// Builds the daily alert schedule: a warning [leadMinutes] before the window,
/// an opening alert, and follow-ups spread through the window.
///
/// Alerts repeat daily until rescheduled, so copy states a "clean since" date
/// rather than a day count that would go stale.
List<RiskAlert> buildRiskAlertPlan({
  required RiskWindow window,
  required RiskAlertFacts facts,
  List<String> userMessages = const [],
  int leadMinutes = 15,
  int inWindowCount = 4,
}) {
  final label = window.label;
  final share = facts.windowSharePercent;
  final shareLine = share == null
      ? null
      : facts.totalCravings >= 3
      ? '$share% of your ${facts.totalCravings} logged cravings hit inside $label.'
      : '${facts.cravingsInWindow} of your ${facts.totalCravings} logged cravings hit inside $label.';
  final triggerLine = facts.topTrigger == null
      ? null
      : 'Top trigger in this window: ${facts.topTrigger!.toUpperCase()} '
            '(${facts.topTriggerCount} ${facts.topTriggerCount == 1 ? 'log' : 'logs'}).';
  final peakLine = facts.peakHour == null
      ? null
      : 'Peak hour in your logs: ${facts.peakHour.toString().padLeft(2, '0')}:00.';
  final cleanLine =
      'Clean since ${DateFormat('d MMM').format(facts.cleanSince)}.';
  const noDataLine =
      'No craving data for this window yet. Log the next urge so these alerts get specific.';
  final messages = userMessages
      .map((message) => message.trim())
      .where((message) => message.isNotEmpty)
      .toList();
  String join(List<String?> parts) => parts.whereType<String>().join(' ');

  final alerts = <RiskAlert>[];
  if (leadMinutes > 0 && leadMinutes < RiskWindow.minutesPerDay) {
    alerts.add(
      RiskAlert(
        id: riskAlertPreWindowId,
        kind: RiskAlertKind.preWindow,
        minuteOfDay:
            (window.startMinutes - leadMinutes) % RiskWindow.minutesPerDay,
        title: 'RISK WINDOW IN $leadMinutes MIN // $label',
        body: join([
          shareLine ?? noDataLine,
          triggerLine,
          cleanLine,
          'Set the plan before it starts: SOS, move, or call.',
        ]),
      ),
    );
  }

  final seenMinutes = <int>{};
  final moments = window.reminderMinutes(count: inWindowCount);
  for (var index = 0; index < moments.length; index++) {
    if (!seenMinutes.add(moments[index])) continue;
    final isOpen = index == 0;
    final message = messages.isEmpty ? null : messages[index % messages.length];
    alerts.add(
      RiskAlert(
        id: riskAlertFirstId + index,
        kind: isOpen ? RiskAlertKind.windowOpen : RiskAlertKind.followUp,
        minuteOfDay: moments[index],
        title: isOpen
            ? 'RISK WINDOW OPEN // $label'
            : 'FOLLOW-UP // WINDOW ENDS ${RiskWindow.formatMinutes(window.endMinutes)}',
        body: isOpen
            ? join([cleanLine, triggerLine ?? shareLine ?? noDataLine, message])
            : join([
                message ??
                    'Still inside the window. Tap I\'M SAFE or open SOS.',
                peakLine ?? shareLine,
                cleanLine,
              ]),
      ),
    );
  }
  return List.unmodifiable(alerts);
}
