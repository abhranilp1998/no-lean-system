import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/cravings/presentation/cravings_screen.dart';
import 'package:no_lean/features/cravings/presentation/trigger_tags_sheet.dart';
import 'package:no_lean/features/plans/presentation/if_then_plans_screen.dart';
import 'package:no_lean/features/plans/presentation/plan_card.dart';
import 'package:no_lean/features/progress/domain/recovery_insights.dart';
import 'package:no_lean/features/progress/presentation/widgets/actionable_insights_panel.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/if_then_plan.dart';
import 'package:no_lean/features/recovery/domain/trigger_tags.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_alert_copy.dart';
import 'package:no_lean/features/zones/presentation/zone_alert_screen.dart';

import '../../support/recovery_fakes.dart';

/// Renders the trigger-tag and if-then screens with the Flutter test
/// renderer (no emulator). Does nothing unless NO_LEAN_CAPTURE_DIR is set:
/// `NO_LEAN_CAPTURE_DIR=/workspace/if-then-screens flutter test <this file>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();
  final now = DateTime(2026, 11, 26, 18, 30);

  setUpAll(() async {
    if (dir == null) return;
    for (final family in ['NoLeanDisplay', 'NoLeanMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    const mono = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf';
    if (File(mono).existsSync()) {
      await (FontLoader('monospace')..addFont(
            Future.value(ByteData.sublistView(File(mono).readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function(RecoveryController c) home, {
    Future<void> Function(RecoveryController)? seed,
    Future<void> Function(WidgetTester)? act,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    await seed?.call(c);
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => c)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNoLeanTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: RepaintBoundary(key: key, child: home(c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await act?.call(tester);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir!).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> seedTagged(RecoveryController c) async {
    final tags = [
      for (var i = 0; i < 6; i++)
        const TriggerTags(mood: 'bored', withWho: 'alone', cash: 'plenty'),
      const TriggerTags(mood: 'stressed', withWho: 'friends', cash: 'none'),
      const TriggerTags(mood: 'tired', place: 'Home'),
    ];
    for (var i = 0; i < tags.length; i++) {
      final id = await c.recordCraving(
        CravingEntry(
          intensity: 6,
          trigger: 'Boredom',
          note: '',
          createdAt: DateTime(2026, 11, 20, 12).add(Duration(hours: i)),
        ),
      );
      await c.recordTriggerTags(id, tags[i]);
    }
  }

  Future<void> seedPlans(RecoveryController c) async {
    await c.addIfThenPlan(
      ifText: "I'm bored on the way home",
      thenText: 'walk the long way and call my brother',
      mood: 'bored',
    );
    await c.addIfThenPlan(
      ifText: "I'm at the bus stand",
      thenText: 'cross the road and keep walking for ten minutes',
      surfaces: {PlanSurface.zone, PlanSurface.window},
    );
  }

  Widget sheetOver(Widget sheet) => Scaffold(
    backgroundColor: Colors.black54,
    body: Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: sheet,
      ),
    ),
  );

  testWidgets('capture trigger tags and if-then plans', (tester) async {
    if (dir == null) return;

    await shoot(
      tester,
      '01_craving_tags_sheet',
      (c) => sheetOver(TriggerTagsSheet(cravingId: c.events.last.id)),
      seed: (c) async {
        await c.recordCraving(
          CravingEntry(
            intensity: 7,
            trigger: 'Boredom',
            note: '',
            createdAt: now,
          ),
        );
      },
    );

    await shoot(
      tester,
      '02_craving_tags_two_taps_with_plan',
      (c) => sheetOver(TriggerTagsSheet(cravingId: c.events.last.id)),
      seed: (c) async {
        await seedPlans(c);
        await c.recordCraving(
          CravingEntry(
            intensity: 7,
            trigger: 'Boredom',
            note: '',
            createdAt: now,
          ),
        );
      },
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('tag-mood-bored')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('tag-with-alone')));
        await t.pump();
      },
    );

    await shoot(
      tester,
      '03_cravings_screen_pattern',
      (_) => const CravingsScreen(),
      seed: (c) async {
        await seedTagged(c);
        await seedPlans(c);
      },
    );

    await shoot(
      tester,
      '04_plans_screen',
      (_) => const IfThenPlansScreen(),
      seed: seedPlans,
    );

    await shoot(
      tester,
      '05_plan_editor_from_pattern',
      (_) => sheetOver(
        const IfThenPlanEditor(
          suggestedIf: "I'm bored, alone and with cash on me",
        ),
      ),
    );

    await shoot(
      tester,
      '06_zone_alert_with_plan',
      (c) => ZoneAlertScreen(
        copy: buildZoneAlertCopy(
          zone: DangerZone(
            id: 'z1',
            name: 'Bus stand',
            latitude: 12.9,
            longitude: 77.5,
            radiusMeters: 200,
            createdAt: DateTime(2026, 11, 1),
          ),
          now: now,
          cleanSince: DateTime(2026, 11, 20),
          plans: c.ifThenPlans,
        ),
      ),
      seed: seedPlans,
    );

    await shoot(
      tester,
      '07_home_plan_now_card',
      (_) => Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            Text(
              'RISK WINDOW / 17:00-21:00 / STAY MOVING',
              style: TextStyle(color: red, fontSize: 11),
            ),
            SizedBox(height: 14),
            PlanNowCard(),
            Text('THE COUNTER', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
      seed: seedPlans,
    );

    await shoot(tester, '08_progress_insight', (c) {
      final insights = patternActionInsights(
        cravings: const [],
        sosSessions: const [],
        dailySpend: 0,
        moneySaved: 0,
        events: c.events,
        now: now,
      ).where((i) => i.id == 'trigger-tags').toList();
      return Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ActionableInsightsPanel(insights: insights, onAction: (_) {}),
          ],
        ),
      );
    }, seed: seedTagged);

    await shoot(
      tester,
      '09_tags_sheet_320dp_200pct_text',
      (c) => sheetOver(TriggerTagsSheet(cravingId: c.events.last.id)),
      size: const Size(320, 640),
      textScale: 2,
      seed: (c) async {
        await c.recordCraving(
          CravingEntry(
            intensity: 7,
            trigger: 'Boredom',
            note: '',
            createdAt: now,
          ),
        );
      },
    );
  });
}
