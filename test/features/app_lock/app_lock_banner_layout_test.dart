import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/app_lock/application/app_lock_providers.dart';
import 'package:no_lean/features/app_lock/presentation/app_lock_banner.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

final _captureKey = GlobalKey();

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['NoLeanDisplay', 'NoLeanMono']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'combined warnings scroll at 200 percent while retry fix and SOS stay reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryRecoveryStore();
      final recovery = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
      );
      await recovery.load();
      final container = ProviderContainer(
        overrides: [recoveryProvider.overrideWith((ref) => recovery)],
      );
      addTearDown(container.dispose);
      container.read(appLockStatusProvider.notifier).state =
          const AppLockStatus(supported: true);
      container.read(appLockSyncFailureProvider.notifier).state =
          AppLockSyncFailure.activation;
      final writes = store.writes;
      var fixes = 0;
      var sosOpens = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildNoLeanTheme(reduceMotion: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: _captureKey,
              child: Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      AppLockHealthBanner(onFix: () => fixes++),
                      Expanded(
                        child: SizedBox.expand(
                          key: const ValueKey('app-lock-layout-body'),
                          child: Center(
                            child: TextButton(
                              onPressed: () => sosOpens++,
                              child: const Text('SOS'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: const SizedBox(height: 80),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final warning in [
        'APP LOCK NOT READY',
        'APP LOCK PAUSED',
        'APP LOCK LIMITED',
        'APP LOCK STOPPED',
      ]) {
        expect(find.textContaining(warning), findsOneWidget);
      }
      final body = find.byKey(const ValueKey('app-lock-layout-body'));
      expect(tester.getSize(body).height, greaterThan(200));
      final retry = find.byKey(const ValueKey('app-lock-health-retry'));
      final fix = find.byKey(const ValueKey('app-lock-health-fix'));
      expect(retry.hitTestable(), findsOneWidget);
      expect(fix.hitTestable(), findsOneWidget);
      await tester.tap(retry);
      await tester.tap(fix);
      expect(container.read(appLockRetryProvider), 1);
      expect(fixes, 1);
      final sos = find.widgetWithText(TextButton, 'SOS');
      expect(sos.hitTestable(), findsOneWidget);
      await tester.tap(sos);
      expect(sosOpens, 1);
      await tester.pumpAndSettle();
      await _capture(tester, 'app-lock-banner-large-top');

      final messages = find.byKey(const ValueKey('app-lock-health-messages'));
      expect(tester.getSize(messages).height, lessThanOrEqualTo(160));
      final lastWarning = find.textContaining('APP LOCK STOPPED');
      await tester.ensureVisible(lastWarning);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(messages);
      expect(
        tester.getRect(lastWarning).top,
        greaterThanOrEqualTo(viewport.top - 1),
      );
      expect(tester.getRect(lastWarning).top, lessThan(viewport.bottom));
      await tester.drag(messages, const Offset(0, -1000));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: messages,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, position.maxScrollExtent);
      expect(
        tester.getRect(lastWarning).bottom,
        lessThanOrEqualTo(viewport.bottom + 1),
      );
      expect(retry.hitTestable(), findsOneWidget);
      expect(fix.hitTestable(), findsOneWidget);
      expect(sos.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(store.writes, writes);
      await _capture(tester, 'app-lock-banner-large-bottom');
    },
  );
}
