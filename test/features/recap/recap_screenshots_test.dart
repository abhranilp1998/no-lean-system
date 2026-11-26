import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recap/domain/weekly_recap.dart';
import 'package:no_lean/features/recap/domain/weekly_recap_schedule.dart';
import 'package:no_lean/features/recap/presentation/weekly_recap_card.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/report/presentation/doctor_report_screen.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recap_events.dart';
import '../../support/recovery_fakes.dart';
import '../report/doctor_report_test.dart' show testFonts;

/// Renders the recap card, the Settings toggle, a drawing of the weekly
/// notification and the doctor report screen with the Flutter test renderer.
/// Writes PNGs only when NO_LEAN_CAPTURE_DIR is set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();
  final now = DateTime(2026, 11, 27, 20);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => <String, Object>{
            'appName': 'NO LEAN',
            'packageName': 'com.nolean.no_lean',
            'version': '1.0.0',
            'buildNumber': '1',
          },
        );
    if (dir == null) return;
    for (final family in ['NoLeanDisplay', 'NoLeanMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const mono = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf';
    if (File(mono).existsSync()) {
      await (FontLoader('monospace')..addFont(
            Future.value(ByteData.sublistView(File(mono).readAsBytesSync())),
          ))
          .load();
    }
  });

  Future<RecoveryController> controller({
    Map<String, Object?> extra = const {},
  }) async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 17,
          'lastDose': DateTime(2026, 11, 20, 22).toIso8601String(),
          'events': [
            startAt(DateTime(2026, 9, 1)).toJson(),
            relapseAt(DateTime(2026, 11, 20, 22)).toJson(),
          ],
          'zones': [],
          ...extra,
        }),
      ),
      relapseLock: FakeRelapseLock(),
    );
    await c.load();
    return c;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    RecoveryController? c,
    Size size = const Size(400, 760),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controllerOrDefault = c ?? await controller();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryProvider.overrideWith((ref) => controllerOrDefault),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNoLeanTheme(),
          builder: (context, child) => RepaintBoundary(key: key, child: child!),
          home: home,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (dir == null) return;
    tester.takeException();
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

  Widget cardPage(WeeklyRecap recap) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('PROGRESS', style: eyebrowStyle.copyWith(color: purple)),
        const SizedBox(height: 12),
        WeeklyRecapCard(recap: recap, onDoctorReport: () {}),
      ],
    ),
  );

  testWidgets('01 a strong week', (tester) async {
    final recap = computeWeeklyRecap(
      events: [
        startAt(DateTime(2026, 10, 1)),
        cravingAt(DateTime(2026, 11, 22, 21, 10)),
        cravingAt(DateTime(2026, 11, 24, 22), intensity: 8),
        cravingAt(DateTime(2026, 11, 25, 20, 30), intensity: 4),
        recheckAt(DateTime(2026, 11, 22, 21, 30), 'gone'),
        sosDoneAt(DateTime(2026, 11, 25, 20, 40)),
      ],
      lastDose: DateTime(2026, 10, 1),
      now: now,
      dailySpend: 300,
      formatMoney: (v) => '₹${v.round()}',
    );
    await pump(tester, cardPage(recap));
    await shoot(tester, '01_recap_clean_week');
    expect(find.byKey(const ValueKey('weekly-recap-card')), findsOneWidget);
  });

  testWidgets('02 a hard week with a slip and benzo-only use', (tester) async {
    final events = [
      startAt(DateTime(2026, 10, 1)),
      relapseAt(DateTime(2026, 11, 24, 23)),
      relapseAt(DateTime(2026, 11, 25, 22), type: 'benzo'),
      cravingAt(DateTime(2026, 11, 23, 21)),
      cravingAt(DateTime(2026, 11, 24, 21, 40), intensity: 9),
      cravingAt(DateTime(2026, 11, 26, 20, 20), intensity: 7),
    ];
    final recap = computeWeeklyRecap(
      events: events,
      lastDose: DateTime(2026, 11, 24, 23),
      now: now,
    );
    await pump(tester, cardPage(recap));
    await shoot(tester, '02_recap_slip_and_benzo_only');
    expect(find.text('BENZO ONLY'), findsOneWidget);
  });

  testWidgets('03 benzo several times points to the doctor', (tester) async {
    final recap = computeWeeklyRecap(
      events: [
        startAt(DateTime(2026, 10, 1)),
        for (var d = 22; d < 26; d++)
          relapseAt(DateTime(2026, 11, d, 22), type: 'benzo'),
      ],
      lastDose: DateTime(2026, 10, 1),
      now: now,
    );
    await pump(tester, cardPage(recap));
    await shoot(tester, '03_recap_benzo_doctor_nudge');
    expect(find.textContaining('doctor or your SOS contact'), findsOneWidget);
  });

  testWidgets('04 settings toggle and doctor summary entry', (tester) async {
    final c = await controller(extra: {'weeklyRecapNotify': true});
    await pump(
      tester,
      const Scaffold(body: SettingsScreen()),
      c: c,
      size: const Size(400, 900),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-doctor-report')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, '04_settings_doctor_summary_entry');
    expect(find.text('Doctor summary (PDF)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-weekly-recap')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await shoot(tester, '05_settings_weekly_recap_toggle');
    expect(find.text('Weekly recap'), findsOneWidget);
  });

  Widget shade({required bool hide}) {
    final text = NotificationPrefs(
      hideSensitive: hide,
    ).textFor(weeklyRecapNotificationTitle, weeklyRecapNotificationBody);
    return Scaffold(
      backgroundColor: const Color(0xFF14161B),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hide
                  ? 'Private notifications ON, Sunday 6:00 PM'
                  : 'Private notifications OFF, Sunday 6:00 PM',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2D35),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text.body,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A drawing from the real strings, not a screenshot of Android.',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('06 notification text, normal and private', (tester) async {
    await pump(tester, shade(hide: false), size: const Size(400, 240));
    await shoot(tester, '06_notification_normal');
    await pump(tester, shade(hide: true), size: const Size(400, 240));
    await shoot(tester, '07_notification_private');
    expect(find.text('Reminder'), findsOneWidget);
  });

  testWidgets('08 doctor report screen', (tester) async {
    await pump(
      tester,
      DoctorReportScreen(loadFonts: () async => testFonts(), now: now),
      size: const Size(400, 1250),
    );
    await shoot(tester, '08_doctor_report_screen');
    expect(find.byKey(const ValueKey('report-privacy-note')), findsOneWidget);
  });
}
