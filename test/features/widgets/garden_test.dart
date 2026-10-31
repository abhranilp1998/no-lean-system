import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/widgets/domain/garden.dart';

RecoveryEvent ev(RecoveryEventType type, DateTime at) =>
    RecoveryEvent.create(type: type, timestamp: at);

void main() {
  final start = DateTime(2026, 10, 1, 9);

  test('one plant per day, relapse days wilt instead of wiping', () {
    final garden = Garden.fromEvents([
      ev(RecoveryEventType.recoveryStart, start),
      ev(RecoveryEventType.relapse, DateTime(2026, 10, 5, 22)),
    ], DateTime(2026, 10, 10, 12));
    expect(garden.plants, hasLength(10));
    expect(
      garden.plants.where((p) => p.state == PlantState.wilted).single.day,
      DateTime(2026, 10, 5),
    );
    expect(garden.growing, 9);
    expect(garden.cleanTotal, 9);
    expect(garden.trees, 1); // 7-day milestone.
  });

  test('milestone trees count all clean days, beyond the drawn window', () {
    final garden = Garden.fromEvents([
      ev(RecoveryEventType.recoveryStart, DateTime(2026, 6, 1)),
    ], DateTime(2026, 10, 30));
    expect(garden.plants, hasLength(Garden.maxPlants));
    expect(garden.cleanTotal, 152);
    expect(garden.trees, 3); // 7, 30, 90.
  });

  test('tomorrow adds one growing plant and may add a tree', () {
    final garden = Garden.fromEvents([
      ev(RecoveryEventType.recoveryStart, start),
    ], DateTime(2026, 10, 6));
    expect(garden.trees, 0);
    final next = garden.plusCleanDay(DateTime(2026, 10, 7));
    expect(next.plants, hasLength(7));
    expect(next.trees, 1);
  });

  test('empty history draws an empty garden', () {
    final garden = Garden.fromEvents(const [], DateTime(2026, 10, 30));
    expect(garden.plants, isEmpty);
    expect(garden.trees, 0);
  });
}
