import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/prayer/fajr_qiyam_alarm_screen.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';

class AlarmStore extends InMemorySharedPreferencesStore {
  AlarmStore() : super.withData({});
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
  final dynamic service = FajrQiyamAlarmService.instance;
  late AlarmStore store;
  final calls = <MethodCall>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AlarmStore();
    SharedPreferencesStorePlatform.instance = store;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      return null;
    });
    await service.init(forceReload: true);
    calls.clear();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            null);
  });
  final cases = <String, (Future<dynamic> Function(), String, Object)>{
    'pre enabled': (
      () => service.setPreFajrEnabled(false),
      'pre_fajr_enabled',
      false
    ),
    'pre minutes': (
      () => service.setPreFajrMinutesBefore(40),
      'pre_fajr_minutes',
      40
    ),
    'pre tone': (
      () => service.setPreFajrTone('takbeerat'),
      'pre_fajr_tone',
      'takbeerat'
    ),
    'qiyam enabled': (
      () => service.setQiyamEnabled(false),
      'qiyam_enabled',
      false
    ),
    'qiyam mode': (
      () => service.setQiyamMode('fixed_time'),
      'qiyam_mode',
      'fixed_time'
    ),
    'qiyam minutes': (
      () => service.setQiyamMinutesBeforeFajr(90),
      'qiyam_minutes_before',
      90
    ),
    'qiyam tone': (
      () => service.setQiyamTone('takbeerat'),
      'qiyam_tone',
      'takbeerat'
    ),
  };
  for (final entry in cases.entries) {
    for (final throwing in [false, true]) {
      test(
          '${entry.key} rejected save preserves live and durable choice throw=$throwing',
          () async {
        final before = service.exportData();
        store.reject = !throwing;
        store.throwing = throwing;
        expect(await entry.value.$1(), false);
        expect(service.exportData(), before);
        expect(calls, isEmpty);
        expect(service.preferenceError, isNotNull);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(prefs.getKeys(), isEmpty);
      });
    }
    test('${entry.key} confirmed save publishes and survives reload', () async {
      expect(await entry.value.$1(), true);
      expect(service.exportData()[entry.value.$2], entry.value.$3);
      expect(service.preferenceError, isNull);
      await service.init(forceReload: true);
      expect(service.exportData()[entry.value.$2], entry.value.$3);
    });
  }
  test('pending writes stay unpublished and serialize in admission order',
      () async {
    store.gate = Completer<void>();
    final first = service.setPreFajrMinutesBefore(35);
    while (store.writes == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = service.setPreFajrMinutesBefore(45);
    expect(service.preFajrMinutesBefore, 25);
    expect(store.writes, 1);
    expect(calls, isEmpty);
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    expect(service.preFajrMinutesBefore, 45);
    await service.init(forceReload: true);
    expect(service.preFajrMinutesBefore, 45);
  });
  test('failed write queue continues and clears only after a confirmed save',
      () async {
    store.reject = true;
    expect(await service.setQiyamTone('takbeerat'), false);
    store.reject = false;
    expect(await service.setQiyamTone('adhan_fajr'), true);
    expect(service.preferenceError, isNull);
    expect(service.qiyamToneId, 'adhan_fajr');
  });
  test('backup import cannot conceal a rejected preference save', () async {
    store.reject = true;
    await expectLater(
        service.importData({'qiyam_tone': 'takbeerat'}), throwsStateError);
    expect(service.qiyamToneId, 'duaa_sharawi_post_prayer');
    expect(calls, isEmpty);
  });
  test('fixed clock commits atomically and preserves legacy keys', () async {
    await store.setValue('Int', 'flutter.wake_qiyam_fixed_hour', 2);
    await store.setValue('Int', 'flutter.wake_qiyam_fixed_minute', 10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await service.init(forceReload: true);
    expect(service.qiyamFixedHour, 2);
    expect(service.qiyamFixedMinute, 10);
    final before = store.writes;
    expect(await service.setQiyamFixedTime(4, 35), true);
    expect(store.writes, before + 1);
    await service.init(forceReload: true);
    expect(service.qiyamFixedHour, 4);
    expect(service.qiyamFixedMinute, 35);
    expect(prefs.getInt('wake_qiyam_fixed_hour'), 2);
    expect(prefs.getInt('wake_qiyam_fixed_minute'), 10);
    expect(prefs.getInt('wake_qiyam_fixed_minutes_v1'), 275);
    expect(service.exportData()['qiyam_fixed_hour'], 4);
    expect(service.exportData()['qiyam_fixed_minute'], 35);
  });
  for (final throwing in [false, true]) {
    test('fixed clock rejected write cannot tear time throw=$throwing',
        () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.setQiyamFixedTime(5, 40), false);
      expect(service.qiyamFixedHour, 3);
      expect(service.qiyamFixedMinute, 15);
      expect(calls, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.get('wake_qiyam_fixed_minutes_v1'), isNull);
      await service.init(forceReload: true);
      expect(service.qiyamFixedHour, 3);
      expect(service.qiyamFixedMinute, 15);
    });
  }
  test(
      'fixed clock pending commit is unpublished, then whole pair survives restart',
      () async {
    store.gate = Completer<void>();
    final first = service.setQiyamFixedTime(1, 5);
    while (store.writes == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = service.setQiyamFixedTime(6, 45);
    expect(service.qiyamFixedHour, 3);
    expect(service.qiyamFixedMinute, 15);
    expect(store.writes, 1);
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    await service.init(forceReload: true);
    expect(service.qiyamFixedHour, 6);
    expect(service.qiyamFixedMinute, 45);
  });
  test('backup fixed time uses the same atomic commit and propagates rejection',
      () async {
    store.reject = true;
    await expectLater(
        service.importData({'qiyam_fixed_hour': 7, 'qiyam_fixed_minute': 20}),
        throwsStateError);
    store.reject = false;
    await service.importData({'qiyam_fixed_hour': 7, 'qiyam_fixed_minute': 20});
    await service.init(forceReload: true);
    expect(service.qiyamFixedHour, 7);
    expect(service.qiyamFixedMinute, 20);
  });
  for (final invalid in [-1, 1440, 'invalid']) {
    test('invalid packed time falls back to untouched legacy fields $invalid',
        () async {
      await store.setValue(invalid is int ? 'Int' : 'String',
          'flutter.wake_qiyam_fixed_minutes_v1', invalid);
      await store.setValue('Int', 'flutter.wake_qiyam_fixed_hour', 2);
      await store.setValue('Int', 'flutter.wake_qiyam_fixed_minute', 50);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await service.init(forceReload: true);
      expect(service.qiyamFixedHour, 2);
      expect(service.qiyamFixedMinute, 50);
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('failed preference is readable without applying at $scale',
        (tester) async {
      await SettingsService.instance.init(forceReload: true);
      IslamicAudioService.instance.disableNativePlayerForTesting = true;
      for (final family in ['Cairo', 'Amiri']) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/$family-Regular.ttf').readAsBytesSync()))))
            .load();
      }
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
      final semantics = tester.ensureSemantics();
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const FajrQiyamAlarmScreen())));
      await tester.pumpAndSettle();
      store.reject = true;
      await service.setPreFajrMinutesBefore(65);
      await tester.pumpAndSettle();
      final error = find.textContaining('تعذر تأكيد حفظ إعداد المنبّه');
      expect(error, findsOneWidget);
      expect(tester.getSemantics(error).label,
          contains('قد يكون الاختيار حُفظ دون تحديث التنبيهات'));
      expect(service.preFajrMinutesBefore, 25);
      expect(tester.takeException(), isNull);
      const directory = String.fromEnvironment('FAJR_STORAGE_PIXELS');
      if (directory.isNotEmpty)
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/failure-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
