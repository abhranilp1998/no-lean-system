import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../domain/craving_entry.dart';
import '../domain/effect_intensity.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';

// These are editable starting points for the interruption system. They are
// configuration, not activity history: a new account should have a useful
// voice immediately, while cravings, pledges, relapses, and clean-day marks
// must start empty and be created only by the user.
const defaultReasons = <String>[
  'I am done financing a habit that steals my evenings.',
  'I want my money, focus, and control back.',
  'I will not trade tomorrow\'s clarity for tonight\'s impulse.',
];

const defaultReminderMessages = <String>[
  'DO NOT BUY LEAN. YOU KNOW EXACTLY HOW THIS ENDS.',
  'THE RISK WINDOW IS NOT AN EXCUSE. MOVE, CALL SOMEONE, OR STAY HERE.',
  'YOU ARE NOT MISSING OUT. YOU ARE ABOUT TO PAY FOR THE SAME CYCLE.',
  'PUT THE MONEY DOWN. GET THROUGH THE NEXT TEN MINUTES.',
];

class RecoveryController extends ChangeNotifier {
  static const stateVersion = 3;

  SharedPreferences? _prefs;
  DateTime lastDose = DateTime.now();
  DateTime? lastPledge;
  double dailySpend = 0;
  int longestStreak = 0;
  List<CravingEntry> cravings = [];
  List<String> reasons = List<String>.from(defaultReasons);
  List<String> reminderMessages = List<String>.from(defaultReminderMessages);
  Map<String, bool> cleanDays = {};
  bool scanlines = true;
  bool reduceMotion = false;
  bool highContrast = false;
  bool riskReminders = true;
  bool soundscape = false;
  bool requirePinAfterRelapse = false;
  String pin = '';
  EffectIntensity intensity = EffectIntensity.standard;
  bool isLoaded = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString('recovery_state');
    if (stored != null) {
      final map = jsonDecode(stored) as Map<String, dynamic>;
      if (map['stateVersion'] == stateVersion) {
        lastDose =
            DateTime.tryParse(map['lastDose'] as String? ?? '') ?? lastDose;
        final pledge = map['lastPledge'] as String?;
        lastPledge = pledge == null ? null : DateTime.tryParse(pledge);
        dailySpend = (map['dailySpend'] as num?)?.toDouble() ?? dailySpend;
        longestStreak = map['longestStreak'] as int? ?? longestStreak;
        cravings = (map['cravings'] as List<dynamic>? ?? [])
            .map(
              (entry) => CravingEntry.fromJson(
                Map<String, dynamic>.from(entry as Map),
              ),
            )
            .toList();
        reasons = List<String>.from(
          map['reasons'] as List<dynamic>? ?? const [],
        );
        reminderMessages = List<String>.from(
          map['reminderMessages'] as List<dynamic>? ?? const [],
        );
        final savedCleanDays = map['cleanDays'];
        if (savedCleanDays is Map) {
          cleanDays = savedCleanDays.map(
            (key, value) => MapEntry(key.toString(), value == true),
          );
        }
        scanlines = map['scanlines'] as bool? ?? scanlines;
        reduceMotion = map['reduceMotion'] as bool? ?? reduceMotion;
        highContrast = map['highContrast'] as bool? ?? highContrast;
        riskReminders = map['riskReminders'] as bool? ?? riskReminders;
        soundscape = map['soundscape'] as bool? ?? soundscape;
        requirePinAfterRelapse =
            map['requirePinAfterRelapse'] as bool? ?? requirePinAfterRelapse;
        pin = map['pin'] as String? ?? pin;
        intensity = EffectIntensity.values.firstWhere(
          (value) => value.name == map['intensity'],
          orElse: () => EffectIntensity.standard,
        );
      } else if (map['stateVersion'] == 2) {
        // Version 2 was the clean-data migration build. Preserve settings and
        // the editable starting messages, but discard any activity that may
        // have been seeded or entered while that build was under review.
        dailySpend = (map['dailySpend'] as num?)?.toDouble() ?? dailySpend;
        scanlines = map['scanlines'] as bool? ?? scanlines;
        reduceMotion = map['reduceMotion'] as bool? ?? reduceMotion;
        highContrast = map['highContrast'] as bool? ?? highContrast;
        riskReminders = map['riskReminders'] as bool? ?? riskReminders;
        soundscape = map['soundscape'] as bool? ?? soundscape;
        requirePinAfterRelapse =
            map['requirePinAfterRelapse'] as bool? ?? requirePinAfterRelapse;
        pin = map['pin'] as String? ?? pin;
        intensity = EffectIntensity.values.firstWhere(
          (value) => value.name == map['intensity'],
          orElse: () => EffectIntensity.standard,
        );
        await _prefs!.remove('recovery_state');
      } else {
        // The pre-versioned build contained seeded demo values. Start this
        // release clean instead of carrying those values into a real account.
        await _prefs!.remove('recovery_state');
      }
    }
    isLoaded = true;
    await _save();
    if (riskReminders) {
      await NotificationService.instance.scheduleRiskWindow(reminderMessages);
    }
  }

  int get streak => cleanDuration.inDays;
  Duration get cleanDuration => DateTime.now().difference(lastDose);
  double get moneySaved => math.max(0, cleanDuration.inHours / 24) * dailySpend;
  bool get isRiskWindow {
    final minutes = DateTime.now().hour * 60 + DateTime.now().minute;
    return minutes >= 17 * 60 + 30 && minutes <= 20 * 60;
  }

  Future<void> _save() async {
    final map = {
      'lastDose': lastDose.toIso8601String(),
      'lastPledge': lastPledge?.toIso8601String(),
      'stateVersion': stateVersion,
      'dailySpend': dailySpend,
      'longestStreak': longestStreak,
      'cravings': cravings.map((entry) => entry.toJson()).toList(),
      'reasons': reasons,
      'reminderMessages': reminderMessages,
      'cleanDays': cleanDays,
      'scanlines': scanlines,
      'reduceMotion': reduceMotion,
      'highContrast': highContrast,
      'riskReminders': riskReminders,
      'soundscape': soundscape,
      'requirePinAfterRelapse': requirePinAfterRelapse,
      'pin': pin,
      'intensity': intensity.name,
    };
    await _prefs?.setString('recovery_state', jsonEncode(map));
    await syncWidget();
    notifyListeners();
  }

  Future<void> pledge() async {
    final now = DateTime.now();
    lastPledge = now;
    cleanDays[dateKey(now)] = true;
    await _save();
    HapticFeedback.mediumImpact();
  }

  Future<void> recordCraving(CravingEntry entry) async {
    cravings = [entry, ...cravings];
    await _save();
  }

  Future<void> recordRelapse() async {
    final now = DateTime.now();
    final previousStreak = streak;
    lastDose = now;
    cleanDays[dateKey(now)] = false;
    longestStreak = math.max(longestStreak, previousStreak);
    await _save();
    HapticFeedback.heavyImpact();
  }

  Future<void> updateReasons(List<String> value) async {
    reasons = value.where((item) => item.trim().isNotEmpty).toList();
    await _save();
  }

  Future<void> updateReminders(List<String> value) async {
    reminderMessages = value.where((item) => item.trim().isNotEmpty).toList();
    await _save();
    if (riskReminders) {
      await NotificationService.instance.scheduleRiskWindow(reminderMessages);
    }
  }

  Future<void> updateDailySpend(double value) async {
    dailySpend = math.max(0, value);
    await _save();
  }

  Future<void> setSetting(String key, dynamic value) async {
    switch (key) {
      case 'scanlines':
        scanlines = value as bool;
        break;
      case 'reduceMotion':
        reduceMotion = value as bool;
        break;
      case 'highContrast':
        highContrast = value as bool;
        break;
      case 'riskReminders':
        riskReminders = value as bool;
        break;
      case 'soundscape':
        soundscape = value as bool;
        break;
      case 'requirePinAfterRelapse':
        requirePinAfterRelapse = value as bool;
        break;
      case 'intensity':
        intensity = value as EffectIntensity;
        break;
    }
    await _save();
  }

  Future<void> syncWidget() => HomeWidgetService.update(
    cleanTime: formatDuration(cleanDuration, compact: true),
    streak: streak,
  );
}
