import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../domain/craving_entry.dart';
import '../domain/effect_intensity.dart';
import '../domain/risk_window.dart';
import '../domain/sos_session.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../services/relapse_lock_service.dart';

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

enum ProtectedActionResult { completed, authenticationRequired, denied }

class RecoveryController extends ChangeNotifier {
  RecoveryController({RelapseLockGateway? relapseLock})
    : _relapseLock = relapseLock ?? SecureRelapseLockService.instance;

  static const stateVersion = 4;

  final RelapseLockGateway _relapseLock;
  SharedPreferences? _prefs;

  DateTime lastDose = DateTime.now();
  DateTime? lastPledge;
  double dailySpend = 0;
  int longestStreak = 0;
  List<CravingEntry> cravings = [];
  List<SosSession> sosSessions = [];
  List<String> reasons = List<String>.from(defaultReasons);
  List<String> reminderMessages = List<String>.from(defaultReminderMessages);
  Map<String, bool> cleanDays = {};
  RiskWindow riskWindow = const RiskWindow.defaultWindow();
  bool scanlines = true;
  bool reduceMotion = false;
  bool highContrast = false;
  bool riskReminders = true;
  bool soundscape = false;
  bool requirePinAfterRelapse = false;
  EffectIntensity intensity = EffectIntensity.standard;
  bool isLoaded = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString('recovery_state');
    if (stored != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        final version = map['stateVersion'] as int?;
        if (version == stateVersion || version == 3) {
          _restoreState(map);
          if (version == 3) {
            await _migrateLegacyPin(map['pin'] as String?);
          }
        } else if (version == 2) {
          _restoreSettings(map);
          await _migrateLegacyPin(map['pin'] as String?);
        } else {
          await _prefs!.remove('recovery_state');
        }
      } catch (_) {
        // A damaged preference blob must not prevent the recovery tools from
        // opening. Start from safe defaults and replace it with valid state.
        await _prefs!.remove('recovery_state');
      }
    }

    isLoaded = true;
    await _save();
    await _syncRiskNotifications();
  }

  void _restoreState(Map<String, dynamic> map) {
    lastDose = DateTime.tryParse(map['lastDose'] as String? ?? '') ?? lastDose;
    final pledge = map['lastPledge'] as String?;
    lastPledge = pledge == null ? null : DateTime.tryParse(pledge);
    dailySpend = (map['dailySpend'] as num?)?.toDouble() ?? dailySpend;
    longestStreak = map['longestStreak'] as int? ?? longestStreak;
    cravings = _decodeList(map['cravings'], CravingEntry.fromJson);
    sosSessions = _decodeList(map['sosSessions'], SosSession.fromJson);
    reasons = _decodeStrings(map['reasons'], defaultReasons);
    reminderMessages = _decodeStrings(
      map['reminderMessages'],
      defaultReminderMessages,
    );
    final savedCleanDays = map['cleanDays'];
    if (savedCleanDays is Map) {
      cleanDays = savedCleanDays.map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
    }
    riskWindow = RiskWindow.fromJson(map['riskWindow']);
    _restoreSettings(map);
  }

  void _restoreSettings(Map<String, dynamic> map) {
    dailySpend = (map['dailySpend'] as num?)?.toDouble() ?? dailySpend;
    scanlines = map['scanlines'] as bool? ?? scanlines;
    reduceMotion = map['reduceMotion'] as bool? ?? reduceMotion;
    highContrast = map['highContrast'] as bool? ?? highContrast;
    riskReminders = map['riskReminders'] as bool? ?? riskReminders;
    soundscape = map['soundscape'] as bool? ?? soundscape;
    requirePinAfterRelapse =
        map['requirePinAfterRelapse'] as bool? ?? requirePinAfterRelapse;
    intensity = EffectIntensity.values.firstWhere(
      (value) => value.name == map['intensity'],
      orElse: () => EffectIntensity.standard,
    );
  }

  List<T> _decodeList<T>(
    Object? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  List<String> _decodeStrings(Object? value, List<String> fallback) {
    if (value is! List) return List<String>.from(fallback);
    return value.whereType<String>().toList();
  }

  Future<void> _migrateLegacyPin(String? legacyPin) async {
    if (legacyPin == null || legacyPin.isEmpty) return;
    await _relapseLock.savePin(legacyPin);
    requirePinAfterRelapse = true;
  }

  int get streak => cleanDuration.inDays;
  Duration get cleanDuration => DateTime.now().difference(lastDose);
  double get moneySaved => math.max(0, cleanDuration.inHours / 24) * dailySpend;
  bool get isRiskWindow => riskWindow.contains(DateTime.now());

  Future<void> _save() async {
    final map = {
      'lastDose': lastDose.toIso8601String(),
      'lastPledge': lastPledge?.toIso8601String(),
      'stateVersion': stateVersion,
      'dailySpend': dailySpend,
      'longestStreak': longestStreak,
      'cravings': cravings.map((entry) => entry.toJson()).toList(),
      'sosSessions': sosSessions.map((session) => session.toJson()).toList(),
      'reasons': reasons,
      'reminderMessages': reminderMessages,
      'cleanDays': cleanDays,
      'riskWindow': riskWindow.toJson(),
      'scanlines': scanlines,
      'reduceMotion': reduceMotion,
      'highContrast': highContrast,
      'riskReminders': riskReminders,
      'soundscape': soundscape,
      'requirePinAfterRelapse': requirePinAfterRelapse,
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
  }

  Future<void> recordCraving(CravingEntry entry) async {
    cravings = [entry, ...cravings];
    await _save();
  }

  Future<ProtectedActionResult> recordRelapse({
    String? pin,
    bool tryBiometrics = true,
  }) async {
    final authorization = await _authorizeProtectedAction(
      pin: pin,
      tryBiometrics: tryBiometrics,
      reason: 'Authenticate to record a relapse and reset clean time.',
    );
    if (authorization != ProtectedActionResult.completed) {
      return authorization;
    }

    final now = DateTime.now();
    final previousStreak = streak;
    lastDose = now;
    cleanDays[dateKey(now)] = false;
    longestStreak = math.max(longestStreak, previousStreak);
    await _save();
    return ProtectedActionResult.completed;
  }

  Future<void> recordSosSession(SosSession session) async {
    sosSessions = [session, ...sosSessions];
    await _save();
  }

  Future<void> enableRelapseLock(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN must contain 4–6 digits.');
    }
    await _relapseLock.savePin(pin);
    requirePinAfterRelapse = true;
    await _save();
  }

  Future<ProtectedActionResult> disableRelapseLock({
    String? pin,
    bool tryBiometrics = true,
  }) async {
    final authorization = await _authorizeProtectedAction(
      pin: pin,
      tryBiometrics: tryBiometrics,
      reason: 'Authenticate to disable the NO LEAN relapse lock.',
    );
    if (authorization != ProtectedActionResult.completed) {
      return authorization;
    }

    await _relapseLock.clearPin();
    requirePinAfterRelapse = false;
    await _save();
    return ProtectedActionResult.completed;
  }

  Future<ProtectedActionResult> _authorizeProtectedAction({
    required String reason,
    String? pin,
    bool tryBiometrics = true,
  }) async {
    if (!requirePinAfterRelapse) return ProtectedActionResult.completed;
    if (pin != null) {
      return await _relapseLock.verifyPin(pin)
          ? ProtectedActionResult.completed
          : ProtectedActionResult.denied;
    }
    if (tryBiometrics) {
      final result = await _relapseLock.authenticateBiometrically(
        reason: reason,
      );
      if (result == BiometricAuthResult.authenticated) {
        return ProtectedActionResult.completed;
      }
    }
    return ProtectedActionResult.authenticationRequired;
  }

  Future<void> updateReasons(List<String> value) async {
    reasons = value.where((item) => item.trim().isNotEmpty).toList();
    await _save();
  }

  Future<void> updateReminders(List<String> value) async {
    reminderMessages = value.where((item) => item.trim().isNotEmpty).toList();
    await _save();
    await _syncRiskNotifications();
  }

  Future<void> updateDailySpend(double value) async {
    dailySpend = math.max(0, value);
    await _save();
  }

  Future<void> updateRiskWindow(RiskWindow value) async {
    riskWindow = value;
    await _save();
    await _syncRiskNotifications();
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
      case 'intensity':
        intensity = value as EffectIntensity;
        break;
    }
    await _save();
    if (key == 'riskReminders') await _syncRiskNotifications();
  }

  Future<void> _syncRiskNotifications() async {
    if (riskReminders) {
      await NotificationService.instance.scheduleRiskWindow(
        reminderMessages,
        riskWindow: riskWindow,
      );
    } else {
      await NotificationService.instance.cancelRiskWindow();
    }
  }

  Future<void> syncWidget() => HomeWidgetService.update(
    lastDose: lastDose,
    cleanTime: formatDuration(cleanDuration, compact: true),
    streak: streak,
  );
}
