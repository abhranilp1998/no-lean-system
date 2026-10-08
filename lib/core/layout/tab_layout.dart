import 'package:flutter/material.dart';

/// One layout contract for the five shell tabs (Dashboard, Cravings,
/// Progress, Timeline, Settings).
///
/// The shell owns the only Scaffold and SafeArea: it handles the status bar,
/// display cutouts, the navigation bar and the keyboard. Tabs never add their
/// own Scaffold or SafeArea; they scroll inside [TabListView], which applies
/// the same gutters and bottom clearance everywhere, plus any bottom inset
/// still unconsumed above it (0 inside the shell).
abstract final class TabLayout {
  static const gutter = 18.0;
  static const top = 14.0;

  /// Space after the last item so it never sits flush on the nav bar.
  static const bottomClearance = 30.0;

  static EdgeInsets padding(BuildContext context) => EdgeInsets.fromLTRB(
    gutter,
    top,
    gutter,
    bottomClearance + MediaQuery.paddingOf(context).bottom,
  );
}

/// The scroll view every shell tab uses.
class TabListView extends StatelessWidget {
  const TabListView({required List<Widget> this.children, super.key})
    : itemCount = null,
      itemBuilder = null;

  /// Lazily built rows for long lists such as the timeline.
  const TabListView.builder({
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
    super.key,
  }) : children = null;

  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final padding = TabLayout.padding(context);
    const dismiss = ScrollViewKeyboardDismissBehavior.onDrag;
    if (children case final items?) {
      return ListView(
        padding: padding,
        keyboardDismissBehavior: dismiss,
        children: items,
      );
    }
    return ListView.builder(
      padding: padding,
      keyboardDismissBehavior: dismiss,
      itemCount: itemCount,
      itemBuilder: itemBuilder!,
    );
  }
}

/// Scrollable dialog body that stays usable with the keyboard open: the
/// dialog already shrinks above the keyboard, this scrolls the remainder and
/// lets a drag dismiss the keyboard.
class KeyboardSafeScroll extends StatelessWidget {
  const KeyboardSafeScroll({required this.child, super.key});

  final Widget child;

  /// Pass to a TextField's `scrollPadding` so the primary button below the
  /// field scrolls into view together with it.
  static const fieldScrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 96);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: child,
  );
}
