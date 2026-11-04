import '../../recovery/domain/recovery_event.dart';

enum PlantState { growing, wilted }

/// One day in the garden.
class GardenPlant {
  const GardenPlant(this.day, this.state);
  final DateTime day;
  final PlantState state;
}

/// Clean days drawn as a garden. A relapse wilts that day's plant; it never
/// wipes the garden. Every milestone of total clean days adds a tree.
class Garden {
  const Garden({required this.plants, required this.cleanTotal});

  /// Total clean days that earn a tree.
  static const treeMilestones = [7, 30, 90, 180, 365];

  /// Plants beyond this are summarised by trees, so the bitmap stays legible.
  static const maxPlants = 84;

  final List<GardenPlant> plants;

  /// Clean days over the whole history, including ones no longer drawn.
  final int cleanTotal;

  int get trees => _treesFor(cleanTotal);

  int get growing => plants.where((p) => p.state == PlantState.growing).length;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Builds the garden for every day from the first event to [today].
  factory Garden.fromEvents(List<RecoveryEvent> events, DateTime today) {
    final end = _day(today);
    if (events.isEmpty) return const Garden(plants: [], cleanTotal: 0);
    final first = events
        .map((e) => e.timestamp.toLocal())
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final relapseDays = {
      for (final e in events)
        if (e.type == RecoveryEventType.relapse) _day(e.timestamp.toLocal()),
    };
    final plants = <GardenPlant>[];
    var cleanTotal = 0;
    for (
      var d = _day(first);
      !d.isAfter(end);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final wilted = relapseDays.contains(d);
      if (!wilted) cleanTotal++;
      plants.add(
        GardenPlant(d, wilted ? PlantState.wilted : PlantState.growing),
      );
    }
    final shown = plants.length > maxPlants
        ? plants.sublist(plants.length - maxPlants)
        : plants;
    return Garden(plants: shown, cleanTotal: cleanTotal);
  }

  /// Tomorrow's garden if tomorrow stays clean, pre-rendered so the widget
  /// can roll over at midnight without the app running.
  Garden plusCleanDay(DateTime day) {
    final next = [...plants, GardenPlant(_day(day), PlantState.growing)];
    return Garden(
      plants: next.length > maxPlants
          ? next.sublist(next.length - maxPlants)
          : next,
      cleanTotal: cleanTotal + 1,
    );
  }

  static int _treesFor(int clean) =>
      treeMilestones.where((m) => clean >= m).length;
}
