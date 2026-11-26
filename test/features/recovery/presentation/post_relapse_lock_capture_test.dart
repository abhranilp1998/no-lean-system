import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/app_lock_session.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/presentation/app_lock_screen.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

/// Renders the post-relapse lock screen with the Flutter test renderer (no
/// emulator). Does nothing unless NO_LEAN_CAPTURE_DIR is set:
/// `NO_LEAN_CAPTURE_DIR=/workspace/relapse-lock-screens flutter test <file>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final prefix = Platform.environment['NO_LEAN_CAPTURE_PREFIX'] ?? '';
  final key = GlobalKey();
  final today = DateTime.now();
  final now = DateTime(today.year, today.month, today.day - 1, 21, 30);

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
    String name, {
    required int cleanDays,
    List<RelapseType> types = const [RelapseType.fullLean],
    Size size = const Size(390, 844),
    double textScale = 1,
    double scrollTo = 0,
    bool highContrast = false,
    bool reduceMotion = false,
    TrustedContact? contact,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': RecoveryController.stateVersion,
          'events': [
            RecoveryEvent.create(
              type: RecoveryEventType.recoveryStart,
              timestamp: now.subtract(Duration(days: cleanDays, hours: 1)),
            ).toJson(),
          ],
        }),
      ),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    await c.recordRelapse(
      tryBiometrics: false,
      entries: [
        for (final t in types)
          RelapseLogEntry(
            occurredAt: now.subtract(const Duration(minutes: 3)),
            type: t,
            note: 'Rough evening, gave in.',
            attemptedSos: false,
          ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => c),
        trustedContactProvider.overrideWith((ref) async => contact),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNoLeanTheme(
            highContrast: highContrast,
            reduceMotion: reduceMotion,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SafeArea(
                child: AppLockScreen(
                  reason: AppLockReason.relapseLogged,
                  onUnlocked: () {},
                  onOpenSos: () {},
                  onLogCraving: () {},
                  now: () => now,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    if (scrollTo > 0) {
      await tester.drag(
        find.byKey(const ValueKey('app-lock-screen')),
        Offset(0, -scrollTo),
      );
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir!).create(recursive: true);
      await File(
        '$dir/$prefix$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    // Let the controller's zero-duration timers drain before the next shot.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  const riya = TrustedContact(name: 'Riya', phone: '+919800000000');

  testWidgets('capture post-relapse lock screens', (tester) async {
    if (dir == null) return;
    await shoot(tester, '01_after_81_days_top', cleanDays: 81, contact: riya);
    await shoot(
      tester,
      '02_after_81_days_scrolled',
      cleanDays: 81,
      contact: riya,
      scrollTo: 700,
    );
    await shoot(
      tester,
      '03_after_81_days_bottom',
      cleanDays: 81,
      contact: riya,
      scrollTo: 4000,
    );
    await shoot(
      tester,
      '04_mixed_lean_and_benzo_top',
      cleanDays: 81,
      types: [RelapseType.fullLean, RelapseType.benzo],
      contact: riya,
    );
    await shoot(
      tester,
      '05_mixed_lean_and_benzo_mixing_card',
      cleanDays: 81,
      types: [RelapseType.fullLean, RelapseType.benzo],
      contact: riya,
      scrollTo: 520,
    );
    await shoot(
      tester,
      '06_small_screen_large_text_high_contrast',
      cleanDays: 12,
      size: const Size(320, 568),
      textScale: 1.4,
      highContrast: true,
      reduceMotion: true,
    );
    await shoot(tester, '07_day_one_no_streak', cleanDays: 0);
    await shoot(
      tester,
      '08_benzo_only_streak_intact',
      cleanDays: 81,
      types: [RelapseType.benzo],
      contact: riya,
    );
  });
}
