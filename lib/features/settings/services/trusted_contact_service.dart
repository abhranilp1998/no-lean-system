import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TrustedContactService {
  const TrustedContactService(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyName = 'trusted_contact_name';
  static const _keyPhone = 'trusted_contact_phone';

  Future<void> saveContact(String name, String phone) async {
    await _storage.write(key: _keyName, value: name);
    await _storage.write(key: _keyPhone, value: phone);
  }

  Future<({String name, String phone})?> getContact() async {
    final name = await _storage.read(key: _keyName);
    final phone = await _storage.read(key: _keyPhone);
    if (name != null && phone != null && phone.isNotEmpty) {
      return (name: name, phone: phone);
    }
    return null;
  }

  Future<void> clearContact() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _keyPhone);
  }
}
