import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/app_lock/domain/native_config.dart';
import 'package:no_lean/features/app_lock/domain/never_lockable.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';

void main() {
  const risk = RiskWindow.defaultWindow(); // 17:00-21:00
  const chat = LockedApp(packageName: 'com.example.chat', label: 'Chat');
  const pay = LockedApp(
    packageName: 'com.phonepe.app',
    label: 'PhonePe',
    paymentApp: true,
  );
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 10, h, m);

  group('schedule', () {
    test('disabled or empty policies never block', () {
      const off = AppLockPolicy(apps: [chat], schedule: AppLockSchedule.always);
      expect(off.isActiveAt(at(18), riskWindow: risk), isFalse);
      const empty = AppLockPolicy(
        enabled: true,
        schedule: AppLockSchedule.always,
      );
      expect(empty.isActiveAt(at(18), riskWindow: risk), isFalse);
      expect(empty.armed, isFalse);
    });

    test('always blocks around the clock', () {
      const policy = AppLockPolicy(
        enabled: true,
        apps: [chat],
        schedule: AppLockSchedule.always,
      );
      for (final hour in [0, 6, 12, 18, 23]) {
        expect(
          policy.blocks(chat.packageName, at(hour), riskWindow: risk),
          isTrue,
        );
      }
      expect(policy.blocks('com.other', at(12), riskWindow: risk), isFalse);
    });

    test(
      'risk window 17:00-21:00 uses the existing setting, edges included',
      () {
        const policy = AppLockPolicy(
          enabled: true,
          apps: [chat],
          lockInsideDangerZones: false,
        );
        expect(policy.schedule, AppLockSchedule.riskWindow);
        expect(policy.isActiveAt(at(16, 59), riskWindow: risk), isFalse);
        expect(policy.isActiveAt(at(17), riskWindow: risk), isTrue);
        expect(policy.isActiveAt(at(21), riskWindow: risk), isTrue);
        expect(policy.isActiveAt(at(21, 1), riskWindow: risk), isFalse);
        const night = RiskWindow(startMinutes: 22 * 60, endMinutes: 2 * 60);
        expect(policy.isActiveAt(at(1), riskWindow: night), isTrue);
        expect(policy.isActiveAt(at(12), riskWindow: night), isFalse);
      },
    );

    test('danger zones lock on any schedule, including zones-only', () {
      const zonesOnly = AppLockPolicy(
        enabled: true,
        apps: [chat],
        schedule: AppLockSchedule.off,
      );
      expect(zonesOnly.armed, isTrue);
      expect(zonesOnly.isActiveAt(at(12), riskWindow: risk), isFalse);
      expect(
        zonesOnly.isActiveAt(at(12), riskWindow: risk, insideDangerZone: true),
        isTrue,
      );
      const noZones = AppLockPolicy(
        enabled: true,
        apps: [chat],
        schedule: AppLockSchedule.off,
        lockInsideDangerZones: false,
      );
      expect(noZones.armed, isFalse);
      expect(
        noZones.isActiveAt(at(12), riskWindow: risk, insideDangerZone: true),
        isFalse,
      );
    });

    test('a paused app is not blocked', () {
      final policy = AppLockPolicy(
        enabled: true,
        apps: [chat.copyWith(enabled: false), pay],
        schedule: AppLockSchedule.always,
      );
      expect(policy.enabledPackages, {pay.packageName});
    });
  });

  group('never lockable', () {
    test('dialer, emergency, maps, NO LEAN, settings and launchers', () {
      for (final pkg in [
        'com.google.android.dialer',
        'com.android.phone',
        'com.android.emergency',
        'com.google.android.apps.safetyhub',
        'com.google.android.apps.maps',
        'com.waze',
        'com.nolean.no_lean',
        'com.nolean.no_lean.preview',
        'com.android.settings',
        'com.google.android.apps.nexuslauncher',
        'com.sec.android.app.launcher',
        'com.miui.home',
        '',
      ]) {
        expect(isNeverLockable(pkg), isTrue, reason: pkg);
      }
      expect(isNeverLockable('com.whatsapp'), isFalse);
      expect(
        isNeverLockable('com.custom.home', extra: {'com.custom.home'}),
        isTrue,
      );
    });

    test('sanitizing drops protected and duplicate apps and clamps budget', () {
      const policy = AppLockPolicy(
        enabled: true,
        apps: [
          chat,
          LockedApp(packageName: 'com.google.android.dialer', label: 'Phone'),
          LockedApp(packageName: 'com.example.chat', label: 'Dup'),
          LockedApp(packageName: 'com.nolean.no_lean', label: 'Me'),
        ],
        dailyUnlockBudget: 99,
      );
      final clean = policy.sanitized();
      expect(clean.apps.map((a) => a.packageName), ['com.example.chat']);
      expect(clean.dailyUnlockBudget, AppLockPolicy.maxDailyUnlockBudget);
      expect(
        policy.sanitized(extraProtected: {'com.example.chat'}).apps,
        isEmpty,
      );
    });

    test('a protected app is never enforced even if it slipped in', () {
      const policy = AppLockPolicy(
        enabled: true,
        apps: [LockedApp(packageName: 'com.waze', label: 'Waze')],
        schedule: AppLockSchedule.always,
      );
      expect(policy.blocks('com.waze', at(18), riskWindow: risk), isFalse);
    });

    test('payment suggestions are GPay, PhonePe, Paytm and BHIM', () {
      expect(suggestedPaymentPackages.keys.toSet(), {
        'com.google.android.apps.nbu.paisa.user',
        'com.phonepe.app',
        'net.one97.paytm',
        'in.org.npci.upiapp',
      });
    });
  });

  group('loosening needs the relapse lock', () {
    const base = AppLockPolicy(
      enabled: true,
      apps: [chat, pay],
      schedule: AppLockSchedule.riskWindow,
    );

    test('tightening is free', () {
      expect(
        base.copyWith(schedule: AppLockSchedule.always).isLooserThan(base),
        isFalse,
      );
      expect(
        base
            .copyWith(
              apps: [
                ...base.apps,
                const LockedApp(
                  packageName: 'x.y',
                  label: 'X',
                  paymentApp: true,
                ),
              ],
            )
            .isLooserThan(base),
        isFalse,
      );
      expect(base.copyWith(dailyUnlockBudget: 1).isLooserThan(base), isFalse);
      expect(base.isLooserThan(const AppLockPolicy()), isFalse);
    });

    test('weakening is detected', () {
      expect(base.copyWith(enabled: false).isLooserThan(base), isTrue);
      expect(base.copyWith(apps: [pay]).isLooserThan(base), isTrue);
      expect(
        base.copyWith(schedule: AppLockSchedule.off).isLooserThan(base),
        isTrue,
      );
      expect(
        base.copyWith(lockInsideDangerZones: false).isLooserThan(base),
        isTrue,
      );
      expect(base.copyWith(dailyUnlockBudget: 5).isLooserThan(base), isTrue);
      expect(
        base
            .copyWith(apps: [chat.copyWith(paymentApp: true), pay])
            .isLooserThan(base),
        isTrue,
      );
    });
  });

  test('JSON round-trips and malformed input fails safe (off)', () {
    const policy = AppLockPolicy(
      enabled: true,
      apps: [chat, pay],
      schedule: AppLockSchedule.always,
      dailyUnlockBudget: 2,
      lockInsideDangerZones: false,
    );
    expect(AppLockPolicy.fromJson(policy.toJson()), policy);
    final garbage = AppLockPolicy.fromJson({
      'enabled': 'yes',
      'apps': [
        42,
        {'packageName': 'com.ok', 'label': 'OK'},
      ],
      'schedule': 'whenever',
      'dailyUnlockBudget': 'lots',
    });
    expect(garbage.enabled, isFalse);
    expect(garbage.apps.single.packageName, 'com.ok');
    expect(garbage.schedule, AppLockSchedule.riskWindow);
    expect(garbage.dailyUnlockBudget, AppLockPolicy.defaultDailyUnlockBudget);
    expect(AppLockPolicy.fromJson(null), const AppLockPolicy());
  });

  test('native config carries only what enforcement needs', () {
    final zone = DangerZone(
      id: 'z1',
      name: 'Corner',
      latitude: 22.5,
      longitude: 88.3,
      radiusMeters: 200,
      createdAt: DateTime(2026),
    );
    final config = buildNativeAppLockConfig(
      policy: const AppLockPolicy(enabled: true, apps: [chat, pay]),
      riskWindow: risk,
      zones: [zone],
      hideSensitive: true,
    );
    expect(config['enabled'], isTrue);
    expect(config['packages'], ['com.example.chat', 'com.phonepe.app']);
    expect(config['paymentPackages'], ['com.phonepe.app']);
    expect(config['windowStart'], 17 * 60);
    expect(config['windowEnd'], 21 * 60);
    expect(config['hideSensitive'], isTrue);
    expect((config['zones'] as List).single, containsPair('name', 'Corner'));
    expect(config['neverLockable'], contains('com.google.android.dialer'));

    final off = buildNativeAppLockConfig(
      policy: const AppLockPolicy(
        apps: [chat],
        schedule: AppLockSchedule.always,
        lockInsideDangerZones: false,
      ),
      riskWindow: risk,
      zones: [zone],
      hideSensitive: false,
    );
    expect(off['enabled'], isFalse);
    expect(off['windowStart'], isNull);
    expect(off['zones'], isEmpty);
  });
}
