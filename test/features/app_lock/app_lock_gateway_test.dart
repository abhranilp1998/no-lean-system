import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('no_lean/app_lock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('parses status, apps and block requests from Android', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'status' => {
          'usageAccess': true,
          'overlay': false,
          'serviceRunning': true,
        },
        'installedApps' => [
          {'packageName': 'com.b', 'label': 'beta'},
          {'packageName': 'com.a', 'label': 'Alpha', 'neverLockable': true},
          {'label': 'broken'},
        ],
        'drainBlocks' => [
          {
            'packageName': 'com.b',
            'label': 'beta',
            'zoneName': 'Corner',
            'cause': 'zone',
          },
          {'packageName': ''},
        ],
        'apply' || 'grantTemporaryUnlock' || 'disable' => true,
        _ => null,
      };
    });
    final gateway = MethodChannelAppLockGateway();
    final status = await gateway.status();
    expect(status.usageAccess, isTrue);
    expect(status.overlay, isFalse);
    expect(status.availability, AppLockAvailability.permissionRequired);

    final apps = await gateway.installedApps();
    expect(apps.map((a) => a.packageName), ['com.a', 'com.b']);
    expect(apps.first.neverLockable, isTrue);

    final blocks = await gateway.drainBlockRequests();
    expect(blocks.single.zoneName, 'Corner');
    expect(blocks.single.cause, 'zone');

    expect((await gateway.apply({'enabled': true})).supported, isTrue);
    expect(jsonDecode(calls.last.arguments as String), {'enabled': true});
    expect(
      await gateway.grantTemporaryUnlock('com.b', const Duration(minutes: 5)),
      isTrue,
    );
    expect(calls.last.arguments, {'packageName': 'com.b', 'millis': 300000});
  });

  test('a missing or failing native side never blocks anything', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    final gateway = MethodChannelAppLockGateway();
    expect((await gateway.status()).supported, isFalse);
    expect(await gateway.installedApps(), isEmpty);
    expect(await gateway.drainBlockRequests(), isEmpty);
    expect(await gateway.grantTemporaryUnlock('x', Duration.zero), isFalse);
    expect(
      await const UnsupportedAppLockGateway().availability(),
      AppLockAvailability.notImplemented,
    );
  });
}
