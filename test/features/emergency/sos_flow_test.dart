import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/emergency/domain/sos_flow.dart';

void main() {
  test('stages run in order: breathe, ground 5-4-3-2-1, reasons, pledge', () {
    final flow = SosFlow(breathSeconds: 20, minSecondsBeforeExit: 5);
    expect(flow.stage, SosStage.breathe);
    expect(flow.canExit, isFalse);

    // Grounding and reasons cannot be skipped from the breathing stage.
    expect(flow.completeGroundingStep(), isFalse);
    expect(flow.finishReasons(), isFalse);

    for (var i = 0; i < 5; i++) {
      flow.tick();
    }
    expect(flow.canExit, isTrue);
    var advanced = false;
    for (var i = 0; i < 15 && !advanced; i++) {
      advanced = flow.tick();
    }
    expect(advanced, isTrue);
    expect(flow.stage, SosStage.ground);
    expect(flow.progress, closeTo(.25, .001));

    final senses = <String>[];
    while (flow.stage == SosStage.ground) {
      senses.add('${flow.groundingStep.count} ${flow.groundingStep.sense}');
      flow.completeGroundingStep();
    }
    expect(senses, ['5 SEE', '4 TOUCH', '3 HEAR', '2 SMELL', '1 TASTE']);
    expect(flow.stage, SosStage.reasons);
    expect(flow.isComplete, isFalse);

    expect(flow.finishReasons(), isTrue);
    expect(flow.stage, SosStage.pledge);
    expect(flow.isComplete, isTrue);
    expect(flow.progress, 1);
  });

  test('box breathing cycles every 16 seconds', () {
    final flow = SosFlow();
    final phases = <String>[];
    for (var i = 0; i < 16; i += 4) {
      phases.add(flow.breathPhase);
      for (var j = 0; j < 4; j++) {
        flow.tick();
      }
    }
    expect(phases, ['BREATHE IN', 'HOLD', 'BREATHE OUT', 'HOLD EMPTY']);
    expect(flow.breathPhase, 'BREATHE IN');
  });

  test('exit is only held during the first seconds of breathing', () {
    final flow = SosFlow();
    for (var i = 0; i < 14; i++) {
      flow.tick();
    }
    expect(flow.canExit, isFalse);
    flow.tick();
    expect(flow.canExit, isTrue);
  });
}
