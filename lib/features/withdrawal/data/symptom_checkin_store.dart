import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/companion.dart';
import '../domain/withdrawal_guide.dart';

/// Stores check-ins locally under its own key, so the main recovery state and
/// backup format are untouched.
class SymptomCheckInStore {
  static const key = 'withdrawal_checkins_v1';

  Future<List<SymptomCheckIn>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .map(SymptomCheckIn.fromJson)
          .whereType<SymptomCheckIn>()
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
    } catch (_) {
      return [];
    }
  }

  static const prefsKey = 'withdrawal_prefs_v1';

  Future<CompanionPrefs> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return CompanionPrefs.fromJson(
        jsonDecode(prefs.getString(prefsKey) ?? '{}'),
      );
    } catch (_) {
      return const CompanionPrefs();
    }
  }

  Future<void> savePrefs(CompanionPrefs p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(p.toJson()));
  }

  /// Optional backup section. Older app versions ignore unknown keys.
  Future<Map<String, Object>> exportSection() async => {
    'checkIns': (await load()).map((e) => e.toJson()).toList(),
    'prefs': (await loadPrefs()).toJson(),
  };

  /// Merges a backup section by timestamp; local prefs win unless unset.
  Future<int> importSection(Object? raw) async {
    if (raw is! Map) return 0;
    final incoming = raw['checkIns'] is List
        ? (raw['checkIns'] as List)
              .map(SymptomCheckIn.fromJson)
              .whereType<SymptomCheckIn>()
              .toList()
        : <SymptomCheckIn>[];
    final local = await load();
    final seen = local.map((e) => e.at.toIso8601String()).toSet();
    final added = incoming
        .where((e) => seen.add(e.at.toIso8601String()))
        .toList();
    final all = [...local, ...added]..sort((a, b) => b.at.compareTo(a.at));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(all.take(60).map((e) => e.toJson()).toList()),
    );
    final mine = await loadPrefs();
    if (!mine.asked && raw['prefs'] != null) {
      await savePrefs(CompanionPrefs.fromJson(raw['prefs']));
    }
    return added.length;
  }

  Future<void> add(SymptomCheckIn c) async {
    final all = [c, ...await load()].take(60).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }
}

final symptomCheckInStoreProvider = Provider((_) => SymptomCheckInStore());
