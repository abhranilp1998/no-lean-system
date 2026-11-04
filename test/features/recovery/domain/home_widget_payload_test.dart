import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/home_widget_payload.dart';
import 'package:no_lean/features/recovery/services/home_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lastDose = DateTime.utc(2026, 9, 27, 6);

  test('full mode sends the counter, streak, risk and pledge state', () {
    final payload = homeWidgetPayload(
      lastDose: lastDose,
      cleanTime: '12d 04h',
      streak: 12,
      isRiskWindow: true,
      hasPledgedToday: true,
      privacy: false,
    );
    expect(payload, {
      'privacy': false,
      'lastDoseEpochMillis': lastDose.millisecondsSinceEpoch,
      'cleanTime': '12d 04h',
      'streak': '12 DAYS',
      'isRiskWindow': true,
      'hasPledgedToday': true,
    });
  });

  test('privacy mode sends nothing recovery-specific', () {
    final payload = homeWidgetPayload(
      lastDose: lastDose,
      cleanTime: '12d 04h',
      streak: 12,
      isRiskWindow: true,
      hasPledgedToday: true,
      privacy: true,
    );
    expect(payload['privacy'], isTrue);
    expect(payload['lastDoseEpochMillis'], 0);
    expect(payload['isRiskWindow'], isFalse);
    expect(payload['hasPledgedToday'], isFalse);
    expect(payload.values.whereType<String>().join(), isEmpty);
  });

  test('the service forwards the payload over no_lean/widget', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HomeWidgetService.channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HomeWidgetService.channel, null),
    );
    await HomeWidgetService.update(
      lastDose: lastDose,
      cleanTime: '1d',
      streak: 1,
      isRiskWindow: false,
      hasPledgedToday: false,
      privacy: true,
    );
    expect(calls.single.method, 'update');
    expect((calls.single.arguments as Map)['privacy'], isTrue);
    expect((calls.single.arguments as Map)['streak'], '');
  });

  test('risk window minutes ride along for the night timeline', () {
    final payload = homeWidgetPayload(
      lastDose: lastDose,
      cleanTime: '1d',
      streak: 1,
      isRiskWindow: false,
      hasPledgedToday: false,
      privacy: false,
      riskStartMinutes: 18 * 60,
      riskEndMinutes: 22 * 60,
    );
    expect(payload['riskStartMinutes'], 1080);
    expect(payload['riskEndMinutes'], 1320);
    final private = homeWidgetPayload(
      lastDose: lastDose,
      cleanTime: '1d',
      streak: 1,
      isRiskWindow: false,
      hasPledgedToday: false,
      privacy: true,
      riskStartMinutes: 1080,
      riskEndMinutes: 1320,
    );
    expect(private.containsKey('riskStartMinutes'), isFalse);
  });
}
