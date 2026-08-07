import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';

void main() {
  test('CravingEntry round-trips through JSON', () {
    final createdAt = DateTime.parse('2026-08-07T18:15:00.000');
    final entry = CravingEntry(
      intensity: 8,
      trigger: 'After Work',
      note: 'Walked instead of buying.',
      createdAt: createdAt,
    );

    final restored = CravingEntry.fromJson(entry.toJson());

    expect(restored.intensity, 8);
    expect(restored.trigger, 'After Work');
    expect(restored.note, 'Walked instead of buying.');
    expect(restored.createdAt, createdAt);
  });

  test('CravingEntry supplies safe defaults for incomplete JSON', () {
    final before = DateTime.now();
    final entry = CravingEntry.fromJson(const {});
    final after = DateTime.now();

    expect(entry.intensity, 5);
    expect(entry.trigger, 'Other');
    expect(entry.note, isEmpty);
    expect(
      entry.createdAt.isBefore(before),
      isFalse,
      reason: 'fallback timestamp should be created during parsing',
    );
    expect(entry.createdAt.isAfter(after), isFalse);
  });
}
