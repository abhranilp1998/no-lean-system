import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/layout/tab_layout.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/timeline/domain/history_projection.dart';
import 'package:no_lean/features/timeline/presentation/timeline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

final _captureKey = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<(RecoveryController, MemoryRecoveryStore, List<RecoveryEvent>)> _pump(
  WidgetTester tester, {
  HistoryCategory category = HistoryCategory.recovery,
  double scale = 1,
  bool empty = false,
}) async {
  if (scale == 1) {
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final at = DateTime(2026, 1, 20, 18);
  final events = [
    RecoveryEvent.create(
      type: RecoveryEventType.recoveryStart,
      timestamp: at.subtract(const Duration(days: 1)),
    ),
    if (!empty) ...[
      RecoveryEvent.create(
        type: RecoveryEventType.relapse,
        timestamp: at,
        metadata: {
          'zoneName': 'Sample place',
          'amount': 100,
          'unit': 'ml',
          'cost': 120,
          'note': 'A recovery record',
          'recordedAt': '2026-01-20T18:15:00.123456',
        },
      ),
      RecoveryEvent.create(
        type: RecoveryEventType.settingsChange,
        timestamp: at.add(const Duration(minutes: 4)),
        metadata: {'setting': 'scanlines', 'newValue': 'false'},
      ),
      for (final (source, minute) in [
        ('background', 3),
        ('app', 2),
        ('manualPin', 1),
      ])
        RecoveryEvent.create(
          type: RecoveryEventType.zoneEntry,
          timestamp: at.add(Duration(minutes: minute)),
          metadata: {
            'zoneId': 'sample-zone',
            'zoneName': 'Sample place',
            'source': source,
          },
        ),
    ],
  ];
  final store = MemoryRecoveryStore(
    jsonEncode({
      'stateVersion': RecoveryController.stateVersion,
      'events': events.map((e) => e.toJson()).toList(),
    }),
  );
  final c = RecoveryController(
    store: store,
    relapseLock: FakeRelapseLock(),
    now: () => at.add(const Duration(hours: 1)),
  );
  await c.load();
  final container = ProviderContainer(
    overrides: [recoveryProvider.overrideWith((ref) => c)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNoLeanTheme(reduceMotion: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: _captureKey,
          child: Scaffold(body: TimelineScreen(initialCategory: category)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c, store, events);
}

Future<void> _tab(WidgetTester tester, HistoryCategory category) async {
  final tab = find.byKey(ValueKey('history-tab-${category.name}'));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['NoLeanDisplay', 'NoLeanMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'default recovery view excludes settings and visit observations; tabs preserve data/metrics',
    (tester) async {
      final (c, store, events) = await _pump(tester);
      final before = c.events.map((e) => e.toJson()).toList();
      final lastDose = c.lastDose, streak = c.streak, money = c.moneySaved;
      final writes = store.writes;
      final use = events.firstWhere((e) => e.type == RecoveryEventType.relapse);
      final setting = events.firstWhere(
        (e) => e.type == RecoveryEventType.settingsChange,
      );
      expect(find.byKey(ValueKey('history-record-${use.id}')), findsOneWidget);
      expect(find.text('SETTING CHANGED'), findsNothing);
      expect(find.textContaining('ZONE OBSERVED'), findsNothing);
      await _capture(tester, 'recovery');
      await _tab(tester, HistoryCategory.settings);
      expect(
        find.byKey(ValueKey('history-record-${setting.id}')),
        findsOneWidget,
      );
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Not recorded'), findsWidgets);
      await _capture(tester, 'settings');
      await _tab(tester, HistoryCategory.location);
      await _capture(tester, 'locations');
      await _tab(tester, HistoryCategory.recovery);
      expect(c.events.map((e) => e.toJson()).toList(), before);
      expect(c.lastDose, lastDose);
      expect(c.streak, streak);
      expect(c.moneySaved, money);
      expect(store.writes, writes);
    },
  );

  testWidgets(
    'location source filtering separates automatic/manual/context and keeps its selection',
    (tester) async {
      final (_, _, events) = await _pump(
        tester,
        category: HistoryCategory.location,
      );
      final manual = events.firstWhere(
        (e) => e.metadata['source'] == 'manualPin',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('history-record-${manual.id}')),
        findsOneWidget,
      );
      expect(
        find.text('User-selected location; this does not establish presence.'),
        findsOneWidget,
      );
      expect(find.text('LOCATION SAVED // Sample place'), findsOneWidget);
      expect(find.textContaining('ZONE OBSERVED'), findsNothing);
      expect(find.text('Automatic · background'), findsNothing);
      await _tab(tester, HistoryCategory.recovery);
      await _tab(tester, HistoryCategory.location);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Manual'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Unknown'));
      await tester.pumpAndSettle();
      expect(
        find.text('No location records match this source.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shared details cross-link the same record without changing history',
    (tester) async {
      final (c, store, events) = await _pump(tester);
      final use = events.firstWhere((e) => e.type == RecoveryEventType.relapse);
      final writes = store.writes;
      final details = find.byKey(ValueKey('history-details-${use.id}'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('Record details'), findsOneWidget);
      expect(find.text('Happened at'), findsOneWidget);
      expect(find.text('Recorded at'), findsOneWidget);
      expect(find.textContaining('timezone not recorded'), findsOneWidget);
      final link = find.byKey(const ValueKey('history-crosslink-location'));
      await tester.scrollUntilVisible(
        link,
        250,
        scrollable: find
            .descendant(
              of: find.byType(TabListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('Linked record'), findsOneWidget);
      expect(find.byKey(ValueKey('history-record-${use.id}')), findsOneWidget);
      await tester.tap(find.byTooltip('Show all records'));
      await tester.pumpAndSettle();
      expect(find.text('Linked record'), findsNothing);
      expect(find.text('4 records'), findsOneWidget);
      expect(c.events.where((e) => e.id == use.id), hasLength(1));
      expect(store.writes, writes);
    },
  );

  testWidgets('settings and location have useful empty states', (tester) async {
    await _pump(tester, empty: true);
    await _tab(tester, HistoryCategory.settings);
    expect(find.text('No settings changes recorded yet.'), findsOneWidget);
    await _tab(tester, HistoryCategory.location);
    expect(find.textContaining('No location records yet.'), findsOneWidget);
  });

  testWidgets('small screen and large text keep tabs/records reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (_, _, events) = await _pump(tester, scale: 2);
    for (final category in HistoryCategory.values) {
      await _tab(tester, category);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'large-${category.name}');
      final record = projectHistory(events, category).first;
      final details = find.byKey(ValueKey('history-details-${record.id}'));
      await tester.scrollUntilVisible(
        details,
        250,
        scrollable: find
            .descendant(
              of: find.byType(TabListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'large-${category.name}-record');
    }
  });
}
