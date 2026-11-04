import 'dose_units.dart';
import 'double_tap.dart';
import 'recovery_event.dart';

/// (C) Data fixes applied once when reading state older than v17 or a backup
/// older than v12. Every fix is idempotent and pure.

/// Codeine cough syrups, by brand (plus codeine itself). Generic words like
/// "lean" or "syrup" are too broad ("lean on a friend", "maple syrup").
final _leanBrand = RegExp(
  r'\b(ascoril[\s-]*c|phensedyl|corex|codeine)\b',
  caseSensitive: false,
);

/// "no", "not", "without", "didn't have", "instead of"… shortly before the
/// brand cancels the mention ("skipped the Phensedyl", "no corex today").
final _negatedBefore = RegExp(
  r"\b(no|not|never|without|instead of|skipped|avoided|didn'?t (have|take|buy|drink|use)|did not (have|take|buy|drink|use))\b(\s+\S+){0,2}\s*$",
  caseSensitive: false,
);

bool mentionsLeanBrand(String? text) {
  if (text == null) return false;
  for (final m in _leanBrand.allMatches(text)) {
    // Negation applies per clause: "no beer, two corex" is a mention.
    final clause = text
        .substring(0, m.start)
        .split(RegExp(r'[,.;!?]|\b(but|though|then)\b', caseSensitive: false))
        .last;
    if (!_negatedBefore.hasMatch(clause)) return true;
  }
  return false;
}

/// "1x100 ml", "2 x 100ml" → total; otherwise the normal parser.
DoseAmount? parseQuantityTextV12(String text, {required double bottleMl}) {
  final times = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s*[x×*]\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (times != null) {
    final n = double.tryParse(times.group(1)!);
    final each = parseQuantityText(times.group(2)!, bottleMl: bottleMl);
    if (n == null || each == null || n <= 0) return null;
    try {
      return DoseAmount.entered(n * each.amount, each.unit, bottleMl: bottleMl);
    } on ArgumentError {
      return null;
    }
  }
  return parseQuantityText(text, bottleMl: bottleMl);
}

bool _sameDose(DoseAmount a, DoseAmount b) {
  final am = a.amountMl, bm = b.amountMl;
  if (am != null && bm != null) return (am - bm).abs() < 0.5;
  return a.unit == b.unit && (a.amount - b.amount).abs() < 1e-9;
}

/// Makes amount / unit / amountMl agree with each other and with the typed
/// quantity. An untouched form default (1 bottle) loses to a specific typed
/// amount; a real disagreement is kept and flagged `doseConflict`.
RecoveryEvent fixDoseConsistency(
  RecoveryEvent event, {
  required double bottleMl,
}) {
  if (event.type != RecoveryEventType.relapse) return event;
  final m = Map<String, dynamic>.of(event.metadata);
  final stored = DoseAmount.fromMetadata(m);
  final bottle = (m['bottleMl'] is num)
      ? (m['bottleMl'] as num).toDouble()
      : bottleMl;
  // Internal consistency: ml must follow amount × unit.
  if (stored != null && stored.unit.isVolume) {
    final ml = toMl(stored.amount, stored.unit, bottleMl: bottle);
    if (ml != null &&
        (stored.amountMl == null || (stored.amountMl! - ml).abs() >= 0.5)) {
      m['amountMl'] = ml;
      if (stored.unit == DoseUnit.bottle) m['bottleMl'] = bottle;
    }
  }
  final text = m['quantity'];
  if (text is! String) return event.copyWith(metadata: m);
  final typed = parseQuantityTextV12(text, bottleMl: bottle);
  if (typed == null) return event.copyWith(metadata: m);
  final current = DoseAmount.fromMetadata(m);
  if (current == null) {
    if (typed.unit == DoseUnit.bottle && m['bottleMl'] is! num) {
      return event.copyWith(metadata: m);
    }
    return event.copyWith(
      metadata: {...m, ...typed.toMetadata(), 'amountSource': 'parsed'},
    );
  }
  if (_sameDose(current, typed)) {
    m.remove('doseConflict');
    return event.copyWith(metadata: m);
  }
  final untouchedDefault =
      current.unit == DoseUnit.bottle && current.amount == 1;
  if (untouchedDefault || m['amountSource'] == 'parsed') {
    m
      ..remove('bottleMl')
      ..remove('amountMl');
    return event.copyWith(
      metadata: {
        ...m,
        ...typed.toMetadata(),
        'amountSource': 'parsed',
        'doseFixedFrom': current.display,
      },
    );
  }
  return event.copyWith(metadata: {...m, 'doseConflict': true});
}

/// Ascoril C, Phensedyl etc. logged as "other" are lean.
RecoveryEvent fixLeanBrand(RecoveryEvent event) {
  if (event.type != RecoveryEventType.relapse) return event;
  final m = event.metadata;
  if (m['relapseType'] != 'other') return event;
  if (!mentionsLeanBrand('${m['note'] ?? ''} ${m['quantity'] ?? ''}')) {
    return event;
  }
  return event.copyWith(
    metadata: {...m, 'relapseType': 'fullLean', 'relapseTypeFrom': 'other'},
  );
}

/// Result of the v12 fixes: the visible history plus double-tap copies that
/// are kept but hidden (marked `duplicateOf`), never deleted.
class DataFixResult {
  const DataFixResult(this.events, this.hidden);
  final List<RecoveryEvent> events;
  final List<RecoveryEvent> hidden;
}

/// Hides a later copy of the same relapse / craving saved within
/// [doubleTapWindow] in a *different* save, using the one shared rule in
/// double_tap.dart (recordedAt + batchId; pledges and blank-note backfills
/// are never touched). The copy is returned in [DataFixResult.hidden] with
/// `duplicateOf` set to the kept event's id.
DataFixResult dedupeDoubleTaps(List<RecoveryEvent> events) {
  final sorted = List<RecoveryEvent>.of(events)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final lastByKey = <String, RecoveryEvent>{};
  final out = <RecoveryEvent>[];
  final hidden = <RecoveryEvent>[];
  for (final e in sorted) {
    final key = doubleTapKey(e);
    final prev = key == null ? null : lastByKey[key];
    if (prev != null && isDoubleTap(prev, e)) {
      hidden.add(
        e.copyWith(
          metadata: {...e.metadata, 'duplicateOf': prev.id, 'hidden': true},
        ),
      );
      continue;
    }
    if (key != null) lastByKey[key] = e;
    out.add(e);
  }
  return DataFixResult(out, hidden);
}

/// Pure and idempotent: running it on its own output changes nothing.
DataFixResult applyDataFixesV12(
  List<RecoveryEvent> events, {
  required double bottleMl,
}) => dedupeDoubleTaps([
  for (final e in events)
    fixLeanBrand(fixDoseConsistency(e, bottleMl: bottleMl)),
]);
