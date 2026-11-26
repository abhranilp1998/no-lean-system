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
import 'package:no_lean/features/recovery/domain/mixing_alert.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/slip_review.dart';
import 'package:no_lean/features/recovery/presentation/mixing_alert_screen.dart';
import 'package:no_lean/features/recovery/presentation/slip_review_sheet.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';

import '../../../support/recovery_fakes.dart';

/// Renders the mixing card and the slip review with the Flutter test
/// renderer (no emulator). Does nothing unless NO_LEAN_CAPTURE_DIR is set:
/// `NO_LEAN_CAPTURE_DIR=/workspace/mixing-screens flutter test <this file>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final key = GlobalKey();
  final now = DateTime(2026, 11, 26, 22, 30);

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
    double scrollTo = 0,
    Future<void> Function(WidgetTester)? act,
    TrustedContact? contact,
    Future<void> Function(RecoveryController)? seed,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    await seed?.call(c);
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
          theme: buildNoLeanTheme(),
          home: RepaintBoundary(key: key, child: home(c)),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(recoveryPositionAsset),
        tester.element(find.byType(Scaffold).first),
      );
    });
    await tester.pumpAndSettle();
    if (scrollTo > 0) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, -scrollTo));
      await tester.pumpAndSettle();
    }
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

  final alert = MixingAlert(
    substances: const ['codeine', 'alprazolam'],
    eventIds: const {'a', 'b'},
    latest: now,
    today: true,
  );
  const riya = TrustedContact(name: 'Riya', phone: '+919800000000');

  testWidgets('capture mixing card and slip review', (tester) async {
    if (dir == null) return;
    await shoot(
      tester,
      '01_mixing_card_top',
      (_) => MixingAlertScreen(alert: alert, contact: riya),
      contact: riya,
    );
    await shoot(
      tester,
      '02_mixing_card_recovery_position',
      (_) => MixingAlertScreen(alert: alert, contact: riya),
      scrollTo: 600,
      contact: riya,
    );
    await shoot(
      tester,
      '03_mixing_card_no_contact',
      (_) => MixingAlertScreen(alert: alert),
    );

    RelapseLogEntry slip(DateTime at) => RelapseLogEntry(
      occurredAt: at,
      type: RelapseType.fullLean,
      note: 'Rough evening, gave in.',
      attemptedSos: false,
    );
    Future<void> seedSlips(RecoveryController c) async {
      await c.recordRelapse(
        entries: [slip(DateTime(2026, 11, 20, 19))],
        tryBiometrics: false,
      );
      await c.recordSlipReview(
        c.takeSlipReview()!.eventIds,
        const SlipReview(place: "Friend's place", withWho: 'friends'),
      );
      await c.recordRelapse(
        entries: [slip(DateTime(2026, 11, 26, 21))],
        tryBiometrics: false,
      );
    }

    Widget sheet(RecoveryController c) => Scaffold(
      backgroundColor: Colors.black54,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SlipReviewSheet(request: c.takeSlipReview()!, now: now),
        ),
      ),
    );

    await shoot(tester, '04_slip_review_empty', sheet, seed: seedSlips);
    await shoot(
      tester,
      '05_slip_review_zone_offer',
      sheet,
      seed: seedSlips,
      act: (t) async {
        await t.tap(find.byKey(const ValueKey("review-place-Friend's place")));
        await t.tap(find.byKey(const ValueKey('review-with-friends')));
        await t.tap(find.byKey(const ValueKey('review-trigger-Boredom')));
        await t.pumpAndSettle();
      },
    );
  });
}
