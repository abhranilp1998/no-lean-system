import 'recovery_event.dart';
import 'slip_review.dart';

/// Optional quick tags on a craving: where, who with, mood, cash on hand.
///
/// They reuse the slip review's metadata keys (`place`, `zoneId`, `withWho`)
/// so one reading of "where and who" covers cravings and slips alike, and add
/// two optional keys of their own (`mood`, `cash`). Everything is additive
/// metadata on the craving event: no new event type, no state or backup
/// version change. Old data simply has none of these keys.

const triggerMoodKey = 'mood';
const triggerCashKey = 'cash';
const triggerTaggedAtKey = 'taggedAt';

/// How the user felt. Stored as the key; shown as the label.
const triggerMoodOptions = <String, String>{
  'bored': 'Bored',
  'stressed': 'Stressed',
  'low': 'Low',
  'anxious': 'Anxious',
  'angry': 'Angry',
  'tired': 'Tired',
  'celebrating': 'Celebrating',
};

/// Whether they had money on them. Stored as the key; shown as the label.
const triggerCashOptions = <String, String>{
  'none': 'No cash',
  'some': 'A little cash',
  'plenty': 'Cash on me',
};

/// Most tags saved in one go. The sheet closes itself after this many taps.
const triggerTagMaxTaps = 3;

enum TagDimension { place, withWho, mood, cash }

/// One craving's tags. Everything is optional.
class TriggerTags {
  const TriggerTags({
    this.place,
    this.zoneId,
    this.withWho,
    this.mood,
    this.cash,
  });

  final String? place;
  final String? zoneId;
  final String? withWho;
  final String? mood;
  final String? cash;

  String? get cleanPlace {
    final value = place?.trim();
    if (value == null || value.isEmpty) return null;
    return value.length > slipPlaceMaxLength
        ? value.substring(0, slipPlaceMaxLength)
        : value;
  }

  /// Which of the four questions have an answer (known or not).
  Set<TagDimension> get answered => {
    if (cleanPlace != null) TagDimension.place,
    if (withWho != null) TagDimension.withWho,
    if (mood != null) TagDimension.mood,
    if (cash != null) TagDimension.cash,
  };

  bool get isEmpty => answered.isEmpty;
  int get count => answered.length;

  TriggerTags copyWith({
    String? place,
    String? zoneId,
    String? withWho,
    String? mood,
    String? cash,
    bool clearPlace = false,
    bool clearWith = false,
    bool clearMood = false,
    bool clearCash = false,
  }) => TriggerTags(
    place: clearPlace ? null : place ?? this.place,
    zoneId: clearPlace ? null : zoneId ?? this.zoneId,
    withWho: clearWith ? null : withWho ?? this.withWho,
    mood: clearMood ? null : mood ?? this.mood,
    cash: clearCash ? null : cash ?? this.cash,
  );
}

/// Reads whatever tags an event carries. A value this build does not know
/// (say, from a newer app) is kept as-is so it round-trips, and simply
/// ignored by the pattern code.
TriggerTags triggerTagsOf(RecoveryEvent event) {
  final m = event.metadata;
  String? text(String key) {
    final value = m[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  return TriggerTags(
    place: text(slipPlaceKey),
    zoneId: text(slipZoneIdKey),
    withWho: text(slipWithKey),
    mood: text(triggerMoodKey),
    cash: text(triggerCashKey),
  );
}

/// Writes [tags] onto a craving's metadata, replacing the tag keys only. A
/// question left unanswered is removed, so tapping a chip off un-tags it.
/// Nothing else in the metadata is touched.
Map<String, dynamic> applyTriggerTags(
  Map<String, dynamic> metadata,
  TriggerTags tags, {
  required DateTime now,
}) {
  final out = Map<String, dynamic>.from(metadata);
  void put(String key, String? value) =>
      value == null ? out.remove(key) : out[key] = value;

  put(slipPlaceKey, tags.cleanPlace);
  put(slipZoneIdKey, tags.cleanPlace == null ? null : tags.zoneId);
  put(
    slipWithKey,
    slipWithOptions.containsKey(tags.withWho) ? tags.withWho : null,
  );
  put(
    triggerMoodKey,
    triggerMoodOptions.containsKey(tags.mood) ? tags.mood : null,
  );
  put(
    triggerCashKey,
    triggerCashOptions.containsKey(tags.cash) ? tags.cash : null,
  );
  if (tags.isEmpty) {
    out.remove(triggerTaggedAtKey);
  } else {
    out[triggerTaggedAtKey] = now.toIso8601String();
  }
  return out;
}

/// Tolerant read for a craving's optional tag fields: a value of the wrong
/// type is dropped, never an error, so an odd backup is not refused over an
/// optional field.
Map<String, dynamic> normalizeTriggerTagMetadata(Map<String, dynamic> m) {
  normalizeSlipReviewMetadata(m);
  for (final key in [triggerMoodKey, triggerCashKey]) {
    final value = m[key];
    if (value is String && value.trim().isNotEmpty) {
      m[key] = value.trim();
    } else {
      m.remove(key);
    }
  }
  if (m[triggerTaggedAtKey] is! String) m.remove(triggerTaggedAtKey);
  return m;
}
