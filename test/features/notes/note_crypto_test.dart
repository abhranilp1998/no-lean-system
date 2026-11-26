import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/notes/domain/note_crypto.dart';

void main() {
  final key = randomBytes(noteKeyBytes);

  test('seal and open round-trips, and nothing readable is stored', () async {
    final sealed = await sealBytes(
      utf8.encode('You got through worse.'),
      keyId: 'k1',
      key: key,
      wrap: null,
      aad: noteAad('n1'),
    );
    expect(
      utf8.decode(sealed.data, allowMalformed: true),
      isNot(contains('worse')),
    );
    final opened = await openBytes(sealed, key, noteAad('n1'));
    expect(utf8.decode(opened!), 'You got through worse.');
  });

  test('wrong key, other note id, or a flipped byte do not open', () async {
    final sealed = await sealBytes(
      [1, 2, 3, 4],
      keyId: 'k1',
      key: key,
      wrap: null,
      aad: noteAad('n1'),
    );
    expect(await openBytes(sealed, randomBytes(32), noteAad('n1')), isNull);
    expect(await openBytes(sealed, key, noteAad('n2')), isNull);
    expect(await openBytes(sealed, key, voiceAad('n1')), isNull);
    final tampered = Uint8List.fromList(sealed.data)..[20] ^= 1;
    expect(
      await openBytes(
        SealedPayload(keyId: 'k1', data: tampered, wrap: null),
        key,
        noteAad('n1'),
      ),
      isNull,
    );
  });

  test('two seals of the same text differ (fresh nonce)', () async {
    final a = await sealBytes([9], keyId: 'k', key: key, wrap: null, aad: []);
    final b = await sealBytes([9], keyId: 'k', key: key, wrap: null, aad: []);
    expect(b64(a.data), isNot(b64(b.data)));
  });

  test('the PIN wrap opens only with the PIN', () async {
    final wrap = await wrapNoteKey(key, '2468', rounds: 1000);
    expect(await unwrapNoteKey(wrap, '2468'), key);
    expect(await unwrapNoteKey(wrap, '2469'), isNull);
    expect(await unwrapNoteKey(wrap, ''), isNull);
  });

  test('envelope JSON round-trips and rejects junk', () async {
    final wrap = await wrapNoteKey(key, '2468', rounds: 1000);
    final sealed = await sealBytes(
      [5, 6],
      keyId: 'k9',
      key: key,
      wrap: wrap,
      aad: noteAad('x'),
    );
    final back = SealedPayload.tryFromJson(
      jsonDecode(jsonEncode(sealed.toJson())),
    )!;
    expect(back.keyId, 'k9');
    expect(await unwrapNoteKey(back.wrap!, '2468'), key);
    expect(await openBytes(back, key, noteAad('x')), [5, 6]);
    expect(SealedPayload.tryFromJson({'v': 2}), isNull);
    expect(SealedPayload.tryFromJson('nope'), isNull);
    expect(NoteKeyWrap.tryFromJson({'s': '!!', 'i': 1, 'k': 'x'}), isNull);
  });
}
