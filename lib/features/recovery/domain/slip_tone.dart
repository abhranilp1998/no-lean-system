/// P1 warmer tone after a slip. Plain, human lines instead of system-speak.
/// Picked deterministically from [seed] so the copy varies without
/// randomness in tests.
const slipLoggedLines = <String>[
  'Thanks for telling me. One use does not erase what you have built.',
  'Logged. You were honest, and that is the hardest part. Be kind to yourself tonight.',
  'Got it. This is a moment, not the whole story. Drink some water and rest.',
  'Saved. You are still in this. We start again from right here.',
];

const slipCooldownSubtitle =
    'You are not starting from zero. Breathe slowly, drink some water, and remember why you began.';

String slipLoggedMessage({int seed = 0}) =>
    slipLoggedLines[seed.abs() % slipLoggedLines.length];

String slipsRecordedMessage(int count) => count == 1
    ? 'Saved that one. Thank you for being honest with yourself.'
    : 'Saved all $count. Thank you for being honest with yourself.';

/// True if the copy avoids cold, robotic phrasing.
bool isWarmCopy(String s) {
  final l = s.toLowerCase();
  return !s.contains('//') &&
      s != s.toUpperCase() &&
      !RegExp(
        r'\b(failed|failure|relapse recorded|history preserved)\b',
      ).hasMatch(l);
}
