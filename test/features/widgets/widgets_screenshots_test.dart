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
import 'package:no_lean/features/widgets/presentation/widgets_screen.dart';
import 'package:no_lean/features/widgets/services/widget_choice_service.dart';

import '../../support/recovery_fakes.dart';

/// Renders the Widgets page with the Flutter test renderer (no emulator).
/// Does nothing unless NO_LEAN_CAPTURE_DIR is set, e.g.
/// `NO_LEAN_CAPTURE_DIR=/tmp/shots flutter test test/features/widgets/widgets_screenshots_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();

  setUpAll(() async {
    if (dir == null) return;
    for (final family in ['NoLeanDisplay', 'NoLeanMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
    // The previews ask for the platform `monospace`; the test renderer has
    // none, so lend it a real one when the box has it (cosmetic only).
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
    WidgetTester tester, {
    required String name,
    required Size size,
    bool privacy = false,
    double textScale = 1,
    double scrollTo = 0,
    List<PlacedWidget> placed = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 14,
          'widgetPrivacy': privacy,
          'events': [
            {
              'id': 'base',
              'type': 'recoveryStart',
              'timestamp': DateTime.now()
                  .subtract(const Duration(days: 1, hours: 4))
                  .toIso8601String(),
            },
          ],
        }),
      ),
      relapseLock: FakeRelapseLock(),
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
            child: WidgetsScreen(key: ValueKey(name), service: _Fixed(placed)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (placed.isNotEmpty) {
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -6000),
        6000,
      );
      await tester.pumpAndSettle();
    } else if (scrollTo > 0) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, -scrollTo));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir!).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('capture widgets page', (tester) async {
    if (dir == null) return;
    await shoot(
      tester,
      name: '01_widgets_page_top',
      size: const Size(390, 844),
    );
    await shoot(
      tester,
      name: '02_widgets_page_buttons_i_used',
      size: const Size(390, 844),
      scrollTo: 330,
    );
    await shoot(
      tester,
      name: '03_widgets_page_privacy',
      size: const Size(390, 844),
      privacy: true,
    );
    await shoot(
      tester,
      name: '04_widgets_page_320dp_text_200pct',
      size: const Size(320, 700),
      textScale: 2,
      scrollTo: 300,
    );
    await shoot(
      tester,
      name: '06_widgets_page_choices_200pct',
      size: const Size(390, 844),
      textScale: 2,
      scrollTo: 2600,
    );
    await shoot(
      tester,
      name: '05_widgets_page_placed_list',
      size: const Size(390, 844),
      placed: const [
        PlacedWidget(id: 3, kind: 'small'),
        PlacedWidget(id: 4, kind: 'medium'),
        PlacedWidget(id: 5, kind: 'full'),
        PlacedWidget(id: 6, kind: 'garden'),
      ],
    );
  });
}

class _Fixed extends WidgetChoiceService {
  _Fixed(this.items) : super(enabled: false);
  final List<PlacedWidget> items;
  @override
  Future<List<PlacedWidget>> placed() async => items;
}
