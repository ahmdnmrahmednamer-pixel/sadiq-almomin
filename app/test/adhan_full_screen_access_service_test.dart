import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/adhan_full_screen_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const query = MethodChannel('almomin/adhan_permissions');
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = AdhanFullScreenAccessService();
  tearDown(() {
    messenger.setMockMethodCallHandler(query, null);
    messenger.setMockMethodCallHandler(plugin, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test('check is read-only and distinguishes denied from unavailable',
      () async {
    var requests = 0;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      requests++;
      return true;
    });
    messenger.setMockMethodCallHandler(query, (call) async {
      expect(call.method, 'canUseFullScreenIntent');
      return false;
    });
    expect(await service.check(), isFalse);
    expect(requests, 0);
    messenger.setMockMethodCallHandler(
        query, (call) async => throw PlatformException(code: 'unavailable'));
    expect(await service.check(), isNull);
    expect(requests, 0);
  });
  test('check reports an existing grant without requesting again', () async {
    messenger.setMockMethodCallHandler(query, (call) async => true);
    expect(await service.check(), isTrue);
  });
  test('request uses FSI API, not overlay, and reads actual state after return',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call.method);
      return true;
    });
    messenger.setMockMethodCallHandler(query, (call) async {
      calls.add(call.method);
      return false;
    });
    expect(await service.request(), isFalse);
    expect(
        calls, ['requestFullScreenIntentPermission', 'canUseFullScreenIntent']);
  });
  test('request failure does not fabricate a grant', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
        plugin, (call) async => throw PlatformException(code: 'denied'));
    messenger.setMockMethodCallHandler(query, (call) async => null);
    expect(await service.request(), isNull);
  });
}
