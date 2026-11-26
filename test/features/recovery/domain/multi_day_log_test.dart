import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/multi_day_log.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';

void main() {
  final now = DateTime(2026, 11, 26, 18, 30);

  test('slots drop future days, de-duplicate and sort', () {
    final slots = buildMultiDaySlots([
      DateTime(2026, 11, 24, 3),
      DateTime(2026, 11, 22),
      DateTime(2026, 11, 24, 23),
      DateTime(2026, 11, 27),
    ], now: now);
    expect(slots.map((s) => s.occurredAt), [
      DateTime(2026, 11, 22, multiDayDefaultHour),
      DateTime(2026, 11, 24, multiDayDefaultHour),
    ]);
  });

  test('today at a later time is moved back to now, never the future', () {
    final slots = buildMultiDaySlots([now], now: now, hour: 22, minute: 0);
    expect(slots.single.occurredAt, DateTime(2026, 11, 26, 18, 30));
    final early = buildMultiDaySlots([now], now: now, hour: 9, minute: 15);
    expect(early.single.occurredAt, DateTime(2026, 11, 26, 9, 15));
  });

  test('last N days ends today, oldest first', () {
    expect(lastDays(3, now: now), [
      DateTime(2026, 11, 24),
      DateTime(2026, 11, 25),
      DateTime(2026, 11, 26),
    ]);
    expect(lastDays(2, now: DateTime(2026, 3, 1), includeToday: false), [
      DateTime(2026, 2, 27),
      DateTime(2026, 2, 28),
    ]);
  });

  test('one shared entry expands to one entry per day', () {
    final template = RelapseLogEntry(
      occurredAt: now,
      type: RelapseType.partial,
      note: 'Missed days, same pattern each night.',
      attemptedSos: false,
      contextTags: const ['Stress'],
      cost: 120,
    );
    final slots = buildMultiDaySlots(lastDays(3, now: now), now: now);
    final entries = expandMultiDayEntries(template, slots);
    expect(entries, hasLength(3));
    expect(entries.map((e) => e.occurredAt).toSet(), hasLength(3));
    for (final e in entries) {
      expect(e.toMetadata(), template.toMetadata());
    }
  });

  test('only benzo-only saves leave the lean timer alone', () {
    RelapseLogEntry e(RelapseType t) => RelapseLogEntry(
      occurredAt: now,
      type: t,
      note: 'Twelve chars at least',
      attemptedSos: false,
    );
    expect(entriesResetLeanTimer([e(RelapseType.benzo)]), isFalse);
    expect(
      entriesResetLeanTimer([e(RelapseType.benzo), e(RelapseType.fullLean)]),
      isTrue,
    );
    expect(entriesResetLeanTimer([e(RelapseType.leanPlusAlcohol)]), isTrue);
  });

  test('pickable days exclude the future and pre-2000', () {
    expect(isPickableDay(DateTime(2026, 11, 26, 23, 59), now: now), isTrue);
    expect(isPickableDay(DateTime(2026, 11, 27), now: now), isFalse);
    expect(isPickableDay(DateTime(1999, 12, 31), now: now), isFalse);
  });
}
