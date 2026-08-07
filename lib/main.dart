import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

const ink = Color(0xFF05060A);
const panel = Color(0xFF0B0F1A);
const panelRaised = Color(0xFF111726);
const cyan = Color(0xFF4DE8FF);
const magenta = Color(0xFFFF3DAF);
const purple = Color(0xFF9A5CFF);
const toxic = Color(0xFFB5FF5E);
const muted = Color(0xFF7B879E);
const red = Color(0xFFFF456A);

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

final recoveryProvider = ChangeNotifierProvider<RecoveryController>((ref) {
  return RecoveryController()..load();
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  // Keep the device awake only during debug investigation sessions; releases
  // must respect the user's normal display timeout and battery settings.
  if (kDebugMode) {
    unawaited(WakelockPlus.enable());
  }
  runApp(const ProviderScope(child: NoLeanApp()));
}

class NoLeanApp extends ConsumerWidget {
  const NoLeanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'NO LEAN',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: ink,
        colorScheme: const ColorScheme.dark(
          primary: cyan,
          secondary: magenta,
          surface: panel,
          error: red,
        ),
        textTheme: base.textTheme
            .apply(fontFamily: 'NoLeanMono')
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
        splashFactory: InkSparkle.splashFactory,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panelRaised.withValues(alpha: .8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cyan.withValues(alpha: .18)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cyan.withValues(alpha: .18)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: cyan),
          ),
          labelStyle: const TextStyle(color: muted),
        ),
      ),
      home: const Shell(),
    );
  }
}

enum EffectIntensity { calm, standard, aggressive }

class CravingEntry {
  CravingEntry({
    required this.intensity,
    required this.trigger,
    required this.note,
    required this.createdAt,
  });

  final int intensity;
  final String trigger;
  final String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'intensity': intensity,
    'trigger': trigger,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CravingEntry.fromJson(Map<String, dynamic> json) => CravingEntry(
    intensity: json['intensity'] as int? ?? 5,
    trigger: json['trigger'] as String? ?? 'Other',
    note: json['note'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

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

  Future<void> syncWidget() async {
    try {
      final value = formatDuration(cleanDuration, compact: true);
      await const MethodChannel('no_lean/widget').invokeMethod<void>(
        'update',
        <String, String>{'cleanTime': value, 'streak': '$streak DAYS'},
      );
    } catch (_) {
      // Widget support is optional on unsupported launchers; core tracking stays local.
    }
  }
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int tab = 0;
  final pages = const [
    DashboardScreen(),
    CravingsScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(recoveryProvider);
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBackground(
            risk: data.isRiskWindow,
            scanlines: data.scanlines && !data.reduceMotion,
          ),
          SafeArea(
            child: IndexedStack(index: tab, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        backgroundColor: panel.withValues(alpha: .96),
        indicatorColor: cyan.withValues(alpha: .15),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer, color: cyan),
            label: 'Counter',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt, color: cyan),
            label: 'Cravings',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: cyan),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune, color: cyan),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class AnimatedBackground extends StatelessWidget {
  const AnimatedBackground({
    required this.risk,
    required this.scanlines,
    super.key,
  });

  final bool risk;
  final bool scanlines;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: BackgroundPainter(risk: risk, scanlines: scanlines),
        ),
      ),
    );
  }
}

class BackgroundPainter extends CustomPainter {
  BackgroundPainter({required this.risk, required this.scanlines});
  final bool risk;
  final bool scanlines;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: risk
          ? [ink, const Color(0xFF190B16), const Color(0xFF090811)]
          : [ink, const Color(0xFF080D19), const Color(0xFF110A1D)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
    glow.color = (risk ? red : cyan).withValues(alpha: .08);
    canvas.drawCircle(Offset(size.width * .75, size.height * .12), 170, glow);
    glow.color = purple.withValues(alpha: .06);
    canvas.drawCircle(Offset(size.width * .15, size.height * .78), 210, glow);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (scanlines) {
      final line = Paint()..color = Colors.white.withValues(alpha: .018);
      for (var y = 0.0; y < size.height; y += 5) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundPainter oldDelegate) =>
      oldDelegate.risk != risk || oldDelegate.scanlines != scanlines;
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(recoveryProvider);
    final duration = data.cleanDuration;
    return RefreshIndicator(
      color: cyan,
      backgroundColor: panel,
      onRefresh: () async => ref.read(recoveryProvider).syncWidget(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        children: [
          const BrandHeader(),
          const SizedBox(height: 22),
          if (data.isRiskWindow) const RiskWindowBanner(),
          if (data.isRiskWindow) const SizedBox(height: 14),
          Text('THE COUNTER', style: eyebrowStyle.copyWith(color: cyan)),
          const SizedBox(height: 6),
          Text(
            'No debate. No purchase.',
            style: displayFont(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 18),
          GlassCard(
            accent: data.isRiskWindow ? red : cyan,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusPill(
                      label: data.isRiskWindow
                          ? 'RISK WINDOW'
                          : 'SYSTEM STABLE',
                      color: data.isRiskWindow ? red : toxic,
                    ),
                    Text(
                      'LIVE SINCE ${DateFormat('MMM d • HH:mm').format(data.lastDose)}',
                      style: microStyle,
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                AnimatedCounter(
                  duration: duration,
                  reduceMotion: data.reduceMotion,
                ),
                const SizedBox(height: 25),
                Text(
                  'CLEAN TIME',
                  style: eyebrowStyle.copyWith(
                    color: muted,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlowButton(
            label: 'I WILL NOT BUY LEAN TODAY',
            icon: Icons.lock_outline,
            color: magenta,
            onTap: () => showPledgeDialog(context, ref),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'CURRENT STREAK',
                  value: '${data.streak}D',
                  detail: 'Keep the line clean',
                  color: cyan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'MONEY SAVED',
                  value: money(data.moneySaved),
                  detail: 'At ${money(data.dailySpend)} / day',
                  color: toxic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'LONGEST STREAK',
                  value: '${data.longestStreak}D',
                  detail: 'Beat your record',
                  color: purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'LOGGED CRAVINGS',
                  value: '${data.cravings.length}',
                  detail: 'Awareness is data',
                  color: magenta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('FAST INTERRUPTS', style: eyebrowStyle.copyWith(color: muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ActionTile(
                  icon: Icons.sos,
                  title: 'SOS MODE',
                  subtitle: '60 sec override',
                  color: red,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmergencyScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionTile(
                  icon: Icons.bolt,
                  title: 'LOG CRAVING',
                  subtitle: 'Name the trigger',
                  color: cyan,
                  onTap: () => showCravingDialog(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ActionTile(
            icon: Icons.code,
            title: 'CODE INSTEAD',
            subtitle: 'A small task beats a big spiral',
            color: purple,
            onTap: () => showCodeChallenge(context),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'TODAY\'S CHECK-IN',
            action: 'OPEN',
            onTap: () => showCheckInDialog(context, ref),
          ),
          const SizedBox(height: 10),
          GlassCard(
            accent:
                data.lastPledge != null &&
                    DateUtils.isSameDay(data.lastPledge, DateTime.now())
                ? toxic
                : magenta,
            child: Row(
              children: [
                Icon(
                  data.lastPledge != null &&
                          DateUtils.isSameDay(data.lastPledge, DateTime.now())
                      ? Icons.verified
                      : Icons.pending_actions,
                  color:
                      data.lastPledge != null &&
                          DateUtils.isSameDay(data.lastPledge, DateTime.now())
                      ? toxic
                      : magenta,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.lastPledge != null &&
                            DateUtils.isSameDay(data.lastPledge, DateTime.now())
                        ? 'Pledge locked for today. You made the decision before the urge.'
                        : 'Morning pledge is still open. Make the decision while it is yours.',
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: cyan.withValues(alpha: .25), blurRadius: 20),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/no_lean_icon.png'),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NO LEAN',
              style: displayFont(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text('PERSONAL OVERRIDE SYSTEM', style: microStyle),
          ],
        ),
        const Spacer(),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: toxic,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: toxic, blurRadius: 12)],
          ),
        ),
      ],
    );
  }
}

class RiskWindowBanner extends StatelessWidget {
  const RiskWindowBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: red.withValues(alpha: .08),
        border: Border.all(color: red.withValues(alpha: .42)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: red, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'RISK WINDOW  /  17:30—20:00  /  STAY MOVING',
              style: microStyle.copyWith(color: red, letterSpacing: .7),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    required this.duration,
    required this.reduceMotion,
    super.key,
  });
  final Duration duration;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CounterBlock(
            value: days.toString().padLeft(2, '0'),
            label: 'DAYS',
            accent: cyan,
          ),
          const CounterDivider(),
          CounterBlock(
            value: hours.toString().padLeft(2, '0'),
            label: 'HRS',
            accent: cyan,
          ),
          const CounterDivider(),
          CounterBlock(
            value: minutes.toString().padLeft(2, '0'),
            label: 'MIN',
            accent: purple,
          ),
          const CounterDivider(),
          CounterBlock(
            value: seconds.toString().padLeft(2, '0'),
            label: 'SEC',
            accent: magenta,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class CounterBlock extends StatelessWidget {
  const CounterBlock({
    required this.value,
    required this.label,
    required this.accent,
    this.compact = false,
    super.key,
  });
  final String value;
  final String label;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: displayFont(
          fontSize: compact ? 32 : 38,
          fontWeight: FontWeight.w700,
          color: accent,
          letterSpacing: -2,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: microStyle.copyWith(
          color: accent.withValues(alpha: .75),
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}

class CounterDivider extends StatelessWidget {
  const CounterDivider({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
    child: Text(':', style: displayFont(fontSize: 24, color: muted)),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.accent = cyan,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });
  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: panel.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent.withValues(alpha: .26)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: .07),
          blurRadius: 24,
          spreadRadius: -3,
        ),
      ],
    ),
    child: child,
  );
}

class GlowButton extends StatelessWidget {
  const GlowButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: .28), blurRadius: 18),
      ],
    ),
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon ?? Icons.arrow_forward, size: 18),
      label: Text(
        label,
        style: displayFont(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: .16),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .72)),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    super.key,
  });
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => GlassCard(
    accent: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: microStyle.copyWith(color: color)),
        const SizedBox(height: 9),
        Text(
          value,
          style: displayFont(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          style: TextStyle(fontSize: 10.5, color: muted.withValues(alpha: .9)),
        ),
      ],
    ),
  );
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: GlassCard(
      accent: color,
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: displayFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: muted),
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.color, super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      border: Border.all(color: color.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: microStyle.copyWith(color: color, fontSize: 9, letterSpacing: .7),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    required this.action,
    required this.onTap,
    super.key,
  });
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: eyebrowStyle.copyWith(color: muted)),
      TextButton(
        onPressed: onTap,
        child: Text(action, style: microStyle.copyWith(color: cyan)),
      ),
    ],
  );
}

class CravingsScreen extends ConsumerWidget {
  const CravingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(recoveryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('CRAVING LOG', style: eyebrowStyle.copyWith(color: magenta)),
        const SizedBox(height: 7),
        Text(
          'Name the pattern.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        const Text(
          'A craving is a signal, not an instruction. Log it while it is happening so your future self has evidence.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 18),
        GlowButton(
          label: 'LOG A CRAVING',
          icon: Icons.add,
          color: magenta,
          onTap: () => showCravingDialog(context, ref),
        ),
        const SizedBox(height: 22),
        SectionHeader(
          title: 'RECENT SIGNALS',
          action: '${data.cravings.length} TOTAL',
          onTap: () {},
        ),
        if (data.cravings.isEmpty)
          GlassCard(
            accent: muted,
            child: const Text(
              'No cravings logged yet. When the next one hits, put it here before you make a move.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ...data.cravings.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CravingTile(entry: entry),
          ),
        ),
      ],
    );
  }
}

class CravingTile extends StatelessWidget {
  const CravingTile({required this.entry, super.key});
  final CravingEntry entry;
  @override
  Widget build(BuildContext context) {
    final color = entry.intensity >= 8
        ? red
        : entry.intensity >= 6
        ? magenta
        : cyan;
    return GlassCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label: entry.trigger.toUpperCase(), color: color),
              const Spacer(),
              Text(
                DateFormat('MMM d  •  HH:mm').format(entry.createdAt),
                style: microStyle,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Text(
                '${entry.intensity}',
                style: displayFont(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text('/ 10 INTENSITY', style: microStyle.copyWith(color: muted)),
            ],
          ),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry.note,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(recoveryProvider);
    final maxIntensity = data.cravings.isEmpty
        ? 0
        : data.cravings.map((entry) => entry.intensity).reduce(math.max);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('PROGRESS', style: eyebrowStyle.copyWith(color: purple)),
        const SizedBox(height: 7),
        Text(
          'Evidence beats vibes.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        GlassCard(
          accent: purple,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CLEAN DAYS / LAST 30',
                style: microStyle.copyWith(color: purple),
              ),
              const SizedBox(height: 18),
              CleanHeatMap(cleanDays: data.cleanDays),
              const SizedBox(height: 14),
              Row(
                children: [
                  const StatusPill(label: 'ACTIVE', color: toxic),
                  const SizedBox(width: 8),
                  Text(
                    '${data.streak} day current streak',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          accent: cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CRAVING INTENSITY',
                style: microStyle.copyWith(color: cyan),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                child: IntensityChart(entries: data.cravings),
              ),
              const SizedBox(height: 8),
              Text(
                data.cravings.isEmpty
                    ? 'Log signals to reveal your triggers.'
                    : 'Peak logged intensity: $maxIntensity / 10',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('MILESTONE TRACKER', style: eyebrowStyle.copyWith(color: muted)),
        const SizedBox(height: 10),
        const MilestoneRow(days: 3, label: 'BREAK THE LOOP', color: cyan),
        const MilestoneRow(days: 7, label: 'FIRST WEEK', color: purple),
        const MilestoneRow(
          days: 14,
          label: 'HABIT PRESSURE DROPS',
          color: magenta,
        ),
        const MilestoneRow(days: 30, label: 'NEW BASELINE', color: toxic),
        const MilestoneRow(days: 60, label: 'SYSTEM REBUILT', color: cyan),
        const MilestoneRow(days: 90, label: 'LONG GAME', color: purple),
      ],
    );
  }
}

class CleanHeatMap extends StatelessWidget {
  const CleanHeatMap({required this.cleanDays, super.key});
  final Map<String, bool> cleanDays;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: List.generate(30, (index) {
        final day = today.subtract(Duration(days: 29 - index));
        final status = cleanDays[dateKey(day)];
        final color = status == true
            ? cyan.withValues(alpha: .85)
            : status == false
            ? red.withValues(alpha: .65)
            : panelRaised;
        return Container(
          width: 19,
          height: 19,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class IntensityChart extends StatelessWidget {
  const IntensityChart({required this.entries, super.key});
  final List<CravingEntry> entries;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: ChartPainter(
      entries.map((entry) => entry.intensity.toDouble()).toList(),
    ),
    child: const SizedBox.expand(),
  );
}

class ChartPainter extends CustomPainter {
  ChartPainter(this.points);
  final List<double> points;
  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = muted.withValues(alpha: .18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axis,
    );
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), axis);
    if (points.isEmpty) return;
    final line = Paint()
      ..color = cyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [cyan.withValues(alpha: .22), Colors.transparent],
      ).createShader(Offset.zero & size);
    final path = Path();
    final area = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1 ? 0.0 : i * size.width / (points.length - 1);
      final y = size.height - (points[i] / 10) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area.lineTo(size.width, size.height);
    area.close();
    canvas.drawPath(area, fill);
    canvas.drawPath(path, line);
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1 ? 0.0 : i * size.width / (points.length - 1);
      final y = size.height - (points[i] / 10) * size.height;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = panel);
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = cyan);
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class MilestoneRow extends ConsumerWidget {
  const MilestoneRow({
    required this.days,
    required this.label,
    required this.color,
    super.key,
  });
  final int days;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(recoveryProvider).streak;
    final done = current >= days;
    final progress = (current / days).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        accent: done ? color : muted,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? color : muted,
              size: 19,
            ),
            const SizedBox(width: 11),
            SizedBox(
              width: 42,
              child: Text(
                '${days}D',
                style: displayFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? color : Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: panelRaised,
                    color: color,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              done ? 'CLEARED' : '${(progress * 100).round()}%',
              style: microStyle.copyWith(color: done ? color : muted),
            ),
          ],
        ),
      ),
    );
  }
}

class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});
  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  Timer? timer;
  int remaining = 60;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (remaining <= 1) {
        timer?.cancel();
        setState(() {
          remaining = 0;
          finished = true;
        });
      } else {
        setState(() => remaining--);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(recoveryProvider);
    final phase = remaining > 45
        ? 'BREATHE IN'
        : remaining > 30
        ? 'HOLD THE LINE'
        : remaining > 15
        ? 'BREATHE OUT'
        : 'LET THE WAVE PASS';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: SosPainter(remaining))),
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.close, color: Colors.transparent),
                    ),
                    const Spacer(),
                    StatusPill(label: 'SYSTEM OVERRIDE', color: red),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: red),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'SOS MODE',
                  textAlign: TextAlign.center,
                  style: displayFont(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: red,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'DO NOT BUY. DO NOT DRIVE. STAY HERE.',
                  textAlign: TextAlign.center,
                  style: microStyle.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  height: 246,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: remaining / 60,
                          strokeWidth: 7,
                          color: red,
                          backgroundColor: red.withValues(alpha: .12),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$remaining',
                            style: displayFont(
                              fontSize: 70,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'SECONDS',
                            style: microStyle.copyWith(color: red),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  phase,
                  textAlign: TextAlign.center,
                  style: displayFont(
                    fontSize: 15,
                    color: red,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 30),
                GlassCard(
                  accent: red,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHY YOU ARE DONE WITH THIS',
                        style: microStyle.copyWith(color: red),
                      ),
                      const SizedBox(height: 12),
                      if (data.reasons.isEmpty)
                        const Text(
                          'No reasons saved yet. Add them in Settings before the next risk window.',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.35,
                          ),
                        )
                      else
                        ...data.reasons.map(
                          (reason) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '—',
                                  style: TextStyle(
                                    color: red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (!finished)
                  Text(
                    'The urge peaks, then drops. Give it the minute it is asking for.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                if (finished) ...[
                  const Text(
                    'You stayed for the wave. Lock in the next decision before you leave.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: toxic,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlowButton(
                    label: 'I WILL NOT BUY LEAN TODAY',
                    icon: Icons.lock_outline,
                    color: toxic,
                    onTap: () async {
                      await ref.read(recoveryProvider).pledge();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SosPainter extends CustomPainter {
  SosPainter(this.remaining);
  final int remaining;
  @override
  void paint(Canvas canvas, Size size) {
    final pulse = .06 + (remaining % 2) * .03;
    final paint = Paint()
      ..color = red.withValues(alpha: pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(Offset(size.width / 2, 260), 160, paint);
    final line = Paint()
      ..color = red.withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant SosPainter oldDelegate) =>
      oldDelegate.remaining != remaining;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(recoveryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('SETTINGS', style: eyebrowStyle.copyWith(color: cyan)),
        const SizedBox(height: 7),
        Text(
          'Tune the override.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 22),
        SettingsSection(
          title: 'PERSONAL DATA',
          children: [
            SettingAction(
              icon: Icons.edit_note,
              title: 'Reasons for quitting',
              subtitle: '${data.reasons.length} reasons loaded',
              color: magenta,
              onTap: () => showReasonsDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.notifications_active_outlined,
              title: 'Reminder messages',
              subtitle: '${data.reminderMessages.length} blunt reminders',
              color: cyan,
              onTap: () => showReminderDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.payments_outlined,
              title: 'Average daily spend',
              subtitle: '${money(data.dailySpend)} per day',
              color: toxic,
              onTap: () => showSpendDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.ios_share,
              title: 'Export recovery data',
              subtitle: 'Portable JSON file',
              color: purple,
              onTap: () => exportData(context, data),
            ),
          ],
        ),
        SettingsSection(
          title: 'INTERFACE',
          children: [
            SettingToggle(
              title: 'CRT scanlines',
              subtitle: 'Subtle display texture',
              value: data.scanlines,
              color: cyan,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('scanlines', value),
            ),
            SettingToggle(
              title: 'Reduce motion',
              subtitle: 'Softer transitions and glow',
              value: data.reduceMotion,
              color: toxic,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('reduceMotion', value),
            ),
            SettingToggle(
              title: 'High contrast',
              subtitle: 'Increase edge and text separation',
              value: data.highContrast,
              color: purple,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('highContrast', value),
            ),
            SettingIntensity(
              value: data.intensity,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('intensity', value),
            ),
          ],
        ),
        SettingsSection(
          title: 'PROTECTION',
          children: [
            SettingToggle(
              title: 'Risk-window reminders',
              subtitle: 'Enable the 17:30—20:00 interrupt window',
              value: data.riskReminders,
              color: red,
              onChanged: (value) async {
                await ref
                    .read(recoveryProvider)
                    .setSetting('riskReminders', value);
                if (value) {
                  await NotificationService.instance.scheduleRiskWindow(
                    data.reminderMessages,
                  );
                } else {
                  await NotificationService.instance.cancelRiskWindow();
                }
              },
            ),
            SettingToggle(
              title: 'Relapse lock',
              subtitle: data.requirePinAfterRelapse
                  ? 'PIN gate enabled'
                  : 'Protect history after a relapse',
              value: data.requirePinAfterRelapse,
              color: magenta,
              onChanged: (value) => showPinSetup(context, ref, value),
            ),
            SettingAction(
              icon: Icons.fingerprint,
              title: 'Test device biometrics',
              subtitle: 'Use fingerprint / face unlock when available',
              color: cyan,
              onTap: () => testBiometrics(context),
            ),
          ],
        ),
        SettingsSection(
          title: 'ABOUT THE BUILD',
          children: [
            GlassCard(
              accent: muted,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NO LEAN  /  MVP 01',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Offline-first recovery tracking with a direct voice, local data, a risk-window interrupt, SOS breathing timer, data export, and Android widget support.',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: eyebrowStyle.copyWith(color: muted)),
        const SizedBox(height: 9),
        ...children.map(
          (child) =>
              Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
        ),
      ],
    ),
  );
}

class SettingAction extends StatelessWidget {
  const SettingAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: GlassCard(
      accent: color,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: muted, size: 18),
        ],
      ),
    ),
  );
}

class SettingToggle extends StatelessWidget {
  const SettingToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
    super.key,
  });
  final String title;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => GlassCard(
    accent: value ? color : muted,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 10.5, color: muted),
      ),
      value: value,
      activeThumbColor: color,
      onChanged: onChanged,
    ),
  );
}

class SettingIntensity extends StatelessWidget {
  const SettingIntensity({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final EffectIntensity value;
  final ValueChanged<EffectIntensity> onChanged;
  @override
  Widget build(BuildContext context) => GlassCard(
    accent: purple,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('EFFECT INTENSITY', style: microStyle.copyWith(color: purple)),
        const SizedBox(height: 10),
        SegmentedButton<EffectIntensity>(
          segments: const [
            ButtonSegment(value: EffectIntensity.calm, label: Text('CALM')),
            ButtonSegment(
              value: EffectIntensity.standard,
              label: Text('STANDARD'),
            ),
            ButtonSegment(
              value: EffectIntensity.aggressive,
              label: Text('AGGRESSIVE'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 9, fontFamily: 'NoLeanMono'),
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: purple.withValues(alpha: .35)),
            ),
          ),
        ),
      ],
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({required this.title, required this.child, super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: cyan.withValues(alpha: .3)),
    ),
    title: Text(
      title,
      style: displayFont(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    content: child,
  );
}

Future<void> showPledgeDialog(BuildContext context, WidgetRef ref) async {
  final confirm =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'LOCK TODAY\'S DECISION',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You do not need to feel ready. You need to make one clean decision before the risk window makes it for you.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('NOT YET'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(backgroundColor: magenta),
                    child: const Text('LOCK IT'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (confirm && context.mounted) {
    await ref.read(recoveryProvider).pledge();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PLEDGE LOCKED. KEEP MOVING.'),
        backgroundColor: Color(0xFF42152F),
      ),
    );
  }
}

Future<void> showCravingDialog(BuildContext context, WidgetRef ref) async {
  var intensity = 6.0;
  var trigger = 'After Work';
  final note = TextEditingController();
  const triggers = [
    'After Work',
    'Boredom',
    'Muscle Tension',
    'Loneliness',
    'Office Stress',
    'Habit',
    'Other',
  ];
  final entry = await showDialog<CravingEntry>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AppDialog(
        title: 'LOG THE SIGNAL',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Intensity  /  ${intensity.round()} of 10',
                style: const TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Slider(
                value: intensity,
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: intensity >= 8 ? red : cyan,
                onChanged: (value) => setState(() => intensity = value),
              ),
              const SizedBox(height: 4),
              const Text('TRIGGER', style: microStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: triggers
                    .map(
                      (item) => ChoiceChip(
                        label: Text(item, style: const TextStyle(fontSize: 10)),
                        selected: trigger == item,
                        selectedColor: magenta.withValues(alpha: .25),
                        onSelected: (_) => setState(() => trigger = item),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What is actually happening?',
                  hintText: 'Name the moment, not the story.',
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    // Close the route first. Persisting while this dialog is
                    // deactivating causes Flutter's inherited-element
                    // lifecycle assertion in debug mode.
                    Navigator.pop(
                      dialogContext,
                      CravingEntry(
                        intensity: intensity.round(),
                        trigger: trigger,
                        note: note.text.trim(),
                        createdAt: DateTime.now(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(backgroundColor: magenta),
                  child: const Text('LOG IT'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  note.dispose();
  if (entry != null && context.mounted) {
    await ref.read(recoveryProvider).recordCraving(entry);
  }
}

Future<void> showCheckInDialog(BuildContext context, WidgetRef ref) async {
  final stayedClean = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'EVENING CHECK-IN',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Did you stay clean today?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: GlowButton(
              label: 'YES — I STAYED CLEAN',
              color: toxic,
              icon: Icons.check,
              onTap: () => Navigator.pop(dialogContext, true),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'NO — RECORD A RELAPSE',
              style: TextStyle(color: red),
            ),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (stayedClean == true) {
    await ref.read(recoveryProvider).pledge();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CHECK-IN SAVED. SAME DECISION TOMORROW.'),
          backgroundColor: Color(0xFF223C1B),
        ),
      );
    }
  } else if (stayedClean == false) {
    await showRelapseDialog(context, ref);
  }
}

Future<void> showRelapseDialog(BuildContext context, WidgetRef ref) async {
  final confirm =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'RECORD THE FACTS',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This resets the timer. It does not erase the data. Record it, learn from the chain, and start the next clean minute.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('CANCEL'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(backgroundColor: red),
                    child: const Text('RESET TIMER'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (confirm) {
    await ref.read(recoveryProvider).recordRelapse();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TIMER RESET. NO HIDING. START THE NEXT CLEAN MINUTE.'),
          backgroundColor: Color(0xFF431522),
        ),
      );
    }
  }
}

Future<void> showCodeChallenge(BuildContext context) async {
  const challenges = [
    'Write a function that reverses a string without using built-in reverse helpers.',
    'Build a tiny CLI that prints the current time in three time zones.',
    'Refactor one function you wrote today into two smaller functions.',
    'Solve FizzBuzz, then add a custom rule for multiples of seven.',
  ];
  final task = challenges[DateTime.now().second % challenges.length];
  await showDialog(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'CODE INSTEAD',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusPill(label: '10 MINUTE TASK', color: purple),
          const SizedBox(height: 14),
          Text(task, style: const TextStyle(fontSize: 13, height: 1.45)),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: const Text('START'),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showReasonsDialog(BuildContext context, WidgetRef ref) async {
  final controllers = ref
      .read(recoveryProvider)
      .reasons
      .map((text) => TextEditingController(text: text))
      .toList();
  final updatedReasons = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'WHY YOU ARE DONE',
      child: StatefulBuilder(
        builder: (_, setState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final controller in controllers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Reason',
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => controllers.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ADD REASON'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      controllers.map((item) => item.text).toList(),
                    );
                  },
                  child: const Text('SAVE REASONS'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  for (final controller in controllers) {
    controller.dispose();
  }
  if (updatedReasons != null && context.mounted) {
    await ref.read(recoveryProvider).updateReasons(updatedReasons);
  }
}

Future<void> showReminderDialog(BuildContext context, WidgetRef ref) async {
  final controllers = ref
      .read(recoveryProvider)
      .reminderMessages
      .map((text) => TextEditingController(text: text))
      .toList();
  final updatedMessages = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'RISK-WINDOW MESSAGES',
      child: StatefulBuilder(
        builder: (_, setState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final controller in controllers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextField(
                    controller: controller,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Reminder',
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => controllers.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ADD MESSAGE'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      controllers.map((item) => item.text).toList(),
                    );
                  },
                  child: const Text('SAVE MESSAGES'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  for (final controller in controllers) {
    controller.dispose();
  }
  if (updatedMessages != null && context.mounted) {
    await ref.read(recoveryProvider).updateReminders(updatedMessages);
  }
}

Future<void> showSpendDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(
    text: ref.read(recoveryProvider).dailySpend > 0
        ? ref.read(recoveryProvider).dailySpend.round().toString()
        : '',
  );
  final updatedSpend = await showDialog<double>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'AVERAGE DAILY SPEND',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              prefixText: '₹  ',
              labelText: 'Amount per day',
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                double.tryParse(controller.text) ?? 0,
              ),
              child: const Text('SAVE'),
            ),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (updatedSpend != null && context.mounted) {
    await ref.read(recoveryProvider).updateDailySpend(updatedSpend);
  }
}

Future<void> showPinSetup(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  if (!enabled) {
    await ref
        .read(recoveryProvider)
        .setSetting('requirePinAfterRelapse', false);
    return;
  }
  final controller = TextEditingController();
  final enteredPin = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'SET RELAPSE LOCK PIN',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: '4–6 digit PIN'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                if (controller.text.length < 4) return;
                // Return the value first. Persisting while the dialog route is
                // being deactivated triggers Flutter's inherited-element
                // lifecycle assertion in debug mode.
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('ENABLE'),
            ),
          ),
        ],
      ),
    ),
  );
  if (enteredPin != null && context.mounted) {
    final data = ref.read(recoveryProvider);
    data.pin = enteredPin;
    await data.setSetting('requirePinAfterRelapse', true);
  }
  controller.dispose();
}

Future<void> testBiometrics(BuildContext context) async {
  try {
    final auth = LocalAuthentication();
    final available =
        await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          available
              ? 'BIOMETRIC HARDWARE DETECTED.'
              : 'NO BIOMETRIC AUTHENTICATOR AVAILABLE ON THIS DEVICE.',
        ),
        backgroundColor: available
            ? const Color(0xFF223C1B)
            : const Color(0xFF431522),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BIOMETRIC CHECK UNAVAILABLE.')),
      );
    }
  }
}

Future<void> exportData(BuildContext context, RecoveryController data) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/no_lean_recovery_export.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'lastDose': data.lastDose.toIso8601String(),
        'currentStreakDays': data.streak,
        'longestStreakDays': data.longestStreak,
        'dailySpend': data.dailySpend,
        'cravings': data.cravings.map((entry) => entry.toJson()).toList(),
        'reasons': data.reasons,
      }),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'NO LEAN recovery export',
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EXPORT FAILED. YOUR LOCAL DATA IS STILL INTACT.'),
        ),
      );
    }
  }
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    try {
      final zone = await const MethodChannel(
        'no_lean/timezone',
      ).invokeMethod<String>('get');
      if (zone != null) {
        tz.setLocalLocation(tz.getLocation(zone));
      }
    } catch (_) {
      // UTC is the safe fallback if a platform does not expose its IANA zone.
    }
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('no_lean_icon'),
      ),
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> scheduleRiskWindow(List<String> messages) async {
    await _initialize();
    try {
      await cancelRiskWindow();
      if (messages.isEmpty) return;
      const moments = [17 * 60 + 30, 18 * 60 + 15, 19 * 60, 19 * 60 + 45];
      for (var index = 0; index < moments.length; index++) {
        final message = messages[index % messages.length];
        final hour = moments[index] ~/ 60;
        final minute = moments[index] % 60;
        final now = tz.TZDateTime.now(tz.local);
        var scheduled = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
        if (!scheduled.isAfter(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
        }
        await plugin.zonedSchedule(
          500 + index,
          'NO LEAN / RISK WINDOW',
          message,
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'risk_window',
              'Risk window',
              channelDescription:
                  'Direct NO LEAN interrupts from 17:30 to 20:00',
              importance: Importance.max,
              priority: Priority.high,
              color: red,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {}
  }

  Future<void> cancelRiskWindow() async {
    for (var id = 500; id < 504; id++) {
      await plugin.cancel(id);
    }
  }
}

String money(num value) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
).format(value);

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String formatDuration(Duration duration, {bool compact = false}) {
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24).toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return compact
      ? '${days}d ${hours}h ${minutes}m'
      : '$days days, $hours:$minutes:$seconds';
}

const eyebrowStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.4,
);
const microStyle = TextStyle(fontSize: 9.5, color: muted, letterSpacing: .45);

TextStyle displayFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'NoLeanDisplay',
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  letterSpacing: letterSpacing,
);
