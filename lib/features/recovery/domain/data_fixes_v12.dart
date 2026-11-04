import 'dose_units.dart';
import 'recovery_event.dart';

/// (C) Data fixes applied once when reading state older than v17 or a backup
/// older than v12. Every fix is idempotent and pure.

/// Codeine cough syrups people call lean, by brand.
final _leanBrand = RegExp(
  r'\b(ascoril[\s-]*c|phensedyl|corex|codeine|lean|syrup)\b',
  caseSensitive: false,
);

bool mentionsLeanBrand(String? text) =>
    text != null && _leanBrand.hasMatch(text);

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

const doubleTapWindow = Duration(seconds: 60);

String? _doubleTapKey(RecoveryEvent e) => switch (e.type) {
  RecoveryEventType.relapse =>
    'r|${e.metadata['relapseType']}|${e.metadata['note']}|${e.metadata['quantity']}|${e.metadata['amount']}|${e.metadata['unit']}',
  RecoveryEventType.craving =>
    'c|${e.metadata['intensity']}|${e.metadata['trigger']}|${e.metadata['note']}',
  RecoveryEventType.pledge => 'p',
  _ => null,
};

/// Drops a later copy of the same relapse / craving / pledge saved within
/// [doubleTapWindow] in a *different* save (a double-tap). Entries of one
/// multi-entry save (same batchId) are never touched.
List<RecoveryEvent> dedupeDoubleTaps(List<RecoveryEvent> events) {
  final sorted = List<RecoveryEvent>.of(events)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final lastByKey = <String, RecoveryEvent>{};
  final out = <RecoveryEvent>[];
  for (final e in sorted) {
    final key = _doubleTapKey(e);
    if (key == null) {
      out.add(e);
      continue;
    }
    final prev = lastByKey[key];
    final sameBatch =
        prev != null &&
        e.metadata['batchId'] != null &&
        prev.metadata['batchId'] == e.metadata['batchId'];
    if (prev != null &&
        !sameBatch &&
        e.timestamp.difference(prev.timestamp).abs() <= doubleTapWindow) {
      continue;
    }
    lastByKey[key] = e;
    out.add(e);
  }
  return out;
}

List<RecoveryEvent> applyDataFixesV12(
  List<RecoveryEvent> events, {
  required double bottleMl,
}) => dedupeDoubleTaps([
  for (final e in events)
    fixLeanBrand(fixDoseConsistency(e, bottleMl: bottleMl)),
]);
