import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/widgets/domain/fullscreen_widgets.dart';
import 'package:no_lean/features/widgets/presentation/home_widget_settings_screen.dart';
import 'package:no_lean/features/widgets/services/widget_choice_service.dart';

import '../../support/recovery_fakes.dart';
import '../cravings/craving_stress_recheck_test.dart' show pumpHost;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecoveryController, MemoryRecoveryStore)> load([
    String? stored,
  ]) async {
    final store = MemoryRecoveryStore(stored);
    final c = RecoveryController(store: store, relapseLock: FakeRelapseLock());
    await c.load();
    return (c, store);
  }

  test('Dart choices match the Android cycle order exactly', () {
    final kt = File(
      'android/app/src/main/kotlin/com/nolean/no_lean/StretchedViews.kt',
    ).readAsStringSync();
    final list = RegExp(
      r'val CHOICES = listOf\(([^)]*)\)',
    ).firstMatch(kt)!.group(1)!;
    final native = RegExp(r'"(\w+)"').allMatches(list).map((m) => m.group(1));
    expect(native, StretchedWidgetView.values.map((v) => v.nativeName));
    expect(StretchedWidgetView.fromName('nope'), StretchedWidgetView.auto);
    expect(
      StretchedWidgetView.fromName('shield'),
      StretchedWidgetView.eveningShield,
    );
  });

  test('state v14 loads as auto; the choice persists as v15', () async {
    final (c, store) = await load(
      jsonEncode({'stateVersion': 14, 'events': <Object>[]}),
    );
    expect(c.stretchedWidgetView, StretchedWidgetView.auto);
    await c.setStretchedWidgetView(StretchedWidgetView.wave);
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect(saved['stateVersion'], 15);
    expect(saved['stretchedWidgetView'], 'wave');
    final (reloaded, _) = await load(store.value);
    expect(reloaded.stretchedWidgetView, StretchedWidgetView.wave);
  });

  group('backups', () {
    test(
      'format 10 carries the choice; older formats keep the current one',
      () async {
        final (c, _) = await load();
        await c.setStretchedWidgetView(StretchedWidgetView.map);
        final service = BackupService();
        final preview = service.validateBackupJson(
          jsonEncode(
            service.buildBackupPayload(
              c.events,
              preferences: c.portablePreferences,
            ),
          ),
        );
        expect(preview.preferences!['stretchedWidgetView'], 'map');

        final (target, _) = await load();
        await target.setStretchedWidgetView(StretchedWidgetView.note);
        await target.mergeImportedEvents(
          const [],
          preferences: preview.preferences,
          restorePreferences: true,
        );
        expect(target.stretchedWidgetView, StretchedWidgetView.map);

        final old = service.validateBackupJson(
          jsonEncode({
            'version': 9,
            'events': <Object>[],
            'preferences': {'dailySpend': 5},
          }),
        );
        await target.mergeImportedEvents(
          const [],
          preferences: old.preferences,
          restorePreferences: true,
        );
        expect(target.stretchedWidgetView, StretchedWidgetView.map);
      },
    );

    test('an unknown view in a backup is refused', () {
      expect(
        () => BackupService().validateBackupJson(
          jsonEncode({
            'version': 10,
            'events': <Object>[],
            'preferences': {'stretchedWidgetView': 'launcher'},
          }),
        ),
        throwsFormatException,
      );
    });
  });

  test('per-widget overrides go to the platform channel', () async {
    const channel = MethodChannel('test/widget');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'placedWidgets') {
            return [
              {'id': 7, 'kind': 'large', 'view': 'garden'},
              {'id': 9, 'kind': 'full', 'view': null},
            ];
          }
          return null;
        });
    final service = WidgetChoiceService(channel: channel, enabled: true);
    final placed = await service.placed();
    expect(placed.map((p) => (p.id, p.label, p.override)), [
      (7, 'NO LEAN 4x3', StretchedWidgetView.garden),
      (9, 'NO LEAN Full', null),
    ]);
    await service.setOverride(9, StretchedWidgetView.note);
    expect(calls.last.arguments, {'id': 9, 'view': 'note'});
  });

  testWidgets('settings screen: tapping a thumbnail sets the view', (
    tester,
  ) async {
    final c = await pumpHost(
      tester,
      child: (context, ref) => TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HomeWidgetSettingsScreen(
              service: WidgetChoiceService(enabled: false),
            ),
          ),
        ),
        child: const Text('OPEN'),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    for (final v in StretchedWidgetView.values) {
      expect(find.byKey(Key('stretched-choice-${v.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('stretched-choice-garden')));
    await tester.pumpAndSettle();
    expect(c.stretchedWidgetView, StretchedWidgetView.garden);
  });
}
