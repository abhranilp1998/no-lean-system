/// P1 "Tell me anything": a tiny on-device classifier. No network, no model;
/// keyword rules over normalised text, so it is predictable and testable.
enum TellKind { relapse, aboutToUse, feedback, other }

class TellResult {
  const TellResult(this.kind, {this.hoursAgo});
  final TellKind kind;

  /// "2 hours ago", "an hour back" → prefill for the past-relapse logger.
  final int? hoursAgo;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[’']"), '')
    .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _negation = RegExp(
  r'\b(didnt|did not|havent|have not|never|not) (use|used|drink|drank|take|took|relapse|relapsed|buy|bought)\b',
);

final _relapse = RegExp(
  r'\b(i (just |already )?(used|relapsed|slipped)|relapsed|slipped up|(had|drank|took|bought|got) (a |one |two |some |\d+ )?(bottle|bottles|lean|syrup|ascoril|phensedyl|corex|codeine|sip|sips)|fell off|messed up again)\b',
);

final _about = RegExp(
  r'\b(about to|going to|gonna|wanna|want to|want some|need some|craving|crave|urge|tempted|thinking (of|about) (buying|using|getting)|on my way to (buy|get)|might (use|buy|relapse)|cant stop thinking)\b',
);

final _feedback = RegExp(
  r'\b(app|bug|crash|crashes|feature|button|screen|notification|notifications|widget|setting|settings|should|please add|would be nice|can you add|feedback|suggestion|ui|ux|broken|doesnt work|not working|annoying|fix)\b',
);

final _hoursAgo = RegExp(
  r'\b(\d{1,2}|an|a|one|two|three|four|five|six) (hour|hours|hr|hrs|h) (ago|back|before)\b',
);

const _words = {
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
};

TellResult classifyTell(String raw) {
  final t = _norm(raw);
  if (t.isEmpty) return const TellResult(TellKind.other);
  final ago = _hoursAgo.firstMatch(t);
  final hours = ago == null
      ? null
      : (int.tryParse(ago.group(1)!) ?? _words[ago.group(1)!]);
  final negated = _negation.hasMatch(t);
  // Safety first: a used/using signal outranks feedback in the same text.
  if (!negated && _relapse.hasMatch(t)) {
    return TellResult(TellKind.relapse, hoursAgo: hours);
  }
  if (_about.hasMatch(t)) return const TellResult(TellKind.aboutToUse);
  if (_feedback.hasMatch(t)) return const TellResult(TellKind.feedback);
  return const TellResult(TellKind.other);
}
