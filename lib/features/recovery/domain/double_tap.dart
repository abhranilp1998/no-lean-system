import 'recovery_event.dart';

/// One double-tap rule shared by the live quick-log guard (P0-5) and the
/// v12 data fix (C). Two saves are a double-tap when they record the same
/// relapse or craving within [doubleTapWindow] of each other, in different
/// saves (batchId). Pledges and blank-note backfills are never touched.
const doubleTapWindow = Duration(seconds: 60);

/// When the event was written down. Relapses carry `recordedAt`; cravings
/// are always logged at the moment, so their timestamp is the save time.
DateTime? recordedAtOf(RecoveryEvent e) {
  final raw = e.metadata['recordedAt'] ?? e.metadata['createdAt'];
  if (raw is String) return DateTime.tryParse(raw);
  return e.type == RecoveryEventType.craving ? e.timestamp : null;
}

bool _blank(Object? v) => v == null || '$v'.trim().isEmpty;

/// A relapse logged for an earlier time with no note: these are deliberate
/// catch-up entries and look identical by design.
bool isBlankNoteBackfill(RecoveryEvent e) {
  if (e.type != RecoveryEventType.relapse || !_blank(e.metadata['note'])) {
    return false;
  }
  if (e.metadata['backfilled'] == true) return true;
  final at = recordedAtOf(e);
  return at == null || at.difference(e.timestamp) > doubleTapWindow;
}

String? doubleTapKey(RecoveryEvent e) => switch (e.type) {
  RecoveryEventType.relapse =>
    'r|${e.metadata['relapseType']}|${e.metadata['note'] ?? ''}|${e.metadata['quantity'] ?? ''}|${e.metadata['amount'] ?? ''}|${e.metadata['unit'] ?? ''}',
  RecoveryEventType.craving =>
    'c|${e.metadata['intensity']}|${e.metadata['trigger'] ?? ''}|${e.metadata['note'] ?? ''}',
  _ => null,
};

/// True when [later] is a double-tap copy of [earlier].
bool isDoubleTap(RecoveryEvent earlier, RecoveryEvent later) {
  final key = doubleTapKey(later);
  if (key == null || key != doubleTapKey(earlier)) return false;
  if (isBlankNoteBackfill(earlier) || isBlankNoteBackfill(later)) return false;
  final a = recordedAtOf(earlier), b = recordedAtOf(later);
  if (a == null || b == null) return false;
  if (b.difference(a).abs() > doubleTapWindow) return false;
  final ba = earlier.metadata['batchId'], bb = later.metadata['batchId'];
  return !(ba != null && ba == bb);
}
