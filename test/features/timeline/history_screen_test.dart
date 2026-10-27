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

class _HistoryRoutes extends NavigatorObserver {
  int depth = 0;
  int maximumDepth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth++;
    if (depth > maximumDepth) maximumDepth = depth;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => depth--;
}

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
  bool standalone = false,
  NavigatorObserver? observer,
  String manualSource = 'manualPin',
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
        (manualSource, 1),
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
        navigatorObservers: [?observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: _captureKey,
          child: Scaffold(
            body: standalone
                ? Builder(
                    builder: (context) => TextButton(
                      key: const ValueKey('open-history'),
                      onPressed: () =>
                          TimelineScreen.openPage(context, category: category),
                      child: const Text('Open history'),
                    ),
                  )
                : TimelineScreen(initialCategory: category),
          ),
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

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find
        .descendant(
          of: find.byType(TabListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(target);
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

  testWidgets(
    'repeated history links switch tabs in place and Back returns to the entry page once',
    (tester) async {
      final routes = _HistoryRoutes();
      final (c, store, events) = await _pump(
        tester,
        standalone: true,
        observer: routes,
      );
      final before = c.events.map((event) => event.toJson()).toList();
      final writes = store.writes;
      final use = events.firstWhere(
        (event) => event.type == RecoveryEventType.relapse,
      );
      expect(routes.depth, 1);
      await tester.tap(find.byKey(const ValueKey('open-history')));
      await tester.pumpAndSettle();
      expect(routes.depth, 2);

      // A direct link must reveal its record even if that tab previously had
      // an incompatible source filter, without pushing another History page.
      await _tab(tester, HistoryCategory.location);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Unknown'));
      await tester.pumpAndSettle();
      await _tab(tester, HistoryCategory.recovery);
      final direct = find.byKey(ValueKey('history-location-link-${use.id}'));
      await _reveal(tester, direct);
      await tester.tap(direct);
      await tester.pumpAndSettle();
      expect(routes.depth, 2);
      expect(routes.maximumDepth, 2);
      expect(find.byKey(ValueKey('history-record-${use.id}')), findsOneWidget);
      expect(find.text('No location records match this source.'), findsNothing);

      for (final destination in [
        HistoryCategory.recovery,
        HistoryCategory.location,
        HistoryCategory.recovery,
        HistoryCategory.location,
      ]) {
        final details = find.byKey(ValueKey('history-details-${use.id}'));
        await _reveal(tester, details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(routes.depth, 3);
        final link = find.byKey(
          ValueKey('history-crosslink-${destination.name}'),
        );
        await _reveal(tester, link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(routes.depth, 2);
        expect(routes.maximumDepth, 3);
        expect(find.text('Record details'), findsNothing);
        expect(
          find.byType(TimelineScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          DefaultTabController.of(tester.element(find.byType(TabBar))).index,
          destination.index,
        );
      }

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(routes.depth, 1);
      expect(find.byKey(const ValueKey('open-history')), findsOneWidget);
      expect(c.events.map((event) => event.toJson()).toList(), before);
      expect(store.writes, writes);
    },
  );

  for (final source in ['manual', 'manualGps', 'manualPin']) {
    testWidgets('manual source $source has the same saved-location copy', (
      tester,
    ) async {
      final (c, store, events) = await _pump(
        tester,
        category: HistoryCategory.location,
        manualSource: source,
      );
      final event = events.firstWhere(
        (event) => event.metadata['source'] == source,
      );
      final before = event.toJson();
      final writes = store.writes;
      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();
      expect(find.text('LOCATION SAVED // Sample place'), findsOneWidget);
      expect(find.text('Manual · recorded source'), findsOneWidget);
      expect(
        find.text('User-selected location; this does not establish presence.'),
        findsOneWidget,
      );
      expect(find.textContaining('ZONE OBSERVED'), findsNothing);
      expect(
        c.events.firstWhere((item) => item.id == event.id).toJson(),
        before,
      );
      expect(event.metadata.containsKey('latitude'), isFalse);
      expect(store.writes, writes);
    });
  }

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
