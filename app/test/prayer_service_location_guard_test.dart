import 'dart:async';
import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:timezone/timezone.dart' as timezone;
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
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/backup/backup_restore_screen.dart';
import 'package:almomin/features/egypt/egyptian_heritage_screen.dart';
import 'package:almomin/features/home/widgets/home_next_prayer_card.dart';
import 'package:almomin/features/onboarding/onboarding_screen.dart';
import 'package:almomin/features/prayer/fajr_qiyam_alarm_screen.dart';
import 'package:almomin/features/prayer/qibla_compass_screen.dart';
import 'package:almomin/features/prayer/widgets/prayer_location_banner.dart';
import 'package:almomin/features/prayer/widgets/prayer_times_card.dart';
import 'package:almomin/features/ramadan/ramadan_screen.dart';
import 'package:almomin/features/settings/widgets/sections/settings_prayer_and_fiqh_section.dart';

const MethodChannel _kSharedPrefsChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

const MethodChannel _kLocalNotificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

const MethodChannel _kSensorsMethodChannel = MethodChannel(
  'dev.fluttercommunity.plus/sensors/method',
);

const MethodChannel _kSensorsMagnetometerChannel = MethodChannel(
  'dev.fluttercommunity.plus/sensors/magnetometer',
);

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_GPS_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_GPS_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

/// Deterministic mock SharedPreferences backend using MethodChannel so
/// individual persistence writes can be paused/interleaved via [onBeforeWrite].
class _ControllableMockSharedPreferences {
  final Map<String, Object> _storage = <String, Object>{};
  final List<Future<void>> _inFlightWrites = <Future<void>>[];

  Future<void> Function(String key, Object value)? onBeforeWrite;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kSharedPrefsChannel, _handleCall);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kSharedPrefsChannel, null);
  }

  void reset([Map<String, Object> initialValues = const <String, Object>{}]) {
    onBeforeWrite = null;
    _inFlightWrites.clear();
    _storage.clear();
    for (final entry in initialValues.entries) {
      final prefixedKey = entry.key.startsWith('flutter.')
          ? entry.key
          : 'flutter.${entry.key}';
      _storage[prefixedKey] = entry.value;
    }
    SharedPreferences.resetStatic();
  }

  Object? readPersisted(String key) {
    final prefixedKey = key.startsWith('flutter.') ? key : 'flutter.$key';
    return _storage[prefixedKey];
  }

  Future<void> waitForAllWrites() async {
    while (_inFlightWrites.isNotEmpty) {
      final batch = List<Future<void>>.from(_inFlightWrites);
      await Future.wait(batch);
      await Future<void>.microtask(() {});
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'getAll':
      case 'getAllWithParameters':
        return Map<String, Object>.from(_storage);
      case 'setBool':
      case 'setDouble':
      case 'setInt':
      case 'setString':
      case 'setStringList':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String;
        final value = args['value'] as Object;
        final unprefixedKey =
            key.startsWith('flutter.') ? key.substring('flutter.'.length) : key;
        final completer = Completer<void>();
        _inFlightWrites.add(completer.future);
        try {
          if (onBeforeWrite != null) {
            await onBeforeWrite!(unprefixedKey, value);
          }
          _storage[key] = value;
          return true;
        } finally {
          if (!completer.isCompleted) {
            completer.complete();
          }
          _inFlightWrites.remove(completer.future);
        }
      case 'remove':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _storage.remove(args['key'] as String);
        return true;
      case 'clear':
      case 'clearWithParameters':
        _storage.clear();
        return true;
      default:
        return null;
    }
  }
}

Position _pos(
  double lat,
  double lng, {
  double accuracy = 10.0,
  DateTime? timestamp,
}) {
  return Position(
    longitude: lng,
    latitude: lat,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0.0,
    altitudeAccuracy: 0.0,
    heading: 0.0,
    headingAccuracy: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );
}

class _FakeLocationProvider implements PrayerLocationProvider {
  bool serviceEnabled = true;
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  LocationPermission requestPermissionResult = LocationPermission.whileInUse;
  bool openLocationSettingsResult = true;
  bool openAppSettingsResult = true;
  Position? lastKnownPosition;
  Future<Position> Function()? onGetCurrentPosition;
  final StreamController<Position> positionStreamController =
      StreamController<Position>.broadcast();

  int isServiceEnabledCalls = 0;
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int openLocationSettingsCalls = 0;
  int openAppSettingsCalls = 0;
  int getLastKnownCalls = 0;
  int getCurrentPositionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async {
    isServiceEnabledCalls++;
    return serviceEnabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    return checkPermissionResult;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    return requestPermissionResult;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls++;
    return openLocationSettingsResult;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return openAppSettingsResult;
  }

  @override
  Future<Position?> getLastKnownPosition() async {
    getLastKnownCalls++;
    return lastKnownPosition;
  }

  @override
  Future<Position> getCurrentPosition({
    required LocationAccuracy desiredAccuracy,
    required Duration timeLimit,
  }) async {
    getCurrentPositionCalls++;
    if (onGetCurrentPosition != null) {
      return onGetCurrentPosition!();
    }
    return _pos(51.5074, -0.1278);
  }

  @override
  Stream<Position> getPositionStream({
    required LocationSettings locationSettings,
  }) {
    return positionStreamController.stream;
  }

  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  Future<void> dispose() async {
    await positionStreamController.close();
  }
}

String? _resolveMaterialIconsFontPath() {
  final candidates = <String>[
    if (_kMaterialIconsFontPath.isNotEmpty) _kMaterialIconsFontPath,
    if (Platform.environment['FLUTTER_ROOT'] != null &&
        Platform.environment['FLUTTER_ROOT']!.isNotEmpty)
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];

  // Also walk up from the running dart/flutter_tester executable to find bin/cache/artifacts/material_fonts
  Directory dir = File(Platform.resolvedExecutable).parent;
  for (int i = 0; i < 8; i++) {
    candidates.add(
      '${dir.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    candidates.add(
      '${dir.path}/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    candidates.add(
      '${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync() && file.lengthSync() > 0) {
      return file.path;
    }
  }
  return null;
}

bool _fontsLoaded = false;
Future<void> _loadRealAppFonts() async {
  if (_fontsLoaded) return;
  Future<bool> loadFont(String family, List<String> paths) async {
    final loader = FontLoader(family);
    int added = 0;
    for (final p in paths) {
      final file = File(p);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
        added++;
      }
    }
    if (added > 0) {
      await loader.load();
      return true;
    }
    return false;
  }

  await loadFont('Cairo', [
    'assets/fonts/Cairo-Regular.ttf',
  ]);
  await loadFont('monospace', [
    'assets/fonts/Cairo-Regular.ttf',
  ]);
  await loadFont('Amiri', [
    'assets/fonts/Amiri-Regular.ttf',
    'assets/fonts/Amiri-Bold.ttf',
  ]);
  final matPath = _resolveMaterialIconsFontPath();
  final matLoaded = matPath != null && await loadFont('MaterialIcons', [matPath]);
  if (_kCapturePixels) {
    expect(
      matLoaded,
      isTrue,
      reason: 'Real MaterialIcons font must be loaded for pixel capture so icons never render as missing boxes',
    );
  }
  _fontsLoaded = true;
}

Future<void> _maybeCapturePng(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String fileName,
) async {
  if (!_kCapturePixels || _kCaptureOutDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final outFile = File('$_kCaptureOutDir/$fileName');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockPrefs = _ControllableMockSharedPreferences();
  final notifCalls = <MethodCall>[];
  final activeOsNotifications = <int, Map<String, dynamic>>{};
  Future<void> Function(MethodCall call)? onBeforeNotifCall;
  final inFlightNotifOps = <Future<void>>[];
  late _FakeLocationProvider fakeProvider;

  Future<void> waitForAllNotifOps() async {
    while (inFlightNotifOps.isNotEmpty) {
      final batch = List<Future<void>>.from(inFlightNotifOps);
      await Future.wait(batch);
      await Future<void>.microtask(() {});
    }
  }

  setUpAll(() {
    tz_data.initializeTimeZones();
    mockPrefs.install();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kLocalNotificationsChannel, (call) async {
      final opCompleter = Completer<void>();
      inFlightNotifOps.add(opCompleter.future);
      try {
        if (onBeforeNotifCall != null) {
          await onBeforeNotifCall!(call);
        }
        notifCalls.add(call);
        if (call.method == 'initialize') return true;
        if (call.method == 'pendingNotificationRequests') return <dynamic>[];
        if (call.method == 'zonedSchedule' && call.arguments is Map) {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final id = args['id'];
          if (id is int) {
            activeOsNotifications[id] = args;
          }
        } else if (call.method == 'cancel') {
          final args = call.arguments;
          final id = args is int
              ? args
              : (args is Map && args['id'] is int ? args['id'] as int : null);
          if (id != null) {
            activeOsNotifications.remove(id);
          }
        } else if (call.method == 'cancelAll') {
          activeOsNotifications.clear();
        }
        return null;
      } finally {
        if (!opCompleter.isCompleted) {
          opCompleter.complete();
        }
        inFlightNotifOps.remove(opCompleter.future);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kSensorsMethodChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kSensorsMagnetometerChannel, (_) async => null);
  });

  tearDownAll(() {
    mockPrefs.uninstall();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kLocalNotificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kSensorsMethodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kSensorsMagnetometerChannel, null);
  });

  setUp(() async {
    mockPrefs.reset();
    onBeforeNotifCall = null;
    notifCalls.clear();
    activeOsNotifications.clear();
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init();
    fakeProvider = _FakeLocationProvider();
    PrayerService.instance.setClockForTesting(null);
    PrayerService.instance.setLocationProviderForTesting(fakeProvider);
  });

  tearDown(() async {
    mockPrefs.onBeforeWrite = null;
    onBeforeNotifCall = null;
    PrayerService.instance.stopLiveTicker();
    PrayerService.instance.setClockForTesting(null);
    PrayerService.instance.setLocationProviderForTesting(null);
    await fakeProvider.dispose();
    await mockPrefs.waitForAllWrites();
    await waitForAllNotifOps();
  });

  testWidgets('seven calendar days survive stopped Dart ticker with distinct times and bounded IDs', (tester) async {
    final oldZone = timezone.local;
    timezone.setLocalLocation(timezone.getLocation('Africa/Cairo'));
    addTearDown(() => timezone.setLocalLocation(oldZone));
    final clock = DateTime(2027, 1, 31, 0, 0, 1);
    PrayerService.instance.setClockForTesting(() => clock);
    mockPrefs.reset({
      PrayerService.locationSourceKey: PrayerService.locationSourceGps,
      PrayerService.locationUpdatedAtMsKey: clock.toUtc().millisecondsSinceEpoch,
      'last_latitude': 30.0, 'last_longitude': 31.0, 'last_city': 'موقع محفوظ',
      'notif_master_enabled': true, 'notif_prayer_الشروق': true,
    });
    fakeProvider..serviceEnabled = true..checkPermissionResult = LocationPermission.denied;
     await SettingsService.instance.init(forceReload: true); 
    await tester.runAsync(() => PrayerNotificationService.instance.init(forceReload: true)); 
    await PrayerService.instance.init(forceReload: true); 
    await tester.pump(const Duration(milliseconds: 100));
    await waitForAllNotifOps();
    await tester.pump(const Duration(milliseconds: 100));
    await waitForAllNotifOps();
    final data = PrayerService.instance.currentData!;
    expect(data.prayers, hasLength(6), reason: 'display stays today only');
    expect(data.notificationPrayers, hasLength(42));
    final previous = adhan.PrayerTimes(coordinates: adhan.Coordinates(30,31),
      date: DateTime(clock.year, clock.month, clock.day - 1),
      calculationParameters: adhan.CalculationMethodParameters.egyptian());
    expect(data.previousMaghribTime, previous.maghrib.toLocal());
    await tester.pump(const Duration(seconds: 1));
    expect(PrayerService.instance.currentData!.previousMaghribTime, previous.maghrib.toLocal(),
      reason: 'countdown state copies retain the independently calculated prior sunset');
    expect(identical(PrayerService.instance.currentData, data), isFalse,
      reason: 'the ticker really produced a new countdown state');
    PrayerService.instance.stopLiveTicker();

    for (var day = 0; day < 7; day++) {
      final date = DateTime(clock.year, clock.month, clock.day + day);
      final expected = adhan.PrayerTimes(coordinates: adhan.Coordinates(30,31), date: date,
        calculationParameters: adhan.CalculationMethodParameters.egyptian());
      final fajr = data.notificationPrayers![day * 6];
      expect(fajr.time, expected.fajr.toLocal());
      final scheduled = activeOsNotifications.values.where((v) => v['payload'] == 'type=adhan&prayer=الفجر');
      expect(scheduled.any((v) => v['scheduledDateTime'] == timezone.TZDateTime.from(fajr.time, timezone.getLocation(v['timeZoneName'] as String)).toIso8601String().split('.').first), isTrue);
    }
    final derived = activeOsNotifications.entries.where((e) => e.key >= 100 && e.key <= 399).toList();
    expect(derived.length, 161, reason: '23 independently dated alarms per day for all seven days');
    expect(derived.map((e)=>e.key).toSet().length, derived.length);
    expect(derived.any((e) => e.key > 139), isTrue);
    final before = Map<int,Map<String,dynamic>>.from(activeOsNotifications);
     await tester.pump(const Duration(days: 2)); 
    expect(activeOsNotifications, before, reason: 'already handed to OS channel, no Dart ticker renewal needed inside finite window');
    notifCalls.clear();
    await PrayerService.instance.clearLocationToUnknown(); 
    await waitForAllNotifOps();
    expect(activeOsNotifications.keys.where((id) => id >= 100 && id <= 399), isEmpty);
    expect(notifCalls.any((c)=>c.method=='cancelAll'), isFalse);
  });

  group('GPS-Only Core: Legacy Migration, Provenance, Freshness & Etiquette', () {
    testWidgets('countdown boundary keeps due OS alarm while moving next prayer; midnight still rebuilds', (tester) async {
      var clock = DateTime(2026, 11, 21, 9);
      PrayerService.instance.setClockForTesting(() => clock);
      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey: clock.toUtc().millisecondsSinceEpoch,
        'last_latitude': 30.0, 'last_longitude': 31.0, 'last_city': 'موقع محفوظ',
      });
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);
      await tester.pump(const Duration(milliseconds: 100));
      await waitForAllNotifOps();
      await tester.pump(const Duration(milliseconds: 100));
      await waitForAllNotifOps();
      final before = PrayerService.instance.currentData!;
      final next = before.nextPrayer!;
      expect(next.time.day, before.lastUpdated.day);
      final scheduledBefore = Map<int, Map<String, dynamic>>.from(activeOsNotifications);
      notifCalls.clear();
      clock = next.time.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await waitForAllNotifOps();
      expect(PrayerService.instance.currentData!.nextPrayer!.time.isAfter(clock), isTrue);
      expect(notifCalls.where((c) => c.method == 'cancel' || c.method == 'zonedSchedule'), isEmpty,
        reason: 'countdown must not cancel the due alarm at delivery time');
      expect(activeOsNotifications, scheduledBefore);
      clock = DateTime(clock.year, clock.month, clock.day + 1, 0, 0, 1);
      await tester.pump(const Duration(seconds: 1));
      await waitForAllNotifOps();
      expect(PrayerService.instance.currentData!.lastUpdated.day, clock.day);
      expect(notifCalls.any((c) => c.method == 'zonedSchedule'), isTrue);
      PrayerService.instance.stopLiveTicker();
    });

    test('Fresh install starts UNKNOWN (no Cairo fallback) and never auto-prompts permission', () async {
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied
        ..requestPermissionResult = LocationPermission.whileInUse;

      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(PrayerService.instance.currentData, isNull);
      expect(PrayerService.instance.hasVerifiedGpsLocation, isFalse);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
      expect(PrayerService.instance.lastGpsFixTime, isNull);
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.permissionDenied));
      expect(fakeProvider.checkPermissionCalls, greaterThanOrEqualTo(1));
      expect(fakeProvider.requestPermissionCalls, equals(0));
      expect(fakeProvider.getCurrentPositionCalls, equals(0));
      expect(mockPrefs.readPersisted('last_city'), isNull);
      expect(mockPrefs.readPersisted('last_latitude'), isNull);
    });

    test('Legacy manual, untagged, default Cairo, or missing-timestamp prefs migrate to UNKNOWN and NEVER relabel as GPS', () async {
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;

      final legacyPayloads = <Map<String, Object>>[
        // 1) Legacy manual city selection
        {
          'is_manual_location': true,
          'auto_location_enabled': false,
          'last_latitude': 31.2001,
          'last_longitude': 29.9187,
          'last_city': 'الإسكندرية، مصر',
          'last_country': 'مصر',
        },
        // 2) Legacy untagged Cairo default (no location_source)
        {
          'last_latitude': 30.0444,
          'last_longitude': 31.2357,
          'last_city': 'القاهرة، مصر',
        },
        // 3) Tagged GPS but missing required timestamp
        {
          PrayerService.locationSourceKey: PrayerService.locationSourceGps,
          'last_latitude': 24.7136,
          'last_longitude': 46.6753,
          'last_city': 'الرياض، السعودية (موقعك الفعلي)',
        },
        // 4) Tagged GPS but conflicting legacy is_manual_location == true
        {
          PrayerService.locationSourceKey: PrayerService.locationSourceGps,
          PrayerService.locationUpdatedAtMsKey:
              DateTime.now().toUtc().millisecondsSinceEpoch,
          'is_manual_location': true,
          'last_latitude': 24.7136,
          'last_longitude': 46.6753,
          'last_city': 'الرياض، السعودية',
        },
      ];

      for (final payload in legacyPayloads) {
        mockPrefs.reset(payload);
        await SettingsService.instance.init(forceReload: true);
        await PrayerService.instance.init(forceReload: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await mockPrefs.waitForAllWrites();

        expect(PrayerService.instance.currentData, isNull);
        expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
        expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), isNull);
        expect(mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey), isNull);
        expect(mockPrefs.readPersisted('last_latitude'), isNull);
        expect(mockPrefs.readPersisted('last_longitude'), isNull);
        expect(mockPrefs.readPersisted('last_city'), isNull);
        expect(mockPrefs.readPersisted('is_manual_location'), isNull);
        expect(mockPrefs.readPersisted('auto_location_enabled'), isNull);
        expect(mockPrefs.readPersisted('last_country'), isNull);
      }
    });

    test('Verified GPS cache is always visibly saved/cached (never current for 2h cache); only recent (<15m) live fix is current', () async {
      final baseTime = DateTime(2026, 11, 18, 12, 0);
      PrayerService.instance.setClockForTesting(() => baseTime);

      // 1) 2-hour-old persisted GPS cache -> MUST be cachedStale (never current!)
      final twoHoursAgo = baseTime.subtract(const Duration(hours: 2));
      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey:
            twoHoursAgo.toUtc().millisecondsSinceEpoch,
        'last_latitude': 51.5074,
        'last_longitude': -0.1278,
        'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
      });
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;

      await PrayerService.instance.init(forceReload: true);
      expect(PrayerService.instance.currentData, isNotNull);
      expect(PrayerService.instance.isLocationStale, isTrue);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));
      expect(PrayerService.instance.cachedFixAgeLabel, contains('ساعة'));

      // 2) Even a 5-minute-old persisted cache loaded from disk (no live fix yet) stays visibly cached
      final fiveMinAgo = baseTime.subtract(const Duration(minutes: 5));
      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey:
            fiveMinAgo.toUtc().millisecondsSinceEpoch,
        'last_latitude': 51.5074,
        'last_longitude': -0.1278,
        'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
      });
      await PrayerService.instance.init(forceReload: true);
      expect(PrayerService.instance.isLocationStale, isTrue);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));

      // 3) Live GPS refresh with recent (<15m) timestamp transitions to current
      final liveNow = baseTime.add(const Duration(minutes: 10));
      PrayerService.instance.setClockForTesting(() => liveNow);
      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition = () async => _pos(
              51.5074,
              -0.1278,
              timestamp: liveNow.subtract(const Duration(minutes: 1)),
            );
      final refreshed = await PrayerService.instance.requestGpsLocation();
      await mockPrefs.waitForAllWrites();
      expect(refreshed, isTrue);
      expect(PrayerService.instance.isLocationStale, isFalse);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.current));

      // 4) Advance clock past 15-minute cutoff -> live fix transitions to cachedStale
      PrayerService.instance.setClockForTesting(
        () => liveNow.add(const Duration(minutes: 16)),
      );
      expect(PrayerService.instance.isLocationStale, isTrue);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));
    });

    test('Explicit GPS distinguishes all 5 failures, delegates settings affordances, rejects invalid coords, and clears error on success', () async {
      fakeProvider
        ..serviceEnabled = false
        ..checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);

      // 1) Service disabled + openLocationSettings
      expect(await PrayerService.instance.requestGpsLocation(), isFalse);
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.serviceDisabled));
      final disabledMsg = PrayerService.instance.errorMessage!;
      expect(await PrayerService.instance.openLocationSettings(), isTrue);
      expect(fakeProvider.openLocationSettingsCalls, equals(1));

      // 2) Permission denied
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied
        ..requestPermissionResult = LocationPermission.denied
        ..requestPermissionCalls = 0;
      expect(await PrayerService.instance.requestGpsLocation(), isFalse);
      expect(fakeProvider.requestPermissionCalls, equals(1));
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.permissionDenied));
      final deniedMsg = PrayerService.instance.errorMessage!;

      // 3) Permission deniedForever + openAppSettings (must NOT call requestPermission)
      fakeProvider
        ..checkPermissionResult = LocationPermission.deniedForever
        ..requestPermissionCalls = 0;
      expect(await PrayerService.instance.requestGpsLocation(), isFalse);
      expect(fakeProvider.requestPermissionCalls, equals(0));
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.permissionDeniedForever));
      final deniedForeverMsg = PrayerService.instance.errorMessage!;
      expect(await PrayerService.instance.openAppSettings(), isTrue);
      expect(fakeProvider.openAppSettingsCalls, equals(1));

      // 4) Timeout
      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition = () => Future<Position>.error(TimeoutException('GPS timeout'));
      expect(await PrayerService.instance.requestGpsLocation(), isFalse);
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.timeout));
      final timeoutMsg = PrayerService.instance.errorMessage!;

      // 5) Generic error
      fakeProvider.onGetCurrentPosition = () => Future<Position>.error(Exception('sensor failure'));
      expect(await PrayerService.instance.requestGpsLocation(), isFalse);
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.unavailable));
      final genericMsg = PrayerService.instance.errorMessage!;

      expect({disabledMsg, deniedMsg, deniedForeverMsg, timeoutMsg, genericMsg}.length, equals(5));

      // 6) Invalid/non-finite GPS coordinates rejected with zero pref writes
      for (final (lat, lng) in <(double, double)>[
        (double.nan, 10.0),
        (20.0, double.infinity),
        (91.0, 0.0),
        (0.0, -181.0),
      ]) {
        fakeProvider
          ..lastKnownPosition = _pos(lat, lng)
          ..onGetCurrentPosition = () async => _pos(lat, lng);
        expect(await PrayerService.instance.requestGpsLocation(), isFalse);
        expect(PrayerService.instance.currentData, isNull);
        expect(mockPrefs.readPersisted('last_latitude'), isNull);
      }

      // 7) Valid worldwide GPS fix clears error and persists verified provenance
      fakeProvider
        ..lastKnownPosition = null
        ..onGetCurrentPosition = () async => _pos(35.6762, 139.6503);
      expect(await PrayerService.instance.requestGpsLocation(), isTrue);
      await mockPrefs.waitForAllWrites();
      expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.none));
      expect(PrayerService.instance.errorMessage, isNull);
      expect(PrayerService.instance.currentData?.locationName, equals('موقعك الفعلي (35.68°, 139.65°)'));
      expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), equals(PrayerService.locationSourceGps));
      expect(mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey), isA<int>());
    });
  });

  group('Adversarial Timestamp Integrity: Old Cache, Resume Repeat, Old Stream, Future GPS & Persisted Future', () {
    test('oldaccuratecache: accurate but old OS lastKnownPosition triggers live refresh and never renews by receipt when refresh fails', () async {
      final now = DateTime(2026, 11, 18, 14, 0);
      final oldFixTime = now.subtract(const Duration(hours: 10));
      PrayerService.instance.setClockForTesting(() => now);

      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Part A: OS lastKnownPosition is accurate (5m) but 10 hours old; getCurrentPosition returns a fresh fix
      final freshFixTime = now.subtract(const Duration(minutes: 2));
      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..getCurrentPositionCalls = 0
        ..lastKnownPosition =
            _pos(51.5074, -0.1278, accuracy: 5.0, timestamp: oldFixTime)
        ..onGetCurrentPosition =
            () async => _pos(48.8566, 2.3522, accuracy: 8.0, timestamp: freshFixTime);

      expect(
        await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false),
        isTrue,
      );
      await mockPrefs.waitForAllWrites();
      expect(fakeProvider.getCurrentPositionCalls, equals(1));
      expect(PrayerService.instance.currentData?.latitude, closeTo(48.8566, 0.0001));
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.current));
      expect(
        PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
        equals(freshFixTime.toUtc().millisecondsSinceEpoch),
      );
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(freshFixTime.toUtc().millisecondsSinceEpoch),
      );

      // Part B: On fresh UNKNOWN start, old accurate OS lastKnownPosition when live getCurrentPosition times out
      // must NEVER be stamped with receipt time `now` (must remain visibly cachedStale with oldFixTime)
      mockPrefs.reset();
      fakeProvider.checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..getCurrentPositionCalls = 0
        ..lastKnownPosition =
            _pos(51.5074, -0.1278, accuracy: 5.0, timestamp: oldFixTime)
        ..onGetCurrentPosition =
            () => Future<Position>.error(TimeoutException('GPS timeout'));

      await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false);
      await mockPrefs.waitForAllWrites();
      expect(fakeProvider.getCurrentPositionCalls, equals(1));
      expect(PrayerService.instance.currentData, isNotNull);
      expect(PrayerService.instance.isLocationStale, isTrue);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));
      expect(
        PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
        equals(oldFixTime.toUtc().millisecondsSinceEpoch),
      );
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(oldFixTime.toUtc().millisecondsSinceEpoch),
      );
    });

    test('resumerepeat: repeated resumes with same old OS fix never renew cached timestamp to current', () async {
      final now = DateTime(2026, 11, 18, 16, 0);
      final oldFixTime = now.subtract(const Duration(hours: 9));
      PrayerService.instance.setClockForTesting(() => now);

      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey: oldFixTime.toUtc().millisecondsSinceEpoch,
        'last_latitude': 51.5074,
        'last_longitude': -0.1278,
        'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
      });
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.whileInUse
        ..lastKnownPosition =
            _pos(51.5074, -0.1278, accuracy: 5.0, timestamp: oldFixTime)
        ..onGetCurrentPosition =
            () async => _pos(51.5074, -0.1278, accuracy: 5.0, timestamp: oldFixTime);

      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      for (int i = 0; i < 3; i++) {
        PrayerService.instance.setClockForTesting(
          () => now.add(Duration(minutes: i * 15)),
        );
        await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false);
        await mockPrefs.waitForAllWrites();

        expect(PrayerService.instance.isLocationStale, isTrue);
        expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));
        expect(
          PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
          equals(oldFixTime.toUtc().millisecondsSinceEpoch),
        );
        expect(
          mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
          equals(oldFixTime.toUtc().millisecondsSinceEpoch),
        );
      }
    });

    test('oldstream: old streamed fix never overwrites newer fix or renews timestamp as current', () async {
      final now = DateTime(2026, 11, 18, 18, 0);
      final currentFixTime = now.subtract(const Duration(minutes: 5));
      final oldStreamFixTime = now.subtract(const Duration(hours: 12));
      PrayerService.instance.setClockForTesting(() => now);

      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition =
            () async => _pos(51.5074, -0.1278, timestamp: currentFixTime);

      await PrayerService.instance.init(forceReload: true);
      expect(
        await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false),
        isTrue,
      );
      await mockPrefs.waitForAllWrites();

      // Emit an old (12h-ago) streamed fix for Tokyo -> must NOT overwrite newer London fix
      fakeProvider.positionStreamController.add(
        _pos(35.6762, 139.6503, timestamp: oldStreamFixTime),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData?.latitude, closeTo(51.5074, 0.0001));
      expect(
        PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
        equals(currentFixTime.toUtc().millisecondsSinceEpoch),
      );

      // Even if a stream emits a fix that is newer than existing (say existing was 20h ago, stream is 10h ago),
      // it MUST keep the true 10h-old acquisition timestamp and stay cachedStale, NEVER current!
      final veryOldFix = now.subtract(const Duration(hours: 20));
      final tenHoursOldFix = now.subtract(const Duration(hours: 10));
      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey: veryOldFix.toUtc().millisecondsSinceEpoch,
        'last_latitude': 51.5074,
        'last_longitude': -0.1278,
        'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
      });
      fakeProvider.onGetCurrentPosition =
          () async => _pos(51.5074, -0.1278, timestamp: veryOldFix);
      await PrayerService.instance.init(forceReload: true);
      await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false);
      await mockPrefs.waitForAllWrites();

      fakeProvider.positionStreamController.add(
        _pos(35.6762, 139.6503, timestamp: tenHoursOldFix),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData?.latitude, closeTo(35.6762, 0.0001));
      expect(PrayerService.instance.isLocationStale, isTrue);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));
      expect(
        PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
        equals(tenHoursOldFix.toUtc().millisecondsSinceEpoch),
      );
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(tenHoursOldFix.toUtc().millisecondsSinceEpoch),
      );
    });

    test('sameplace_newstream: strictly newer same-place streamed fix updates provenance/timestamp/freshness without recalculating prayers, rejects old replay, and stays safe under delayed clearLocationToUnknown', () async {
      final now = DateTime(2026, 11, 18, 18, 0);
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      final recentStreamTime = now.subtract(const Duration(minutes: 1));
      final olderReplayTime = now.subtract(const Duration(minutes: 10));
      PrayerService.instance.setClockForTesting(() => now);

      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey: twoHoursAgo.toUtc().millisecondsSinceEpoch,
        'last_latitude': 51.5074,
        'last_longitude': -0.1278,
        'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
      });
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.whileInUse
        ..lastKnownPosition = _pos(51.5074, -0.1278, timestamp: twoHoursAgo)
        ..onGetCurrentPosition = () => Future<Position>.error(TimeoutException('live timeout'));

      await PrayerService.instance.init(forceReload: true);
      await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false);
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData, isNotNull);
      expect(PrayerService.instance.isLocationStale, isTrue);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.cachedStale));
      final initialCalculatedAt = PrayerService.instance.currentData!.lastUpdated;

      // Wait 15ms so any unnecessary _calculatePrayers() call would produce a different lastUpdated timestamp
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 1) Emit strictly newer streamed fix at the SAME place (~11m away, < 2500m, same city label)
      fakeProvider.positionStreamController.add(
        _pos(51.5075, -0.1278, timestamp: recentStreamTime),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await mockPrefs.waitForAllWrites();

      expect(
        PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
        equals(recentStreamTime.toUtc().millisecondsSinceEpoch),
        reason: 'Strictly newer same-place streamed fix must update lastGpsFixTime',
      );
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(recentStreamTime.toUtc().millisecondsSinceEpoch),
        reason: 'Strictly newer same-place streamed fix must persist updated timestamp',
      );
      expect(
        mockPrefs.readPersisted(PrayerService.locationSourceKey),
        equals(PrayerService.locationSourceGps),
      );
      expect(PrayerService.instance.isLocationStale, isFalse);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.current));
      expect(
        PrayerService.instance.currentData!.lastUpdated,
        equals(initialCalculatedAt),
        reason: 'Stationary same-place refresh must NOT trigger unnecessary prayer recalculation',
      );

      // 2) Older/replayed same-place stream fix must still be rejected
      fakeProvider.positionStreamController.add(
        _pos(51.5075, -0.1278, timestamp: olderReplayTime),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await mockPrefs.waitForAllWrites();
      expect(
        PrayerService.instance.lastGpsFixTime?.toUtc().millisecondsSinceEpoch,
        equals(recentStreamTime.toUtc().millisecondsSinceEpoch),
      );
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(recentStreamTime.toUtc().millisecondsSinceEpoch),
      );

      // 3) Delayed clearLocationToUnknown() while same-place stream write is paused mid-persistence
      final writeStarted = Completer<void>();
      final writeRelease = Completer<void>();
      mockPrefs.onBeforeWrite = (key, value) async {
        if (key == PrayerService.locationUpdatedAtMsKey && !writeStarted.isCompleted) {
          writeStarted.complete();
          await writeRelease.future;
        }
      };

      final evenNewerTime = now;
      fakeProvider.positionStreamController.add(
        _pos(51.5075, -0.1278, timestamp: evenNewerTime),
      );
      await writeStarted.future;

      final clearFuture = PrayerService.instance.clearLocationToUnknown();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      writeRelease.complete();
      await clearFuture;
      mockPrefs.onBeforeWrite = null;
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData, isNull);
      expect(PrayerService.instance.lastGpsFixTime, isNull);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
      expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), isNull);
      expect(mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey), isNull);
      expect(mockPrefs.readPersisted('last_latitude'), isNull);
    });

    test('future_boundary: zero future skew allowance — exact now accepted as current, +1s and +4m rejected across live/cache/stream/persisted', () async {
      final now = DateTime(2026, 11, 18, 12, 0, 0);
      final plusOneSec = now.add(const Duration(seconds: 1));
      final plusFourMin = now.add(const Duration(minutes: 4));
      PrayerService.instance.setClockForTesting(() => now);

      expect(PrayerService.isValidFixTimestampMs(now.toUtc().millisecondsSinceEpoch, now: now), isTrue);
      expect(PrayerService.isValidFixTimestampMs(plusOneSec.toUtc().millisecondsSinceEpoch, now: now), isFalse);
      expect(PrayerService.isValidFixTimestampMs(plusFourMin.toUtc().millisecondsSinceEpoch, now: now), isFalse);

      // 1) Persisted +4m and +1s future timestamps migrate to UNKNOWN
      for (final badTs in <DateTime>[plusOneSec, plusFourMin]) {
        mockPrefs.reset({
          PrayerService.locationSourceKey: PrayerService.locationSourceGps,
          PrayerService.locationUpdatedAtMsKey: badTs.toUtc().millisecondsSinceEpoch,
          'last_latitude': 51.5074,
          'last_longitude': -0.1278,
          'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
        });
        fakeProvider
          ..serviceEnabled = true
          ..checkPermissionResult = LocationPermission.denied;
        await PrayerService.instance.init(forceReload: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await mockPrefs.waitForAllWrites();
        expect(PrayerService.instance.currentData, isNull);
        expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
        expect(mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey), isNull);
      }

      // 2) Live getCurrentPosition and OS lastKnownPosition with +1s / +4m rejected (never current)
      for (final badTs in <DateTime>[plusOneSec, plusFourMin]) {
        fakeProvider
          ..checkPermissionResult = LocationPermission.whileInUse
          ..lastKnownPosition = _pos(35.6762, 139.6503, timestamp: badTs)
          ..onGetCurrentPosition = () async => _pos(35.6762, 139.6503, timestamp: badTs);
        expect(await PrayerService.instance.requestGpsLocation(), isFalse);
        expect(PrayerService.instance.currentData, isNull);
        expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
      }

      // 3) Exact `now` accepted as current, then +1s and +4m stream events rejected
      fakeProvider
        ..lastKnownPosition = null
        ..onGetCurrentPosition = () async => _pos(51.5074, -0.1278, timestamp: now);
      expect(await PrayerService.instance.requestGpsLocation(), isTrue);
      await mockPrefs.waitForAllWrites();
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.current));

      fakeProvider.positionStreamController.add(_pos(35.6762, 139.6503, timestamp: plusOneSec));
      fakeProvider.positionStreamController.add(_pos(35.6762, 139.6503, timestamp: plusFourMin));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await mockPrefs.waitForAllWrites();
      expect(PrayerService.instance.currentData?.latitude, closeTo(51.5074, 0.0001));
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(now.toUtc().millisecondsSinceEpoch),
      );
    });

    test('futureGPS: future or epoch-0 Position.timestamp rejected across lastKnown, getCurrentPosition, and stream with zero pref writes', () async {
      final now = DateTime(2026, 11, 18, 12, 0);
      final futureTime = now.add(const Duration(hours: 2));
      final epochZero = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      PrayerService.instance.setClockForTesting(() => now);

      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);

      // 1) Future timestamp from getCurrentPosition & lastKnownPosition rejected
      for (final badTs in <DateTime>[futureTime, epochZero]) {
        fakeProvider
          ..checkPermissionResult = LocationPermission.whileInUse
          ..lastKnownPosition = _pos(35.6762, 139.6503, timestamp: badTs)
          ..onGetCurrentPosition = () async => _pos(35.6762, 139.6503, timestamp: badTs);

        expect(await PrayerService.instance.requestGpsLocation(), isFalse);
        await mockPrefs.waitForAllWrites();
        expect(PrayerService.instance.currentData, isNull);
        expect(PrayerService.instance.lastLocationError, equals(LocationErrorType.unavailable));
        expect(mockPrefs.readPersisted('last_latitude'), isNull);
        expect(mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey), isNull);
      }

      // 2) Establish valid current fix, then verify future & epoch-0 stream events are ignored
      fakeProvider
        ..lastKnownPosition = null
        ..onGetCurrentPosition = () async => _pos(51.5074, -0.1278, timestamp: now);
      expect(await PrayerService.instance.requestGpsLocation(), isTrue);
      await mockPrefs.waitForAllWrites();

      fakeProvider.positionStreamController.add(_pos(35.6762, 139.6503, timestamp: futureTime));
      fakeProvider.positionStreamController.add(_pos(35.6762, 139.6503, timestamp: epochZero));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData?.latitude, closeTo(51.5074, 0.0001));
      expect(
        mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey),
        equals(now.toUtc().millisecondsSinceEpoch),
      );
    });

    test('persistedfuture: persisted GPS cache with future timestamp migrates to UNKNOWN and cancels derived notifications', () async {
      final now = DateTime(2026, 11, 18, 12, 0);
      final futureMs = now.add(const Duration(hours: 3)).toUtc().millisecondsSinceEpoch;
      PrayerService.instance.setClockForTesting(() => now);

      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey: futureMs,
        'last_latitude': 35.6762,
        'last_longitude': 139.6503,
        'last_city': 'موقعك الفعلي (35.68°, 139.65°)',
        'notif_master_enabled': true,
        'notif_friday_enabled': true,
        'wake_pre_fajr_enabled': true,
        'wake_qiyam_enabled': true,
        'wake_qiyam_mode': 'last_third',
      });
      await SettingsService.instance.init(forceReload: true);
      await PrayerNotificationService.instance.init();
      await FajrQiyamAlarmService.instance.init(forceReload: true);

      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      notifCalls.clear();

      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData, isNull);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
      expect(mockPrefs.readPersisted('last_latitude'), isNull);
      expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), isNull);
      expect(mockPrefs.readPersisted(PrayerService.locationUpdatedAtMsKey), isNull);

      final cancelled = notifCalls
          .where((c) => c.method == 'cancel')
          .map((c) => c.arguments is int ? c.arguments as int : (c.arguments is Map ? (c.arguments as Map)['id'] as int? : null))
          .whereType<int>()
          .toList();
      expect(cancelled, contains(PrayerNotificationService.prayerDerivedNotificationIdStart));
      expect(cancelled, contains(PrayerNotificationService.adhanSnoozeNotificationId));
      expect(cancelled, contains(FajrQiyamAlarmService.preFajrAlarmNotificationId));
    });
  });

  group('CRITICAL Notification Ownership Split & Unknown-Location Policy', () {
    List<int> cancelledIds(List<MethodCall> calls) => calls
        .where((c) => c.method == 'cancel')
        .map((c) {
          final args = c.arguments;
          if (args is int) return args;
          if (args is Map && args['id'] is int) return args['id'] as int;
          return null;
        })
        .whereType<int>()
        .toList();

    List<int> scheduledIds(List<MethodCall> calls) => calls
        .where((c) => c.method == 'zonedSchedule' && c.arguments is Map)
        .map((c) => (c.arguments as Map)['id'] as int)
        .toList();

    test('Friday fixed-clock reminder owns dedicated ID 804; legacy migration cancels 100..139 + 995 + derived 880/881, rebuilds 804, and preserves Adhkar 801..803 & Khatma 990', () async {
      // Configure legacy manual prefs + astronomical Qiyam mode ('last_third')
      mockPrefs.reset({
        'is_manual_location': true,
        'last_latitude': 30.0444,
        'last_longitude': 31.2357,
        'last_city': 'القاهرة، مصر',
        'notif_master_enabled': true,
        'notif_friday_enabled': true,
        'notif_friday_hour': 9,
        'wake_pre_fajr_enabled': true,
        'wake_qiyam_enabled': true,
        'wake_qiyam_mode': 'last_third',
      });
      await SettingsService.instance.init(forceReload: true);
      await PrayerNotificationService.instance.init();
      await FajrQiyamAlarmService.instance.init(forceReload: true);

      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      notifCalls.clear();

      // Trigger legacy migration to UNKNOWN
      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final cancelled = cancelledIds(notifCalls);
      final scheduled = scheduledIds(notifCalls);

      // Must NEVER use destructive cancelAll()
      expect(notifCalls.any((c) => c.method == 'cancelAll'), isFalse);

      // Must cancel entire derived prayer range 100..139 (cleaning legacy Friday if any)
      expect(cancelled, contains(PrayerNotificationService.prayerDerivedNotificationIdStart));
      expect(cancelled, contains(PrayerNotificationService.prayerDerivedNotificationIdEnd));

      // Must cancel stale Adhan snooze 995 by policy
      expect(cancelled, contains(PrayerNotificationService.adhanSnoozeNotificationId));

      // Must cancel derived Pre-Fajr 880 and astronomical Qiyam 881
      expect(cancelled, contains(FajrQiyamAlarmService.preFajrAlarmNotificationId));
      expect(cancelled, contains(FajrQiyamAlarmService.qiyamAlarmNotificationId));

      // Must rebuild/migrate fixed-clock Friday onto dedicated ID 804 (never inside 100..139)
      expect(scheduled, contains(PrayerNotificationService.fridayReminderNotificationId));
      expect(
        scheduled.where((id) =>
            id >= PrayerNotificationService.prayerDerivedNotificationIdStart &&
            id <= PrayerNotificationService.prayerDerivedNotificationIdEnd),
        isEmpty,
      );

      // Must NEVER cancel Adhkar (801..803) or Khatma (990)
      expect(cancelled, isNot(contains(PrayerNotificationService.morningAdhkarNotificationId)));
      expect(cancelled, isNot(contains(PrayerNotificationService.eveningAdhkarNotificationId)));
      expect(cancelled, isNot(contains(PrayerNotificationService.sleepAdhkarNotificationId)));
      expect(cancelled, isNot(contains(990)));
    });

    test('Fixed-clock Qiyam (fixed_time) ID 881 is PRESERVED when location migrates to UNKNOWN while derived Pre-Fajr 880 is cancelled', () async {
      mockPrefs.reset({
        'is_manual_location': true,
        'last_latitude': 30.0444,
        'last_longitude': 31.2357,
        'last_city': 'القاهرة، مصر',
        'wake_pre_fajr_enabled': true,
        'wake_qiyam_enabled': true,
        'wake_qiyam_mode': 'fixed_time',
        'wake_qiyam_fixed_hour': 3,
        'wake_qiyam_fixed_minute': 30,
      });
      await SettingsService.instance.init(forceReload: true);
      await PrayerNotificationService.instance.init();
      await FajrQiyamAlarmService.instance.init(forceReload: true);

      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      notifCalls.clear();

      await PrayerService.instance.init(forceReload: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final cancelled = cancelledIds(notifCalls);
      expect(cancelled, contains(FajrQiyamAlarmService.preFajrAlarmNotificationId));
      expect(cancelled, isNot(contains(FajrQiyamAlarmService.qiyamAlarmNotificationId)));

      // And scheduling alarms while location is UNKNOWN schedules fixed Qiyam 881 but NOT derived 880
      notifCalls.clear();
      await FajrQiyamAlarmService.instance.scheduleAlarms();
      final scheduled = scheduledIds(notifCalls);
      expect(scheduled, contains(FajrQiyamAlarmService.qiyamAlarmNotificationId));
      expect(scheduled, isNot(contains(FajrQiyamAlarmService.preFajrAlarmNotificationId)));
    });

    test('schedulePrayerNotifications schedules Friday on 804 (outside 100..139) and never calls cancelAll()', () async {
      final now = DateTime.now();
      final verifiedData = PrayerData(
        latitude: 24.7136,
        longitude: 46.6753,
        locationName: 'الرياض، السعودية (موقعك الفعلي)',
        prayers: [
          PrayerInfo(name: 'الفجر', time: now.add(const Duration(hours: 2)), formattedTime: '04:30 ص'),
          PrayerInfo(name: 'الظهر', time: now.add(const Duration(hours: 4)), formattedTime: '12:00 م'),
        ],
        qiblaDegrees: 245.0,
        lastUpdated: now,
      );

      await PrayerNotificationService.instance.toggleFridayReminder(true);
      notifCalls.clear();

      await PrayerNotificationService.instance.schedulePrayerNotifications(verifiedData);

      expect(notifCalls.any((c) => c.method == 'cancelAll'), isFalse);
      final scheduled = scheduledIds(notifCalls);
      expect(scheduled, contains(PrayerNotificationService.fridayReminderNotificationId));
      expect(
        scheduled.any((id) =>
            id >= PrayerNotificationService.prayerDerivedNotificationIdStart &&
            id <= PrayerNotificationService.prayerDerivedNotificationIdEnd),
        isTrue,
      );
      // Stale snooze 995 is NOT cancelled during normal valid-GPS scheduling
      expect(cancelledIds(notifCalls), isNot(contains(PrayerNotificationService.adhanSnoozeNotificationId)));
    });

    test('Notification async race: delayed schedulePrayerNotifications cannot enqueue 100..139 after UNKNOWN cancellation while preserving Friday 804, Adhkar 801..803 & Khatma 990', () async {
      await PrayerNotificationService.instance.toggleFridayReminder(true);
      await PrayerNotificationService.instance.scheduleAdhkarReminders();
      // Simulate preexisting Khatma (990) and stale Adhan snooze (995) in OS queue
      activeOsNotifications[990] = {'id': 990, 'title': 'Khatma'};
      activeOsNotifications[PrayerNotificationService.adhanSnoozeNotificationId] = {
        'id': PrayerNotificationService.adhanSnoozeNotificationId,
        'title': 'Stale Snooze',
      };

      final now = DateTime.now();
      final verifiedData = PrayerData(
        latitude: 24.7136,
        longitude: 46.6753,
        locationName: 'الرياض، السعودية (موقعك الفعلي)',
        prayers: [
          PrayerInfo(name: 'الفجر', time: now.add(const Duration(hours: 2)), formattedTime: '04:30 ص'),
          PrayerInfo(name: 'الظهر', time: now.add(const Duration(hours: 4)), formattedTime: '12:00 م'),
        ],
        qiblaDegrees: 245.0,
        lastUpdated: now,
      );

      final schedulePaused = Completer<void>();
      final scheduleGate = Completer<void>();
      onBeforeNotifCall = (call) async {
        if (call.method == 'zonedSchedule' &&
            call.arguments is Map &&
            ((call.arguments as Map)['id'] as int) >=
                PrayerNotificationService.prayerDerivedNotificationIdStart &&
            ((call.arguments as Map)['id'] as int) <=
                PrayerNotificationService.prayerDerivedNotificationIdEnd &&
            !schedulePaused.isCompleted) {
          schedulePaused.complete();
          await scheduleGate.future;
        }
      };

      // 1) Start schedulePrayerNotifications, pause mid-plugin call
      final schedFuture =
          PrayerNotificationService.instance.schedulePrayerNotifications(verifiedData);
      await schedulePaused.future;

      // 2) While schedule is in flight, location becomes UNKNOWN -> triggers cancellation
      final cancelFuture = PrayerNotificationService.instance
          .cancelLocationDerivedNotifications(cancelStaleAdhanSnooze: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 3) Release delayed plugin call and wait for everything to settle
      scheduleGate.complete();
      await Future.wait(<Future<void>>[schedFuture, cancelFuture]);
      await waitForAllNotifOps();

      // Active OS notifications MUST have ZERO derived 100..139 and ZERO stale 995
      final remainingDerived = activeOsNotifications.keys.where((id) =>
          id >= PrayerNotificationService.prayerDerivedNotificationIdStart &&
          id <= PrayerNotificationService.prayerDerivedNotificationIdEnd);
      expect(remainingDerived, isEmpty);
      expect(
        activeOsNotifications.containsKey(
          PrayerNotificationService.adhanSnoozeNotificationId,
        ),
        isFalse,
      );
      // Fixed reminders MUST be preserved/rebuilt
      expect(
        activeOsNotifications.containsKey(
          PrayerNotificationService.fridayReminderNotificationId,
        ),
        isTrue,
      );
      expect(
        activeOsNotifications.containsKey(
          PrayerNotificationService.morningAdhkarNotificationId,
        ),
        isTrue,
      );
      expect(
        activeOsNotifications.containsKey(
          PrayerNotificationService.eveningAdhkarNotificationId,
        ),
        isTrue,
      );
      expect(
        activeOsNotifications.containsKey(
          PrayerNotificationService.sleepAdhkarNotificationId,
        ),
        isTrue,
      );
      expect(activeOsNotifications.containsKey(990), isTrue);
    });

    test('Alarm async race: delayed FajrQiyamAlarmService.scheduleAlarms cannot enqueue derived 880/881 after UNKNOWN cancellation, while fixed-clock Qiyam 881 is preserved', () async {
      final now = DateTime.now();
      final verifiedData = PrayerData(
        latitude: 24.7136,
        longitude: 46.6753,
        locationName: 'الرياض، السعودية (موقعك الفعلي)',
        prayers: [
          PrayerInfo(name: 'الفجر', time: now.add(const Duration(hours: 6)), formattedTime: '04:30 ص'),
          PrayerInfo(name: 'المغرب', time: now.subtract(const Duration(hours: 4)), formattedTime: '06:00 م'),
        ],
        qiblaDegrees: 245.0,
        lastUpdated: now,
      );

      // Part A: Astronomical Qiyam ('last_third') -> BOTH 880 and 881 must be absent after UNKNOWN
      mockPrefs.reset({
        'wake_pre_fajr_enabled': true,
        'wake_qiyam_enabled': true,
        'wake_qiyam_mode': 'last_third',
      });
      await FajrQiyamAlarmService.instance.init(forceReload: true);
      activeOsNotifications.clear();

      final alarmPausedA = Completer<void>();
      final alarmGateA = Completer<void>();
      onBeforeNotifCall = (call) async {
        if (call.method == 'zonedSchedule' &&
            call.arguments is Map &&
            (call.arguments as Map)['id'] ==
                FajrQiyamAlarmService.preFajrAlarmNotificationId &&
            !alarmPausedA.isCompleted) {
          alarmPausedA.complete();
          await alarmGateA.future;
        }
      };

      final schedA = FajrQiyamAlarmService.instance.scheduleAlarms(verifiedData);
      await alarmPausedA.future;

      // Trigger UNKNOWN cancellation while scheduleAlarms is paused mid-plugin call
      fakeProvider.checkPermissionResult = LocationPermission.denied;
      final clearA = PrayerService.instance.clearLocationToUnknown();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      alarmGateA.complete();
      await Future.wait(<Future<void>>[schedA, clearA]);
      await waitForAllNotifOps();

      expect(
        activeOsNotifications.containsKey(
          FajrQiyamAlarmService.preFajrAlarmNotificationId,
        ),
        isFalse,
      );
      expect(
        activeOsNotifications.containsKey(
          FajrQiyamAlarmService.qiyamAlarmNotificationId,
        ),
        isFalse,
      );

      // Part B: Fixed-clock Qiyam ('fixed_time') -> 880 must be absent, fixed 881 MUST stay active
      onBeforeNotifCall = null;
      mockPrefs.reset({
        'wake_pre_fajr_enabled': true,
        'wake_qiyam_enabled': true,
        'wake_qiyam_mode': 'fixed_time',
        'wake_qiyam_fixed_hour': 3,
        'wake_qiyam_fixed_minute': 30,
      });
      await FajrQiyamAlarmService.instance.init(forceReload: true);
      activeOsNotifications.clear();

      final alarmPausedB = Completer<void>();
      final alarmGateB = Completer<void>();
      onBeforeNotifCall = (call) async {
        if (call.method == 'zonedSchedule' &&
            call.arguments is Map &&
            (call.arguments as Map)['id'] ==
                FajrQiyamAlarmService.preFajrAlarmNotificationId &&
            !alarmPausedB.isCompleted) {
          alarmPausedB.complete();
          await alarmGateB.future;
        }
      };

      final schedB = FajrQiyamAlarmService.instance.scheduleAlarms(verifiedData);
      await alarmPausedB.future;

      final clearB = PrayerService.instance.clearLocationToUnknown();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      alarmGateB.complete();
      await Future.wait(<Future<void>>[schedB, clearB]);
      await waitForAllNotifOps();

      expect(
        activeOsNotifications.containsKey(
          FajrQiyamAlarmService.preFajrAlarmNotificationId,
        ),
        isFalse,
      );
      expect(
        activeOsNotifications.containsKey(
          FajrQiyamAlarmService.qiyamAlarmNotificationId,
        ),
        isTrue,
      );
    });
  });

  group('Backup & Restore GPS-Only Policy', () {
    test('Export emits null location when UNKNOWN; merge preserves device GPS; replace resets to UNKNOWN and never imports coordinates as GPS', () async {
      // 1) UNKNOWN -> export has null location (NO Cairo fabrication)
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);
      final unknownExport = await BackupRestoreService.instance.exportBackupData();
      expect((unknownExport['data'] as Map<String, dynamic>)['location'], isNull);

      // 2) Obtain verified device GPS (Tokyo)
      final fixTime = DateTime(2026, 11, 18, 10, 0);
      PrayerService.instance.setClockForTesting(() => fixTime);
      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition =
            () async => _pos(35.6762, 139.6503, timestamp: fixTime);
      expect(await PrayerService.instance.requestGpsLocation(), isTrue);
      await mockPrefs.waitForAllWrites();

      // Export now contains verified GPS provenance + timestamp
      final verifiedExport = await BackupRestoreService.instance.exportBackupData();
      final exportedLoc =
          (verifiedExport['data'] as Map<String, dynamic>)['location']
              as Map<String, dynamic>?;
      expect(exportedLoc, isNotNull);
      expect(exportedLoc!['location_source'], equals(PrayerService.locationSourceGps));
      expect(exportedLoc['location_updated_at_ms'], equals(fixTime.toUtc().millisecondsSinceEpoch));
      expect(exportedLoc['last_latitude'], closeTo(35.6762, 0.0001));

      // Prepare foreign backup containing Cairo coordinates
      final foreignBackup = <String, dynamic>{
        'app': 'AlMomin',
        'schema_version': 1,
        'data': {
          'settings': {'mushaf_font_size': 28.0},
          'location': {
            'location_source': 'gps',
            'location_updated_at_ms': fixTime.toUtc().millisecondsSinceEpoch,
            'last_latitude': 30.0444,
            'last_longitude': 31.2357,
            'last_city': 'القاهرة، مصر',
          },
        },
      };

      // 3) MERGE mode preserves current device GPS (Tokyo), ignoring backup Cairo
      fakeProvider.checkPermissionResult = LocationPermission.denied;
      expect(
        await BackupRestoreService.instance.restoreBackup(foreignBackup, replaceMode: false),
        isTrue,
      );
      await mockPrefs.waitForAllWrites();
      expect(PrayerService.instance.currentData?.latitude, closeTo(35.6762, 0.0001));
      expect(PrayerService.instance.currentData?.longitude, closeTo(139.6503, 0.0001));
      expect(mockPrefs.readPersisted('last_latitude'), closeTo(35.6762, 0.0001));

      // 4) REPLACE mode resets to UNKNOWN and NEVER imports backup coordinates as GPS
      expect(
        await BackupRestoreService.instance.restoreBackup(foreignBackup, replaceMode: true),
        isTrue,
      );
      await mockPrefs.waitForAllWrites();
      expect(PrayerService.instance.currentData, isNull);
      expect(PrayerService.instance.locationFreshness, equals(LocationFreshness.unknown));
      expect(mockPrefs.readPersisted('last_latitude'), isNull);
      expect(mockPrefs.readPersisted('last_longitude'), isNull);
      expect(mockPrefs.readPersisted('last_city'), isNull);
      expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), isNull);
    });
  });

  group('Delayed Persistence Race Consistency (Auto-GPS & Stream vs clearLocationToUnknown)', () {
    test('Auto-GPS paused mid-persistence cannot resurrect coordinates/method after clearLocationToUnknown()', () async {
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await PrayerService.instance.init(forceReload: true);

      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition = () async => _pos(30.0444, 31.2357);

      final latWriteStarted = Completer<void>();
      final latWriteGate = Completer<void>();
      mockPrefs.onBeforeWrite = (key, value) async {
        if (key == 'last_latitude' &&
            value is double &&
            (value - 30.0444).abs() < 0.001 &&
            !latWriteStarted.isCompleted) {
          latWriteStarted.complete();
          await latWriteGate.future;
        }
      };

      final autoFuture = PrayerService.instance.checkAndUpdateLocationOnResume(
        isUserTriggered: false,
      );
      await latWriteStarted.future;

      final clearFuture = PrayerService.instance.clearLocationToUnknown();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      latWriteGate.complete();

      await Future.wait(<Future<Object?>>[autoFuture, clearFuture]);
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData, isNull);
      expect(mockPrefs.readPersisted('last_latitude'), isNull);
      expect(mockPrefs.readPersisted('last_city'), isNull);
      expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), isNull);
    });

    test('Streamed GPS paused mid-persistence cannot resurrect coordinates after clearLocationToUnknown()', () async {
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition = () async => _pos(51.5074, -0.1278);
      await PrayerService.instance.init(forceReload: true);
      expect(
        await PrayerService.instance.checkAndUpdateLocationOnResume(isUserTriggered: false),
        isTrue,
      );
      await mockPrefs.waitForAllWrites();

      final streamWriteStarted = Completer<void>();
      final streamWriteGate = Completer<void>();
      mockPrefs.onBeforeWrite = (key, value) async {
        if (key == 'last_latitude' &&
            value is double &&
            (value - 30.0444).abs() < 0.001 &&
            !streamWriteStarted.isCompleted) {
          streamWriteStarted.complete();
          await streamWriteGate.future;
        }
      };

      fakeProvider.positionStreamController.add(_pos(30.0444, 31.2357));
      await streamWriteStarted.future;

      final clearFuture = PrayerService.instance.clearLocationToUnknown();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      streamWriteGate.complete();

      await clearFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await mockPrefs.waitForAllWrites();

      expect(PrayerService.instance.currentData, isNull);
      expect(mockPrefs.readPersisted('last_latitude'), isNull);
      expect(mockPrefs.readPersisted(PrayerService.locationSourceKey), isNull);
    });
  });

  group('GPS-Only UI, Semantics & 360/412 (1.0x & 2.0x) Layout Verification', () {
    Future<GlobalKey<ScaffoldMessengerState>> pumpHarness(
      WidgetTester tester, {
      required Widget child,
      required Size logicalSize,
      required double textScale,
      GlobalKey? boundaryKey,
    }) async {
      await tester.runAsync(_loadRealAppFonts);
      tester.view.physicalSize = logicalSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey ?? GlobalKey(),
          child: MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: messengerKey,
            theme: AppTheme.lightTheme,
            builder: (context, appChild) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: logicalSize,
                textScaler: TextScaler.linear(textScale),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: appChild ?? const SizedBox.shrink(),
              ),
            ),
            home: child,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      return messengerKey;
    }

    Future<void> clearSnackBarsAndSettle(
      WidgetTester tester,
      GlobalKey<ScaffoldMessengerState> messengerKey,
    ) async {
      messengerKey.currentState?.clearSnackBars();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(SnackBar), findsNothing);
    }

    void assertInViewport(
      WidgetTester tester,
      Finder finder,
      Size viewportSize, {
      String? reason,
    }) {
      final rect = tester.getRect(finder);
      expect(
        rect.left,
        greaterThanOrEqualTo(-0.5),
        reason: '${reason ?? finder} clipped on left: $rect in $viewportSize',
      );
      expect(
        rect.top,
        greaterThanOrEqualTo(-0.5),
        reason: '${reason ?? finder} clipped on top: $rect in $viewportSize',
      );
      expect(
        rect.right,
        lessThanOrEqualTo(viewportSize.width + 0.5),
        reason: '${reason ?? finder} clipped on right: $rect in $viewportSize',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(viewportSize.height + 0.5),
        reason: '${reason ?? finder} clipped on bottom: $rect in $viewportSize',
      );
    }

    Future<void> scrollToBottom(WidgetTester tester, Finder scrollableFinder) async {
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      for (int step = 0; step < 12; step++) {
        final pos = scrollableState.position;
        if (pos.maxScrollExtent <= 0) break;
        final nextOffset = (pos.pixels + 450.0).clamp(0.0, pos.maxScrollExtent);
        if ((nextOffset - pos.pixels).abs() < 0.5 &&
            (pos.maxScrollExtent - pos.pixels).abs() < 0.5) {
          break;
        }
        pos.jumpTo(nextOffset);
        await tester.pump();
      }
      final finalPos = scrollableState.position;
      if (finalPos.maxScrollExtent > 0) {
        finalPos.jumpTo(finalPos.maxScrollExtent);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> scrollToTop(WidgetTester tester, Finder scrollableFinder) async {
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      scrollableState.position.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('No manual city UI exists in Onboarding or Heritage Mosque screen', (tester) async {
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await tester.runAsync(() => PrayerService.instance.init(forceReload: true));

      // 1) Onboarding Page 2 has GPS-only controls and zero manual city chips
      await pumpHarness(
        tester,
        logicalSize: const Size(412, 915),
        textScale: 1.0,
        child: const OnboardingScreen(),
      );
      await tester.tap(find.text('التالي'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('المدينة لمواقيت الصلاة'), findsNothing);
      expect(find.text('القاهرة، مصر'), findsNothing);
      expect(find.byKey(const ValueKey('gps_enable_retry_button')), findsOneWidget);

      // 2) Heritage Mosques tab has zero manual prayer override button and zero Cairo distance fallback
      await pumpHarness(
        tester,
        logicalSize: const Size(412, 915),
        textScale: 1.0,
        child: const EgyptianHeritageScreen(),
      );
      final tabsToggle = find.byTooltip('عرض التبويبات التفصيلية');
      if (tabsToggle.evaluate().isNotEmpty) {
        await tester.tap(tabsToggle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.tap(find.text('مساجد مصر التاريخية'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.textContaining('الأزهر'), findsWidgets);
      expect(find.textContaining('ضبط مواقيت الصلاة والقبلة على موقع هذا المسجد'), findsNothing);
      expect(find.textContaining(' كم'), findsNothing);
    });

    testWidgets('Explicit Enable/Retry/Settings affordances work semantically & visually at 360x800 and 412x915 (1.0x & 2.0x) with scrolled bottoms and clean snackbars', (tester) async {
      final semHandle = tester.ensureSemantics();
      try {

      final viewports = <(String, Size, double)>[
        ('360x800_1x', const Size(360, 800), 1.0),
        ('360x800_2x', const Size(360, 800), 2.0),
        ('412x915_1x', const Size(412, 915), 1.0),
        ('412x915_2x', const Size(412, 915), 2.0),
      ];

      // 1) UNKNOWN + serviceDisabled -> openLocationSettings affordance works via real tap & semantics (top AND scrolled bottom at 2.0x)
      for (final (tag, size, scale) in viewports) {
        fakeProvider
          ..serviceEnabled = false
          ..openLocationSettingsCalls = 0;
        await tester.runAsync(() async {
          await PrayerService.instance.init(forceReload: true);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });

        final bKey = GlobalKey();
        await pumpHarness(
          tester,
          logicalSize: size,
          textScale: scale,
          boundaryKey: bKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('مواقيت الصلاة والأذان')),
            body: AnimatedBuilder(
              animation: PrayerService.instance,
              builder: (_, __) {
                final data = PrayerService.instance.currentData;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    PrayerLocationBanner(data: data),
                    const SizedBox(height: 12),
                    PrayerTimesCard(data: data, isDark: false),
                  ],
                );
              },
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('القاهرة، مصر'), findsNothing);
        expect(find.byKey(const ValueKey('gps_open_location_settings_button')), findsWidgets);
        await _maybeCapturePng(tester, bKey, 'gps_only_prayer_disabled_$tag.png');

        final settingsBtn =
            find.byKey(const ValueKey('gps_open_location_settings_button')).first;
        await tester.ensureVisible(settingsBtn);
        await tester.pump();
        assertInViewport(tester, settingsBtn, size, reason: 'Prayer top settings btn ($tag)');
        final semNode = tester.getSemantics(settingsBtn);
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(semNode.id, SemanticsAction.tap);
        await tester.pump();
        expect(fakeProvider.openLocationSettingsCalls, equals(1));

        // For 360x800 2.0x, also scroll to the bottom PrayerTimesCard unavailable controls, capture, verify containment + real tap + semantics
        if (tag == '360x800_2x') {
          await scrollToBottom(tester, find.byType(Scrollable).first);
          expect(tester.takeException(), isNull);
          await _maybeCapturePng(tester, bKey, 'gps_only_prayer_disabled_bottom_360x800_2x.png');

          final bottomBtn =
              find.byKey(const ValueKey('gps_open_location_settings_button')).last;
          await tester.ensureVisible(bottomBtn);
          await tester.pump();
          assertInViewport(tester, bottomBtn, size, reason: 'Prayer bottom settings btn (360x800_2x)');
          await tester.tap(bottomBtn);
          await tester.pump();
          expect(fakeProvider.openLocationSettingsCalls, equals(2));
          final bottomSem = tester.getSemantics(bottomBtn);
          tester.binding.pipelineOwner.semanticsOwner!
              .performAction(bottomSem.id, SemanticsAction.tap);
          await tester.pump();
          expect(fakeProvider.openLocationSettingsCalls, equals(3));
        }
      }

      // 2) UNKNOWN + permissionDeniedForever -> openAppSettings affordance works via tap & semantics
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.deniedForever
        ..openAppSettingsCalls = 0;
      await tester.runAsync(() async {
        await PrayerService.instance.init(forceReload: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      final homeDeniedKey = GlobalKey();
      await pumpHarness(
        tester,
        logicalSize: const Size(360, 800),
        textScale: 2.0,
        boundaryKey: homeDeniedKey,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: AnimatedBuilder(
              animation: PrayerService.instance,
              builder: (_, __) => HomeNextPrayerCard(
                prayerData: PrayerService.instance.currentData,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('الصلاة القادمة: الظهر'), findsNothing);
      final appSettingsBtn = find.byKey(const ValueKey('gps_open_app_settings_button'));
      expect(appSettingsBtn, findsOneWidget);
      await _maybeCapturePng(tester, homeDeniedKey, 'gps_only_home_denied_forever_360x800_2x.png');

      await tester.ensureVisible(appSettingsBtn);
      await tester.pump();
      assertInViewport(tester, appSettingsBtn, const Size(360, 800), reason: 'Home deniedForever app settings btn');
      await tester.tap(appSettingsBtn);
      await tester.pump();
      expect(fakeProvider.openAppSettingsCalls, equals(1));
      final appSem = tester.getSemantics(appSettingsBtn);
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(appSem.id, SemanticsAction.tap);
      await tester.pump();
      expect(fakeProvider.openAppSettingsCalls, equals(2));

      // 3) UNKNOWN + permissionDenied -> Qibla unknown (top & scrolled bottom), explicit tap updates live to Tokyo, dismiss snackbar before final verified capture
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied
        ..requestPermissionResult = LocationPermission.whileInUse
        ..requestPermissionCalls = 0
        ..onGetCurrentPosition = () async => _pos(35.6762, 139.6503);
      await tester.runAsync(() async {
        await PrayerService.instance.init(forceReload: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(fakeProvider.requestPermissionCalls, equals(0));

      final qiblaUnknownKey = GlobalKey();
      final qiblaSensorController = StreamController<MagnetometerEvent>.broadcast();
      addTearDown(qiblaSensorController.close);
      DateTime qiblaSensorClock = DateTime(2026, 11, 18, 12, 0, 0);

      final qiblaMessenger = await pumpHarness(
        tester,
        logicalSize: const Size(360, 800),
        textScale: 2.0,
        boundaryKey: qiblaUnknownKey,
        child: QiblaCompassScreen(
          magnetometerStreamForTesting: qiblaSensorController.stream,
          nowProviderForTesting: () => qiblaSensorClock,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('136'), findsNothing);
      expect(find.textContaining('1288'), findsNothing);
      expect(find.text('القاهرة، مصر'), findsNothing);
      // Qibla unknown wording must be compass-specific (never mentions prayer times or accuracy promises)
      expect(find.textContaining('المواقيت'), findsNothing);
      expect(find.textContaining('بدقة'), findsNothing);
      // Unavailable compass must NOT render a direction needle/pointer
      expect(find.byKey(const ValueKey('qibla_direction_needle')), findsNothing);
      expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsOneWidget);
      await _maybeCapturePng(tester, qiblaUnknownKey, 'gps_only_qibla_unknown_360x800_2x.png');

      // Capture scrolled bottom of Qibla unknown screen at 360x800 2x
      await scrollToBottom(tester, find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      // Unknown Qibla must separate sensor heading availability from unavailable Qibla target and NEVER announce 0°
      expect(find.text('0°'), findsNothing);
      expect(find.text('غير محدد (يتطلب GPS)'), findsOneWidget);
      final qiblaTargetSem = tester.getSemantics(
        find.byKey(const ValueKey('qibla_target_angle_stat')),
      );
      expect(qiblaTargetSem.label, contains('زاوية القبلة'));
      expect(qiblaTargetSem.label, contains('غير محدد'));
      expect(qiblaTargetSem.label, isNot(contains('0°')));
      final sensorHeadingSem = tester.getSemantics(
        find.byKey(const ValueKey('qibla_sensor_heading_stat')),
      );
      expect(sensorHeadingSem.label, contains('اتجاه الهاتف'));
      expect(sensorHeadingSem.label, isNot(contains('0°')));
      await _maybeCapturePng(tester, qiblaUnknownKey, 'gps_only_qibla_unknown_bottom_360x800_2x.png');

      // Scroll back up to explicit GPS enable button, verify containment, tap
      await scrollToTop(tester, find.byType(Scrollable).first);
      final enableBtn = find.byKey(const ValueKey('gps_enable_retry_button')).first;
      await tester.ensureVisible(enableBtn);
      await tester.pump();
      assertInViewport(tester, enableBtn, const Size(360, 800), reason: 'Qibla enable GPS btn');
      await tester.tap(enableBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(fakeProvider.requestPermissionCalls, equals(1));
      expect(PrayerService.instance.currentData?.latitude, closeTo(35.6762, 0.0001));
      expect(find.textContaining('35.68°'), findsWidgets);

      // Dismiss success snackbar cleanly before capturing verified-GPS + waiting-sensor state
      await clearSnackBarsAndSettle(tester, qiblaMessenger);
      await scrollToTop(tester, find.byType(Scrollable).first);

      // CRITICAL: Verified GPS WITHOUT any sensor reading must show numeric geographic bearing
      // separately, but MUST NOT render direction needle or move-phone alignment guidance!
      expect(find.textContaining('293.0°'), findsOneWidget);
      expect(find.byKey(const ValueKey('qibla_direction_needle')), findsNothing);
      expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsOneWidget);
      expect(find.textContaining('حرك الهاتف'), findsNothing);
      final waitingGuidanceSem = tester.getSemantics(
        find.byKey(const ValueKey('qibla_guidance_banner')),
      );
      expect(waitingGuidanceSem.label, contains('بانتظار قراءة حساس البوصلة'));
      expect(waitingGuidanceSem.label, isNot(contains('حرك الهاتف')));
      await _maybeCapturePng(tester, qiblaUnknownKey, 'gps_only_qibla_waiting_sensor_360x800_2x.png');

      // Now emit a genuine live magnetometer reading (heading 0° North) -> needle & guidance appear
      qiblaSensorController.add(MagnetometerEvent(0.0, 25.0, 0.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('qibla_direction_needle')), findsOneWidget);
      expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsNothing);
      expect(find.textContaining('حرك الهاتف'), findsOneWidget);
      await _maybeCapturePng(tester, qiblaUnknownKey, 'gps_only_qibla_verified_360x800_2x.png');

      // 4) Cached GPS (2h old) vs recent live GPS (<15m) visible distinction on Home at 360x800 2x & 412x915 2x (zero lingering snackbars)
      final baseTime = DateTime(2026, 11, 18, 18, 0);
      PrayerService.instance.setClockForTesting(() => baseTime);
      mockPrefs.reset({
        PrayerService.locationSourceKey: PrayerService.locationSourceGps,
        PrayerService.locationUpdatedAtMsKey:
            baseTime.subtract(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        'last_latitude': 51.5074,
        'last_longitude': -0.1278,
        'last_city': 'موقعك الفعلي (51.51°, -0.13°)',
      });
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied;
      await tester.runAsync(() async {
        await PrayerService.instance.init(forceReload: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      for (final (tag, size) in <(String, Size)>[
        ('360x800_2x', const Size(360, 800)),
        ('412x915_2x', const Size(412, 915)),
      ]) {
        final staleKey = GlobalKey();
        await pumpHarness(
          tester,
          logicalSize: size,
          textScale: 2.0,
          boundaryKey: staleKey,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: AnimatedBuilder(
                animation: PrayerService.instance,
                builder: (_, __) => HomeNextPrayerCard(
                  prayerData: PrayerService.instance.currentData,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsNothing);
        // Cached Home headline must say saved location ('موقع محفوظ (...)'), NEVER 'موقعك الفعلي'
        expect(find.text('موقع محفوظ (51.51°, -0.13°)'), findsOneWidget);
        expect(find.textContaining('موقعك الفعلي'), findsNothing);
        expect(find.textContaining('موقع محفوظ'), findsWidgets);
        expect(find.text('GPS حالي'), findsNothing);
        expect(find.text('GPS حديث'), findsNothing);
        expect(find.textContaining('ساعة'), findsWidgets);
        await _maybeCapturePng(tester, staleKey, 'gps_only_home_cached_stale_$tag.png');
      }

      // Refresh GPS with recent live fix -> badge transitions visibly to recent ('GPS حديث'), zero snackbar masking
      fakeProvider
        ..checkPermissionResult = LocationPermission.whileInUse
        ..onGetCurrentPosition =
            () async => _pos(51.5074, -0.1278, timestamp: baseTime);
      expect(await tester.runAsync(() => PrayerService.instance.requestGpsLocation()), isTrue);

      final currentKey = GlobalKey();
      await pumpHarness(
        tester,
        logicalSize: const Size(360, 800),
        textScale: 2.0,
        boundaryKey: currentKey,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: AnimatedBuilder(
              animation: PrayerService.instance,
              builder: (_, __) => HomeNextPrayerCard(
                prayerData: PrayerService.instance.currentData,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('موقعك الفعلي (51.51°, -0.13°)'), findsOneWidget);
      expect(find.text('GPS حديث'), findsOneWidget);
      await _maybeCapturePng(tester, currentKey, 'gps_only_home_current_360x800_2x.png');

      // 5) Ramadan screen when UNKNOWN at 360x800 2x: top AND scrolled bottom + containment + real tap & semantics
      mockPrefs.reset();
      fakeProvider
        ..serviceEnabled = true
        ..checkPermissionResult = LocationPermission.denied
        ..requestPermissionResult = LocationPermission.denied
        ..requestPermissionCalls = 0;
      await tester.runAsync(() async {
        await PrayerService.instance.init(forceReload: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      final ramadanKey = GlobalKey();
      final ramadanMessenger = await pumpHarness(
        tester,
        logicalSize: const Size(360, 800),
        textScale: 2.0,
        boundaryKey: ramadanKey,
        child: const RamadanScreen(),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('جمهورية مصر العربية'), findsNothing);
      expect(find.textContaining('تتطلب تحديد موقعك عبر GPS'), findsOneWidget);
      await _maybeCapturePng(tester, ramadanKey, 'gps_only_ramadan_unknown_360x800_2x.png');

      // Scroll Ramadan screen down so the sticky hero scrolls away and the FULL unavailable notice + action card are unmasked & wholly contained in viewport
      final ramadanUnavailableCard =
          find.byKey(const ValueKey('ramadan_imsakiyyah_unavailable_card'));
      expect(ramadanUnavailableCard, findsOneWidget);
      await scrollToBottom(tester, find.byType(Scrollable).first);
      await tester.ensureVisible(ramadanUnavailableCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      assertInViewport(
        tester,
        ramadanUnavailableCard,
        const Size(360, 800),
        reason: 'Full Ramadan unavailable notice card must be unmasked & wholly contained in viewport',
      );
      await _maybeCapturePng(tester, ramadanKey, 'gps_only_ramadan_unknown_bottom_360x800_2x.png');

      final ramadanBottomBtn =
          find.byKey(const ValueKey('gps_enable_retry_button')).last;
      assertInViewport(tester, ramadanBottomBtn, const Size(360, 800), reason: 'Ramadan bottom enable GPS btn');
      await tester.tap(ramadanBottomBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeProvider.requestPermissionCalls, equals(1));
      await clearSnackBarsAndSettle(tester, ramadanMessenger);
      final ramadanSem = tester.getSemantics(ramadanBottomBtn);
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(ramadanSem.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeProvider.requestPermissionCalls, equals(2));
      await clearSnackBarsAndSettle(tester, ramadanMessenger);
      } finally {
        semHandle.dispose();
      }
    });

    testWidgets('Additional changed UI screens (Onboarding, Settings, Heritage, Alarm, Backup) render cleanly at 360x800 2.0x with real icons, containment & semantics', (tester) async {
      final semHandle = tester.ensureSemantics();
      try {
        const size360 = Size(360, 800);

        // Reset to UNKNOWN + permissionDenied
        mockPrefs.reset();
        fakeProvider
          ..serviceEnabled = true
          ..checkPermissionResult = LocationPermission.denied
          ..requestPermissionResult = LocationPermission.denied
          ..requestPermissionCalls = 0;
        await tester.runAsync(() async {
          await SettingsService.instance.init(forceReload: true);
          await FajrQiyamAlarmService.instance.init(forceReload: true);
          await PrayerService.instance.init(forceReload: true);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });

        // A) Onboarding Page 2 at 360x800 2.0x (scroll to GPS card, verify containment + tap)
        final onboardingKey = GlobalKey();
        final onboardingMessenger = await pumpHarness(
          tester,
          logicalSize: size360,
          textScale: 2.0,
          boundaryKey: onboardingKey,
          child: const OnboardingScreen(),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('التالي'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
        expect(find.text('المدينة لمواقيت الصلاة'), findsNothing);
        expect(find.text('القاهرة، مصر'), findsNothing);
        final onboardingBtn = find.byKey(const ValueKey('gps_enable_retry_button'));
        await tester.ensureVisible(onboardingBtn);
        await tester.pump();
        assertInViewport(tester, onboardingBtn, size360, reason: 'Onboarding GPS btn');
        await _maybeCapturePng(tester, onboardingKey, 'gps_only_onboarding_360x800_2x.png');
        await tester.tap(onboardingBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fakeProvider.requestPermissionCalls, equals(1));
        await clearSnackBarsAndSettle(tester, onboardingMessenger);

        // B) Settings Prayer & Fiqh Section at 360x800 2.0x (top + scrolled bottom with GPS controls)
        fakeProvider.requestPermissionCalls = 0;
        final settingsKey = GlobalKey();
        final settingsMessenger = await pumpHarness(
          tester,
          logicalSize: size360,
          textScale: 2.0,
          boundaryKey: settingsKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('إعدادات المواقيت والفقه')),
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  SettingsService.instance,
                  PrayerService.instance,
                ]),
                builder: (_, __) => const SettingsPrayerAndFiqhSection(),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('القاهرة، مصر'), findsNothing);
        // Large-text stacked readable selectors (no squished 2-col dropdowns / floating-label overlap)
        final calcTile = find.byKey(const ValueKey('settings_large_text_calc_method'));
        final fiqhTile = find.byKey(const ValueKey('settings_large_text_fiqh_madhhab'));
        final hijriTile = find.byKey(const ValueKey('settings_large_text_hijri_adjust'));
        expect(calcTile, findsOneWidget);
        expect(fiqhTile, findsOneWidget);
        expect(hijriTile, findsOneWidget);
        expect(find.textContaining('الهيئة المصرية العامة للمساحة'), findsOneWidget);
        expect(find.text('الشافعي / دار الإفتاء المصرية'), findsOneWidget);
        expect(find.text('فلكي (٠)'), findsOneWidget);
        await _maybeCapturePng(tester, settingsKey, 'gps_only_settings_prayer_360x800_2x.png');

        // 1) Actual tap open/select/persist on calc_method + capture open picker pixels at 360x800 2x
        await tester.ensureVisible(calcTile);
        await tester.pump();
        assertInViewport(tester, calcTile, size360, reason: 'Settings calc_method large-text tile');
        await tester.tap(calcTile);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('رابطة العالم الإسلامي'), findsOneWidget);
        await _maybeCapturePng(tester, settingsKey, 'gps_only_settings_picker_open_360x800_2x.png');

        final mwlOption = find.textContaining('رابطة العالم الإسلامي').last;
        await tester.ensureVisible(mwlOption);
        await tester.pump();
        await tester.tap(mwlOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(() => mockPrefs.waitForAllWrites());
        await tester.pump();
        expect(SettingsService.instance.calculationMethod, equals('mwl'));
        expect(mockPrefs.readPersisted('calculation_method'), equals('mwl'));
        expect(find.textContaining('رابطة العالم الإسلامي'), findsOneWidget);

        // 2) Semantic open/select/persist on fiqh_madhhab
        await tester.ensureVisible(fiqhTile);
        await tester.pump();
        assertInViewport(tester, fiqhTile, size360, reason: 'Settings fiqh_madhhab large-text tile');
        final fiqhSem = tester.getSemantics(fiqhTile);
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(fiqhSem.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
        final hanafiOption = find.text('المذهب الحنفي').last;
        await tester.ensureVisible(hanafiOption);
        await tester.pump();
        await tester.tap(hanafiOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(() => mockPrefs.waitForAllWrites());
        await tester.pump();
        expect(SettingsService.instance.fiqhMadhhab, equals('hanafi'));
        expect(mockPrefs.readPersisted('fiqh_madhhab'), equals('hanafi'));
        expect(find.text('المذهب الحنفي'), findsOneWidget);

        // 3) Semantic open/select/persist on hijri_adjust
        await tester.ensureVisible(hijriTile);
        await tester.pump();
        assertInViewport(tester, hijriTile, size360, reason: 'Settings hijri_adjust large-text tile');
        final hijriSem = tester.getSemantics(hijriTile);
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(hijriSem.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
        final plusOneOption = find.text('+١ يوم').last;
        await tester.ensureVisible(plusOneOption);
        await tester.pump();
        await tester.tap(plusOneOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(() => mockPrefs.waitForAllWrites());
        await tester.pump();
        expect(SettingsService.instance.hijriAdjustmentDays, equals(1));
        expect(mockPrefs.readPersisted('hijri_adjustment_days'), equals(1));
        expect(find.text('+١ يوم'), findsOneWidget);

        await scrollToBottom(tester, find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
        final settingsBtn = find.byKey(const ValueKey('gps_enable_retry_button'));
        await tester.ensureVisible(settingsBtn);
        await tester.pump();
        assertInViewport(tester, settingsBtn, size360, reason: 'Settings GPS btn');
        await _maybeCapturePng(tester, settingsKey, 'gps_only_settings_prayer_bottom_360x800_2x.png');
        final settingsSem = tester.getSemantics(settingsBtn);
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(settingsSem.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fakeProvider.requestPermissionCalls, equals(1));
        await clearSnackBarsAndSettle(tester, settingsMessenger);

        // C) Egyptian Heritage Mosques screen (tab 2) at 360x800 2.0x
        final heritageKey = GlobalKey();
        await pumpHarness(
          tester,
          logicalSize: size360,
          textScale: 2.0,
          boundaryKey: heritageKey,
          child: const EgyptianHeritageScreen(initialTabIndex: 2),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('الأزهر'), findsWidgets);
        expect(find.textContaining('ضبط مواقيت الصلاة والقبلة على موقع هذا المسجد'), findsNothing);
        expect(find.textContaining(' كم'), findsNothing);
        await _maybeCapturePng(tester, heritageKey, 'gps_only_heritage_360x800_2x.png');

        // D) Fajr & Qiyam Alarm Screen when UNKNOWN at 360x800 2.0x (top + scrolled bottom)
        fakeProvider.requestPermissionCalls = 0;
        final alarmKey = GlobalKey();
        final alarmMessenger = await pumpHarness(
          tester,
          logicalSize: size360,
          textScale: 2.0,
          boundaryKey: alarmKey,
          child: const FajrQiyamAlarmScreen(),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('04:45'), findsNothing);
        expect(find.textContaining('18:00'), findsNothing);
        expect(find.text('حدّث المواقيت'), findsWidgets);
        await _maybeCapturePng(tester, alarmKey, 'gps_only_alarm_unknown_360x800_2x.png');

        final alarmBtn = find.byKey(const ValueKey('gps_enable_retry_button'));
        await tester.ensureVisible(alarmBtn);
        await tester.pump();
        assertInViewport(tester, alarmBtn, size360, reason: 'Alarm GPS btn');
        await tester.tap(alarmBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fakeProvider.requestPermissionCalls, equals(1));
        await clearSnackBarsAndSettle(tester, alarmMessenger);

        final qiyamTestBtn = find.textContaining('تجربة رنين منبّه قيام الليل');
        await tester.scrollUntilVisible(
          qiyamTestBtn,
          300.0,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(qiyamTestBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        assertInViewport(tester, qiyamTestBtn, size360, reason: 'Alarm bottom Qiyam test btn');
        await _maybeCapturePng(tester, alarmKey, 'gps_only_alarm_unknown_bottom_360x800_2x.png');

        // E) Backup & Restore Screen at 360x800 2.0x (top + scrolled bottom)
        final backupKey = GlobalKey();
        await pumpHarness(
          tester,
          logicalSize: size360,
          textScale: 2.0,
          boundaryKey: backupKey,
          child: const BackupRestoreScreen(),
        );
        expect(tester.takeException(), isNull);
        await _maybeCapturePng(tester, backupKey, 'gps_only_backup_360x800_2x.png');
        await scrollToBottom(tester, find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
        await _maybeCapturePng(tester, backupKey, 'gps_only_backup_bottom_360x800_2x.png');
      } finally {
        semHandle.dispose();
      }
    });

    testWidgets('Qibla sensor lifecycle: waiting, live aligned, stale timeout invalidation, fresh recovery, stream error/done invalidation with deterministic clock/timer & pixels', (tester) async {
      final semHandle = tester.ensureSemantics();
      try {
        const size360 = Size(360, 800);
        DateTime clock = DateTime(2026, 11, 18, 12, 0, 0);
        PrayerService.instance.setClockForTesting(() => clock);
        mockPrefs.reset();
        fakeProvider
          ..serviceEnabled = true
          ..checkPermissionResult = LocationPermission.whileInUse
          ..lastKnownPosition = null
          ..onGetCurrentPosition = () async => _pos(35.6762, 139.6503, timestamp: clock);
        await tester.runAsync(() async {
          await PrayerService.instance.init(forceReload: true);
          await PrayerService.instance.requestGpsLocation();
          await mockPrefs.waitForAllWrites();
          await waitForAllNotifOps();
        });
        expect(PrayerService.instance.currentData, isNotNull);
        // Prevent QiblaCompassScreen.initState() resume check from rescheduling notifications in FakeAsync
        fakeProvider.checkPermissionResult = LocationPermission.denied;
        final qiblaDeg = PrayerService.instance.currentData!.qiblaDegrees;

        final sensorController = StreamController<MagnetometerEvent>.broadcast();
        final qiblaKey = GlobalKey();
        await pumpHarness(
          tester,
          logicalSize: size360,
          textScale: 2.0,
          boundaryKey: qiblaKey,
          child: QiblaCompassScreen(
            magnetometerStreamForTesting: sensorController.stream,
            nowProviderForTesting: () => clock,
          ),
        );

        // 1) Waiting state: verified GPS numeric bearing shown, NO needle, NO move-phone/aligned semantics
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsNothing);
        expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsOneWidget);
        expect(find.textContaining('حرك الهاتف'), findsNothing);
        expect(find.textContaining('أنت الآن باتجاه القبلة'), findsNothing);
        expect(find.textContaining('${qiblaDeg.toStringAsFixed(1)}°'), findsOneWidget);

        // 2) Live aligned reading -> needle renders & aligned guidance semantics active
        // atan2(-x, y) == qiblaRad => x = -sin(qiblaRad), y = cos(qiblaRad)
        final qiblaRad = qiblaDeg * (math.pi / 180.0);
        sensorController.add(
          MagnetometerEvent(-25.0 * math.sin(qiblaRad), 25.0 * math.cos(qiblaRad), 0.0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsOneWidget);
        expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsNothing);
        final alignedSem = tester.getSemantics(
          find.byKey(const ValueKey('qibla_guidance_banner')),
        );
        expect(alignedSem.label, contains('أنت الآن باتجاه القبلة'));

        // 3) Advance deterministic clock & timer past stale timeout (5s) with NO new readings ->
        // heading invalidated, arrow & alignment semantics REMOVED (no unbounded remembered heading!)
        clock = clock.add(const Duration(seconds: 6));
        await tester.pump(QiblaCompassScreen.sensorHeadingStaleTimeout);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsNothing);
        expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsOneWidget);
        final staleSem = tester.getSemantics(
          find.byKey(const ValueKey('qibla_guidance_banner')),
        );
        expect(staleSem.label, contains('توقفت قراءات حساس البوصلة'));
        expect(staleSem.label, isNot(contains('أنت الآن باتجاه القبلة')));
        expect(staleSem.label, isNot(contains('حرك الهاتف')));
        await _maybeCapturePng(tester, qiblaKey, 'gps_only_qibla_stale_sensor_360x800_2x.png');

        await scrollToBottom(tester, find.byType(Scrollable).first);
        expect(find.text('قراءة منتهية'), findsOneWidget);
        expect(find.text('غير متاح'), findsOneWidget);
        expect(find.text('${qiblaDeg.toStringAsFixed(0)}°'), findsOneWidget);

        // 4) Recovery on fresh reading -> needle & live heading restored immediately
        await scrollToTop(tester, find.byType(Scrollable).first);
        sensorController.add(MagnetometerEvent(0.0, 25.0, 0.0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsOneWidget);
        expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsNothing);
        expect(find.textContaining('حرك الهاتف'), findsOneWidget);

        // 5) Stream error invalidates heading, removes arrow & alignment guidance, preserves numeric bearing
        sensorController.addError(Exception('magnetometer lost'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsNothing);
        expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsOneWidget);
        final errSem = tester.getSemantics(
          find.byKey(const ValueKey('qibla_guidance_banner')),
        );
        expect(errSem.label, contains('حساس البوصلة غير متاح'));
        expect(errSem.label, contains('${qiblaDeg.toStringAsFixed(0)}°'));
        expect(errSem.label, isNot(contains('حرك الهاتف')));
        await _maybeCapturePng(tester, qiblaKey, 'gps_only_qibla_sensor_error_360x800_2x.png');

        // 6) Recovery after transient stream error -> needle returns on fresh valid reading
        clock = clock.add(const Duration(seconds: 1));
        sensorController.add(MagnetometerEvent(0.0, 25.0, 0.0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsOneWidget);

        // 7) Stream done invalidates heading & removes arrow/alignment semantics
        await sensorController.close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('qibla_direction_needle')), findsNothing);
        expect(find.byKey(const ValueKey('qibla_unavailable_dial_notice')), findsOneWidget);
        final doneSem = tester.getSemantics(
          find.byKey(const ValueKey('qibla_guidance_banner')),
        );
        expect(doneSem.label, contains('حساس البوصلة غير متاح'));
        expect(doneSem.label, isNot(contains('حرك الهاتف')));

        // Unmount QiblaCompassScreen cleanly so its repeating AnimationController disposes before FakeAsync teardown
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        semHandle.dispose();
      }
    });
  });
}
