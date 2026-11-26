import 'package:uuid/uuid.dart';

import 'recovery_event.dart';
import 'risk_window.dart';
import 'trigger_tags.dart';

/// Where a plan is brought up for the user.
enum PlanSurface {
  /// When they enter a danger zone.
  zone,

  /// Inside their risk window, or near their usual craving peak.
  window,

  /// When they log or ride out a craving.
  craving,
}

/// A user-written "If I'm at X or feel Y, then I will Z".
///
/// The words are the user's own, kept on the phone and in their backup. No
/// field is required beyond the two sentences, so a plan never blocks on a
/// form, and older saves simply have no plans.
class IfThenPlan {
  const IfThenPlan({
    required this.id,
    required this.ifText,
    required this.thenText,
    required this.createdAt,
    this.surfaces = defaultSurfaces,
    this.zoneId,
    this.mood,
  });

  factory IfThenPlan.create({
    required String ifText,
    required String thenText,
    required DateTime at,
    Set<PlanSurface> surfaces = defaultSurfaces,
    String? zoneId,
    String? mood,
  }) => IfThenPlan(
    id: const Uuid().v4(),
    ifText: validateIf(ifText),
    thenText: validateThen(thenText),
    createdAt: at,
    surfaces: surfaces.isEmpty ? defaultSurfaces : surfaces,
    zoneId: zoneId,
    mood: triggerMoodOptions.containsKey(mood) ? mood : null,
  );

  static const maxPlans = 20;
  static const maxIfLength = 120;
  static const maxThenLength = 200;
  static const defaultSurfaces = {
    PlanSurface.zone,
    PlanSurface.window,
    PlanSurface.craving,
  };

  final String id;

  /// The situation: "I'm at the bus stand" / "I feel bored". Without the
  /// leading "If".
  final String ifText;

  /// The step: "walk to the tea stall and call Ravi". Without "then I will".
  final String thenText;
  final DateTime createdAt;
  final Set<PlanSurface> surfaces;

  /// Optional: only for this danger zone.
  final String? zoneId;

  /// Optional: only when this mood (a `triggerMoodOptions` key) is tagged.
  final String? mood;

  /// "If I'm at the bus stand, then I will walk to the tea stall."
  String get sentence => 'If $ifText, then I will $thenText.';

  IfThenPlan copyWith({
    String? ifText,
    String? thenText,
    Set<PlanSurface>? surfaces,
    String? zoneId,
    String? mood,
    bool clearZone = false,
    bool clearMood = false,
  }) => IfThenPlan(
    id: id,
    ifText: ifText == null ? this.ifText : validateIf(ifText),
    thenText: thenText == null ? this.thenText : validateThen(thenText),
    createdAt: createdAt,
    surfaces: surfaces == null || surfaces.isEmpty ? this.surfaces : surfaces,
    zoneId: clearZone ? null : zoneId ?? this.zoneId,
    mood: clearMood ? null : mood ?? this.mood,
  );

  static final _leadingIf = RegExp(r'^\s*if\s+', caseSensitive: false);
  static final _leadingThen = RegExp(
    r'^\s*(?:then\s+)?(?:i\s+will\s+|i\x27ll\s+|i\s+)?',
    caseSensitive: false,
  );

  /// Trims, and drops a leading "If" the user typed out of habit.
  static String cleanIf(String text) => text
      .replaceFirst(_leadingIf, '')
      .trim()
      .replaceAll(RegExp(r'[,.]+$'), '');

  /// Trims, and drops a leading "then I will" the user typed out of habit.
  static String cleanThen(String text) => text
      .replaceFirst(_leadingThen, '')
      .trim()
      .replaceAll(RegExp(r'[.]+$'), '');

  static String validateIf(String text) {
    final clean = cleanIf(text);
    if (clean.isEmpty) {
      throw const FormatException('Say what the situation is.');
    }
    if (clean.length > maxIfLength) {
      throw const FormatException('Keep the "if" under 120 characters.');
    }
    return clean;
  }

  static String validateThen(String text) {
    final clean = cleanThen(text);
    if (clean.isEmpty) {
      throw const FormatException('Say what you will do.');
    }
    if (clean.length > maxThenLength) {
      throw const FormatException('Keep the "then" under 200 characters.');
    }
    return clean;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'if': ifText,
    'then': thenText,
    'createdAt': createdAt.toIso8601String(),
    'surfaces': [
      for (final s in PlanSurface.values)
        if (surfaces.contains(s)) s.name,
    ],
    'zoneId': ?zoneId,
    'mood': ?mood,
  };

  /// Tolerant: returns null for an item that cannot be read.
  static IfThenPlan? tryFromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final id = json['id'];
      final created = DateTime.tryParse(json['createdAt']?.toString() ?? '');
      if (id is! String || id.isEmpty || created == null) return null;
      final raw = json['surfaces'];
      final surfaces = raw is List
          ? {
              for (final s in PlanSurface.values)
                if (raw.contains(s.name)) s,
            }
          : <PlanSurface>{};
      final zone = json['zoneId'];
      final mood = json['mood'];
      return IfThenPlan(
        id: id,
        ifText: validateIf('${json['if']}'),
        thenText: validateThen('${json['then']}'),
        createdAt: created,
        surfaces: surfaces.isEmpty ? defaultSurfaces : surfaces,
        zoneId: zone is String && zone.isNotEmpty ? zone : null,
        mood: mood is String && mood.isNotEmpty ? mood : null,
      );
    } on FormatException {
      return null;
    }
  }

  /// Missing or malformed means none (older saves and backups). An item that
  /// cannot be read is skipped, never an error: plans must not be able to
  /// stop a backup or a save from loading.
  static List<IfThenPlan> decodeList(Object? json) {
    if (json is! List) return const [];
    final seen = <String>{};
    final out = <IfThenPlan>[];
    for (final item in json) {
      final plan = tryFromJson(item);
      if (plan != null && seen.add(plan.id) && out.length < maxPlans) {
        out.add(plan);
      }
    }
    return List.unmodifiable(out);
  }
}

/// Plans for entering [zoneId]: that zone's own plans first, then the ones
/// meant for any zone.
List<IfThenPlan> plansForZone(List<IfThenPlan> plans, String? zoneId) {
  final own = <IfThenPlan>[];
  final any = <IfThenPlan>[];
  for (final plan in plans) {
    if (!plan.surfaces.contains(PlanSurface.zone)) continue;
    // A mood plan belongs to the craving sheet, where the mood is tagged.
    if (plan.mood != null) continue;
    if (plan.zoneId == null) {
      any.add(plan);
    } else if (plan.zoneId == zoneId) {
      own.add(plan);
    }
  }
  return [...own, ...any];
}

/// Plans for the risk window or craving peak. A plan tied to one danger zone
/// or one mood is left for those moments.
List<IfThenPlan> plansForWindow(List<IfThenPlan> plans) => [
  for (final plan in plans)
    if (plan.surfaces.contains(PlanSurface.window) &&
        plan.zoneId == null &&
        plan.mood == null)
      plan,
];

/// Plans for a craving. A plan tied to a mood shows only when that mood was
/// just tagged, and comes first; a plan tied to a zone shows only for it.
List<IfThenPlan> plansForCraving(
  List<IfThenPlan> plans, {
  String? mood,
  String? zoneId,
}) {
  final matched = <IfThenPlan>[];
  final general = <IfThenPlan>[];
  for (final plan in plans) {
    if (!plan.surfaces.contains(PlanSurface.craving)) continue;
    if (plan.zoneId != null && plan.zoneId != zoneId) continue;
    if (plan.mood != null) {
      if (plan.mood == mood) matched.add(plan);
    } else {
      general.add(plan);
    }
  }
  return [...matched, ...general];
}

/// The hour of day cravings and slips usually cluster in, or null until
/// there is enough to say: 5 signals, at least 3 in the top hour, and more
/// than the next hour.
int? usualPeakHour(List<RecoveryEvent> events) {
  final hours = List<int>.filled(24, 0);
  var total = 0;
  for (final e in events) {
    if (e.type != RecoveryEventType.craving &&
        e.type != RecoveryEventType.relapse) {
      continue;
    }
    hours[e.timestamp.toLocal().hour]++;
    total++;
  }
  if (total < 5) return null;
  final ranked = [for (var h = 0; h < 24; h++) h]
    ..sort((a, b) => hours[b].compareTo(hours[a]));
  final top = ranked.first;
  if (hours[top] < 3 || hours[top] <= hours[ranked[1]]) return null;
  return top;
}

/// True inside the risk window, or from 30 minutes before to an hour after
/// the usual peak hour. That is when a window plan is worth showing.
bool isPlanMoment({
  required DateTime now,
  required RiskWindow window,
  required List<RecoveryEvent> events,
}) {
  final local = now.toLocal();
  if (window.contains(local)) return true;
  final peak = usualPeakHour(events);
  if (peak == null) return false;
  final minute = local.hour * 60 + local.minute;
  final from = peak * 60 - 30;
  final to = peak * 60 + 60;
  bool within(int m) => m >= from && m < to;
  return within(minute) || within(minute + 1440) || within(minute - 1440);
}

/// One line for a notification: only the user's own "then", prefixed. Never
/// built for private notifications (they are replaced wholesale by neutral
/// wording before they are shown).
String planNotificationLine(IfThenPlan plan) => 'Your plan: ${plan.sentence}';
