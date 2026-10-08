/// The multi-stage SOS sequence: breathe, ground, reasons, re-pledge.
///
/// Pure state so the sequencing rules are testable without widgets.
enum SosStage { breathe, ground, reasons, pledge }

extension SosStageCopy on SosStage {
  String get label => switch (this) {
    SosStage.breathe => 'BREATHE',
    SosStage.ground => 'GROUND',
    SosStage.reasons => 'REASONS',
    SosStage.pledge => 'PLEDGE',
  };

  String get headline => switch (this) {
    SosStage.breathe => 'SLOW THE BODY DOWN',
    SosStage.ground => 'GET BACK INTO THE ROOM',
    SosStage.reasons => 'REMEMBER WHY',
    SosStage.pledge => 'LOCK IT IN',
  };
}

class GroundingStep {
  const GroundingStep(this.count, this.sense, this.prompt);

  final int count;
  final String sense;
  final String prompt;
}

const groundingSteps = [
  GroundingStep(5, 'SEE', 'Name 5 things you can see right now. Say them.'),
  GroundingStep(4, 'TOUCH', 'Touch 4 things. Feel the texture and weight.'),
  GroundingStep(3, 'HEAR', 'Name 3 sounds you can hear, near or far.'),
  GroundingStep(2, 'SMELL', 'Find 2 things you can smell.'),
  GroundingStep(1, 'TASTE', 'Notice 1 thing you can taste.'),
];

class SosFlow {
  SosFlow({this.breathSeconds = 60, this.minSecondsBeforeExit = 15});

  final int breathSeconds;

  /// The only hold on leaving: the first seconds of breathing.
  final int minSecondsBeforeExit;

  SosStage stage = SosStage.breathe;
  late int remaining = breathSeconds;
  int groundIndex = 0;

  int get elapsedBreathing => breathSeconds - remaining;

  bool get canExit =>
      stage != SosStage.breathe || elapsedBreathing >= minSecondsBeforeExit;

  /// Box breathing: 4 s in, 4 s hold, 4 s out, 4 s hold.
  String get breathPhase => switch ((elapsedBreathing % 16) ~/ 4) {
    0 => 'BREATHE IN',
    1 => 'HOLD',
    2 => 'BREATHE OUT',
    _ => 'HOLD EMPTY',
  };

  GroundingStep get groundingStep =>
      groundingSteps[groundIndex.clamp(0, groundingSteps.length - 1)];

  /// Overall progress 0–1 across the four stages.
  double get progress {
    final within = switch (stage) {
      SosStage.breathe => elapsedBreathing / breathSeconds,
      SosStage.ground => groundIndex / groundingSteps.length,
      SosStage.reasons => 0.0,
      SosStage.pledge => 1.0,
    };
    final value = (stage.index + within) / SosStage.values.length;
    return stage == SosStage.pledge ? 1 : value.clamp(0, 1);
  }

  /// Advances the breathing timer by one second. Returns true when breathing
  /// just finished and the flow moved to grounding.
  bool tick() {
    if (stage != SosStage.breathe) return false;
    if (remaining > 1) {
      remaining--;
      return false;
    }
    remaining = 0;
    stage = SosStage.ground;
    return true;
  }

  /// Marks the current 5-4-3-2-1 sense done. Returns true when grounding
  /// finished and the flow moved to reasons.
  bool completeGroundingStep() {
    if (stage != SosStage.ground) return false;
    groundIndex++;
    if (groundIndex < groundingSteps.length) return false;
    stage = SosStage.reasons;
    return true;
  }

  /// Moves from reasons to the re-pledge. Returns true on the transition.
  bool finishReasons() {
    if (stage != SosStage.reasons) return false;
    stage = SosStage.pledge;
    return true;
  }

  /// Reaching the pledge stage counts as a completed SOS.
  bool get isComplete => stage == SosStage.pledge;
}
