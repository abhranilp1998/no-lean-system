/// The full-screen home-screen widgets shipped in the widget pack.
///
/// Every widget is on for every user today. This list is the single switch a
/// future per-user picker will drive: the app only renders art for, and the
/// native side only draws, widgets in [enabledFullscreenWidgets].
enum FullscreenWidget {
  nightTimeline,
  garden,
  eveningShield,
  dangerRadar,
  futureNote,
}

const enabledFullscreenWidgets = FullscreenWidget.values;

/// What a stretched NO LEAN widget (4x2/4x3 made large, or the "NO LEAN
/// Full" widget at any size) shows. Stored in app state (v15+) and backups
/// (format 10+); `auto` changes through the day. Privacy mode always forces
/// the neutral timeline on the native side.
enum StretchedWidgetView {
  auto('auto', 'Auto', 'Changes through the day: garden, evening, tonight.'),
  garden('garden', 'Garden', 'One plant per day.'),
  eveningShield('shield', 'Evening', 'Countdown and three big buttons.'),
  nightTimeline('night', 'Tonight', 'The evening hour by hour.'),
  wave('wave', 'Ride it out', 'A calm wave; tap to open it in the app.'),
  map('map', 'Map', 'Saved places, no names.'),
  note('note', 'Note', 'A sealed envelope; the note opens in the app.');

  const StretchedWidgetView(this.nativeName, this.label, this.description);

  /// The value the Android side stores and reads.
  final String nativeName;
  final String label;
  final String description;

  static StretchedWidgetView fromName(
    Object? name, {
    StretchedWidgetView fallback = StretchedWidgetView.auto,
  }) {
    for (final v in values) {
      if (v.name == name || v.nativeName == name) return v;
    }
    return fallback;
  }
}
