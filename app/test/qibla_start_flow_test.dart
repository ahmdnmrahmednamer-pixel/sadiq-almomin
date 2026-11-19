import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/prayer/qibla_compass_screen.dart';

class _Location implements PrayerLocationProvider {
  bool enabled = false;
  LocationPermission permission = LocationPermission.denied;
  int checks = 0;
  int prompts = 0;
  Future<Position> Function()? position;
  final updates = StreamController<Position>.broadcast();
  @override
  Future<bool> isLocationServiceEnabled() async {
    checks++;
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return permission = LocationPermission.whileInUse;
  }

  @override
  Future<bool> openLocationSettings() async => true;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<Position?> getLastKnownPosition() async => null;
  @override
  Future<Position> getCurrentPosition(
          {required LocationAccuracy desiredAccuracy,
          required Duration timeLimit}) =>
      position!();
  @override
  Stream<Position> getPositionStream(
          {required LocationSettings locationSettings}) =>
      updates.stream;
  @override
  double distanceBetween(double a, double b, double c, double d) =>
      Geolocator.distanceBetween(a, b, c, d);
}

Position _fix(DateTime now) => Position(
    longitude: 31.2357,
    latitude: 30.0444,
    timestamp: now,
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Location location;
  late StreamController<MagnetometerEvent> sensor;
  late DateTime clock;
  int listens = 0;
  const action = ValueKey('qibla_check_direction_button');
  const needle = ValueKey('qibla_direction_needle');

  Future<void> mount(WidgetTester tester,
      {Size size = const Size(360, 800),
      double scale = 1,
      GlobalKey? boundary}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
            data: MediaQueryData(
                size: size, textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
                key: boundary,
                child: QiblaCompassScreen(
                    magnetometerStreamForTesting: sensor.stream,
                    nowProviderForTesting: () => clock)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const out = String.fromEnvironment('QIBLA_PIXELS_DIR');
    if (out.isEmpty) return;
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(out).create(recursive: true);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  setUpAll(() async {
    tz.initializeTimeZones();
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(
            ByteData.sublistView(await File(icons).readAsBytes())));
      await loader.load();
    }
    for (final family in ['Amiri', 'Cairo']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(
            await File('assets/fonts/$family-Regular.ttf').readAsBytes())));
      await loader.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'pendingNotificationRequests') return <dynamic>[];
      return null;
    });
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init();
    clock = DateTime(2026, 11, 19, 12);
    location = _Location()..position = () async => _fix(clock);
    listens = 0;
    sensor = StreamController<MagnetometerEvent>.broadcast(onListen: () {
      listens++;
    });
    PrayerService.instance.setClockForTesting(() => clock);
    PrayerService.instance.setLocationProviderForTesting(location);
    await PrayerService.instance.init(forceReload: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  tearDown(() async {
    PrayerService.instance.stopLiveTicker();
    PrayerService.instance.setClockForTesting(null);
    PrayerService.instance.setLocationProviderForTesting(null);
    await sensor.close();
    await location.updates.close();
  });

  testWidgets(
      'explicit check works by screen-reader activation without inventing GPS',
      (tester) async {
    final semantics = tester.ensureSemantics();

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    expect(find.text('بوصلة القبلة التفاعلية'), findsOneWidget);
    expect(find.text('تحقق من اتجاه القبلة'), findsOneWidget);
    expect(find.byKey(needle), findsNothing);
    final before = location.checks;
    final node = tester.getSemantics(find.byKey(action));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    await flush(tester);
    expect(location.checks, greaterThan(before));
    expect(location.prompts, 0);
    expect(find.text('إعادة التحقق من القبلة'), findsOneWidget);
    expect(find.byKey(needle), findsNothing);
    expect(PrayerService.instance.currentData, isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets(
      'check requests existing GPS permission flow, disables repeat while waiting, and stays safe on dispose',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    location.enabled = true;
    final pending = Completer<Position>();
    location.position = () => pending.future;
    await tester.tap(find.byKey(action));
    await flush(tester);
    expect(location.prompts, 1);
    expect(find.text('جارٍ التحقق من الموقع والقبلة'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(action)).onPressed, isNull);
    expect(find.byKey(needle), findsNothing);
    await tester.pumpWidget(const SizedBox());
    pending.complete(_fix(clock));
    await flush(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'explicit retry recovers failed sensor, preserves alignment and rejects stale readings',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await mount(tester, scale: 2, boundary: boundary);
    location.enabled = true;
    location.permission = LocationPermission.whileInUse;
    await tester.runAsync(() => PrayerService.instance.requestGpsLocation());
    await tester.pump();
    final bearing =
        PrayerService.instance.currentData!.qiblaDegrees * math.pi / 180;
    sensor.addError(Exception('sensor unavailable'));
    await tester.pump();
    expect(find.byKey(needle), findsNothing);
    final previous = listens;
    await tester.tap(find.byKey(action));
    await flush(tester);
    expect(listens, greaterThan(previous));
    expect(find.byKey(needle), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('qibla_guidance_banner')));
    await tester.pump();
    await capture(tester, boundary, 'qibla_retry_waiting_360x800_2x');
    sensor.add(
        MagnetometerEvent(-25 * math.sin(bearing), 25 * math.cos(bearing), 0));
    await tester.pump();
    expect(find.byKey(needle), findsOneWidget);
    expect(find.textContaining('أنت الآن باتجاه القبلة'), findsOneWidget);
    await capture(tester, boundary, 'qibla_retry_aligned_360x800_2x');
    clock = clock.add(QiblaCompassScreen.sensorHeadingStaleTimeout);
    await tester.pump(QiblaCompassScreen.sensorHeadingStaleTimeout);
    await tester.pump();
    expect(find.byKey(needle), findsNothing);
    expect(find.textContaining('أنت الآن باتجاه القبلة'), findsNothing);
    await capture(tester, boundary, 'qibla_retry_stale_360x800_2x');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'check controls remain visible and actionable at narrow and large-text sizes',
      (tester) async {
    final semantics = tester.ensureSemantics();

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      for (final scale in [1.0, 2.0]) {
        final key = GlobalKey();
        await mount(tester, size: size, scale: scale, boundary: key);
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(find.byKey(action));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThan(size.height));
        expect(
            tester
                .getSemantics(find.byKey(action))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue);
        await capture(tester, key,
            'qibla_${size.width.toInt()}x${size.height.toInt()}_${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox());
      }
    }
    semantics.dispose();
  });
}
