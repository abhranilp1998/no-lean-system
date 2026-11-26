import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';

RelapseLogEntry _entry(RelapseType type, {String note = ''}) => RelapseLogEntry(
  occurredAt: DateTime(2026, 11, 26, 21),
  type: type,
  note: note,
  attemptedSos: false,
);

void main() {
  test('benzo-only saves do not promise to update clean time', () {
    final reason = relapseAuthReason([
      _entry(RelapseType.benzo),
      _entry(RelapseType.benzo),
    ]);
    expect(reason, isNot(contains('update clean time')));
    expect(reason, contains('not reset'));
  });

  test('lean or mixed saves still say clean time updates', () {
    for (final entries in [
      [_entry(RelapseType.fullLean)],
      [_entry(RelapseType.benzo), _entry(RelapseType.fullLean)],
      [_entry(RelapseType.leanPlusAlcohol)],
      // OTHER naming a lean brand is lean.
      [_entry(RelapseType.other, note: 'Phensedyl')],
    ]) {
      expect(relapseAuthReason(entries), contains('update clean time'));
    }
  });

  test('plain time-only saves (no entries) keep the reset wording', () {
    expect(relapseAuthReason(null), contains('update clean time'));
    expect(relapseAuthReason(const []), contains('update clean time'));
  });
}
