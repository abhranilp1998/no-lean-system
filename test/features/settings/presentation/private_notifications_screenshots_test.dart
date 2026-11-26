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
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:no_lean/features/widgets/presentation/widgets_screen.dart';
import 'package:no_lean/features/widgets/services/widget_choice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

/// Renders the Private notifications setting (Settings and the Widgets page)
/// with the Flutter test renderer. Writes PNGs when NO_LEAN_CAPTURE_DIR is set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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

  Future<ProviderContainer> pump({
    required WidgetTester tester,
    required Size size,
    required Widget home,
    bool hideSensitive = false,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryRecoveryStore();
    final c = RecoveryController(store: store, relapseLock: FakeRelapseLock());
    await c.load();
    if (hideSensitive) await c.setHideSensitiveNotifications(true);
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
          home: RepaintBoundary(key: key, child: home),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (dir == null) return;
    // Overflow at large text scales is noted, not failed: the shot still ships.
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

  testWidgets('capture private notification settings', (tester) async {
    if (dir == null) return;
    const phone = Size(390, 844);

    await pump(
      tester: tester,
      size: phone,
      home: const Scaffold(body: SettingsScreen()),
    );
    final toggle = find.byKey(const ValueKey('settings-hide-sensitive'));
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shoot(tester, '01_settings_privacy_off');

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await shoot(tester, '02_settings_privacy_on');

    await pump(
      tester: tester,
      size: phone,
      home: WidgetsScreen(service: WidgetChoiceService(enabled: false)),
    );
    await shoot(tester, '03_widgets_page_both_toggles_off');

    await pump(
      tester: tester,
      size: phone,
      home: WidgetsScreen(service: WidgetChoiceService(enabled: false)),
      hideSensitive: true,
    );
    await shoot(tester, '04_widgets_page_notifications_on');

    await pump(
      tester: tester,
      size: const Size(320, 700),
      textScale: 2,
      home: const Scaffold(body: SettingsScreen()),
      hideSensitive: true,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-hide-sensitive')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shoot(tester, '05_settings_privacy_on_320dp_200pct');
  });
}
