import 'event_derived_state.dart';
import 'recovery_event.dart';

/// The fact chip on a relapse card that says which streak it ended.
///
/// `streakLost` is whole days of lean/codeine clean time before this
/// relapse, by occurred time. Benzo-only use never resets the lean timer,
/// so it never "interrupts" a streak. Returns null when nothing is known.
String? interruptedStreakLabel(RecoveryEvent event) {
  if (event.type != RecoveryEventType.relapse) return null;
  if (!resetsLeanCleanTimer(event)) return 'LEAN TIMER KEPT';
  final value = event.metadata['streakLost'];
  if (value is! num) return null;
  final days = value.round();
  if (days <= 0) return 'STREAK UNDER 1 DAY';
  return '$days-DAY STREAK INTERRUPTED';
}
