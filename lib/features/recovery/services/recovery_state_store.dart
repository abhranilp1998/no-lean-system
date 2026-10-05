import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

export 'recovery_state_store_io.dart'
    if (dart.library.js_interop) 'recovery_state_store_web.dart';

abstract interface class RecoveryStateStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> preserve(String value);
  Future<List<String>> recoveryCopies();
  Future<void> removeLegacyPin();
}

/// Legacy preference adapter, also used by tests. Platform stores retain it as
/// a migration source instead of replacing or discarding existing history.
class PreferencesRecoveryStateStore implements RecoveryStateStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read() async => (await _prefs).getString('recovery_state');

  Future<void> _put(String key, String value) async {
    if (!await (await _prefs).setString(key, value)) {
      throw StateError('Recovery data could not be saved.');
    }
  }

  @override
  Future<void> write(String value) => _put('recovery_state', value);

  @override
  Future<void> preserve(String value) => _put(
    'recovery_snapshot_${const Uuid().v5(Namespace.url.value, value)}',
    value,
  );

  @override
  Future<List<String>> recoveryCopies() async {
    final prefs = await _prefs;
    return [
      for (final key in prefs.getKeys())
        if (key.startsWith('recovery_snapshot_') ||
            key == 'recovery_state_v5_backup' ||
            key == 'recovery_state_rejected_backup')
          if (prefs.get(key) case final String value) value,
    ];
  }

  @override
  Future<void> removeLegacyPin() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('recovery_'),
    )) {
      final value = prefs.get(key);
      if (value is! String) continue;
      Map<String, dynamic> map;
      try {
        map = Map<String, dynamic>.from(jsonDecode(value) as Map);
      } catch (_) {
        continue;
      }
      if (map.containsKey('pin')) {
        map.remove('pin');
        await _put(key, jsonEncode(map));
      }
    }
  }
}
