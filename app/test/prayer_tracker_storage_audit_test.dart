import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/prayer/prayer_tracker_screen.dart';
import 'package:almomin/features/prayer/adhan_control_screen.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/prayer_tracker_service.dart';

class TrackerStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  bool reject = false, throwWrite = false;
  Completer<void>? hold;
  int writes = 0;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (hold != null) await hold!.future;
    if (throwWrite) throw PlatformException(code: 'test-write');
    if (reject) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'flutter.prayer_tracker_records_v1';
  final service = PrayerTrackerService.instance;
  late TrackerStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = TrackerStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  for (final throwing in [false, true]) {
    test(
        'failed tracker write does not publish or leak into next save, throwing=$throwing',
        () async {
      store.reject = !throwing;
      store.throwWrite = throwing;
      try {
        await service.toggleObligatory('الفجر', DateTime(2026, 11, 21));
      } catch (_) {}
      final visible = service.getRecordForDate(DateTime(2026, 11, 21)).fajr;
      store.reject = false;
      store.throwWrite = false;
      await service.toggleSunnah('witr', DateTime(2026, 11, 21));
      final saved = jsonDecode(store.values[key] as String);
      expect(visible, isFalse);
      expect(saved['2026-11-21']['fajr'], isFalse);
    });
  }
  for (final raw in [
    '{broken',
    jsonEncode({
      '2026-11-20': {'dateStr': '2026-11-20', 'fajr': true},
      '2026-11-21': {'dateStr': '2026-11-21', 'fajr': 'bad'}
    })
  ]) {
    test(
        'unreadable tracker storage cannot be overwritten by a later edit: $raw',
        () async {
      store.values[key] = raw;
      SharedPreferences.resetStatic();
      try {
        await service.init(forceReload: true);
      } catch (_) {}
      try {
        await service.toggleSunnah('witr', DateTime(2026, 11, 21));
      } catch (_) {}
      expect(store.values[key], raw);
    });
  }
  test('pending edits do not publish and rapid double toggle is serialized',
      () async {
    final date = DateTime(2026, 11, 21);
    final gate = Completer<void>();
    store.hold = gate;
    final first = service.toggleObligatory('الفجر', date);
    final second = service.toggleObligatory('الفجر', date);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.getRecordForDate(date).fajr, isFalse);
    store.hold = null;
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(store.writes, 2);
    expect(service.getRecordForDate(date).fajr, isFalse);
    expect(
        jsonDecode(store.values[key] as String)['2026-11-21']['fajr'], isFalse);
  });

  test('all edit APIs reject failed writes and clear error only after success',
      () async {
    final date = DateTime(2026, 11, 21);
    store.reject = true;
    expect(
        await service.setPrayerFormStatus(
            prayerNameAr: 'الفجر',
            status: PrayerPerformanceStatus.missed,
            reasonText: 'reason',
            date: date),
        isFalse);
    expect(await service.toggleSunnah('witr', date), isFalse);
    expect(service.getRecordForDate(date).missedReasons, isEmpty);
    expect(service.storageError, isNotNull);
    store.reject = false;
    expect(
        await service.setPrayerFormStatus(
            prayerNameAr: 'الفجر',
            status: PrayerPerformanceStatus.onTimeIndividual,
            date: date),
        isTrue);
    expect(service.storageError, isNull);
    await service.init(forceReload: true);
    expect(service.getRecordForDate(date).getPrayerStatus('الفجر'),
        PrayerPerformanceStatus.onTimeIndividual);
  });

  test('legacy and unknown history fields survive unrelated edits', () async {
    final old = {
      'dateStr': '2025-01-01',
      'fajr': true,
      'futureField': {
        'x': [1, 2]
      }
    };
    store.values[key] = jsonEncode({'2025-01-01': old});
    await service.init(forceReload: true);
    expect(service.getRecordForDate(DateTime(2025, 1, 1)).fajr, isTrue);
    await service.toggleSunnah('witr', DateTime(2026, 11, 21));
    var saved = jsonDecode(store.values[key] as String);
    expect(saved['2025-01-01'], old);
    await service.toggleSunnah('duha', DateTime(2025, 1, 1));
    saved = jsonDecode(store.values[key] as String);
    expect(saved['2025-01-01']['futureField'], old['futureField']);
    expect(saved['2025-01-01']['fajr'], isTrue);
  });

  for (final raw in ['[]', '{"bad":42}', '']) {
    test('unsupported history stays intact: $raw', () async {
      store.values[key] = raw;
      await service.init(forceReload: true);
      expect(service.storageError, isNotNull);
      expect(await service.toggleObligatory('الفجر'), isFalse);
      expect(store.values[key], raw);
      expect(store.writes, 0);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('save failure stays readable and announced at ${scale}x',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.runAsync(() async {
        for (final family in ['Cairo', 'Amiri']) {
          final loader = FontLoader(family);
          final bytes =
              await File('assets/fonts/$family-Regular.ttf').readAsBytes();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
      await SettingsService.instance.init();
      store.reject = true;
      await service.toggleObligatory('الفجر');
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: RepaintBoundary(
              key: boundary, child: const PrayerTrackerScreen())));
      await tester.pumpAndSettle();
      final text = find.text(service.storageError!);
      expect(text, findsOneWidget);
      final rect = tester.getRect(text);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThan(800));
      final sem = tester.widget<Semantics>(
          find.ancestor(of: text, matching: find.byType(Semantics)).first);
      expect(sem.properties.liveRegion, isTrue);
      expect(service.todayRecord.fajr, isFalse);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/tracker1555/save-failure-$scale.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
  for (final congregation in [false, true]) {
    testWidgets(
        'adhan caller respects saved result and status, congregation=$congregation',
        (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await SettingsService.instance.init();
      IslamicAudioService.instance.disableNativePlayerForTesting = true;
      AdhanSensorGestureService.instance.accelerometerStreamOverride =
          const Stream<AccelerometerEvent>.empty();
      addTearDown(() {
        AdhanSensorGestureService.instance.accelerometerStreamOverride = null;
        IslamicAudioService.instance.disableNativePlayerForTesting = false;
      });
      await tester.pumpWidget(const MaterialApp(
          home: AdhanControlScreen(prayerName: 'العصر', autoPlay: false)));
      await tester.pump(const Duration(milliseconds: 100));
      final button = find.text(congregation ? 'جماعة بالمسجد' : 'صليت حاضراً');
      await tester.scrollUntilVisible(button, 350,
          scrollable: find.byType(Scrollable).first);
      store.reject = true;
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.todayRecord.asr, isFalse);
      expect(
          find.textContaining('تم تسجيل أداء صلاة العصر بنجاح'), findsNothing);
      expect(find.textContaining('لم يُحفظ التعديل'), findsOneWidget);
      store.reject = false;
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          service.todayRecord.getPrayerStatus('العصر'),
          congregation
              ? PrayerPerformanceStatus.onTimeCongregation
              : PrayerPerformanceStatus.onTimeIndividual);
      expect(find.textContaining('تم تسجيل أداء صلاة العصر بنجاح'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
