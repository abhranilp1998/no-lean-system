import '../../zones/domain/zone_presence.dart';

/// How long the SOS button must be held to open a prefilled text, rather
/// than today's short-tap path (the SOS screen).
const sosHoldDuration = Duration(milliseconds: 2000);

/// SharedPreferences key. Missing or blank means [defaultSosTextTemplate].
/// Not part of recovery state or a backup: an older build simply ignores it
/// and a missing value is the historical default.
const sosTextTemplateKey = 'sos_text_template_v1';

/// Longest user-edited template we keep. Anything longer is dropped (the
/// default is used) so a bad backup or paste can never break SOS.
const sosTextTemplateMaxLength = 280;

/// A maps link is "current" if the fix is this fresh.
const sosFixFresh = Duration(minutes: 5);

/// Last-known fixes older than this are not useful enough to send.
const sosFixMaxAge = Duration(hours: 24);

/// Short, calm default. No government numbers or helplines. The location
/// line is added by [composeSosText] unless the template already contains
/// `{location}`.
const defaultSosTextTemplate =
    'I need help right now. Please call or come check on me.';

/// A `{location}` token in a custom template is replaced by the maps line.
const sosLocationToken = '{location}';

/// Google Maps query URL, composed locally from coordinates. Opening the
/// SMS composer does not need a network; the recipient uses the link later.
String sosMapsLink(LocationFix fix) =>
    'https://maps.google.com/?q='
    '${fix.latitude.toStringAsFixed(5)},${fix.longitude.toStringAsFixed(5)}';

/// One line describing where the user is, or that we could not share it.
String sosLocationLine(LocationFix? fix, {DateTime? now}) {
  if (fix == null) {
    return "I couldn't share my location — please call me.";
  }
  final age = (now ?? DateTime.now()).difference(fix.at);
  if (age.isNegative || age > sosFixMaxAge) {
    return "I couldn't share my location — please call me.";
  }
  final link = sosMapsLink(fix);
  if (age <= sosFixFresh) return "I'm here: $link";
  return 'Last place I was (${_ageLabel(age)} ago): $link';
}

String _ageLabel(Duration age) {
  if (age.inMinutes < 60) {
    final m = age.inMinutes < 1 ? 1 : age.inMinutes;
    return '~$m min';
  }
  final hours = age.inHours;
  return hours == 1 ? '~1 hour' : '~$hours hours';
}

/// Blank, whitespace-only or over-long values fall back to the default, so
/// an empty optional settings field stays backwards compatible.
String normalizeSosTextTemplate(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.length > sosTextTemplateMaxLength) {
    return defaultSosTextTemplate;
  }
  return value;
}

/// The SMS body: the (default or edited) template plus a location line.
///
/// Never auto-sends. The caller only opens the phone's SMS composer.
String composeSosText({String? template, LocationFix? fix, DateTime? now}) {
  final body = normalizeSosTextTemplate(template);
  final line = sosLocationLine(fix, now: now);
  if (body.contains(sosLocationToken)) {
    return body.replaceAll(sosLocationToken, line);
  }
  return '$body\n$line';
}

/// `sms:` URI for the phone's composer. An empty [phone] still opens the
/// composer so the user can pick someone; they press Send themselves.
Uri sosTextUri({required String body, String? phone}) =>
    Uri(scheme: 'sms', path: phone ?? '', queryParameters: {'body': body});
