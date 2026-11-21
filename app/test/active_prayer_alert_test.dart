import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/notifications/active_prayer_alert.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('almomin/active_prayer_alert');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test('manual preview without notification does not call native methods',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    await (await ActivePrayerAlert.capture(null)).stop();
    expect(calls, 0);
  });
  test('missing posted alert does not cancel a future reused ID', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await (await ActivePrayerAlert.capture(100)).stop();
    expect(calls, ['capture']);
  });
  for (final outcome in ['stopped', 'gone']) {
    test(
        '$outcome requires the exact captured identity and no schedule operation',
        () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'capture'
            ? {'id': 100, 'key': 'posted-key', 'postTime': 777}
            : outcome;
      });
      await (await ActivePrayerAlert.capture(100)).stop();
      expect(calls.map((c) => c.method), ['capture', 'stopCaptured']);
      expect(calls.last.arguments,
          {'id': 100, 'key': 'posted-key', 'postTime': 777});
    });
  }
  test('replacement is not claimed stopped and must block a second player',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture'
            ? {'id': 100, 'key': 'posted-key', 'postTime': 777}
            : 'replaced');
    final alert = await ActivePrayerAlert.capture(100);
    expect(alert.stop(), throwsStateError);
  });
  test('capture failure is not mistaken for no active sound', () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => throw PlatformException(code: 'unavailable'));
    expect(ActivePrayerAlert.capture(100), throwsA(isA<PlatformException>()));
  });
  test('mismatched capture ID is rejected', () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => {'id': 101, 'key': 'other', 'postTime': 777});
    expect(ActivePrayerAlert.capture(100), throwsFormatException);
  });
  test('unconfirmed stop is a failure, not a success claim', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture'
            ? {'id': 100, 'key': 'posted-key', 'postTime': 777}
            : null);
    final session = await ActivePrayerAlert.capture(100);
    expect(session.stop(), throwsStateError);
  });
  test('non-Android builds do not require the Android bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      throw PlatformException(code: 'unexpected');
    });
    await (await ActivePrayerAlert.capture(100)).stop();
    expect(calls, 0);
  });
}
