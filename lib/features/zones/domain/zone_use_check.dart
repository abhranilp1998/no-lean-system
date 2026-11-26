import 'dart:convert';

import '../../recovery/domain/use_check.dart';
import 'zone_entry.dart';

/// Follow-up "Did you use?" after a visit to a saved danger zone.
///
/// Built on the use-check (A) pipeline: one pending check, the same YES / NO
/// / LATER actions, the same quiet-hours rule. This file only decides *whether*
/// to ask, so the app never nags.

/// How long after arriving the check becomes due ([UseCheckTrigger.zoneVisit]).
Duration get zoneUseCheckDelay => UseCheckTrigger.zoneVisit.delay;

/// A visit older than this is not asked about any more.
const zoneUseCheckMaxAge = Duration(hours: 24);

/// The same zone is asked about at most once per this long.
const zoneUseCheckZoneCooldown = Duration(hours: 4);

/// Any two questions are at least this far apart.
const zoneUseCheckAnyCooldown = Duration(minutes: 90);

/// At most this many zone questions in any 24 hours.
const zoneUseCheckDailyMax = 3;

/// "Not sure / later" snoozes this many times, then the question is dropped.
const zoneUseCheckMaxSnoozes = 2;

enum ZoneUseCheckDecision {
  ask,

  /// The visit is too old to ask about.
  stale,

  /// Same visit already reported (app and background geofence both fire).
  alreadyAsked,

  /// This zone was asked about recently.
  zoneCooldown,

  /// Another zone question was asked recently.
  anyCooldown,

  /// Already asked the daily maximum.
  dailyLimit,
}

/// Visits we have already asked about, newest last. No coordinates, only the
/// zone id and when the visit started.
class ZoneUseCheckLedger {
  const ZoneUseCheckLedger([this.asked = const []]);

  final List<({String zoneId, DateTime at})> asked;

  ZoneUseCheckDecision decide(ZoneEntry entry, DateTime now) {
    final age = now.difference(entry.at);
    if (age > zoneUseCheckMaxAge) return ZoneUseCheckDecision.stale;
    for (final a in asked) {
      if (a.zoneId == entry.zoneId &&
          a.at.difference(entry.at).abs() < zoneEntryDedupWindow) {
        return ZoneUseCheckDecision.alreadyAsked;
      }
    }
    for (final a in asked) {
      if (a.zoneId == entry.zoneId &&
          a.at.difference(entry.at).abs() < zoneUseCheckZoneCooldown) {
        return ZoneUseCheckDecision.zoneCooldown;
      }
    }
    for (final a in asked) {
      if (a.at.difference(entry.at).abs() < zoneUseCheckAnyCooldown) {
        return ZoneUseCheckDecision.anyCooldown;
      }
    }
    final recent = asked.where(
      (a) => entry.at.difference(a.at) < const Duration(hours: 24),
    );
    if (recent.length >= zoneUseCheckDailyMax) {
      return ZoneUseCheckDecision.dailyLimit;
    }
    return ZoneUseCheckDecision.ask;
  }

  ZoneUseCheckLedger withVisit(ZoneEntry entry, DateTime now) =>
      ZoneUseCheckLedger([
        for (final a in asked)
          if (now.difference(a.at) < const Duration(days: 2)) a,
        (zoneId: entry.zoneId, at: entry.at),
      ]);

  String encode() => jsonEncode([
    for (final a in asked) {'zoneId': a.zoneId, 'at': a.at.toIso8601String()},
  ]);

  static ZoneUseCheckLedger decode(String? raw) {
    if (raw == null) return const ZoneUseCheckLedger();
    try {
      return ZoneUseCheckLedger([
        for (final item in jsonDecode(raw) as List)
          (
            zoneId: (item as Map)['zoneId'] as String,
            at: DateTime.parse(item['at'] as String),
          ),
      ]);
    } catch (_) {
      return const ZoneUseCheckLedger();
    }
  }
}

/// True once a zone question has used up its snoozes.
bool zoneCheckExhausted(UseCheck check) =>
    check.snoozes >= zoneUseCheckMaxSnoozes;

/// A pending zone check older than this is dropped instead of shown.
bool zoneCheckExpired(UseCheck check, DateTime now) =>
    now.difference(check.triggeredAt) > zoneUseCheckMaxAge;

/// Warm card / dialog copy. The zone name stays on screen only (never in a
/// notification) and only when we have it.
String zoneCheckHeadline(UseCheck check) => 'Checking in, no pressure';

String zoneCheckBody(UseCheck check) {
  final place = check.zoneName == null ? 'a tough spot' : check.zoneName!;
  return 'You stopped by $place earlier. However it went, you showed up '
      'to answer, and that counts. Did you use?';
}

const zoneCheckNoLabel = 'NO, I STAYED CLEAN';
const zoneCheckYesLabel = 'YES';
const zoneCheckLaterLabel = 'NOT SURE / LATER';

/// What "NO" says back, with the running count of zones resisted.
String zoneResistedMessage(int count) => count <= 1
    ? 'That took strength. One zone resisted. Be proud of that.'
    : 'That took strength. $count zones resisted so far. Be proud of that.';

const zoneCheckSnoozedMessage = 'No problem. I\'ll ask again in 30 minutes.';
const zoneCheckDroppedMessage =
    'No pressure. I won\'t ask about this visit again. You can always log it yourself.';

/// Prefilled note when "YES" opens the logger.
String zoneCheckPrefillNote(UseCheck check) => check.zoneName == null
    ? 'After a visit to a danger zone.'
    : 'After a visit to ${check.zoneName}.';
