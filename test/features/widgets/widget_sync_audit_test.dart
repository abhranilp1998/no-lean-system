import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/home_widget_payload.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/recovery/services/home_widget_service.dart';
import 'package:no_lean/features/widgets/presentation/widgets_screen.dart';
import 'package:no_lean/features/widgets/services/widget_choice_service.dart';

import '../../support/recovery_fakes.dart';
import '../cravings/craving_stress_recheck_test.dart' show pumpHost;

/// Widgets audit: what the app pushes to the home-screen widgets after each
/// kind of change, the shared wording, and the Widgets page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <Map<Object?, Object?>>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HomeWidgetService.channel, (call) async {
          if (call.method == 'update') {
            calls.add(Map<Object?, Object?>.from(call.arguments as Map));
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HomeWidgetService.channel, null),
  );

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<RecoveryController> load([String? stored]) async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(stored),
      relapseLock: FakeRelapseLock(),
    );
    await c.load();
    await settle();
    return c;
  }

  String stored({int daysAgo = 3, Map<String, Object?> extra = const {}}) =>
      jsonEncode({
        'stateVersion': 14,
        'events': [
          {
            'id': 'base',
            'type': 'recoveryStart',
            'timestamp': DateTime.now()
                .subtract(Duration(days: daysAgo))
                .toIso8601String(),
          },
        ],
        ...extra,
      });

  group('the app pushes fresh state to the widgets', () {
    test('on load, from an older (v14) save, with the pledge time', () async {
      final c = await load(stored());
      expect(calls, isNotEmpty);
      final p = calls.last;
      expect(p['privacy'], isFalse);
      expect(p['lastDoseEpochMillis'], c.lastDose.millisecondsSinceEpoch);
      expect(p['streak'], '3 DAYS CLEAN');
      // No pledge yet: the key is simply absent, never a bogus zero.
      expect(p.containsKey('lastPledgeEpochMillis'), isFalse);
    });

    test('after a pledge: the widget gets the pledge time', () async {
      final c = await load(stored());
      calls.clear();
      await c.pledge();
      await settle();
      expect(calls, isNotEmpty);
      expect(
        calls.last['lastPledgeEpochMillis'],
        c.lastPledge!.millisecondsSinceEpoch,
      );
      expect(calls.last['hasPledgedToday'], isTrue);
    });

    test('after logging a relapse the timer restarts on the widget', () async {
      final c = await load(stored());
      final before = calls.last['lastDoseEpochMillis']! as int;
      calls.clear();
      await c.recordRelapse();
      await settle();
      expect(calls, isNotEmpty);
      expect(
        calls.last['lastDoseEpochMillis'] as int,
        greaterThan(before + const Duration(days: 2).inMilliseconds),
      );
      expect(calls.last['streak'], '0 DAYS CLEAN');
    });

    test('after deleting that relapse the older timer is back', () async {
      final c = await load(stored());
      final original = calls.last['lastDoseEpochMillis']! as int;
      await c.recordRelapse();
      await settle();
      final relapse = c.events.lastWhere((e) => e.type.name == 'relapse');
      calls.clear();
      await c.deleteEvent(id: relapse.id);
      await settle();
      expect(calls, isNotEmpty);
      expect(calls.last['lastDoseEpochMillis'], original);
    });

    test('a new risk window reaches the widget minutes', () async {
      final c = await load(stored());
      calls.clear();
      await c.updateRiskWindow(
        const RiskWindow(startMinutes: 22 * 60, endMinutes: 2 * 60),
      );
      await settle();
      expect(calls.last['riskStartMinutes'], 22 * 60);
      expect(calls.last['riskEndMinutes'], 2 * 60);
    });

    test('privacy on: nothing recovery-specific is pushed', () async {
      final c = await load(stored());
      await c.pledge();
      calls.clear();
      await c.setWidgetPrivacy(true);
      await settle();
      final p = calls.last;
      expect(p['privacy'], isTrue);
      expect(p['lastDoseEpochMillis'], 0);
      expect(p.containsKey('lastPledgeEpochMillis'), isFalse);
      expect(p['streak'], '');
    });

    test(
      'after importing an older (format 7) backup the widget updates',
      () async {
        final c = await load(stored(daysAgo: 1));
        calls.clear();
        final importedStart = DateTime.now().subtract(const Duration(days: 40));
        final preview = BackupService().validateBackupJson(
          jsonEncode({
            'version': 7,
            'exportedAt': DateTime.now().toIso8601String(),
            'events': [
              {
                'id': 'old-base',
                'type': 'recoveryStart',
                'timestamp': importedStart.toIso8601String(),
              },
            ],
          }),
        );
        await c.mergeImportedEvents(preview.events);
        await settle();
        expect(calls, isNotEmpty);
        expect(c.cleanDuration.inDays, greaterThanOrEqualTo(39));
        expect(
          calls.last['lastDoseEpochMillis'],
          c.lastDose.millisecondsSinceEpoch,
        );
        expect(calls.last['streak'], '${c.streak} DAYS CLEAN');
      },
    );
  });

  group('wording', () {
    test('streak text is singular for exactly one day', () {
      expect(widgetStreakText(0), '0 DAYS CLEAN');
      expect(widgetStreakText(1), '1 DAY CLEAN');
      expect(widgetStreakText(2), '2 DAYS CLEAN');
      expect(widgetStreakText(365), '365 DAYS CLEAN');
    });

    test('Dart wording matches the native plural resource', () {
      final xml = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      final plural = RegExp(
        r'<plurals name="widget_clean_days">([\s\S]*?)</plurals>',
      ).firstMatch(xml)!.group(1)!;
      String item(String q) =>
          RegExp('quantity="$q">%d ([^<]*)<').firstMatch(plural)!.group(1)!;
      expect(widgetStreakText(1), '1 ${item('one')}');
      expect(widgetStreakText(5), '5 ${item('other')}');
    });

    test('payload carries the pledge time only when there is one', () {
      final at = DateTime.utc(2026, 11, 26, 8);
      final withPledge = homeWidgetPayload(
        lastDose: at,
        cleanTime: '1d',
        streak: 1,
        isRiskWindow: false,
        hasPledgedToday: true,
        privacy: false,
        lastPledge: at,
      );
      expect(withPledge['lastPledgeEpochMillis'], at.millisecondsSinceEpoch);
      final without = homeWidgetPayload(
        lastDose: at,
        cleanTime: '1d',
        streak: 1,
        isRiskWindow: false,
        hasPledgedToday: false,
        privacy: false,
      );
      expect(without.containsKey('lastPledgeEpochMillis'), isFalse);
      final private = homeWidgetPayload(
        lastDose: at,
        cleanTime: '1d',
        streak: 1,
        isRiskWindow: false,
        hasPledgedToday: true,
        privacy: true,
        lastPledge: at,
      );
      expect(private.containsKey('lastPledgeEpochMillis'), isFalse);
    });
  });

  group('native source stays honest', () {
    const kt = 'android/app/src/main/kotlin/com/nolean/no_lean';
    String read(String name) => File('$kt/$name').readAsStringSync();

    test('classic widget derives risk and pledge from its own clock', () {
      final src = read('NoLeanWidgetProvider.kt');
      expect(src, contains('WidgetPack.riskActive('));
      expect(src, contains('WidgetPack.pledgedToday('));
      expect(src, contains('KEY_LAST_PLEDGE_EPOCH_MILLIS'));
      // The old stored booleans stay only as the pre-first-sync fallback.
      expect(src, contains('KEY_IS_RISK_WINDOW'));
    });

    test('main activity stores the pledge time and clears it in privacy', () {
      final src = read('MainActivity.kt');
      expect(src, contains('"lastPledgeEpochMillis"'));
      expect(src, contains('KEY_LAST_PLEDGE_EPOCH_MILLIS'));
    });

    test('legacy garden and map widgets obey privacy mode', () {
      for (final name in [
        'GardenWidgetProvider.kt',
        'RadarWidgetProvider.kt',
      ]) {
        final src = read(name);
        expect(src, contains('NoLeanWidgetProvider.KEY_PRIVACY'), reason: name);
        expect(src, contains('R.string.widget_neutral'), reason: name);
      }
    });

    test('the 4x2 window-edge alarm is cancelled with the last widget', () {
      final src = read('NoLeanWidgetProvider.kt');
      expect(src, contains('ACTION_REFRESH_BOUNDARY, 70'));
    });

    test('2x1 counter shrinks to fit beside the SOS button', () {
      final xml = File(
        'android/app/src/main/res/layout/no_lean_widget_small.xml',
      ).readAsStringSync();
      final counter = RegExp(
        r'<Chronometer[\s\S]*?/>',
      ).firstMatch(xml)!.group(0)!;
      expect(counter, contains('autoSizeTextType="uniform"'));
      expect(counter, contains('layout_width="match_parent"'));
    });
  });

  group('Widgets page', () {
    String string(String name) {
      final xml = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();
      return RegExp('name="$name">([^<]*)<').firstMatch(xml)!.group(1)!;
    }

    testWidgets('previews use the real button labels from strings.xml', (
      tester,
    ) async {
      await pumpHost(
        tester,
        stored: stored(),
        child: (context, ref) =>
            WidgetsScreen(service: WidgetChoiceService(enabled: false)),
      );
      await tester.pumpAndSettle();
      for (final name in [
        'widget_action_sos',
        'widget_action_craving',
        'widget_action_relapse',
        'widget_action_code',
      ]) {
        // The large preview can sit below the fold once other cards are added.
        final label = find.text(string(name), skipOffstage: false);
        if (label.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.text(string(name)),
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(
          find.text(string(name), skipOffstage: false),
          findsWidgets,
          reason: name,
        );
      }
      expect(find.text('LOG RELAPSES'), findsNothing);
    });

    testWidgets('placed widgets reload when the user returns to the app', (
      tester,
    ) async {
      final service = _CountingService();
      await pumpHost(
        tester,
        stored: stored(),
        child: (context, ref) => WidgetsScreen(service: service),
      );
      await tester.pumpAndSettle();
      expect(service.loads, 1);
      expect(find.byKey(const Key('placed-widget-7')), findsNothing);

      service.placedNow = const [PlacedWidget(id: 7, kind: 'medium')];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(service.loads, 2);
      await tester.scrollUntilVisible(
        find.byKey(const Key('placed-widget-7')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('placed-widget-7')), findsOneWidget);
    });
  });
}

class _CountingService extends WidgetChoiceService {
  _CountingService() : super(enabled: false);
  int loads = 0;
  List<PlacedWidget> placedNow = const [];

  @override
  Future<List<PlacedWidget>> placed() async {
    loads++;
    return placedNow;
  }
}
