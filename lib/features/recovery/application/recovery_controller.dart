import 'dart:async';
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
  Future<void>? _loadFuture;

  List<RecoveryEvent> events = [];
  DateTime? relapseCooldownUntil;
  String? relapseCooldownEventId;
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
  bool riskReminders = false;
  bool soundscape = false;
  bool hapticFeedback = true;
  FeedbackSoundEffect feedbackSound = FeedbackSoundEffect.neonPulse;
  bool requirePinAfterRelapse = false;
  EffectIntensity intensity = EffectIntensity.standard;
  bool isLoaded = false;

  void _recomputeDerivedState() {
    lastDose = computeLastDose(events);
    longestStreak = math.max(computeLongestStreak(events), streak);
    cleanDays = computeCleanDaysMap(events);

    cravings =
        events
            .where((e) => e.type == RecoveryEventType.craving)
            .map(
              (e) => CravingEntry(
                intensity: e.metadata['intensity'] as int? ?? 5,
                trigger: e.metadata['trigger'] as String? ?? 'Other',
                note: e.metadata['note'] as String? ?? '',
                createdAt: e.timestamp,
              ),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final sosStarts = events.where((e) => e.type == RecoveryEventType.sosStart);
    final sosCompletes = events
        .where((e) => e.type == RecoveryEventType.sosComplete)
        .toList();

    final sessions = <SosSession>[];
    for (final start in sosStarts) {
      final startId = start.id;
      final complete = sosCompletes
          .where((e) => e.metadata['startId'] == startId)
          .firstOrNull;

      sessions.add(
        SosSession(
          id: start.id,
          startedAt: start.timestamp,
          completedAt: complete?.timestamp,
          debrief: complete?.metadata['debrief'] as String?,
        ),
      );
    }

    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    sosSessions = sessions;

    final pledges = events
        .where(
          (e) =>
              e.type == RecoveryEventType.pledge ||
              e.type == RecoveryEventType.cleanCheckIn,
        )
        .toList();
    if (pledges.isNotEmpty) {
      pledges.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      lastPledge = pledges.first.timestamp;
    } else {
      lastPledge = null;
    }
  }

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString('recovery_state');
    if (stored != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        final version = map['stateVersion'] as int?;
        if (version == stateVersion) {
          if (map['events'] is! List) {
            throw const FormatException(
              'Current state is missing its event log.',
            );
          }
          events = _decodeCurrentEvents(map['events']);
          _restoreSettings(map);
          final cooldownStr = map['relapseCooldownUntil'] as String?;
          if (cooldownStr != null) {
            relapseCooldownUntil = DateTime.tryParse(cooldownStr);
          }
          relapseCooldownEventId = map['relapseCooldownEventId'] as String?;
        } else if (version != null && version < stateVersion) {
          await _prefs!.setString('recovery_state_v5_backup', stored);
          _restoreSettings(map);
          if (version <= 3) {
            await _migrateLegacyPin(map['pin'] as String?);
          }
          _migrateToV6(map);
        } else {
          await _preserveRejectedState(stored);
        }
      } catch (_) {
        await _preserveRejectedState(stored);
      }
    }

    _ensureBaselineEvent();
    _sortAndRecompute();
    isLoaded = true;
    await _save();
    await _syncRiskNotifications();
  }

  Future<void> _preserveRejectedState(String stored) async {
    await _prefs!.setString('recovery_state_rejected_backup', stored);
    events = [];
    relapseCooldownUntil = null;
    relapseCooldownEventId = null;
    dailySpend = 0;
    reasons = List<String>.from(defaultReasons);
    reminderMessages = List<String>.from(defaultReminderMessages);
    riskWindow = const RiskWindow.defaultWindow();
    postSosWindowMinutes = 60;
    cooldownMinutes = 15;
    scanlines = true;
    reduceMotion = false;
    highContrast = false;
    riskReminders = false;
    soundscape = false;
    hapticFeedback = true;
    feedbackSound = FeedbackSoundEffect.neonPulse;
    requirePinAfterRelapse = await _relapseLock.hasPin();
    intensity = EffectIntensity.standard;
  }

  void _migrateToV6(Map<String, dynamic> map) {
    final synthesizedEvents = <RecoveryEvent>[];

    final legacyCravings = _decodeList(map['cravings'], CravingEntry.fromJson);
    for (final c in legacyCravings) {
      synthesizedEvents.add(
        RecoveryEvent.create(
          type: RecoveryEventType.craving,
          timestamp: c.createdAt,
          metadata: {
            'intensity': c.intensity,
            'trigger': c.trigger,
            'note': c.note,
          },
        ),
      );
    }

    final legacySos = _decodeList(map['sosSessions'], SosSession.fromJson);
    final uuid = const Uuid();
    for (final s in legacySos) {
      final startId = s.id ?? uuid.v4();
      synthesizedEvents.add(
        RecoveryEvent.fromJson({
          'id': startId,
          'type': RecoveryEventType.sosStart.name,
          'timestamp': s.startedAt.toIso8601String(),
          'metadata': {},
        }),
      );

      if (s.isCompleted) {
        synthesizedEvents.add(
          RecoveryEvent.fromJson({
            'id': uuid.v4(),
            'type': RecoveryEventType.sosComplete.name,
            'timestamp': s.completedAt!.toIso8601String(),
            'metadata': {'startId': startId, 'debrief': s.debrief},
          }),
        );
      }
    }

    final savedCleanDays = map['cleanDays'];
    if (savedCleanDays is Map) {
      for (final entry in savedCleanDays.entries) {
        if (entry.value == true) {
          final date = DateTime.tryParse(entry.key.toString());
          if (date != null) {
            synthesizedEvents.add(
              RecoveryEvent.create(
                type: RecoveryEventType.pledge,
                timestamp: DateTime(date.year, date.month, date.day, 12),
              ),
            );
          }
        }
      }
    }

    final lastDoseDate = DateTime.tryParse(map['lastDose'] as String? ?? '');
    if (lastDoseDate != null) {
      synthesizedEvents.add(
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: lastDoseDate,
          metadata: const {'source': 'legacyLastDose'},
        ),
      );
    }

    final legacyLongestStreak = map['longestStreak'];
    if (legacyLongestStreak is num && legacyLongestStreak > 0) {
      synthesizedEvents.add(
        RecoveryEvent.create(
          type: RecoveryEventType.milestone,
          timestamp: lastDoseDate ?? DateTime.now(),
          metadata: {
            'days': legacyLongestStreak.round(),
            'source': 'legacyLongestStreak',
          },
        ),
      );
    }

    events = synthesizedEvents;
    _ensureBaselineEvent();
    _sortAndRecompute();
  }

  void _ensureBaselineEvent() {
    final hasCounterReset = events.any(
      (event) =>
          event.type == RecoveryEventType.recoveryStart ||
          event.type == RecoveryEventType.relapse,
    );
    if (hasCounterReset) return;

    final baseline = events.isEmpty
        ? DateTime.now()
        : events
              .map((event) => event.timestamp)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    events.add(
      RecoveryEvent.create(
        type: RecoveryEventType.recoveryStart,
        timestamp: baseline,
      ),
    );
  }

  void _sortAndRecompute() {
    events.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    _recomputeDerivedState();
  }

  void _restoreSettings(Map<String, dynamic> map) {
    dailySpend = math.max(
      0,
      (map['dailySpend'] as num?)?.toDouble() ?? dailySpend,
    );
    reasons = _decodeStrings(map['reasons'], defaultReasons);
    reminderMessages = _decodeStrings(
      map['reminderMessages'],
      defaultReminderMessages,
    );
    if (map['riskWindow'] != null) {
      riskWindow = RiskWindow.fromJson(map['riskWindow']);
    }
    postSosWindowMinutes =
        (map['postSosWindowMinutes'] as num?)?.round().clamp(15, 360).toInt() ??
        postSosWindowMinutes;
    cooldownMinutes =
        (map['cooldownMinutes'] as num?)?.round().clamp(1, 120).toInt() ??
        cooldownMinutes;
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

  List<RecoveryEvent> _decodeCurrentEvents(Object? value) {
    if (value is! List) {
      throw const FormatException('Current state is missing its event log.');
    }
    final ids = <String>{};
    final decoded = <RecoveryEvent>[];
    for (final item in value) {
      if (item is! Map) {
        throw const FormatException(
          'Every stored recovery event must be an object.',
        );
      }
      final event = RecoveryEvent.fromJson(Map<String, dynamic>.from(item));
      if (!ids.add(event.id)) {
        throw FormatException(
          'Duplicate stored recovery event ID: ${event.id}',
        );
      }
      decoded.add(event);
    }
    return decoded;
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
  Duration get cleanDuration {
    final elapsed = DateTime.now().difference(lastDose);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  double get moneySaved => math.max(0, cleanDuration.inHours / 24) * dailySpend;
  bool get isRiskWindow => riskWindow.contains(DateTime.now());

  Future<void> _save() async {
    final map = {
      'stateVersion': stateVersion,
      'events': events.map((e) => e.toJson()).toList(),
      'relapseCooldownUntil': relapseCooldownUntil?.toIso8601String(),
      'relapseCooldownEventId': relapseCooldownEventId,
      'cooldownMinutes': cooldownMinutes,
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
    unawaited(syncWidget());
    notifyListeners();
  }

  Future<void> appendEvent(RecoveryEvent event) async {
    events.add(event);
    _sortAndRecompute();
    await _save();
  }

  Future<void> clearRelapseCooldown(String reason) async {
    relapseCooldownUntil = null;
    var index = relapseCooldownEventId == null
        ? -1
        : events.indexWhere((event) => event.id == relapseCooldownEventId);
    if (index == -1) {
      index = events.lastIndexWhere(
        (event) => event.type == RecoveryEventType.relapse,
      );
    }
    if (index != -1) {
      final metadata = Map<String, dynamic>.from(events[index].metadata);
      metadata['debrief'] = reason.trim();
      events[index] = events[index].copyWith(
        metadata: RecoveryEvent.validateMetadata(
          RecoveryEventType.relapse,
          metadata,
        ),
      );
    }
    relapseCooldownEventId = null;
    _sortAndRecompute();
    await _save();
  }

  Future<ProtectedActionResult> deleteEvent({
    required String id,
    String? pin,
    bool tryBiometrics = true,
  }) async {
    final event = events.where((candidate) => candidate.id == id).firstOrNull;
    if (event == null || event.type == RecoveryEventType.recoveryStart) {
      return ProtectedActionResult.denied;
    }
    final authorization = await _authorizeProtectedAction(
      pin: pin,
      tryBiometrics: tryBiometrics,
      reason: 'Authenticate to permanently change recovery history.',
    );
    if (authorization != ProtectedActionResult.completed) return authorization;

    events.removeWhere(
      (candidate) =>
          candidate.id == id ||
          (event.type == RecoveryEventType.sosStart &&
              candidate.type == RecoveryEventType.sosComplete &&
              candidate.metadata['startId'] == id),
    );
    if (relapseCooldownEventId == id) {
      relapseCooldownUntil = null;
      relapseCooldownEventId = null;
    }
    _ensureBaselineEvent();
    _sortAndRecompute();
    await _save();
    return ProtectedActionResult.completed;
  }

  Future<ProtectedActionResult> editEventMetadata({
    required String id,
    required Map<String, dynamic> metadata,
    String? pin,
    bool tryBiometrics = true,
  }) async {
    final index = events.indexWhere((e) => e.id == id);
    if (index == -1 || events[index].type == RecoveryEventType.recoveryStart) {
      return ProtectedActionResult.denied;
    }
    final validated = RecoveryEvent.validateMetadata(
      events[index].type,
      metadata,
    );
    final authorization = await _authorizeProtectedAction(
      pin: pin,
      tryBiometrics: tryBiometrics,
      reason: 'Authenticate to permanently change recovery history.',
    );
    if (authorization != ProtectedActionResult.completed) return authorization;

    events[index] = events[index].copyWith(metadata: validated);
    _sortAndRecompute();
    await _save();
    return ProtectedActionResult.completed;
  }

  Future<void> mergeImportedEvents(
    List<RecoveryEvent> importedEvents, {
    Map<String, dynamic>? preferences,
    bool restorePreferences = false,
  }) async {
    final existingIds = events.map((e) => e.id).toSet();
    for (final event in importedEvents) {
      if (existingIds.add(event.id)) events.add(event);
    }
    if (restorePreferences && preferences != null) {
      _restoreSettings(preferences);
    }
    _ensureBaselineEvent();
    _sortAndRecompute();
    await _save();
    if (restorePreferences) await _syncRiskNotifications();
  }

  Map<String, dynamic> get portablePreferences => {
    'dailySpend': dailySpend,
    'reasons': reasons,
    'reminderMessages': reminderMessages,
    'riskWindow': riskWindow.toJson(),
    'postSosWindowMinutes': postSosWindowMinutes,
    'cooldownMinutes': cooldownMinutes,
    'scanlines': scanlines,
    'reduceMotion': reduceMotion,
    'highContrast': highContrast,
    'riskReminders': riskReminders,
    'soundscape': soundscape,
    'hapticFeedback': hapticFeedback,
    'feedbackSound': feedbackSound.name,
    'intensity': intensity.name,
  };

  Future<void> pledge() async {
    await appendEvent(RecoveryEvent.create(type: RecoveryEventType.pledge));
  }

  Future<void> recordCraving(CravingEntry entry) async {
    await appendEvent(
      RecoveryEvent.create(
        type: RecoveryEventType.craving,
        timestamp: entry.createdAt,
        metadata: entry.toJson(),
      ),
    );
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
    final streakBeforeReset = streak;
    final lastSosComplete = events.reversed.firstWhere(
      (e) => e.type == RecoveryEventType.sosComplete,
      orElse: () => RecoveryEvent.create(
        type: RecoveryEventType.sosComplete,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    final isPostSos =
        lastSosComplete.timestamp.millisecondsSinceEpoch > 0 &&
        now.difference(lastSosComplete.timestamp).inMinutes <=
            postSosWindowMinutes;

    final relapse = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: now,
      metadata: {'postSos': isPostSos, 'streakLost': streakBeforeReset},
    );
    events.add(relapse);
    relapseCooldownUntil = now.add(Duration(minutes: cooldownMinutes));
    relapseCooldownEventId = relapse.id;
    _sortAndRecompute();
    await _save();
    return ProtectedActionResult.completed;
  }

  Future<void> recordSosSession(SosSession session) async {
    final startId = session.id ?? const Uuid().v4();
    final start = _ensureSosStart(startId, session.startedAt);

    if (session.isCompleted) {
      final completedAt = session.completedAt!;
      _upsertSosCompletion(
        startId: startId,
        completedAt: completedAt.isBefore(start.timestamp)
            ? start.timestamp
            : completedAt,
        debrief: session.debrief,
      );
    }
    _sortAndRecompute();
    await _save();
  }

  Future<String> startSosSession({String? id, DateTime? startedAt}) async {
    final startId = id ?? const Uuid().v4();
    _ensureSosStart(startId, startedAt ?? DateTime.now());
    _sortAndRecompute();
    await _save();
    return startId;
  }

  RecoveryEvent _ensureSosStart(String startId, DateTime startedAt) {
    final existing = events.where((event) => event.id == startId).firstOrNull;
    if (existing != null) {
      if (existing.type != RecoveryEventType.sosStart) {
        throw StateError(
          'The SOS session ID is already used by another event.',
        );
      }
      return existing;
    }

    final start = RecoveryEvent.fromJson({
      'id': startId,
      'type': RecoveryEventType.sosStart.name,
      'timestamp': startedAt.toIso8601String(),
      'metadata': {},
    });
    events.add(start);
    return start;
  }

  Future<void> completeSosSession({
    required String startId,
    required DateTime completedAt,
    String? debrief,
  }) async {
    final start = events
        .where(
          (event) =>
              event.id == startId && event.type == RecoveryEventType.sosStart,
        )
        .firstOrNull;
    if (start == null) {
      throw StateError('Cannot complete an SOS session that was not started.');
    }
    _upsertSosCompletion(
      startId: startId,
      completedAt: completedAt.isBefore(start.timestamp)
          ? start.timestamp
          : completedAt,
      debrief: debrief,
    );
    _sortAndRecompute();
    await _save();
  }

  void _upsertSosCompletion({
    required String startId,
    required DateTime completedAt,
    String? debrief,
  }) {
    final index = events.indexWhere(
      (event) =>
          event.type == RecoveryEventType.sosComplete &&
          event.metadata['startId'] == startId,
    );
    final metadata = <String, dynamic>{'startId': startId, 'debrief': ?debrief};
    if (index == -1) {
      events.add(
        RecoveryEvent.fromJson({
          'id': const Uuid().v4(),
          'type': RecoveryEventType.sosComplete.name,
          'timestamp': completedAt.toIso8601String(),
          'metadata': metadata,
        }),
      );
    } else if (debrief != null) {
      events[index] = events[index].copyWith(metadata: metadata);
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
    postSosWindowMinutes = minutes.clamp(15, 360).toInt();
    await _save();
    _recomputeDerivedState();
  }

  Future<void> updateCooldownMinutes(int minutes) async {
    cooldownMinutes = minutes.clamp(1, 120).toInt();
    await _save();
  }

  Future<void> setSetting(String key, dynamic value) async {
    bool changed = false;
    switch (key) {
      case 'scanlines':
        if (scanlines != value) {
          scanlines = value as bool;
          changed = true;
        }
        break;
      case 'reduceMotion':
        if (reduceMotion != value) {
          reduceMotion = value as bool;
          changed = true;
        }
        break;
      case 'highContrast':
        if (highContrast != value) {
          highContrast = value as bool;
          changed = true;
        }
        break;
      case 'riskReminders':
        if (riskReminders != value) {
          riskReminders = value as bool;
          changed = true;
        }
        break;
      case 'soundscape':
        if (soundscape != value) {
          soundscape = value as bool;
          changed = true;
        }
        break;
      case 'hapticFeedback':
        if (hapticFeedback != value) {
          hapticFeedback = value as bool;
          changed = true;
        }
        break;
      case 'feedbackSound':
        if (feedbackSound != value) {
          feedbackSound = value as FeedbackSoundEffect;
          changed = true;
        }
        break;
      case 'intensity':
        if (intensity != value) {
          intensity = value as EffectIntensity;
          changed = true;
        }
        break;
    }

    if (changed) {
      await appendEvent(
        RecoveryEvent.create(
          type: RecoveryEventType.settingsChange,
          metadata: {'setting': key, 'newValue': value.toString()},
        ),
      );
    }

    if (key == 'riskReminders') await _syncRiskNotifications();
  }

  Future<void> updateFeedbackPreferences({
    required bool soundEnabled,
    required bool vibrationEnabled,
    required FeedbackSoundEffect soundEffect,
  }) async {
    bool changed = false;
    if (soundscape != soundEnabled) {
      soundscape = soundEnabled;
      changed = true;
    }
    if (hapticFeedback != vibrationEnabled) {
      hapticFeedback = vibrationEnabled;
      changed = true;
    }
    if (feedbackSound != soundEffect) {
      feedbackSound = soundEffect;
      changed = true;
    }

    if (changed) {
      await appendEvent(
        RecoveryEvent.create(
          type: RecoveryEventType.settingsChange,
          metadata: {'setting': 'feedbackPreferences'},
        ),
      );
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
    isRiskWindow: isRiskWindow,
    hasPledgedToday:
        lastPledge != null &&
        dateKey(lastPledge!.toLocal()) == dateKey(DateTime.now()),
  );
}
