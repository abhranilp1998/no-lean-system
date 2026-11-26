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
import 'package:no_lean/features/recovery/domain/daily_check_in.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/presentation/check_in_slip_details.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

/// Renders the daily check-in setting, a drawing of the notification (an
/// approximation of the Android shade, built from the real strings) and the
/// details prompt with the Flutter test renderer. Writes PNGs when
/// NO_LEAN_CAPTURE_DIR is set.
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

  Future<RecoveryController> controller({
    Map<String, Object?> extra = const {},
  }) async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 17,
          'events': [
            RecoveryEvent.create(
              type: RecoveryEventType.recoveryStart,
              timestamp: DateTime.now().subtract(const Duration(days: 9)),
            ).toJson(),
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

  Future<ProviderContainer> pump({
    required WidgetTester tester,
    required Size size,
    required RecoveryController c,
    required Widget home,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          builder: (context, child) => RepaintBoundary(
            key: key,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
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

  Future<void> showToggle(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-daily-check-in')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// A drawing of the shade card built from the real channel, title, body and
  /// button strings; not a screenshot of Android.
  Widget shadeCard({required bool hide, required String caption}) {
    final copy = dailyCheckInCopy(hideSensitive: hide);
    final channel = hide
        ? dailyCheckInChannel.privateName
        : dailyCheckInChannel.publicName;
    return Scaffold(
      backgroundColor: const Color(0xFF14161B),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              caption,
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
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 10, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        channel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        '20:00',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copy.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy.body,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final label in [
                        copy.okayLabel,
                        copy.strugglingLabel,
                        copy.usedLabel,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Color(0xFF7DD3FC),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('capture daily check-in screens', (tester) async {
    if (dir == null) return;
    const phone = Size(390, 844);

    var c = await controller();
    await pump(
      tester: tester,
      size: phone,
      c: c,
      home: const Scaffold(body: SettingsScreen()),
    );
    await showToggle(tester);
    await shoot(tester, '01_settings_off_default');

    await tester.tap(find.byKey(const ValueKey('settings-daily-check-in')));
    await tester.pumpAndSettle();
    await shoot(tester, '02_settings_on_20_00');

    c = await controller(
      extra: {
        'dailyCheckIn': true,
        'dailyCheckInMinutes': 23 * 60,
        'quietHoursEnabled': true,
        'quietHours': {'startMinutes': 22 * 60, 'endMinutes': 7 * 60},
      },
    );
    await pump(
      tester: tester,
      size: phone,
      c: c,
      home: const Scaffold(body: SettingsScreen()),
    );
    await showToggle(tester);
    await shoot(tester, '03_settings_time_inside_quiet_hours');

    await pump(
      tester: tester,
      size: phone,
      c: c,
      home: shadeCard(
        hide: false,
        caption: 'Notification, normal wording (drawing, not Android)',
      ),
    );
    await shoot(tester, '04_notification_normal');

    await pump(
      tester: tester,
      size: phone,
      c: c,
      home: shadeCard(
        hide: true,
        caption: 'Notification, private notifications on (drawing)',
      ),
    );
    await shoot(tester, '05_notification_private');

    c = await controller();
    await c.recordCheckInUsed(
      at: DateTime.now().subtract(const Duration(hours: 1, minutes: 12)),
    );
    final slip = c.slipsNeedingDetails.single;
    late BuildContext context;
    await pump(
      tester: tester,
      size: phone,
      c: c,
      home: Scaffold(
        body: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );
    showSlipDetailsPrompt(context, slip);
    await tester.pumpAndSettle();
    await shoot(tester, '06_details_prompt');
    await tester.tap(find.byKey(const ValueKey('slip-type-benzo')));
    await tester.pumpAndSettle();
    await shoot(tester, '07_details_prompt_benzo_selected');
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    await pump(
      tester: tester,
      size: const Size(320, 700),
      textScale: 2,
      c: c,
      home: Scaffold(
        body: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );
    showSlipDetailsPrompt(context, slip);
    await tester.pumpAndSettle();
    await shoot(tester, '08_details_prompt_320dp_200pct');
  });
}
