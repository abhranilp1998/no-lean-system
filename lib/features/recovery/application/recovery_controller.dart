import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/feedback_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../dashboard/domain/dashboard_notice_style.dart';
import '../domain/craving_entry.dart';
import '../domain/legacy_recovery_migration.dart';
import '../services/recovery_state_store.dart';
import '../domain/effect_intensity.dart';
import '../domain/event_derived_state.dart';
import '../domain/recovery_event.dart';
import '../domain/relapse_log_entry.dart';
import '../domain/milestones.dart';
import '../domain/notification_policy.dart';
import '../domain/risk_alert_plan.dart';
import '../domain/risk_window.dart';
import '../domain/sos_session.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../services/relapse_lock_service.dart';
import '../../zones/domain/danger_zone.dart';
import '../../zones/services/geofence_gateway.dart';

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

enum ProtectedActionResult {
  completed,
  authenticationRequired,
  denied,
  lockedOut,
}

extension ProtectedActionResultMessage on ProtectedActionResult {
  String get failureMessage => switch (this) {
    ProtectedActionResult.lockedOut =>
      'Too many incorrect PIN attempts. PIN entry is paused: 5 minutes, then 15, then 60 on repeat lockouts. Biometrics still work.',
    ProtectedActionResult.denied =>
      'Authentication failed. Nothing was changed.',
    ProtectedActionResult.authenticationRequired =>
      'Authentication is required to continue.',
    ProtectedActionResult.completed => '',
  };
}

enum RecoveryLoadStatus { loading, ready, error, incompatible }

class RecoverySaveException implements Exception {
  const RecoverySaveException();
  @override
  String toString() =>
      'Could not save. Your previous history is intact. Please try again.';
}

class RecoveryController extends ChangeNotifier {
  RecoveryController({
    RelapseLockGateway? relapseLock,
    RecoveryStateStore? store,
    DateTime Function()? now,
    GeofenceGateway? geofences,
  }) : _relapseLock = relapseLock ?? SecureRelapseLockService.instance,
       _store = store ?? PreferencesRecoveryStateStore(),
       _now = now ?? DateTime.now,
       _geofences = geofences ?? const NoopGeofenceGateway();

  /// v8 adds `riskWindowLock` and `appLockPending`; v9 adds `zones`,
  /// `zoneMonitoring` and `backgroundGeofencing`; v10 adds the privacy and
  /// notification preferences (`streetTiles`, ...). Older states need no
  /// transformation: missing keys take the safe defaults below.
  static const stateVersion = 10;

  final RelapseLockGateway _relapseLock;
  final RecoveryStateStore _store;
  final DateTime Function() _now;
  final GeofenceGateway _geofences;
  Future<void>? _loadFuture;
  Future<void> _writeQueue = Future.value();
  Map<String, dynamic> _extraState = {};
  RecoveryLoadStatus loadStatus = RecoveryLoadStatus.loading;
  String? loadMessage;
  String? saveMessage;
  DateTime? lastOpenedAt;
  DateTime? welcomeBackSince;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

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
  bool peakHourLock = true;
  bool soundscape = false;
  bool hapticFeedback = true;
  FeedbackSoundEffect feedbackSound = FeedbackSoundEffect.neonPulse;
  bool requirePinAfterRelapse = false;

  /// Auto-locks the app inside [riskWindow] when a PIN exists.
  bool riskWindowLock = true;

  /// Set when a relapse is logged; the app stays locked until authenticated.
  bool appLockPending = false;

  /// User-defined danger zones (state v9+).
  List<DangerZone> zones = [];

  /// In-app distance checks while NO LEAN is open (opt-in).
  bool zoneMonitoring = false;

  /// Online OSM street tiles on the zone map. Off = grid only, no requests.
  bool streetTiles = true;

  /// Highest milestone reached since the UI last celebrated. Not persisted:
  /// the milestone events themselves are the record.
  int? pendingCelebration;

  /// Home widget privacy: neutral text, no counter, streak or risk state.
  bool widgetPrivacy = false;

  /// Quiet hours and lock-screen privacy for notifications.
  NotificationPrefs notificationPrefs = const NotificationPrefs();

  /// OS geofencing while the app is closed (opt-in, needs background location).
  bool backgroundGeofencing = false;
  EffectIntensity intensity = EffectIntensity.standard;
  DashboardNoticeStyle dashboardNoticeStyle = DashboardNoticeStyle.edgeRail;
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

  Future<void> retryLoad() async {
    if (isLoaded) return;
    _loadFuture = null;
    await load();
  }

  Future<void> _load() async {
    loadStatus = RecoveryLoadStatus.loading;
    loadMessage = null;
    _notify();
    try {
      final stored = await _store.read().timeout(const Duration(seconds: 15));
      final map = stored == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(stored) as Map);
      final version = map['stateVersion'];
      if (stored != null &&
          (version is! int || version < 2 || version > stateVersion)) {
        loadStatus = RecoveryLoadStatus.incompatible;
        loadMessage =
            'This recovery history needs a compatible app version. It has been kept unchanged.';
        _notify();
        return;
      }
      if (version is int && version <= 3 && map['pin'] is String) {
        await _migrateLegacyPin(map['pin'] as String);
        await _store.removeLegacyPin();
      }
      map.remove('pin');
      if (stored != null && version != stateVersion) {
        await _store.preserve(jsonEncode(map));
      }
      _extraState = Map.from(map);
      events = version is int && version < 6
          ? migrateLegacyRecovery(map)
          : _decodeCurrentEvents(map['events'] ?? (stored == null ? [] : null));
      if (version == 6) {
        // Repair day-level facts lost by earlier v5→v6 migrations when the
        // original backup is still present; never synthesize timed relapses.
        for (final copy in await _store.recoveryCopies()) {
          try {
            final legacy = Map<String, dynamic>.from(jsonDecode(copy) as Map);
            if (legacy['stateVersion'] is int && legacy['stateVersion'] <= 5) {
              final ids = events.map((e) => e.id).toSet();
              for (final event in migrateLegacyRecovery(legacy)) {
                if ((event.type == RecoveryEventType.daySummary ||
                        event.metadata['source'] == 'legacyLastPledge') &&
                    ids.add(event.id)) {
                  events.add(event);
                }
              }
            }
          } catch (_) {
            /* The preserved copy stays intact for manual recovery. */
          }
        }
      }
      _restoreSettings(map);
      zones = DangerZone.decodeList(map['zones']);
      relapseCooldownUntil = DateTime.tryParse(
        map['relapseCooldownUntil']?.toString() ?? '',
      );
      relapseCooldownEventId = map['relapseCooldownEventId'] is String
          ? map['relapseCooldownEventId'] as String
          : null;
      lastOpenedAt = DateTime.tryParse(map['lastOpenedAt']?.toString() ?? '');
      _ensureBaselineEvent();
      _sortAndRecompute();
      final previousVisit =
          lastOpenedAt ?? (events.isEmpty ? null : events.last.timestamp);
      welcomeBackSince =
          previousVisit != null &&
              DateTime.now().difference(previousVisit) >=
                  const Duration(hours: 6)
          ? previousVisit
          : null;
      if (version != stateVersion) await _store.write(jsonEncode(_snapshot()));
      isLoaded = true;
      loadStatus = RecoveryLoadStatus.ready;
      _notify();
      unawaited(syncWidget());
      unawaited(_syncRiskNotifications());
      unawaited(_syncGeofences());
    } catch (_) {
      isLoaded = false;
      loadStatus = RecoveryLoadStatus.error;
      loadMessage =
          'Your recovery history could not be opened. Nothing has been reset. Retry, or export a preserved copy.';
      _notify();
    }
  }

  Future<List<String>> recoveryCopies() async {
    final current = await _store.read();
    return [?current, ...await _store.recoveryCopies()];
  }

  Future<void> markOpened() async {
    try {
      await _transaction(() {
        if (lastOpenedAt != null &&
            DateTime.now().difference(lastOpenedAt!) >=
                const Duration(hours: 6)) {
          welcomeBackSince = lastOpenedAt;
        }
        lastOpenedAt = DateTime.now();
      });
    } on RecoverySaveException {
      /* The shell displays the non-blocking save error. */
    }
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
    final spend = map['dailySpend'];
    if (spend is num && spend.isFinite && spend >= 0) {
      dailySpend = spend.toDouble();
    }
    reasons = _decodeStrings(map['reasons'], reasons);
    reminderMessages = _decodeStrings(
      map['reminderMessages'],
      reminderMessages,
    );
    if (map['riskWindow'] is Map) {
      try {
        riskWindow = RiskWindow.fromJson(map['riskWindow']);
      } catch (_) {
        /* Optional setting. */
      }
    }
    int minutes(String key, int fallback, int min, int max) {
      final value = map[key];
      return value is num && value.isFinite
          ? value.round().clamp(min, max)
          : fallback;
    }

    postSosWindowMinutes = minutes(
      'postSosWindowMinutes',
      postSosWindowMinutes,
      15,
      360,
    );
    cooldownMinutes = minutes('cooldownMinutes', cooldownMinutes, 1, 120);
    bool flag(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;
    scanlines = flag('scanlines', scanlines);
    reduceMotion = flag('reduceMotion', reduceMotion);
    highContrast = flag('highContrast', highContrast);
    riskReminders = flag('riskReminders', riskReminders);
    peakHourLock = flag('peakHourLock', peakHourLock);
    soundscape = flag('soundscape', soundscape);
    hapticFeedback = flag('hapticFeedback', hapticFeedback);
    // A malformed protection flag must not silently disable authentication.
    requirePinAfterRelapse = map.containsKey('requirePinAfterRelapse')
        ? map['requirePinAfterRelapse'] != false
        : requirePinAfterRelapse;
    riskWindowLock = map.containsKey('riskWindowLock')
        ? map['riskWindowLock'] != false
        : riskWindowLock;
    appLockPending = map.containsKey('appLockPending')
        ? map['appLockPending'] != false
        : appLockPending;
    zoneMonitoring = flag('zoneMonitoring', zoneMonitoring);
    streetTiles = flag('streetTiles', streetTiles);
    // Privacy flag: once present, anything but an explicit false stays private.
    if (map.containsKey('widgetPrivacy')) {
      widgetPrivacy = map['widgetPrivacy'] != false;
    }
    if (map.containsKey('quietHoursEnabled') ||
        map.containsKey('quietHours') ||
        map.containsKey('hideSensitiveNotifications')) {
      notificationPrefs = NotificationPrefs.fromState(map);
    }
    NotificationService.instance.prefs = notificationPrefs;
    backgroundGeofencing = flag('backgroundGeofencing', backgroundGeofencing);
    feedbackSound = FeedbackSoundEffect.values.firstWhere(
      (v) => v.name == map['feedbackSound'],
      orElse: () => feedbackSound,
    );
    intensity = EffectIntensity.values.firstWhere(
      (v) => v.name == map['intensity'],
      orElse: () => intensity,
    );
    dashboardNoticeStyle = DashboardNoticeStyle.values.firstWhere(
      (value) => value.name == map['dashboardNoticeStyle'],
      orElse: () => dashboardNoticeStyle,
    );
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
    final elapsed = _now().difference(lastDose);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  double get moneySaved => math.max(0, cleanDuration.inHours / 24) * dailySpend;
  bool get isRiskWindow => riskWindow.contains(_now());
  bool get isPeakHourLockActive => peakHourLock && isRiskWindow;

  /// The risk-window wall needs a credential; without a PIN nothing can lock.
  bool get riskWindowWallArmed => requirePinAfterRelapse && riskWindowLock;

  /// True after a relapse was logged with the lock enabled, until unlocked.
  bool get relockPending => requirePinAfterRelapse && appLockPending;
  RiskWindowEvidence get riskWindowEvidence =>
      computeRiskWindowEvidence(events, riskWindow);

  /// Daily risk-window alerts built only from the user's own logged data.
  List<RiskAlert> get riskAlertPlan => buildRiskAlertPlan(
    window: riskWindow,
    facts: computeRiskAlertFacts(
      events: events,
      window: riskWindow,
      cleanSince: lastDose,
    ),
    userMessages: reminderMessages,
  );

  Map<String, dynamic> _snapshot() => {
    ..._extraState,
    'stateVersion': stateVersion,
    'lastOpenedAt': lastOpenedAt?.toIso8601String(),
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
    'peakHourLock': peakHourLock,
    'soundscape': soundscape,
    'hapticFeedback': hapticFeedback,
    'feedbackSound': feedbackSound.name,
    'requirePinAfterRelapse': requirePinAfterRelapse,
    'riskWindowLock': riskWindowLock,
    'appLockPending': appLockPending,
    'zones': zones.map((zone) => zone.toJson()).toList(),
    'zoneMonitoring': zoneMonitoring,
    'streetTiles': streetTiles,
    'widgetPrivacy': widgetPrivacy,
    ...notificationPrefs.toJson(),
    'backgroundGeofencing': backgroundGeofencing,
    'intensity': intensity.name,
    'dashboardNoticeStyle': dashboardNoticeStyle.name,
  };

  void _restoreSnapshot(Map<String, dynamic> map) {
    _extraState = Map.from(map);
    events = _decodeCurrentEvents(map['events']);
    _restoreSettings(map);
    zones = DangerZone.decodeList(map['zones']);
    relapseCooldownUntil = DateTime.tryParse(
      map['relapseCooldownUntil']?.toString() ?? '',
    );
    relapseCooldownEventId = map['relapseCooldownEventId'] as String?;
    lastOpenedAt = DateTime.tryParse(map['lastOpenedAt']?.toString() ?? '');
    _sortAndRecompute();
  }

  Future<T> _transaction<T>(FutureOr<T> Function() change) {
    final result = _writeQueue.then((_) async {
      if (!isLoaded) {
        throw StateError(
          'Recovery history must be loaded before making changes.',
        );
      }
      final before = _snapshot();
      try {
        final value = await change();
        _sortAndRecompute();
        final next = _snapshot();
        if (jsonEncode(before) == jsonEncode(next)) return value;
        try {
          await _store.write(jsonEncode(next));
        } catch (_) {
          throw const RecoverySaveException();
        }
        saveMessage = null;
        if (before['riskReminders'] != next['riskReminders'] ||
            jsonEncode(before['riskWindow']) !=
                jsonEncode(next['riskWindow']) ||
            jsonEncode(before['reminderMessages']) !=
                jsonEncode(next['reminderMessages']) ||
            before['dailySpend'] != next['dailySpend'] ||
            before['hideSensitiveNotifications'] !=
                next['hideSensitiveNotifications'] ||
            (before['events'] as List).length !=
                (next['events'] as List).length) {
          unawaited(_syncRiskNotifications());
        }
        if (jsonEncode(before['zones']) != jsonEncode(next['zones']) ||
            before['backgroundGeofencing'] != next['backgroundGeofencing']) {
          unawaited(_syncGeofences());
        }
        unawaited(syncWidget());
        _notify();
        return value;
      } catch (error) {
        _restoreSnapshot(before);
        if (error is RecoverySaveException) saveMessage = error.toString();
        _notify();
        rethrow;
      }
    });
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> appendEvent(RecoveryEvent event) => _transaction(() async {
    if (event.type == RecoveryEventType.relapse ||
        event.type == RecoveryEventType.recoveryStart) {
      throw StateError('Use the protected relapse flow for timer changes.');
    }
    if (events.any((existing) => existing.id == event.id)) {
      throw StateError('Duplicate event ID.');
    }
    events.add(event);
    _sortAndRecompute();
  });

  /// Records a finished or stopped Code Instead block. Validation lives in
  /// [RecoveryEvent.validateMetadata]; the UI decides what is worth keeping.
  Future<void> recordCodeSession({
    required Map<String, Object> metadata,
    required DateTime at,
  }) => appendEvent(
    RecoveryEvent.create(
      type: RecoveryEventType.codeSession,
      timestamp: at,
      metadata: metadata,
    ),
  );

  /// Records every milestone the current streak has reached but not yet
  /// logged, each stamped at the moment it was reached (last dose + N days),
  /// and queues one celebration for the highest. Cheap when nothing is due,
  /// so the shell can call it on a timer.
  Future<int?> syncMilestones() async {
    if (!isLoaded) return null;
    if (dueMilestones(
      events: events,
      lastDose: lastDose,
      now: _now(),
    ).isEmpty) {
      return null;
    }
    final reached = await _transaction(() {
      final due = dueMilestones(
        events: events,
        lastDose: lastDose,
        now: _now(),
      );
      if (due.isEmpty) return null;
      for (final milestone in due) {
        events.add(
          RecoveryEvent.create(
            type: RecoveryEventType.milestone,
            timestamp: lastDose.add(Duration(days: milestone.days)),
            metadata: {
              'days': milestone.days,
              'label': milestone.label,
              'source': 'auto',
            },
          ),
        );
      }
      _sortAndRecompute();
      return due.last.days;
    });
    if (reached != null) {
      pendingCelebration = reached;
      _notify();
    }
    return reached;
  }

  void consumeCelebration() {
    if (pendingCelebration == null) return;
    pendingCelebration = null;
    _notify();
  }

  Future<void> clearRelapseCooldown(String reason) => _transaction(() async {
    if (relapseCooldownUntil == null && relapseCooldownEventId == null) return;
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
  });

  Future<ProtectedActionResult> deleteEvent({
    required String id,
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
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
    return ProtectedActionResult.completed;
  });

  Future<ProtectedActionResult> editEventMetadata({
    required String id,
    required Map<String, dynamic> metadata,
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
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
    return ProtectedActionResult.completed;
  });

  Future<ProtectedActionResult> mergeImportedEvents(
    List<RecoveryEvent> importedEvents, {
    List<DangerZone> importedZones = const [],
    Map<String, dynamic>? preferences,
    bool restorePreferences = false,
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
    final authorization = await _authorizeProtectedAction(
      reason: 'Authenticate to merge recovery history.',
      pin: pin,
      tryBiometrics: tryBiometrics,
    );
    if (authorization != ProtectedActionResult.completed) return authorization;
    final existingIds = events.map((e) => e.id).toSet();
    for (final event in importedEvents) {
      if (existingIds.add(event.id)) events.add(event);
    }
    final zoneIds = zones.map((zone) => zone.id).toSet();
    final newZones = importedZones
        .where((zone) => zoneIds.add(zone.id))
        .toList();
    if (zones.length + newZones.length > DangerZone.maxZones) {
      throw StateError(
        'This backup would exceed ${DangerZone.maxZones} danger zones.',
      );
    }
    zones = [...zones, ...newZones];
    if (restorePreferences && preferences != null) {
      _restoreSettings(
        Map<String, dynamic>.from(preferences)
          ..remove('requirePinAfterRelapse')
          ..remove('riskWindowLock')
          ..remove('appLockPending')
          ..remove('zones')
          ..remove('zoneMonitoring')
          ..remove('streetTiles')
          ..remove('widgetPrivacy')
          ..remove('quietHoursEnabled')
          ..remove('quietHours')
          ..remove('hideSensitiveNotifications')
          ..remove('backgroundGeofencing')
          ..remove('pin'),
      );
    }
    _ensureBaselineEvent();
    _sortAndRecompute();
    return ProtectedActionResult.completed;
  });

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
    'peakHourLock': peakHourLock,
    'soundscape': soundscape,
    'hapticFeedback': hapticFeedback,
    'feedbackSound': feedbackSound.name,
    'intensity': intensity.name,
    'dashboardNoticeStyle': dashboardNoticeStyle.name,
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
    List<DateTime>? occurredAt,
    List<RelapseLogEntry>? entries,
    String? operationId,
    String source = 'app',
  }) {
    if (occurredAt != null && entries != null) {
      throw ArgumentError('Use occurredAt or entries, not both.');
    }
    final richEntries = entries == null
        ? null
        : (List<RelapseLogEntry>.of(entries)
            ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt)));
    final times = richEntries == null
        ? (List<DateTime>.of(occurredAt ?? [DateTime.now()])..sort())
        : richEntries.map((entry) => entry.occurredAt).toList();
    final batch = operationId ?? const Uuid().v4();
    return _transaction(() async {
      if (times.isEmpty ||
          times.length > 50 ||
          times.any(
            (at) => at.isBefore(DateTime(2000)) || at.isAfter(DateTime.now()),
          )) {
        throw ArgumentError('Choose 1–50 events, dated between 2000 and now.');
      }
      for (final entry in richEntries ?? const <RelapseLogEntry>[]) {
        entry.validate();
      }
      final authorization = await _authorizeProtectedAction(
        pin: pin,
        tryBiometrics: tryBiometrics,
        reason:
            'Authenticate to save these relapse events and update clean time.',
      );
      if (authorization != ProtectedActionResult.completed) {
        return authorization;
      }
      final existing = events
          .where((e) => e.metadata['batchId'] == batch)
          .toList();
      if (existing.isNotEmpty) {
        if (existing.length != times.length ||
            List.generate(
              times.length,
              (i) => existing[i].timestamp != times[i],
            ).any((v) => v)) {
          throw StateError(
            'This save request already contains different events.',
          );
        }
        return ProtectedActionResult.completed;
      }
      RecoveryEvent? latest;
      for (var index = 0; index < times.length; index++) {
        final at = times[index];
        final richEntry = richEntries?[index];
        final resets =
            events
                .where(
                  (e) =>
                      (e.type == RecoveryEventType.relapse ||
                          e.type == RecoveryEventType.recoveryStart) &&
                      !e.timestamp.isAfter(at),
                )
                .toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final lost = resets.isEmpty
            ? 0
            : at.difference(resets.last.timestamp).inDays;
        final postSos = events.any(
          (e) =>
              e.type == RecoveryEventType.sosComplete &&
              !e.timestamp.isAfter(at) &&
              at.difference(e.timestamp) <=
                  Duration(minutes: postSosWindowMinutes),
        );
        latest = RecoveryEvent.fromJson({
          'id': const Uuid().v5(
            Namespace.url.value,
            'no-lean/relapse/$batch/$index',
          ),
          'type': RecoveryEventType.relapse.name,
          'timestamp': at.toIso8601String(),
          'metadata': {
            'batchId': batch,
            'source': source,
            'recordedAt': DateTime.now().toIso8601String(),
            'postSos': postSos,
            'streakLost': lost,
            if (richEntry != null) ...richEntry.toMetadata(),
          },
        });
        if (events.any((e) => e.id == latest!.id)) {
          throw StateError('Event ID conflict.');
        }
        events.add(latest);
      }
      final deadline = latest!.timestamp.add(
        Duration(minutes: cooldownMinutes),
      );
      // Preserve the current debrief owner. Historical logs do not impose a
      // new cooldown, and another event does not extend an existing reset.
      if (relapseCooldownEventId == null && deadline.isAfter(DateTime.now())) {
        relapseCooldownUntil = deadline;
        relapseCooldownEventId = latest.id;
      }
      // Re-lock after every newly saved relapse so the next move is deliberate.
      if (requirePinAfterRelapse) appLockPending = true;
      return ProtectedActionResult.completed;
    });
  }

  Future<void> recordSosSession(SosSession session) => _transaction(() async {
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
  });

  Future<String> startSosSession({String? id, DateTime? startedAt}) =>
      _transaction(() async {
        final startId = id ?? const Uuid().v4();
        _ensureSosStart(startId, startedAt ?? DateTime.now());
        _sortAndRecompute();
        return startId;
      });

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
  }) => _transaction(() async {
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
  });

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

  DangerZone? zoneById(String id) =>
      zones.where((zone) => zone.id == id).firstOrNull;

  Future<DangerZone> addZone({
    required String name,
    required double latitude,
    required double longitude,
    double radiusMeters = DangerZone.defaultRadiusMeters,
  }) => _transaction(() async {
    if (zones.length >= DangerZone.maxZones) {
      throw StateError('You can keep up to ${DangerZone.maxZones} zones.');
    }
    final zone = DangerZone(
      id: const Uuid().v4(),
      name: name.trim(),
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      createdAt: _now(),
    )..validate();
    zones = [...zones, zone];
    return zone;
  });

  /// Renaming or widening a zone is free; shrinking it weakens protection
  /// and therefore authenticates like other protective changes.
  Future<ProtectedActionResult> updateZone(
    String id, {
    String? name,
    double? radiusMeters,
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
    final index = zones.indexWhere((zone) => zone.id == id);
    if (index == -1) return ProtectedActionResult.denied;
    final current = zones[index];
    if (radiusMeters != null && radiusMeters < current.radiusMeters) {
      final authorization = await _authorizeProtectedAction(
        pin: pin,
        tryBiometrics: tryBiometrics,
        reason: 'Authenticate to shrink a danger zone.',
      );
      if (authorization != ProtectedActionResult.completed) {
        return authorization;
      }
    }
    final next = current.copyWith(name: name, radiusMeters: radiusMeters);
    zones = [...zones]..[index] = next;
    return ProtectedActionResult.completed;
  });

  Future<ProtectedActionResult> deleteZone(
    String id, {
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
    if (zoneById(id) == null) return ProtectedActionResult.denied;
    final authorization = await _authorizeProtectedAction(
      pin: pin,
      tryBiometrics: tryBiometrics,
      reason: 'Authenticate to delete a danger zone.',
    );
    if (authorization != ProtectedActionResult.completed) return authorization;
    zones = zones.where((zone) => zone.id != id).toList();
    return ProtectedActionResult.completed;
  });

  /// Location monitoring is a privacy choice: switching it off never needs
  /// authentication, so the user can always stop location use in one tap.
  Future<void> setZoneMonitoring(bool enabled) => _transaction(() async {
    zoneMonitoring = enabled;
  });

  Future<void> setBackgroundGeofencing(bool enabled) => _transaction(() async {
    backgroundGeofencing = enabled;
  });

  /// Quiet hours mute non-critical notifications only; risk-window and
  /// danger-zone alerts always come through.
  Future<void> setQuietHours({required bool enabled, RiskWindow? window}) =>
      _transaction(() async {
        final next = window ?? notificationPrefs.quietHours;
        if (next.startMinutes == next.endMinutes) {
          throw ArgumentError('Quiet hours need a start and end that differ.');
        }
        notificationPrefs = NotificationPrefs(
          quietHoursEnabled: enabled,
          quietHours: next,
          hideSensitive: notificationPrefs.hideSensitive,
        );
        NotificationService.instance.prefs = notificationPrefs;
      });

  /// Home widget privacy; never needs authentication. The widget refreshes
  /// after the commit like every other change.
  Future<void> setWidgetPrivacy(bool enabled) =>
      _transaction(() async => widgetPrivacy = enabled);

  /// Lock-screen privacy; never needs authentication.
  Future<void> setHideSensitiveNotifications(bool hide) =>
      _transaction(() async {
        notificationPrefs = NotificationPrefs(
          quietHoursEnabled: notificationPrefs.quietHoursEnabled,
          quietHours: notificationPrefs.quietHours,
          hideSensitive: hide,
        );
        NotificationService.instance.prefs = notificationPrefs;
      });

  /// Network privacy choice; never needs authentication.
  Future<void> setStreetTiles(bool enabled) => _transaction(() async {
    streetTiles = enabled;
  });

  Future<void> _syncGeofences() async {
    try {
      if (backgroundGeofencing && zones.isNotEmpty) {
        await _geofences.sync(zones);
      } else {
        await _geofences.clear();
      }
    } catch (_) {
      /* Geofencing is optional; local history never depends on it. */
    }
  }

  Future<void> enableRelapseLock(String pin) => _transaction(() async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN must contain 4–8 digits.');
    }
    await _relapseLock.savePin(pin);
    requirePinAfterRelapse = true;
    // The risk-window wall is on by default whenever a PIN exists.
    riskWindowLock = true;
  });

  /// Clears an app lock (risk window or post-relapse) after authentication.
  Future<ProtectedActionResult> unlockApp({
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
    final authorization = await _authorizeProtectedAction(
      pin: pin,
      tryBiometrics: tryBiometrics,
      reason: 'Authenticate to unlock NO LEAN.',
    );
    if (authorization != ProtectedActionResult.completed) return authorization;
    appLockPending = false;
    return ProtectedActionResult.completed;
  });

  /// Enabling the risk-window wall is free; disabling it must authenticate.
  Future<ProtectedActionResult> setRiskWindowLock(
    bool enabled, {
    String? pin,
    bool tryBiometrics = true,
  }) => _transaction(() async {
    if (enabled == riskWindowLock) return ProtectedActionResult.completed;
    if (!enabled) {
      final authorization = await _authorizeProtectedAction(
        pin: pin,
        tryBiometrics: tryBiometrics,
        reason: 'Authenticate to turn off the risk-window lock.',
      );
      if (authorization != ProtectedActionResult.completed) {
        return authorization;
      }
    }
    riskWindowLock = enabled;
    events.add(
      RecoveryEvent.create(
        type: RecoveryEventType.settingsChange,
        metadata: {'setting': 'riskWindowLock', 'newValue': '$enabled'},
      ),
    );
    return ProtectedActionResult.completed;
  });

  Future<ProtectedActionResult> disableRelapseLock({
    String? pin,
    bool tryBiometrics = true,
  }) async {
    final result = await _transaction(() async {
      final authorization = await _authorizeProtectedAction(
        pin: pin,
        tryBiometrics: tryBiometrics,
        reason: 'Authenticate to disable the NO LEAN relapse lock.',
      );
      if (authorization != ProtectedActionResult.completed) {
        return authorization;
      }

      requirePinAfterRelapse = false;
      appLockPending = false;
      return ProtectedActionResult.completed;
    });
    if (result == ProtectedActionResult.completed) {
      await _relapseLock.clearPin();
    }
    return result;
  }

  Future<ProtectedActionResult> _authorizeProtectedAction({
    required String reason,
    String? pin,
    bool tryBiometrics = true,
  }) async {
    if (!requirePinAfterRelapse) return ProtectedActionResult.completed;
    if (pin != null) {
      return switch (await _relapseLock.verifyPin(pin)) {
        PinVerificationResult.verified => ProtectedActionResult.completed,
        PinVerificationResult.denied => ProtectedActionResult.denied,
        PinVerificationResult.lockedOut => ProtectedActionResult.lockedOut,
      };
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

  Future<void> updateReasons(List<String> value) => _transaction(() async {
    reasons = value.where((item) => item.trim().isNotEmpty).toList();
  });

  Future<void> updateReminders(List<String> value) => _transaction(() async {
    reminderMessages = value.where((item) => item.trim().isNotEmpty).toList();
  });

  Future<void> updateDailySpend(double value) => _transaction(() async {
    dailySpend = math.max(0, value);
  });

  Future<void> updateRiskWindow(RiskWindow value) => _transaction(() async {
    riskWindow = value;
  });

  Future<void> updatePostSosWindow(int minutes) => _transaction(() async {
    postSosWindowMinutes = minutes.clamp(15, 360).toInt();
    _recomputeDerivedState();
  });

  Future<void> updateCooldownMinutes(int minutes) => _transaction(() async {
    cooldownMinutes = minutes.clamp(1, 120).toInt();
  });

  Future<void> setSetting(String key, dynamic value) => _transaction(() async {
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
      case 'peakHourLock':
        if (peakHourLock != value) {
          peakHourLock = value as bool;
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
      case 'dashboardNoticeStyle':
        if (dashboardNoticeStyle != value) {
          dashboardNoticeStyle = value as DashboardNoticeStyle;
          changed = true;
        }
        break;
    }

    if (changed) {
      events.add(
        RecoveryEvent.create(
          type: RecoveryEventType.settingsChange,
          metadata: {'setting': key, 'newValue': value.toString()},
        ),
      );
    }
  });

  Future<void> updateFeedbackPreferences({
    required bool soundEnabled,
    required bool vibrationEnabled,
    required FeedbackSoundEffect soundEffect,
  }) => _transaction(() async {
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
      events.add(
        RecoveryEvent.create(
          type: RecoveryEventType.settingsChange,
          metadata: {'setting': 'feedbackPreferences'},
        ),
      );
    }
  });

  /// Reschedules alerts, e.g. after the user grants exact alarms.
  Future<void> resyncRiskNotifications() => _syncRiskNotifications();

  Future<void> _syncRiskNotifications() async {
    try {
      if (riskReminders) {
        await NotificationService.instance.scheduleRiskWindow(
          riskAlertPlan,
          riskWindow: riskWindow,
        );
      } else {
        await NotificationService.instance.cancelRiskWindow();
      }
    } catch (_) {
      /* Notifications never block local history. */
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
    privacy: widgetPrivacy,
  );
}
