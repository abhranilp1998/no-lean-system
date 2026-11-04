import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/slip_tone.dart';

void main() {
  test('every post-slip line is warm, not robotic', () {
    for (final l in [
      ...slipLoggedLines,
      slipCooldownSubtitle,
      slipsRecordedMessage(1),
      slipsRecordedMessage(3),
    ]) {
      expect(isWarmCopy(l), isTrue, reason: l);
    }
    expect(isWarmCopy('2 RELAPSES RECORDED // HISTORY PRESERVED.'), isFalse);
  });
  test('seed picks deterministically and wraps', () {
    expect(slipLoggedMessage(seed: 0), slipLoggedLines[0]);
    expect(
      slipLoggedMessage(seed: slipLoggedLines.length + 1),
      slipLoggedLines[1],
    );
    expect(slipsRecordedMessage(3), contains('3'));
  });
}
