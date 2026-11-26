import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/emergency/application/sos_text_service.dart';
import 'package:no_lean/features/emergency/domain/sos_text.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('resolveSosFix prefers a quick current pin, else last known', () async {
    final loc = FakeLocationService(
      current: LocationAccess.whileInUse,
      fix: here,
      lastKnown: LocationFix(
        latitude: 1,
        longitude: 1,
        accuracyMeters: 50,
        at: now.subtract(const Duration(hours: 1)),
      ),
    );
    expect(await resolveSosFix(loc), here);
    expect(loc.quickFixRequests, 1);

    final denied = FakeLocationService(
      current: LocationAccess.denied,
      lastKnown: here,
    );
    expect(await resolveSosFix(denied), here);
    expect(denied.quickFixRequests, 0);
    expect(denied.lastKnownRequests, 1);
  });

  test('a missing template pref is the default; a saved one is kept', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(sosTextTemplateProvider.future),
      defaultSosTextTemplate,
    );

    await container
        .read(sosTextTemplateProvider.notifier)
        .set('  Come now. {location}  ');
    expect(
      container.read(sosTextTemplateProvider).value,
      'Come now. {location}',
    );

    await container.read(sosTextTemplateProvider.notifier).set('   ');
    expect(
      container.read(sosTextTemplateProvider).value,
      defaultSosTextTemplate,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(sosTextTemplateKey), isFalse);
  });

  testWidgets('openSosTextComposer launches sms: and never sends', (
    tester,
  ) async {
    final launched = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSosTextComposer(
                context,
                contact: const TrustedContact(
                  name: 'Riya',
                  phone: '+919800000000',
                ),
                fix: here,
                now: now,
                launcher: (uri) async {
                  launched.add(uri);
                  return true;
                },
              ),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(launched.single.scheme, 'sms');
    expect(launched.single.path, '+919800000000');
    expect(
      launched.single.queryParameters['body'],
      contains("I'm here: https://maps.google.com/"),
    );
    expect(
      launched.single.queryParameters['body'],
      contains(defaultSosTextTemplate),
    );
  });

  testWidgets('no contact and no fix: composer still opens, with a hint', (
    tester,
  ) async {
    final launched = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSosTextComposer(
                context,
                fix: null,
                now: now,
                resolveFix: () async => null,
                launcher: (uri) async {
                  launched.add(uri);
                  return true;
                },
              ),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    expect(launched.single.path, '');
    expect(
      launched.single.queryParameters['body'],
      contains("I couldn't share my location"),
    );
    expect(find.textContaining('No SOS contact saved yet'), findsOneWidget);
  });

  testWidgets('a failed launch shows an error, still never sends', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSosTextComposer(
                context,
                contact: const TrustedContact(
                  name: 'Riya',
                  phone: '+919800000000',
                ),
                fix: here,
                now: now,
                launcher: (uri) async => false,
              ),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    expect(find.textContaining('COULD NOT OPEN MESSAGES'), findsOneWidget);
  });
}
