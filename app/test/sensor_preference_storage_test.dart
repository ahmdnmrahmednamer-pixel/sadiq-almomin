import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/prayer/adhan_control_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:almomin/core/ui/notification_preference_error.dart';
import 'package:almomin/features/settings/models/settings_session.dart';

class SensorStore extends InMemorySharedPreferencesStore {
  SensorStore() : super.withData({});
  bool reject = false, throwing = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (gate != null) await gate!.future;
    if (throwing) throw PlatformException(code: 'storage');
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
  test('reload waits for an admitted write', () async {
    store.gate = Completer<void>();
    final saved = service.toggleFlipToMute(false);
    await Future<void>.delayed(Duration.zero);
    final reload = service.init(forceReload: true);
    expect(service.flipToMuteEnabled, true);
    store.gate!.complete();
    expect(await saved, true);
    await reload;
    expect(service.flipToMuteEnabled, false);
  });
  test('malformed reload preserves all live choices and reports failure',
      () async {
    await service.toggleShakeToStop(false);
    await store.setValue('Bool', 'flutter.notif_shake_to_stop', true);
    await store.setValue('String', 'flutter.notif_flip_to_mute', 'bad');
    await service.init(forceReload: true);
    expect(service.shakeToStopEnabled, false);
    expect(service.flipToMuteEnabled, true);
    expect(service.preferenceError, isNotNull);
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
    for (final throwing in [false, true]) {
      test(
          '${entry.key} rejected write leaves live and durable choice unchanged throw=$throwing',
          () async {
        store.reject = !throwing;
        store.throwing = throwing;
        final saved = await entry.value.$1(false);
        expect(entry.value.$2(), true);
        expect(saved, false);
        expect(entry.value.$2(), true);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(entry.value.$3), isNull);
        expect(service.preferenceError, isNotNull);
      });
    }
    test('${entry.key} confirmed save publishes and survives reload', () async {
      expect(await entry.value.$1(false), true);
      expect(entry.value.$2(), false);
      await service.init(forceReload: true);
      expect(entry.value.$2(), false);
      expect(service.preferenceError, isNull);
    });
    test('${entry.key} delayed writes serialize and do not publish prematurely',
        () async {
      store.gate = Completer<void>();
      final first = entry.value.$1(false);
      final second = entry.value.$1(true);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1);
      expect(entry.value.$2(), true);
      store.gate!.complete();
      expect(await first, true);
      expect(await second, true);
      await service.init(forceReload: true);
      expect(entry.value.$2(), true);
      expect(store.writes, 2);
    });
  }
  test('settings apply keeps rejected choice pending and retry saves it',
      () async {
    final session = SettingsSession();
    addTearDown(session.draft.dispose);
    session.shake.stage(false);
    store.reject = true;
    final failed = await session.draft.apply();
    expect(failed.success, false);
    expect(failed.failedKey, 'shake');
    expect(service.shakeToStopEnabled, true);
    expect(session.shake.dirty, true);
    store.reject = false;
    expect((await session.draft.apply()).success, true);
    await service.init(forceReload: true);
    expect(service.shakeToStopEnabled, false);
  });
  testWidgets(
      'storage error is visible as a live region and clears after successful retry',
      (tester) async {
    store.reject = true;
    await service.toggleFlipToMute(false);
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NotificationPreferenceError())));
    expect(find.textContaining('تعذر حفظ إعداد التحكم'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true),
        findsOneWidget);
    store.reject = false;
    await tester.runAsync(() => service.toggleFlipToMute(false));
    await tester.pump();
    expect(find.textContaining('تعذر حفظ إعداد التحكم'), findsNothing);
  });
  for (final scale in [1.0]) {
    testWidgets('actual adhan options reject then save gesture at $scale',
        (tester) async {
      await SettingsService.instance.init(forceReload: true);
      IslamicAudioService.instance.disableNativePlayerForTesting = true;
      AdhanSensorGestureService.instance.accelerometerStreamOverride =
          const Stream<AccelerometerEvent>.empty();
      await (FontLoader('Cairo')
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
          .load();
      const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
      if (icons.isNotEmpty)
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(File(icons).readAsBytesSync()))))
            .load();
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const AdhanControlScreen(
                  prayerName: 'العصر', autoPlay: false))));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('خيارات الأذان'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('خيارات الأذان'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final toggle =
          find.widgetWithText(SwitchListTile, 'إيقاف الأذان عند هز الهاتف');
      await tester.scrollUntilVisible(toggle, 200,
          scrollable: find.byType(Scrollable).last);
      await tester.pump(const Duration(milliseconds: 500));
      store.reject = true;
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.shakeToStopEnabled, true);
      expect(tester.widget<SwitchListTile>(toggle).value, true);
      expect(find.textContaining('تعذر حفظ إعداد التحكم'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['SENSOR_PIXELS'];
      if (directory != null)
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/modal-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      store.reject = false;
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.shakeToStopEnabled, false);
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      expect(find.textContaining('تعذر حفظ إعداد التحكم'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => IslamicAudioService.instance.stop());
      IslamicAudioService.instance.disableNativePlayerForTesting = false;
      AdhanSensorGestureService.instance.accelerometerStreamOverride = null;
    });
  }
}
