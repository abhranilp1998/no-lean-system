import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:flutter/foundation.dart';

/// Encryption for notes to future self, only while a PIN is set.
///
/// Design in one paragraph: each phone has one random 256-bit *note key*.
/// Notes are sealed with AES-256-GCM under that key (the note's id is bound
/// in as associated data, so a sealed note cannot be swapped onto another
/// note). The note key lives in the phone's secure storage (the same
/// Keystore-backed store the PIN hash uses), so opening a note never needs
/// typing the PIN. A second copy of the note key is *wrapped* by a key
/// derived from the PIN (PBKDF2-HMAC-SHA256, 120k rounds, random salt) and
/// travels inside every sealed note. That copy is what makes a backup, a new
/// phone, or a lost secure-storage entry recoverable: with the PIN the key
/// can be rebuilt; without the PIN nobody can open the notes, including us.

const noteSealVersion = 1;
const noteKeyBytes = 32;
const _nonceBytes = 12;
const _macBytes = 16;
const defaultNotePbkdf2Rounds = 120000;

final _algorithm = AesGcm.with256bits();
final _random = Random.secure();

Uint8List randomBytes(int length, {Random? random}) {
  final r = random ?? _random;
  return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
}

String b64(List<int> bytes) => base64Url.encode(bytes);

Uint8List? tryB64(Object? value) {
  if (value is! String) return null;
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    return null;
  }
}

/// The note key, sealed under a key derived from the PIN.
class NoteKeyWrap {
  const NoteKeyWrap({
    required this.salt,
    required this.rounds,
    required this.wrapped,
  });

  final Uint8List salt;
  final int rounds;

  /// nonce | ciphertext | tag.
  final Uint8List wrapped;

  Map<String, dynamic> toJson() => {
    's': b64(salt),
    'i': rounds,
    'k': b64(wrapped),
  };

  static NoteKeyWrap? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final salt = tryB64(json['s']);
    final wrapped = tryB64(json['k']);
    final rounds = json['i'];
    if (salt == null || wrapped == null || rounds is! int) return null;
    if (salt.length < 8 || rounds < 1 || rounds > 2000000) return null;
    if (wrapped.length < _nonceBytes + _macBytes) return null;
    return NoteKeyWrap(salt: salt, rounds: rounds, wrapped: wrapped);
  }

  /// Same salt and rounds: one PIN derivation can open both.
  String get derivationId => '${b64(salt)}:$rounds';
}

/// A sealed payload plus what is needed to find and recover its key.
class SealedPayload {
  const SealedPayload({
    required this.keyId,
    required this.data,
    required this.wrap,
  });

  final String keyId;

  /// nonce | ciphertext | tag.
  final Uint8List data;
  final NoteKeyWrap? wrap;

  Map<String, dynamic> toJson() => {
    'v': noteSealVersion,
    'kid': keyId,
    'd': b64(data),
    if (wrap != null) 'w': wrap!.toJson(),
  };

  static SealedPayload? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final kid = json['kid'];
    final data = tryB64(json['d']);
    if (json['v'] != noteSealVersion ||
        kid is! String ||
        kid.isEmpty ||
        data == null ||
        data.length < _nonceBytes + _macBytes) {
      return null;
    }
    return SealedPayload(
      keyId: kid,
      data: data,
      wrap: NoteKeyWrap.tryFromJson(json['w']),
    );
  }
}

Uint8List _pbkdf2(({Uint8List pin, Uint8List salt, int rounds}) a) {
  final hmac = Hmac(sha256, a.pin);
  var u = hmac.convert([...a.salt, 0, 0, 0, 1]).bytes;
  final result = Uint8List.fromList(u);
  for (var round = 1; round < a.rounds; round++) {
    u = hmac.convert(u).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= u[i];
    }
  }
  return result;
}

Future<Uint8List> deriveWrapKey(String pin, Uint8List salt, int rounds) async {
  final args = (
    pin: Uint8List.fromList(utf8.encode('nolean-notes-v1:$pin')),
    salt: salt,
    rounds: rounds,
  );
  // Small round counts (tests) run inline; real ones run off the UI thread.
  return rounds < 5000 ? _pbkdf2(args) : compute(_pbkdf2, args);
}

Future<Uint8List> _encrypt(
  List<int> plain,
  Uint8List key,
  List<int> aad,
) async {
  final box = await _algorithm.encrypt(
    plain,
    secretKey: SecretKey(key),
    nonce: randomBytes(_nonceBytes),
    aad: aad,
  );
  return Uint8List.fromList(box.concatenation());
}

Future<Uint8List?> _decrypt(
  Uint8List data,
  Uint8List key,
  List<int> aad,
) async {
  try {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _nonceBytes,
      macLength: _macBytes,
    );
    return Uint8List.fromList(
      await _algorithm.decrypt(box, secretKey: SecretKey(key), aad: aad),
    );
  } catch (_) {
    return null;
  }
}

List<int> noteAad(String id) => utf8.encode('nolean-note-v1:$id');
List<int> voiceAad(String id) => utf8.encode('nolean-voice-v1:$id');
final _wrapAad = utf8.encode('nolean-keywrap-v1');

/// Seals [plain] under [key]. [wrap] rides along so the key can be rebuilt
/// from the PIN.
Future<SealedPayload> sealBytes(
  List<int> plain, {
  required String keyId,
  required Uint8List key,
  required NoteKeyWrap? wrap,
  required List<int> aad,
}) async => SealedPayload(
  keyId: keyId,
  data: await _encrypt(plain, key, aad),
  wrap: wrap,
);

/// Null when the key is wrong or the data was altered.
Future<Uint8List?> openBytes(
  SealedPayload sealed,
  Uint8List key,
  List<int> aad,
) => _decrypt(sealed.data, key, aad);

Future<NoteKeyWrap> wrapNoteKey(
  Uint8List key,
  String pin, {
  int rounds = defaultNotePbkdf2Rounds,
}) async {
  final salt = randomBytes(16);
  final kek = await deriveWrapKey(pin, salt, rounds);
  return NoteKeyWrap(
    salt: salt,
    rounds: rounds,
    wrapped: await _encrypt(key, kek, _wrapAad),
  );
}

/// Null for a wrong PIN.
Future<Uint8List?> unwrapNoteKey(NoteKeyWrap wrap, String pin) async {
  final kek = await deriveWrapKey(pin, wrap.salt, wrap.rounds);
  final key = await _decrypt(wrap.wrapped, kek, _wrapAad);
  return key != null && key.length == noteKeyBytes ? key : null;
}
