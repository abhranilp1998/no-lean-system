import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No Android toolchain runs in CI here, so these checks keep the widget's
/// Kotlin, layouts, strings and manifest consistent. RemoteViews fails the
/// whole widget when code touches an id its layout lacks.
void main() {
  const res = 'android/app/src/main/res';
  const kotlin =
      'android/app/src/main/kotlin/com/nolean/no_lean/NoLeanWidgetProvider.kt';
  final source = File(kotlin).readAsStringSync();

  Set<String> idsIn(String layout) => RegExp(r'android:id="@\+id/(\w+)"')
      .allMatches(File('$res/layout/$layout.xml').readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  test('each size layout has exactly the views its flags promise', () {
    final sizes = RegExp(
      r'(SMALL|MEDIUM|LARGE)\(R\.layout\.(\w+), (\w+), (\w+), (\w+), (\w+), (\w+)[,)]',
    ).allMatches(source).toList();
    expect(sizes, hasLength(3));
    for (final size in sizes) {
      final ids = idsIn(size.group(2)!);
      bool flag(int group) => size.group(group) == 'true';
      final expected = {
        'widget_root',
        'widget_status',
        'widget_clean_time',
        'widget_neutral',
        'widget_action_sos',
        if (flag(3)) 'widget_title',
        if (flag(4)) ...['widget_streak', 'widget_pledge'],
        if (flag(5)) 'widget_action_craving',
        if (flag(6)) 'widget_action_relapse',
        if (flag(7)) 'widget_action_code',
      };
      expect(ids, expected, reason: size.group(1));
    }
  });

  test('every string the provider uses exists', () {
    final strings = File('$res/values/strings.xml').readAsStringSync();
    final used = RegExp(
      r'R\.string\.(\w+)',
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(used, isNotEmpty);
    for (final name in used) {
      expect(strings, contains('name="$name"'), reason: name);
    }
  });

  test('all three sizes are declared with info, layout and preview', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final (receiver, info) in [
      ('.NoLeanWidgetProvider', 'no_lean_widget_info'),
      ('.NoLeanSmallWidgetProvider', 'no_lean_widget_small_info'),
      ('.NoLeanLargeWidgetProvider', 'no_lean_widget_large_info'),
    ]) {
      expect(manifest, contains('android:name="$receiver"'));
      expect(manifest, contains('@xml/$info'));
      final xml = File('$res/xml/$info.xml').readAsStringSync();
      for (final match in RegExp(r'@(layout|drawable)/(\w+)').allMatches(xml)) {
        final dir = match.group(1) == 'layout'
            ? ['layout']
            : ['drawable', 'drawable-nodpi'];
        final exists = dir.any(
          (d) =>
              File('$res/$d/${match.group(2)}.xml').existsSync() ||
              File('$res/$d/${match.group(2)}.png').existsSync(),
        );
        expect(exists, isTrue, reason: '${match.group(0)} in $info');
      }
    }
    expect(
      RegExp(r'targetCellWidth="(\d)"\s+android:targetCellHeight="(\d)"')
          .allMatches(
            [
              'no_lean_widget_small_info',
              'no_lean_widget_info',
              'no_lean_widget_large_info',
            ].map((n) => File('$res/xml/$n.xml').readAsStringSync()).join(),
          )
          .map((m) => '${m.group(1)}x${m.group(2)}')
          .toList(),
      ['2x1', '4x2', '4x3'],
    );
  });

  test('the code widget action is accepted by MainActivity', () {
    final activity = File(
      'android/app/src/main/kotlin/com/nolean/no_lean/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('WIDGET_ACTION_CODE = "code"'));
    expect(activity, contains('WIDGET_ACTION_CODE -> action'));
  });
}
