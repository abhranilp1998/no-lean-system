import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final trustedContactServiceProvider = Provider<TrustedContactService>((ref) {
  return TrustedContactService(const FlutterSecureStorage());
});

class TrustedContact {
  const TrustedContact({required this.name, required this.phone});

  final String name;
  final String phone;
}

class TrustedContactService {
  const TrustedContactService(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyName = 'trusted_contact_name';
  static const _keyPhone = 'trusted_contact_phone';

  Future<void> saveContact(String name, String phone) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone == null) {
      throw const FormatException(
        'Enter a valid phone number with 7–15 digits.',
      );
    }
    final normalizedName = name.trim();
    await _storage.write(
      key: _keyName,
      value: normalizedName.isEmpty ? 'Trusted contact' : normalizedName,
    );
    await _storage.write(key: _keyPhone, value: normalizedPhone);
  }

  Future<TrustedContact?> getContact() async {
    final name = await _storage.read(key: _keyName);
    final phone = await _storage.read(key: _keyPhone);
    final normalizedPhone = normalizePhone(phone ?? '');
    if (normalizedPhone == null) return null;
    return TrustedContact(
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'Trusted contact',
      phone: normalizedPhone,
    );
  }

  Future<void> clearContact() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _keyPhone);
  }

  static String? normalizePhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty || !RegExp(r'^\+?[0-9()\-\s]+$').hasMatch(trimmed)) {
      return null;
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }
}
