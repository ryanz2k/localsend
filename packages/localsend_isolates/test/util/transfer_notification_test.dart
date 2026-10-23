import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_foreground_task/methods');
  final calls = <MethodCall>[];
  var running = false;

  Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 30));

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    running = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isRunningService':
          return running;
        case 'startService':
          running = true;
        case 'stopService':
          running = false;
        case 'checkNotificationPermission':
        case 'requestNotificationPermission':
          return 0;
      }
      return null;
    });
    TransferNotification.init(NotificationStrings(
      titleReceiving: 'Receiving',
      titleSending: 'Sending',
      remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
      remainingTimeLong: ({required h, required m}) => '${h}h ${m}m',
    ));
  });

  tearDown(() async {
    TransferNotification.stop('receive');
    TransferNotification.stop('send');
    await drain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('peer transfers use connected-device service instead of Android 15 timed data sync', () async {
    TransferNotification.start(sessionId: 'receive', receiving: true);
    await drain();
    final start = calls.singleWhere((call) => call.method == 'startService');
    // Android ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE.
    expect(start.arguments['serviceTypes'], [16]);
    expect(start.arguments['allowWakeLock'], isTrue);
    expect(start.arguments['allowWifiLock'], isTrue);
  });

  test('finishing one of two transfers keeps the service alive', () async {
    TransferNotification.start(sessionId: 'receive', receiving: true);
    TransferNotification.start(sessionId: 'send', receiving: false);
    await drain();
    TransferNotification.stop('receive');
    await drain();
    expect(running, isTrue);
    TransferNotification.stop('send');
    await drain();
    expect(running, isFalse);
  });
}
