import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

/// Renders the Craving-peak heads-up setting with the Flutter test renderer.
/// Writes PNGs when NO_LEAN_CAPTURE_DIR is set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
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

  RecoveryEvent craving(DateTime at) => RecoveryEvent.create(
    type: RecoveryEventType.craving,
    timestamp: at,
    metadata: const {'intensity': 6, 'trigger': 'evening'},
  );

  String storeJson({RiskWindow? window, bool withPeak = false}) => jsonEncode({
    'stateVersion': 18,
    'events': [
      if (withPeak)
        for (var i = 0; i < 5; i++)
          craving(DateTime(2026, 11, 20 + i, 19, 10)).toJson()
      else
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: DateTime(2026, 9, 1),
        ).toJson(),
    ],
    if (window != null) 'riskWindow': window.toJson(),
    'zones': [],
  });

  Future<ProviderContainer> pump({
    required WidgetTester tester,
    required Size size,
    String? stored,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(stored),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 26, 12),
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
          debugShowCheckedModeBanner: false,
          theme: buildNoLeanTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: const Scaffold(body: SettingsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> showToggle(WidgetTester tester) async {
    final toggle = find.byKey(const ValueKey('settings-craving-peak'));
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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

  testWidgets('craving-peak toggle defaults on and can be turned off', (
    tester,
  ) async {
    final container = await pump(tester: tester, size: const Size(390, 844));
    await showToggle(tester);
    expect(container.read(recoveryProvider).cravingPeakHeadsUp, isTrue);
    expect(
      find.textContaining('needs 5 cravings or slips across 3 days'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings-craving-peak')));
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).cravingPeakHeadsUp, isFalse);
    expect(find.text('Off'), findsWidgets);
  });

  testWidgets('capture craving-peak setting states', (tester) async {
    if (dir == null) return;
    const phone = Size(390, 844);
    const morning = RiskWindow(startMinutes: 8 * 60, endMinutes: 11 * 60);

    await pump(tester: tester, size: phone);
    await showToggle(tester);
    await shoot(tester, '01_on_waiting_for_data');

    await tester.tap(find.byKey(const ValueKey('settings-craving-peak')));
    await tester.pumpAndSettle();
    await shoot(tester, '02_off');

    await pump(
      tester: tester,
      size: phone,
      stored: storeJson(window: morning, withPeak: true),
    );
    await showToggle(tester);
    await shoot(tester, '03_on_with_7pm_plan');

    await pump(tester: tester, size: phone, stored: storeJson(withPeak: true));
    await showToggle(tester);
    await shoot(tester, '04_on_skipped_inside_risk_window');

    await pump(
      tester: tester,
      size: const Size(320, 700),
      textScale: 2,
      stored: storeJson(window: morning, withPeak: true),
    );
    await showToggle(tester);
    await shoot(tester, '05_on_with_plan_320dp_200pct');
  });
}
