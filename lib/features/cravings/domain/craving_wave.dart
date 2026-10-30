import '../../recovery/domain/recovery_event.dart';

/// One point on a craving's curve: minutes since it started and how strong.
class WavePoint {
  const WavePoint(this.minute, this.intensity);
  final double minute;
  final int intensity;
}

/// How long past cravings took to pass, from real logs: a craving followed by
/// a recheck at intensity 0 ("It passed").
class CravingWaveHistory {
  const CravingWaveHistory(this.passedMinutes);

  /// Newest first.
  final List<int> passedMinutes;

  int? get lastPassedMinutes => passedMinutes.firstOrNull;

  factory CravingWaveHistory.fromEvents(List<RecoveryEvent> events) {
    final cravings = {
      for (final e in events)
        if (e.type == RecoveryEventType.craving) e.id: e,
    };
    final passed = <(DateTime, int)>[];
    final seen = <String>{};
    for (final e in events) {
      if (e.type != RecoveryEventType.cravingCheck) continue;
      if (e.metadata['intensity'] != 0) continue;
      final id = e.metadata['cravingId'];
      final craving = cravings[id];
      if (craving == null || !seen.add(id as String)) continue;
      final minutes = e.timestamp.difference(craving.timestamp).inMinutes;
      if (minutes < 0) continue;
      passed.add((e.timestamp, minutes < 1 ? 1 : minutes));
    }
    passed.sort((a, b) => b.$1.compareTo(a.$1));
    return CravingWaveHistory([for (final p in passed) p.$2]);
  }

  /// Points of the craving with [cravingId], for redrawing its curve.
  static List<WavePoint> pointsFor(
    List<RecoveryEvent> events,
    String cravingId,
  ) {
    final craving = events.where((e) => e.id == cravingId).firstOrNull;
    if (craving == null) return const [];
    return [
      WavePoint(0, (craving.metadata['intensity'] as int?) ?? 5),
      for (final e in events)
        if (e.type == RecoveryEventType.cravingCheck &&
            e.metadata['cravingId'] == cravingId)
          WavePoint(
            e.timestamp.difference(craving.timestamp).inSeconds / 60,
            (e.metadata['intensity'] as int?) ?? 0,
          ),
    ];
  }
}
