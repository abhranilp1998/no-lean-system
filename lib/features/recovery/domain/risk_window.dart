class RiskWindow {
  const RiskWindow({required this.startMinutes, required this.endMinutes})
    : assert(startMinutes >= 0 && startMinutes < minutesPerDay),
      assert(endMinutes >= 0 && endMinutes < minutesPerDay);

  const RiskWindow.defaultWindow()
    : startMinutes = 17 * 60,
      endMinutes = 21 * 60;

  static const minutesPerDay = 24 * 60;

  final int startMinutes;
  final int endMinutes;

  bool get spansMidnight => endMinutes <= startMinutes;

  int get durationMinutes {
    final duration = (endMinutes - startMinutes) % minutesPerDay;
    return duration == 0 ? minutesPerDay : duration;
  }

  bool contains(DateTime dateTime) {
    final minute = dateTime.hour * 60 + dateTime.minute;
    return _containsMinute(minute);
  }

  bool _containsMinute(int minute) {
    if (!spansMidnight) {
      return minute >= startMinutes && minute <= endMinutes;
    }
    return minute >= startMinutes || minute <= endMinutes;
  }

  /// True only when every previously protected minute stays protected.
  /// Handles overnight and full-day windows, including the end minute.
  bool covers(RiskWindow previous) {
    for (var minute = 0; minute < minutesPerDay; minute++) {
      if (previous._containsMinute(minute) && !_containsMinute(minute)) {
        return false;
      }
    }
    return true;
  }

  List<int> reminderMinutes({int count = 4}) {
    assert(count > 0);
    return List.generate(
      count,
      (index) =>
          (startMinutes + (durationMinutes * index ~/ count)) % minutesPerDay,
    );
  }

  String get label =>
      '${formatMinutes(startMinutes)}—${formatMinutes(endMinutes)}';

  Map<String, int> toJson() => {
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
  };

  factory RiskWindow.fromJson(Object? json) {
    if (json is! Map) return const RiskWindow.defaultWindow();
    final start = json['startMinutes'];
    final end = json['endMinutes'];
    if (start is! int || end is! int) {
      return const RiskWindow.defaultWindow();
    }
    if (start < 0 ||
        start >= minutesPerDay ||
        end < 0 ||
        end >= minutesPerDay) {
      return const RiskWindow.defaultWindow();
    }
    return RiskWindow(startMinutes: start, endMinutes: end);
  }

  static String formatMinutes(int minutes) {
    final normalized = minutes % minutesPerDay;
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}
