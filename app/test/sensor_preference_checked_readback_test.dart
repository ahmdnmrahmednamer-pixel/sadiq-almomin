import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only storage faults.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';

class SensorStore extends InMemorySharedPreferencesStore {
  SensorStore() : super.withData({});
  bool reject = false, throwing = false, afterWrite = false;
  bool failReads = false,
      failReadAfter = false,
      acceptWithoutWrite = false,
      throwAfter = false;
  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw PlatformException(code: 'read');
    return super.getAll();
  }

  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (failReadAfter) failReads = true;
    if (acceptWithoutWrite) return true;
    if (throwAfter) {
      await super.setValue(type, key, value);
      throw PlatformException(code: 'after');
    }
    if (gate != null) await gate!.future;
    if (throwing) throw PlatformException(code: 'storage');
    if (reject && afterWrite) {
      await super.setValue(type, key, value);
      return false;
    }
    return reject ? false : await super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dynamic service = AdhanSensorGestureService.instance;
  late SensorStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = SensorStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  final cases =
      <String, (Future<dynamic> Function(bool), bool Function(), String)>{
    'shake': (
      (v) => service.toggleShakeToStop(v),
      () => service.shakeToStopEnabled as bool,
      'notif_shake_to_stop'
    ),
    'flip': (
      (v) => service.toggleFlipToMute(v),
      () => service.flipToMuteEnabled as bool,
      'notif_flip_to_mute'
    ),
    'overlay': (
      (v) => service.toggleOverlayWindow(v),
      () => service.overlayWindowEnabled as bool,
      'notif_overlay_window'
    ),
  };
  for (final entry in cases.entries) {
    for (final mode in [
      'after',
      'unreadable',
      'acceptedUnreadable',
      'mismatch',
      'throwAfter'
    ]) {
      test('${entry.key} checked saved control $mode', () async {
        store.reject = mode == 'after' || mode == 'unreadable';
        store.afterWrite = mode == 'after';
        store.failReadAfter =
            mode == 'unreadable' || mode == 'acceptedUnreadable';
        store.acceptWithoutWrite = mode == 'mismatch';
        store.throwAfter = mode == 'throwAfter';
        expect(await entry.value.$1(false), false);
        expect(entry.value.$2(),
            mode == 'after' || mode == 'throwAfter' ? false : true);
        expect(service.preferenceError, isNotNull);
        store.reject = false;
        store.afterWrite = false;
        store.failReads = false;
        store.failReadAfter = false;
        store.acceptWithoutWrite = false;
        store.throwAfter = false;
        expect(await entry.value.$1(false), true);
        expect(entry.value.$2(), false);
        expect(service.preferenceError, isNull);
      });
    }
  }
  test('confirmed recovered disabled shake gates actual event handler',
      () async {
    final stream = StreamController<AccelerometerEvent>();
    service.accelerometerStreamOverride = stream.stream;
    var callbacks = 0;
    service.startListening(onShake: () => callbacks++);
    try {
      store.reject = true;
      store.afterWrite = true;
      expect(await service.toggleShakeToStop(false), false);
      stream.add(AccelerometerEvent(35, 0, 0));
      stream.add(AccelerometerEvent(35, 0, 0));
      await Future<void>.delayed(Duration.zero);
      expect(callbacks, 0);
      store.reject = false;
      store.afterWrite = false;
      expect(await service.toggleShakeToStop(true), true);
      stream.add(AccelerometerEvent(35, 0, 0));
      stream.add(AccelerometerEvent(35, 0, 0));
      await Future<void>.delayed(Duration.zero);
      expect(callbacks, 1);
    } finally {
      service.stopListening();
      service.accelerometerStreamOverride = null;
      await stream.close();
    }
  });
}
