import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/core/utils/formatters.dart';
import 'package:no_lean/features/progress/presentation/widgets/money_saved_card.dart';
import 'package:no_lean/features/recovery/domain/money_saved.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/settings/presentation/money_saved_dialogs.dart';

/// Renders money-saved UI with the Flutter test renderer (no emulator).
/// Writes to /workspace/money-saved-screens, or NO_LEAN_CAPTURE_DIR if set.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir =
      Platform.environment['NO_LEAN_CAPTURE_DIR'] ??
      '/workspace/money-saved-screens';
  final key = GlobalKey();

  setUpAll(() async {
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
    const material =
        '/workspace/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    if (File(material).existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(File(material).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  MoneySavedSnapshot shot({
    double daily = 120,
    Duration clean = const Duration(days: 18),
    SavingsGoal? goal,
    bool subtract = false,
    List<RecoveryEvent> events = const [],
    AppCurrency currency = AppCurrency.inr,
    double? spendPerBottle = 240,
    double? usualDailyMl = 50,
  }) => computeMoneySaved(
    dailySpend: daily,
    bottleMl: 100,
    spendPerBottle: spendPerBottle,
    usualDailyMl: usualDailyMl,
    cleanDuration: clean,
    events: events,
    lastDose: DateTime(2026, 10, 1, 12),
    currency: currency,
    subtractOtherCosts: subtract,
    goal: goal,
  );

  Future<void> shoot(
    WidgetTester tester, {
    required String name,
    required Widget child,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildNoLeanTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF07070C),
          body: SafeArea(
            child: RepaintBoundary(
              key: key,
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('capture money saved screens', (tester) async {
    await shoot(
      tester,
      name: '01_prompt_no_spend_set',
      child: MoneySavedCard(
        snapshot: shot(daily: 0, spendPerBottle: null, usualDailyMl: null),
        onSetSpend: () {},
        onSetGoal: () {},
      ),
    );
    await shoot(
      tester,
      name: '02_home_eighteen_days_warm_copy',
      child: MoneySavedCard(
        snapshot: shot(),
        onSetSpend: () {},
        onSetGoal: () {},
      ),
    );
    await shoot(
      tester,
      name: '03_goal_jar_halfway',
      child: MoneySavedCard(
        snapshot: shot(
          goal: const SavingsGoal(name: 'New phone', target: 4000),
        ),
        onSetSpend: () {},
        onSetGoal: () {},
      ),
    );
    await shoot(
      tester,
      name: '04_goal_jar_complete',
      child: MoneySavedCard(
        snapshot: shot(
          daily: 200,
          clean: const Duration(days: 30),
          spendPerBottle: null,
          usualDailyMl: null,
          goal: const SavingsGoal(name: 'New phone', target: 4000),
        ),
        onSetSpend: () {},
        onSetGoal: () {},
      ),
    );
    final benzo = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: DateTime(2026, 10, 5),
      metadata: {'relapseType': 'benzo', 'cost': 500},
    );
    await shoot(
      tester,
      name: '05_other_costs_subtracted',
      child: MoneySavedCard(
        snapshot: shot(subtract: true, events: [benzo]),
        onSetSpend: () {},
        onSetGoal: () {},
      ),
    );
    await shoot(
      tester,
      name: '06_spend_setup_dialog',
      child: const SpendSetupDialog(
        currency: AppCurrency.inr,
        spendPerBottle: 240,
        usualDailyMl: 50,
        dailySpend: 120,
        bottleMl: 100,
        subtractOtherCosts: false,
      ),
    );
    await shoot(
      tester,
      name: '07_usd_currency_and_goal',
      child: MoneySavedCard(
        snapshot: shot(
          currency: AppCurrency.usd,
          spendPerBottle: 12,
          usualDailyMl: 100,
          daily: 12,
          goal: const SavingsGoal(name: 'Headphones', target: 250),
        ),
        onSetSpend: () {},
        onSetGoal: () {},
      ),
    );
    await shoot(
      tester,
      name: '08_privacy_safe_widget_copy',
      size: const Size(390, 400),
      child: Builder(
        builder: (context) {
          final s = shot(goal: const SavingsGoal(name: 'Trip', target: 4000));
          return Container(
            key: const ValueKey('privacy-copy-card'),
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF12121A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WIDGET (PRIVATE OFF)',
                  style: microStyle.copyWith(color: cyan),
                ),
                const SizedBox(height: 8),
                Text(
                  s.widgetKept,
                  style: displayFont(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Text('NOTIFICATION', style: microStyle.copyWith(color: cyan)),
                const SizedBox(height: 8),
                Text(
                  s.notificationText,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Private widgets send none of this — no amount, no substance words.',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  });
}
