import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/core/widgets/action_tile.dart';
import 'package:no_lean/core/widgets/glow_button.dart';
import 'package:no_lean/features/emergency/domain/sos_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders hold-to-text SOS frames with the Flutter test renderer.
/// `NO_LEAN_CAPTURE_DIR=/workspace/sos-text-screens flutter test <this file>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['NO_LEAN_CAPTURE_DIR'];
  final bound = GlobalKey();

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

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(bound),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir!).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Widget shell({required Widget child}) => ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNoLeanTheme(),
      home: RepaintBoundary(
        key: bound,
        child: Scaffold(
          backgroundColor: const Color(0xFF0B0D12),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 72, 20, 24),
            child: child,
          ),
        ),
      ),
    ),
  );

  testWidgets('capture hold-to-text frames', (tester) async {
    if (dir == null) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    const caption = TextStyle(
      color: Color(0xFF8B93A7),
      fontSize: 11,
      letterSpacing: 1.2,
      fontFamily: 'NoLeanMono',
    );

    await tester.pumpWidget(
      shell(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FAST INTERRUPTS', style: caption),
            SizedBox(height: 12),
            _IdleSos(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, '01_dashboard_sos_idle');

    // Rebuild with a holdable tile + lock-screen button, then hold mid-way.
    await tester.pumpWidget(
      shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FAST INTERRUPTS', style: caption),
            const SizedBox(height: 12),
            ActionTile(
              icon: Icons.sos,
              title: 'SOS MODE',
              subtitle: 'Tap to open · hold to text',
              color: const Color(0xFFFF4D4D),
              onTap: () {},
              onHold: () {},
            ),
            const SizedBox(height: 20),
            const Text('ON THE LOCK SCREEN', style: caption),
            const SizedBox(height: 12),
            GlowButton(
              key: const ValueKey('app-lock-sos'),
              label: 'OPEN SOS',
              icon: Icons.emergency_outlined,
              color: const Color(0xFFFF4D4D),
              onTap: () {},
              onHold: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = await tester.startGesture(
      tester.getCenter(find.text('SOS MODE')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await capture(tester, '02_dashboard_sos_holding');
    await tile.up();
    await tester.pumpAndSettle();

    final lock = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('app-lock-sos'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await capture(tester, '03_open_sos_holding');
    await lock.up();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'TRUSTED CONTACT',
              style: TextStyle(
                color: Color(0xFF5CE1E6),
                fontSize: 12,
                letterSpacing: 1.4,
                fontFamily: 'NoLeanMono',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This contact can be called or texted from SOS. Hold the SOS '
              'button to open a prefilled message (you press Send). Clear '
              'name and phone to disable.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Sponsor or Partner',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Phone Number',
                hintText: '+1 555 123 4567',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: TextEditingController(text: defaultSosTextTemplate),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'SOS text message (optional)',
                helperText:
                    'Used when you hold the SOS button. Leave blank for the '
                    'default. Add {location} where you want the maps link, or '
                    "we'll add it at the end. You press Send in your SMS app.",
                helperMaxLines: 5,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, '04_settings_template');

    await tester.pumpWidget(
      shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SOS MODE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NoLeanDisplay',
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.phone),
              label: const Text('CALL RIYA'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('sos-text-contact'),
              onPressed: () {},
              icon: const Icon(Icons.sms_outlined),
              label: const Text('TEXT RIYA'),
            ),
            const SizedBox(height: 16),
            Text(
              composeSosText(fix: null, now: DateTime(2026, 11, 26, 22, 30)),
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, '05_sos_screen_text_button');
  });
}

class _IdleSos extends StatelessWidget {
  const _IdleSos();

  @override
  Widget build(BuildContext context) => ActionTile(
    icon: Icons.sos,
    title: 'SOS MODE',
    subtitle: 'Tap to open · hold to text',
    color: const Color(0xFFFF4D4D),
    onTap: () {},
    onHold: () {},
  );
}
