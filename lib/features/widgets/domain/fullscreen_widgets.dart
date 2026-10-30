/// The full-screen home-screen widgets shipped in the widget pack.
///
/// Every widget is on for every user today. This list is the single switch a
/// future per-user picker will drive: the app only renders art for, and the
/// native side only draws, widgets in [enabledFullscreenWidgets].
enum FullscreenWidget { nightTimeline, garden, eveningShield, dangerRadar }

const enabledFullscreenWidgets = FullscreenWidget.values;
