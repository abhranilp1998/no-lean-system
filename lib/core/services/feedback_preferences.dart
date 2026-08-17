enum FeedbackSoundEffect { neonPulse, terminalTick, reactorPing }

class FeedbackPreferences {
  const FeedbackPreferences({
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.soundEffect,
  });

  final bool soundEnabled;
  final bool vibrationEnabled;
  final FeedbackSoundEffect soundEffect;
}

extension FeedbackSoundEffectDetails on FeedbackSoundEffect {
  String get label => switch (this) {
    FeedbackSoundEffect.neonPulse => 'NEON PULSE',
    FeedbackSoundEffect.terminalTick => 'TERMINAL TICK',
    FeedbackSoundEffect.reactorPing => 'REACTOR PING',
  };

  String get description => switch (this) {
    FeedbackSoundEffect.neonPulse => 'Short synthetic confirmation blip',
    FeedbackSoundEffect.terminalTick => 'Dry, minimal console tick',
    FeedbackSoundEffect.reactorPing => 'Sharper high-energy response',
  };
}
