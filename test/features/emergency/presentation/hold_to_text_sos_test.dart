import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/core/widgets/action_tile.dart';
import 'package:no_lean/core/widgets/glow_button.dart';
import 'package:no_lean/core/widgets/hold_to_act.dart';
import 'package:no_lean/features/companion/presentation/companion_common.dart';
import 'package:no_lean/features/emergency/domain/sos_text.dart';
import 'package:no_lean/features/emergency/presentation/emergency_screen.dart';
import 'package:no_lean/features/emergency/presentation/hold_to_text_sos.dart';
import 'package:no_lean/features/settings/services/trusted_contact_service.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_location.dart';

void main() {
  final now = DateTime(2026, 11, 26, 22, 30);
  final here = LocationFix(
    latitude: 12.9716,
    longitude: 77.5946,
    accuracyMeters: 10,
    at: now,
  );
  const riya = TrustedContact(name: 'Riya', phone: '+919800000000');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<List<Uri>> pumpHold(
    WidgetTester tester, {
    required Widget child,
    FakeLocationService? location,
    TrustedContact? contact = riya,
  }) async {
    final launched = <Uri>[];
    final loc =
        location ??
        FakeLocationService(current: LocationAccess.whileInUse, fix: here);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(loc),
          trustedContactProvider.overrideWith((ref) async => contact),
        ],
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: HoldToTextSos(
              now: now,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
              resolveFix: () async => loc.fix ?? loc.lastKnown,
              onTap: () {},
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return launched;
  }

  testWidgets('a short tap does not open the composer', (tester) async {
    var taps = 0;
    final launched = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            FakeLocationService(fix: here),
          ),
          trustedContactProvider.overrideWith((ref) async => riya),
        ],
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: HoldToTextSos(
              now: now,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
              onTap: () => taps++,
              child: const SizedBox(
                key: ValueKey('sos'),
                width: 200,
                height: 56,
                child: Text('SOS'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('hold-to-act')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(launched, isEmpty);
  });

  testWidgets(
    'holding ~2 s shows a progress ring then opens sms: to the contact',
    (tester) async {
      final launched = await pumpHold(
        tester,
        child: const SizedBox(
          key: ValueKey('sos'),
          width: 240,
          height: 56,
          child: Text('SOS'),
        ),
      );
      expect(find.byKey(const ValueKey('hold-to-act')), findsOneWidget);
      final gesture = await tester.press(
        find.byKey(const ValueKey('hold-to-act')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      final progress = tester
          .state<HoldToActState>(find.byType(HoldToAct))
          .progress;
      expect(progress, greaterThan(0.2), reason: 'progress=$progress');
      expect(
        find.byKey(const ValueKey('hold-to-act-progress')),
        findsOneWidget,
      );
      expect(launched, isEmpty);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(launched, hasLength(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(launched.single.scheme, 'sms');
      expect(launched.single.path, '+919800000000');
      expect(
        launched.single.queryParameters['body'],
        contains('12.97160,77.59460'),
      );
    },
  );

  testWidgets('releasing mid-hold is a tap, not a send', (tester) async {
    var taps = 0;
    final launched = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(
            FakeLocationService(fix: here),
          ),
          trustedContactProvider.overrideWith((ref) async => riya),
        ],
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: HoldToTextSos(
              now: now,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
              onTap: () => taps++,
              child: const SizedBox(
                key: ValueKey('sos'),
                width: 200,
                height: 56,
                child: Text('SOS'),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('hold-to-act'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(launched, isEmpty);
    expect(find.byKey(const ValueKey('hold-to-act-progress')), findsNothing);
  });

  testWidgets('GlowButton hold opens text; short press keeps onTap', (
    tester,
  ) async {
    var taps = 0;
    final launched = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: GlowButton(
            key: const ValueKey('app-lock-sos'),
            label: 'OPEN SOS',
            icon: Icons.emergency_outlined,
            color: Colors.red,
            onTap: () => taps++,
            onHold: () => launched.add(Uri(scheme: 'sms', path: '+1')),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('app-lock-sos')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(launched, isEmpty);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('app-lock-sos'))),
    );
    await tester.pump();
    await tester.pump(sosHoldDuration + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(taps, 1);
  });

  testWidgets('ActionTile hold vs tap', (tester) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: ActionTile(
            icon: Icons.sos,
            title: 'SOS MODE',
            subtitle: 'Tap to open · hold to text',
            color: Colors.red,
            onTap: () => taps++,
            onHold: () => holds++,
          ),
        ),
      ),
    );
    expect(find.text('Tap to open · hold to text'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hold-to-act')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(holds, 0);
    final gesture = await tester.press(
      find.byKey(const ValueKey('hold-to-act')),
    );
    await tester.pump();
    await tester.pump(sosHoldDuration + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(holds, 1);
    expect(taps, 1);
  });

  testWidgets(
    'a short tap on a dashboard-style tile still opens the SOS screen',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildNoLeanTheme(),
            home: Scaffold(
              body: ActionTile(
                icon: Icons.sos,
                title: 'SOS MODE',
                subtitle: 'Tap to open · hold to text',
                color: Colors.red,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      // Without onHold, a tap is just a tap — no ring appears.
      await tester.tap(find.text('SOS MODE'));
      await tester.pump();
      expect(find.byKey(const ValueKey('hold-to-act-progress')), findsNothing);
      expect(find.byType(EmergencyScreen), findsNothing);
    },
  );
}
