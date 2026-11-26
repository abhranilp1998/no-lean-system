import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/emergency/domain/sos_text.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';

void main() {
  final now = DateTime(2026, 11, 26, 22, 30);
  LocationFix fix({Duration ago = Duration.zero, double acc = 12}) =>
      LocationFix(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: acc,
        at: now.subtract(ago),
      );

  test(
    'blank, whitespace and over-long templates fall back to the default',
    () {
      expect(normalizeSosTextTemplate(null), defaultSosTextTemplate);
      expect(normalizeSosTextTemplate(''), defaultSosTextTemplate);
      expect(normalizeSosTextTemplate('   '), defaultSosTextTemplate);
      expect(normalizeSosTextTemplate('x' * 400), defaultSosTextTemplate);
      expect(normalizeSosTextTemplate('  Come now.  '), 'Come now.');
    },
  );

  test('a fresh fix becomes a maps link composed offline from coordinates', () {
    final body = composeSosText(fix: fix(), now: now);
    expect(body, startsWith(defaultSosTextTemplate));
    expect(
      body,
      contains("I'm here: https://maps.google.com/?q=12.97160,77.59460"),
    );
    expect(sosMapsLink(fix()), 'https://maps.google.com/?q=12.97160,77.59460');
  });

  test('a last-known fix under 24 h is labelled as last place', () {
    final body = composeSosText(
      fix: fix(ago: const Duration(minutes: 20)),
      now: now,
    );
    expect(
      body,
      contains('Last place I was (~20 min ago): https://maps.google.com/'),
    );
  });

  test('no fix, or a pin older than 24 h, says so and has no maps link', () {
    expect(
      composeSosText(fix: null, now: now),
      contains("I couldn't share my location — please call me."),
    );
    expect(
      composeSosText(
        fix: fix(ago: const Duration(hours: 30)),
        now: now,
      ),
      isNot(contains('maps.google.com')),
    );
  });

  test('{location} in a custom template is replaced, not appended twice', () {
    final body = composeSosText(
      template: 'It is bad. {location} Please come.',
      fix: fix(),
      now: now,
    );
    expect(body, startsWith('It is bad. I\'m here: https://maps.google.com/'));
    expect(body, endsWith('Please come.'));
    expect('maps.google.com'.allMatches(body).length, 1);
  });

  test('the sms: URI is prefilled and never sent by us', () {
    final uri = sosTextUri(body: 'Hello', phone: '+919800000000');
    expect(uri.scheme, 'sms');
    expect(uri.path, '+919800000000');
    expect(uri.queryParameters['body'], 'Hello');
    // An empty number still opens the composer so the user can pick someone.
    expect(sosTextUri(body: 'Hello', phone: null).path, '');
  });

  test(
    'default copy and source name no government helpline or emergency number',
    () {
      expect(defaultSosTextTemplate.toLowerCase(), isNot(contains('helpline')));
      expect(
        defaultSosTextTemplate,
        isNot(matches(RegExp(r'\b(112|911|999|108|102)\b'))),
      );
      final src = File('lib/features/emergency/domain/sos_text.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src.toLowerCase(), isNot(contains('helpline')));
      expect(
        src,
        isNot(matches(RegExp(r'(?<![\w.])(112|911|999|108|102)(?![\w.])'))),
      );
    },
  );
}
