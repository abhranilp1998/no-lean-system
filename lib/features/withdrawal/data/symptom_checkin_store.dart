import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> add(SymptomCheckIn c) async {
    final all = [c, ...await load()].take(60).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }
}

final symptomCheckInStoreProvider = Provider((_) => SymptomCheckInStore());
