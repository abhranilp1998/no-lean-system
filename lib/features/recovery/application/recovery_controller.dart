import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/feedback_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../domain/craving_entry.dart';
import '../domain/effect_intensity.dart';
import '../domain/event_derived_state.dart';
import '../domain/recovery_event.dart';
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

  static const stateVersion = 6;

  final RelapseLockGateway _relapseLock;
  SharedPreferences? _prefs;

  List<RecoveryEvent> events = [];
  DateTime? relapseCooldownUntil;
  int cooldownMinutes = 15;

  DateTime lastDose = DateTime.now();
  DateTime? lastPledge;
  int longestStreak = 0;
  List<CravingEntry> cravings = [];
  List<SosSession> sosSessions = [];
  Map<String, bool> cleanDays = {};

  double dailySpend = 0;
  List<String> reasons = List<String>.from(defaultReasons);
  List<String> reminderMessages = List<String>.from(defaultReminderMessages);
  RiskWindow riskWindow = const RiskWindow.defaultWindow();
  int postSosWindowMinutes = 60; // Default 1 hour
  bool scanlines = true;
  bool reduceMotion = false;
  bool highContrast = false;
  bool riskReminders = true;
  bool soundscape = false;
  bool hapticFeedback = true;
  FeedbackSoundEffect feedbackSound = FeedbackSoundEffect.neonPulse;
  bool requirePinAfterRelapse = false;
  EffectIntensity intensity = EffectIntensity.standard;
  bool isLoaded = false;

  void _recomputeDerivedState() {
    lastDose = computeLastDose(events);
    longestStreak = computeLongestStreak(events);
    cleanDays = computeCleanDaysMap(events);

    cravings = events
        .where((e) => e.type == RecoveryEventType.craving)
        .map((e) => CravingEntry(
              intensity: e.metadata['intensity'] as int? ?? 5,
              trigger: e.metadata['trigger'] as String? ?? 'Other',
              note: e.metadata['note'] as String? ?? '',
              createdAt: e.timestamp,
            ))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final sosStarts = events.where((e) => e.type == RecoveryEventType.sosStart);
    final sosCompletes = events.where((e) => e.type == RecoveryEventType.sosComplete).toList();

    final sessions = <SosSession>[];
    for (final start in sosStarts) {
      final startId = start.id;
      final complete = sosCompletes.where((e) => e.metadata['startId'] == startId).firstOrNull;
      
      sessions.add(SosSession(
        id: start.id,
        startedAt: start.timestamp,
        completedAt: complete?.timestamp,
        debrief: complete?.metadata['debrief'] as String?,
      ));
    }
    
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    sosSessions = sessions;
    
    final pledges = events.where((e) => e.type == RecoveryEventType.pledge || e.type == RecoveryEventType.cleanCheckIn).toList();
    if (pledges.isNotEmpty) {
      pledges.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      lastPledge = pledges.first.timestamp;
    } else {
      lastPledge = null;
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString('recovery_state');
    if (stored != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        final version = map['stateVersion'] as int?;
        if (version == stateVersion) {
          events = _decodeList(map['events'], RecoveryEvent.fromJson);
          _recomputeDerivedState();
          _restoreSettings(map);
          final cooldownStr = map['relapseCooldownUntil'] as String?;
          if (cooldownStr != null) {
            relapseCooldownUntil = DateTime.tryParse(cooldownStr);
          }
        } else if (version != null && version < stateVersion) {
          await _prefs!.setString('recovery_state_v5_backup', stored);
          _restoreSettings(map);
          if (version <= 3) {
            await _migrateLegacyPin(map['pin'] as String?);
          }
          _migrateToV6(map);
        } else {
          await _prefs!.remove('recovery_state');
        }
      } catch (_) {
        await _prefs!.remove('recovery_state');
      }
    }

    isLoaded = true;
    await _save();
    await _syncRiskNotifications();
  }

  void _migrateToV6(Map<String, dynamic> map) {
    final synthesizedEvents = <RecoveryEvent>[];
    
    final legacyCravings = _decodeList(map['cravings'], CravingEntry.fromJson);
    for (final c in legacyCravings) {
      synthesizedEvents.add(RecoveryEvent.create(
        type: RecoveryEventType.craving,
        timestamp: c.createdAt,
        metadata: {'intensity': c.intensity, 'trigger': c.trigger, 'note': c.note},
      ));
    }

    final legacySos = _decodeList(map['sosSessions'], SosSession.fromJson);
    final uuid = const Uuid();
    for (final s in legacySos) {
      final startId = s.id ?? uuid.v4();
      synthesizedEvents.add(RecoveryEvent.fromJson({
        'id': startId,
        'type': RecoveryEventType.sosStart.name,
        'timestamp': s.startedAt.toIso8601String(),
        'metadata': {},
      }));

      if (s.isCompleted) {
        synthesizedEvents.add(RecoveryEvent.fromJson({
          'id': uuid.v4(),
          'type': RecoveryEventType.sosComplete.name,
          'timestamp': s.completedAt!.toIso8601String(),
          'metadata': {'startId': startId, 'debrief': s.debrief},
        }));
      }
    }

    final savedCleanDays = map['cleanDays'];
    if (savedCleanDays is Map) {
      for (final entry in savedCleanDays.entries) {
        if (entry.value == true) {
          final dateStr = entry.key.toString();
          final parts = dateStr.split('-');
          if (parts.length == 3) {
            final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), 12);
            synthesizedEvents.add(RecoveryEvent.create(
              type: RecoveryEventType.pledge,
              timestamp: date,
            ));
          }
        }
      }
    }

    final lastDoseDate = DateTime.tryParse(map['lastDose'] as String? ?? '');
    if (lastDoseDate != null) {
      if (DateTime.now().difference(lastDoseDate).inMinutes > 1) {
        synthesizedEvents.add(RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: lastDoseDate,
        ));
      }
    }

    synthesizedEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    events = synthesizedEvents;
    _recomputeDerivedState();
  }

  void _restoreSettings(Map<String, dynamic> map) {
    dailySpend = (map['dailySpend'] as num?)?.toDouble() ?? dailySpend;
    reasons = _decodeStrings(map['reasons'], defaultReasons);
    reminderMessages = _decodeStrings(map['reminderMessages'], defaultReminderMessages);
    if (map['riskWindow'] != null) {
      riskWindow = RiskWindow.fromJson(map['riskWindow']);
    }
    postSosWindowMinutes = map['postSosWindowMinutes'] as int? ?? postSosWindowMinutes;
    scanlines = map['scanlines'] as bool? ?? scanlines;
    reduceMotion = map['reduceMotion'] as bool? ?? reduceMotion;
    highContrast = map['highContrast'] as bool? ?? highContrast;
    riskReminders = map['riskReminders'] as bool? ?? riskReminders;
    soundscape = map['soundscape'] as bool? ?? soundscape;
    hapticFeedback = map['hapticFeedback'] as bool? ?? hapticFeedback;
    feedbackSound = FeedbackSoundEffect.values.firstWhere(
      (value) => value.name == map['feedbackSound'],
      orElse: () => FeedbackSoundEffect.neonPulse,
    );
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
      'stateVersion': stateVersion,
      'events': events.map((e) => e.toJson()).toList(),
      'relapseCooldownUntil': relapseCooldownUntil?.toIso8601String(),
      'dailySpend': dailySpend,
      'reasons': reasons,
      'reminderMessages': reminderMessages,
      'riskWindow': riskWindow.toJson(),
      'postSosWindowMinutes': postSosWindowMinutes,
      'scanlines': scanlines,
      'reduceMotion': reduceMotion,
      'highContrast': highContrast,
      'riskReminders': riskReminders,
      'soundscape': soundscape,
      'hapticFeedback': hapticFeedback,
      'feedbackSound': feedbackSound.name,
      'requirePinAfterRelapse': requirePinAfterRelapse,
      'intensity': intensity.name,
    };
    await _prefs?.setString('recovery_state', jsonEncode(map));
    await syncWidget();
    notifyListeners();
  }

  Future<void> appendEvent(RecoveryEvent event) async {
    events.add(event);
    _recomputeDerivedState();
    await _save();
  }

  Future<void> clearRelapseCooldown(String reason) async {
    relapseCooldownUntil = null;
    if (events.isNotEmpty) {
      final index = events.length - 1;
      final metadata = Map<String, dynamic>.from(events[index].metadata);
      metadata['debrief'] = reason;
      events[index] = events[index].copyWith(metadata: metadata);
    }
    _recomputeDerivedState();
    notifyListeners();
    await _save();
  }

  Future<void> deleteEvent(String id) async {
    events.removeWhere((e) => e.id == id);
    _recomputeDerivedState();
    await _save();
  }

  Future<void> editEventMetadata(String id, Map<String, dynamic> metadata) async {
    final index = events.indexWhere((e) => e.id == id);
    if (index != -1) {
      events[index] = events[index].copyWith(metadata: metadata);
      _recomputeDerivedState();
      await _save();
    }
  }

  Future<void> mergeImportedEvents(List<RecoveryEvent> importedEvents) async {
    final existingIds = events.map((e) => e.id).toSet();
    final newEvents = importedEvents.where((e) => !existingIds.contains(e.id));
    
    events.addAll(newEvents);
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    _recomputeDerivedState();
    await _save();
  }

  Future<void> pledge() async {
    await appendEvent(RecoveryEvent.create(type: RecoveryEventType.pledge));
  }

  Future<void> recordCraving(CravingEntry entry) async {
    await appendEvent(RecoveryEvent.create(
      type: RecoveryEventType.craving,
      timestamp: entry.createdAt,
      metadata: entry.toJson(),
    ));
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
    final lastSosComplete = events.reversed.firstWhere(
      (e) => e.type == RecoveryEventType.sosComplete,
      orElse: () => RecoveryEvent.create(type: RecoveryEventType.sosComplete, timestamp: DateTime.fromMillisecondsSinceEpoch(0)),
    );
    final isPostSos = lastSosComplete.timestamp.millisecondsSinceEpoch > 0 &&
        now.difference(lastSosComplete.timestamp).inMinutes <= postSosWindowMinutes;

    await appendEvent(RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      metadata: {'postSos': isPostSos, 'streakLost': longestStreak},
    ));
    relapseCooldownUntil = now.add(Duration(minutes: cooldownMinutes));
    await _save();
    return ProtectedActionResult.completed;
  }

  Future<void> recordSosSession(SosSession session) async {
    final startId = session.id ?? const Uuid().v4();
    await appendEvent(RecoveryEvent.fromJson({
      'id': startId,
      'type': RecoveryEventType.sosStart.name,
      'timestamp': session.startedAt.toIso8601String(),
      'metadata': {},
    }));

    if (session.isCompleted) {
      await appendEvent(RecoveryEvent.fromJson({
        'id': const Uuid().v4(),
        'type': RecoveryEventType.sosComplete.name,
        'timestamp': session.completedAt!.toIso8601String(),
        'metadata': {'startId': startId, 'debrief': session.debrief},
      }));
    }
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

  Future<void> updatePostSosWindow(int minutes) async {
    postSosWindowMinutes = minutes;
    await _save();
    _recomputeDerivedState();
  }

  Future<void> setSetting(String key, dynamic value) async {
    bool changed = false;
    switch (key) {
      case 'scanlines':
        if (scanlines != value) { scanlines = value as bool; changed = true; }
        break;
      case 'reduceMotion':
        if (reduceMotion != value) { reduceMotion = value as bool; changed = true; }
        break;
      case 'highContrast':
        if (highContrast != value) { highContrast = value as bool; changed = true; }
        break;
      case 'riskReminders':
        if (riskReminders != value) { riskReminders = value as bool; changed = true; }
        break;
      case 'soundscape':
        if (soundscape != value) { soundscape = value as bool; changed = true; }
        break;
      case 'hapticFeedback':
        if (hapticFeedback != value) { hapticFeedback = value as bool; changed = true; }
        break;
      case 'feedbackSound':
        if (feedbackSound != value) { feedbackSound = value as FeedbackSoundEffect; changed = true; }
        break;
      case 'intensity':
        if (intensity != value) { intensity = value as EffectIntensity; changed = true; }
        break;
    }
    
    if (changed) {
      await appendEvent(RecoveryEvent.create(
        type: RecoveryEventType.settingsChange,
        metadata: {'setting': key, 'newValue': value.toString()},
      ));
    }
    
    if (key == 'riskReminders') await _syncRiskNotifications();
  }

  Future<void> updateFeedbackPreferences({
    required bool soundEnabled,
    required bool vibrationEnabled,
    required FeedbackSoundEffect soundEffect,
  }) async {
    bool changed = false;
    if (soundscape != soundEnabled) { soundscape = soundEnabled; changed = true; }
    if (hapticFeedback != vibrationEnabled) { hapticFeedback = vibrationEnabled; changed = true; }
    if (feedbackSound != soundEffect) { feedbackSound = soundEffect; changed = true; }
    
    if (changed) {
      await appendEvent(RecoveryEvent.create(
        type: RecoveryEventType.settingsChange,
        metadata: {'setting': 'feedbackPreferences'},
      ));
    }
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
