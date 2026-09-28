enum DashboardNoticeStyle {
  edgeRail,
  statusStack,
  systemInbox;

  String get label => switch (this) {
    DashboardNoticeStyle.edgeRail => 'EDGE PILLS',
    DashboardNoticeStyle.statusStack => 'STATUS STACK',
    DashboardNoticeStyle.systemInbox => 'SYSTEM INBOX',
  };

  String get description => switch (this) {
    DashboardNoticeStyle.edgeRail =>
      'Right-aligned signal pills that expand in place.',
    DashboardNoticeStyle.statusStack =>
      'Two compact status segments with an inline detail panel.',
    DashboardNoticeStyle.systemInbox =>
      'One sleek message capsule that opens a separate drawer.',
  };
}
