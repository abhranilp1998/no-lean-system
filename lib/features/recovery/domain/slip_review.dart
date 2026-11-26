import 'dart:math' as math;

import '../../zones/domain/danger_zone.dart';
import 'recovery_event.dart';
import 'risk_window.dart';

/// Optional 3-tap review after a slip: where, who with, what set it off.
///
/// Answers are stored as additive metadata on the relapse event itself, so
/// no event type, state version or backup version changes. Old data simply
/// has none of these keys; old builds keep unknown keys when they round-trip.

const slipPlaceKey = 'place';
const slipZoneIdKey = 'zoneId';
const slipWithKey = 'withWho';
const slipReviewedAtKey = 'reviewedAt';

/// Longest place label kept (same as a danger-zone name).
const slipPlaceMaxLength = DangerZone.maxNameLength;

/// Who the user was with. Stored as the key; shown as the label.
const slipWithOptions = <String, String>{
  'alone': 'Alone',
  'friends': 'Friends',
  'family': 'Family / partner',
  'work': 'Work people',
  'supplier': 'Someone I got it from',
};

/// Places offered when no danger zone fits. Plain words, no map needed.
const slipPlaceOptions = <String>[
  'Home',
  "Friend's place",
  'Work',
  'Shop / bar',
  'Outside',
];

/// One review's answers. Everything is optional; an empty review saves
/// nothing.
class SlipReview {
  const SlipReview({
    this.place,
    this.zoneId,
    this.withWho,
    this.triggers = const [],
  });

  /// Place label ("Home", or the linked danger zone's name).
  final String? place;

  /// Set when [place] is one of the user's danger zones.
  final String? zoneId;

  /// A key of [slipWithOptions].
  final String? withWho;

  /// Context signals, from `recoveryTriggerOptions`. Merged into the
  /// relapse's existing `contextTags`, so they feed the same trigger counts
  /// as every other log.
  final List<String> triggers;

  String? get cleanPlace {
    final value = place?.trim();
    if (value == null || value.isEmpty) return null;
    return value.length > slipPlaceMaxLength
        ? value.substring(0, slipPlaceMaxLength)
        : value;
  }

  bool get isEmpty =>
      cleanPlace == null &&
      (withWho == null || !slipWithOptions.containsKey(withWho)) &&
      triggers.every((t) => t.trim().isEmpty);

  SlipReview copyWith({
    String? place,
    String? zoneId,
    String? withWho,
    List<String>? triggers,
    bool clearPlace = false,
    bool clearWith = false,
  }) => SlipReview(
    place: clearPlace ? null : place ?? this.place,
    zoneId: clearPlace ? null : zoneId ?? this.zoneId,
    withWho: clearWith ? null : withWho ?? this.withWho,
    triggers: triggers ?? this.triggers,
  );
}

/// Merges [review] into a relapse's metadata. Only adds or replaces the
/// review's own keys and unions the context tags; nothing else changes and
/// nothing is removed.
Map<String, dynamic> applySlipReview(
  Map<String, dynamic> metadata,
  SlipReview review, {
  required DateTime now,
}) {
  final out = Map<String, dynamic>.from(metadata);
  final place = review.cleanPlace;
  if (place != null) {
    out[slipPlaceKey] = place;
    if (review.zoneId != null) {
      out[slipZoneIdKey] = review.zoneId;
    } else {
      out.remove(slipZoneIdKey);
    }
  }
  if (review.withWho != null && slipWithOptions.containsKey(review.withWho)) {
    out[slipWithKey] = review.withWho;
  }
  final tags = <String>{
    if (out['contextTags'] is List)
      ...(out['contextTags'] as List).whereType<String>(),
    for (final t in review.triggers)
      if (t.trim().isNotEmpty) t.trim(),
  };
  if (tags.isNotEmpty) out['contextTags'] = tags.toList(growable: false);
  out[slipReviewedAtKey] = now.toIso8601String();
  return out;
}

/// Tolerant read: a bad or unknown value is dropped, never an error, so an
/// odd backup can't be refused over an optional field.
Map<String, dynamic> normalizeSlipReviewMetadata(Map<String, dynamic> m) {
  final place = m[slipPlaceKey];
  if (place is String && place.trim().isNotEmpty) {
    m[slipPlaceKey] = place.trim().length > slipPlaceMaxLength
        ? place.trim().substring(0, slipPlaceMaxLength)
        : place.trim();
  } else {
    m.remove(slipPlaceKey);
  }
  if (m[slipZoneIdKey] is! String || (m[slipZoneIdKey] as String).isEmpty) {
    m.remove(slipZoneIdKey);
  }
  if (m[slipWithKey] is! String) m.remove(slipWithKey);
  if (m[slipReviewedAtKey] is! String) m.remove(slipReviewedAtKey);
  return m;
}

/// How many logged slips happened at [place] (a zone's name or a typed
/// label), case-insensitively, by the review answers only.
int slipsAtPlace(Iterable<RecoveryEvent> events, String place) {
  final key = place.trim().toLowerCase();
  return events
      .where(
        (e) =>
            e.type == RecoveryEventType.relapse &&
            (e.metadata[slipPlaceKey] as String?)?.trim().toLowerCase() == key,
      )
      .length;
}

/// A reviewed place that keeps showing up but is not a danger zone yet.
class ZoneSuggestion {
  const ZoneSuggestion({required this.place, required this.count});
  final String place;
  final int count;
}

/// Places with at least [minCount] reviewed slips and no danger zone of that
/// name (and no slip linked to a zone), most frequent first. Generic labels
/// ("Outside") are skipped: they are not a place you can fence.
List<ZoneSuggestion> zoneSuggestions(
  Iterable<RecoveryEvent> events,
  Iterable<DangerZone> zones, {
  int minCount = 2,
}) {
  final zoneNames = {for (final z in zones) z.name.trim().toLowerCase()};
  final counts = <String, ({String label, int n})>{};
  for (final e in events) {
    if (e.type != RecoveryEventType.relapse) continue;
    final place = (e.metadata[slipPlaceKey] as String?)?.trim();
    if (place == null || place.isEmpty) continue;
    if (e.metadata[slipZoneIdKey] != null) continue;
    final key = place.toLowerCase();
    if (zoneNames.contains(key) || key == 'outside' || key == 'home') continue;
    final prev = counts[key];
    counts[key] = (label: prev?.label ?? place, n: (prev?.n ?? 0) + 1);
  }
  return [
    for (final c in counts.values)
      if (c.n >= minCount) ZoneSuggestion(place: c.label, count: c.n),
  ]..sort((a, b) => b.count.compareTo(a.count));
}

/// What the logged slips say about timing, place and company. Uses each
/// slip's own `timestamp` (when it happened).
class SlipPattern {
  const SlipPattern({
    required this.total,
    this.peakHour,
    this.topPlace,
    this.topPlaceCount = 0,
    this.topWith,
    this.topWithCount = 0,
    this.minutesBeforeWindow,
  });

  final int total;
  final int? peakHour;
  final String? topPlace;
  final int topPlaceCount;
  final String? topWith;
  final int topWithCount;

  /// If slips tend to start shortly before the risk window opens, how many
  /// minutes before it (rounded up to 15). Null when they don't.
  final int? minutesBeforeWindow;
}

SlipPattern computeSlipPattern(
  Iterable<RecoveryEvent> events,
  RiskWindow window,
) {
  final slips = events
      .where((e) => e.type == RecoveryEventType.relapse)
      .toList();
  if (slips.isEmpty) return const SlipPattern(total: 0);

  final hours = <int, int>{};
  final places = <String, int>{};
  final withs = <String, int>{};
  final gaps = <int>[];
  for (final e in slips) {
    final local = e.timestamp.toLocal();
    hours[local.hour] = (hours[local.hour] ?? 0) + 1;
    final place = (e.metadata[slipPlaceKey] as String?)?.trim();
    if (place != null && place.isNotEmpty) {
      places[place] = (places[place] ?? 0) + 1;
    }
    final who = e.metadata[slipWithKey];
    if (who is String && slipWithOptions.containsKey(who)) {
      withs[who] = (withs[who] ?? 0) + 1;
    }
    final minute = local.hour * 60 + local.minute;
    if (!window.contains(local)) {
      final before = (window.startMinutes - minute) % RiskWindow.minutesPerDay;
      if (before > 0 && before <= 180) gaps.add(before);
    }
  }
  MapEntry<K, int>? top<K>(Map<K, int> m, {int min = 1}) {
    final ranked = m.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : '${a.key}'.compareTo('${b.key}');
      });
    return ranked.isEmpty || ranked.first.value < min ? null : ranked.first;
  }

  final peak = top(hours);
  final place = top(places);
  final who = top(withs);
  // Two or more slips shortly before the window opens: warn earlier.
  final early = gaps.length >= 2 ? gaps.reduce(math.max) : null;
  return SlipPattern(
    total: slips.length,
    peakHour: peak?.key,
    topPlace: place?.key,
    topPlaceCount: place?.value ?? 0,
    topWith: who?.key,
    topWithCount: who?.value ?? 0,
    minutesBeforeWindow: early == null ? null : ((early + 14) ~/ 15) * 15,
  );
}

/// The pre-window warning lead time: the default, or earlier when logged
/// slips start before the window opens. Only ever longer than [base] (more
/// warning, never less) and capped at 3 hours.
int adaptiveLeadMinutes(SlipPattern pattern, {int base = 15}) {
  final early = pattern.minutesBeforeWindow;
  if (early == null) return base;
  return math.min(180, math.max(base, early));
}

/// A review the app should offer right after a save.
class SlipReviewRequest {
  const SlipReviewRequest({required this.eventIds, required this.occurredAt});

  /// The relapse events this review answers (one save; usually one entry).
  final Set<String> eventIds;

  /// When the latest of them happened.
  final DateTime occurredAt;
}

/// Offers a review for a save of one entry, or several that all happened
/// within a day of each other (one episode). A catch-up of separate days gets
/// no automatic prompt: one answer cannot describe different days.
SlipReviewRequest? slipReviewFor(Iterable<RecoveryEvent> saved) {
  final list = saved.where((e) => e.type == RecoveryEventType.relapse).toList();
  if (list.isEmpty) return null;
  list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (list.last.timestamp.difference(list.first.timestamp) >
      const Duration(hours: 24)) {
    return null;
  }
  return SlipReviewRequest(
    eventIds: {for (final e in list) e.id},
    occurredAt: list.last.timestamp,
  );
}
