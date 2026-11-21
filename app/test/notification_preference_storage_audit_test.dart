import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/features/prayer/adhan_control_screen.dart';
import 'package:almomin/features/prayer/widgets/prayer_times_card.dart';
import 'package:almomin/features/settings/widgets/settings_prayer_reminders_modal.dart';
import 'package:almomin/features/settings/widgets/sections/settings_adhan_and_sensors_section.dart';
import 'package:almomin/core/ui/app_dropdown_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';

class RejectNotificationStore extends InMemorySharedPreferencesStore {
  RejectNotificationStore()
      : super.withData({'flutter.notif_master_enabled': false});
  bool reject = false, throwing = false;
  Completer<void>? hold;
  int writes = 0;
  @override
  Future<bool> remove(String key) async {
    if (throwing) throw PlatformException(code: 'test-write');
    if (reject) return false;
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (hold != null) await hold!.future;
    if (throwing) throw PlatformException(code: 'test-write');
    return reject ? false : await super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PrayerNotificationService.instance;
  late RejectNotificationStore store;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/$family-Regular.ttf').readAsBytesSync())));
      await loader.load();
    }
  });
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') return null;
      return true;
    });
    SharedPreferences.setMockInitialValues({});
    store = RejectNotificationStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
    store.reject = true;
    calls.clear();
  });
  test('failed prayer toggle leaves live prayer state unchanged', () async {
    final before = service.isPrayerEnabled('العصر');
    await service.togglePrayer('العصر', !before);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getBool('notif_prayer_العصر'), isNull);
    expect(service.isPrayerEnabled('العصر'), before);
  });
  test('failed sound choice cannot change live alarm mode', () async {
    final before = service.soundMode;
    await service.setSoundMode(AdhanSoundMode.silent);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notif_sound_mode'), isNull);
    expect(service.soundMode, before);
  });
  test('failed temporary mute cannot silence the live schedule', () async {
    expect(service.isTemporarilyMuted, isFalse);
    await service.muteForDuration(const Duration(hours: 2));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('notif_mute_until'), isNull);
    expect(service.isTemporarilyMuted, isFalse);
  });
  for (final throwing in [false, true]) {
    test('failed writes never reschedule and retry recovers, throw=$throwing',
        () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.setSoundMode(AdhanSoundMode.silent), isFalse);
      expect(await service.togglePrayer('العصر', false), isFalse);
      expect(await service.muteForDuration(const Duration(hours: 2)), isFalse);
      expect(
          calls.where(
              (c) => c.method == 'cancel' || c.method == 'zonedSchedule'),
          isEmpty);
      expect(service.preferenceError, isNotNull);
      await service.init(forceReload: true);
      expect(service.soundMode, AdhanSoundMode.fullAdhan);
      expect(service.isPrayerEnabled('العصر'), isTrue);
      expect(service.isTemporarilyMuted, isFalse);
      store.reject = false;
      store.throwing = false;
      expect(await service.setSoundMode(AdhanSoundMode.silent), isTrue);
      expect(service.preferenceError, isNull);
      await service.init(forceReload: true);
      expect(service.soundMode, AdhanSoundMode.silent);
    });
  }
  test('failed mute cancellation keeps saved active mute, including reload',
      () async {
    store.reject = false;
    expect(await service.muteForDuration(const Duration(hours: 2)), isTrue);
    final savedUntil = service.muteUntil;
    store.reject = true;
    expect(await service.cancelTemporaryMute(), isFalse);
    expect(service.muteUntil, savedUntil);
    await service.init(forceReload: true);
    expect(service.muteUntil, savedUntil);
    store.reject = false;
    expect(await service.cancelTemporaryMute(), isTrue);
    await service.init(forceReload: true);
    expect(service.isTemporarilyMuted, isFalse);
  });
  test('pending commands stay unpublished and serialize in issue order',
      () async {
    store.reject = false;
    final gate = Completer<void>();
    store.hold = gate;
    final first = service.setSoundMode(AdhanSoundMode.silent);
    final second = service.setSoundMode(AdhanSoundMode.vibrateOnly);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.soundMode, AdhanSoundMode.fullAdhan);
    store.hold = null;
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(service.soundMode, AdhanSoundMode.vibrateOnly);
    await service.init(forceReload: true);
    expect(service.soundMode, AdhanSoundMode.vibrateOnly);
  });

  Widget app(Widget home, double scale, {GlobalKey? boundary}) => RepaintBoundary(
    key: boundary,
    child: MaterialApp(theme: ThemeData(fontFamily: 'Cairo'),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: home),
  );
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/notif-pref1623/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('legacy mode picker stays open with visible failure at $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await SettingsService.instance.init();
      final boundary = GlobalKey();
      await tester.pumpWidget(app(
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showSettingsSoundModeModal(context),
                      child: const Text('open')))),
          scale,
          boundary: boundary));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final option = find.text('تنبيه صامت (بدون صوت)');
      await tester.scrollUntilVisible(option, 240,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(service.soundMode, AdhanSoundMode.fullAdhan);
      final error = find.text(service.preferenceError!);
      expect(error, findsOneWidget);
      final rect = tester.getRect(error);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(800));
      final sem = tester.widget<Semantics>(
          find.ancestor(of: error, matching: find.byType(Semantics)).first);
      expect(sem.properties.liveRegion, isTrue);
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'mode-failure-$scale');
    });
  }
  testWidgets(
      'prayer-card failed toggle retains live enabled icon and shows error',
      (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(app(
        Scaffold(
            body: PrayerTimesCard(
                isDark: false,
                data: PrayerData(
                    latitude: 30,
                    longitude: 31,
                    locationName: 'القاهرة',
                    prayers: [
                      PrayerInfo(
                          name: 'العصر', time: now, formattedTime: '16:00')
                    ],
                    qiblaDegrees: 135,
                    lastUpdated: now))),
        1));
    await tester.tap(find.byIcon(Icons.notifications_active_rounded));
    await tester.pumpAndSettle();
    expect(service.isPrayerEnabled('العصر'), isTrue);
    expect(find.text(service.preferenceError!), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'dropdown resets retained mode after repeated rejected selections',
      (tester) async {
    await SettingsService.instance.init();
    await tester.pumpWidget(app(
        const Scaffold(
            body:
                SingleChildScrollView(child: SettingsAdhanAndSensorsSection())),
        1));
    final dropdown = find.byType(AppDropdownField<AdhanSoundMode>);
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('إشعار صامت').last);
      await tester.pumpAndSettle();
      expect(service.soundMode, AdhanSoundMode.fullAdhan);
      final selected = tester.state<FormFieldState<AdhanSoundMode>>(
          find.descendant(of: dropdown, matching: find.byType(DropdownButtonFormField<AdhanSoundMode>)));
      expect(selected.value, AdhanSoundMode.fullAdhan);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'options sheet can close during pending preference without late setState',
      (tester) async {
    tester.view.physicalSize = const Size(412,915); tester.view.devicePixelRatio = 1;
    addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
    await SettingsService.instance.init();
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    AdhanSensorGestureService.instance.accelerometerStreamOverride =
        const Stream<AccelerometerEvent>.empty();
    addTearDown(() {
      IslamicAudioService.instance.disableNativePlayerForTesting = false;
      AdhanSensorGestureService.instance.accelerometerStreamOverride = null;
    });
    await tester.pumpWidget(
        app(const AdhanControlScreen(prayerName: 'العصر', autoPlay: false), 1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('خيارات تفعيل وإيقاف الأذان'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final gate = Completer<void>();
    store.hold = gate;
    store.reject = false;
    for (var i = 0; i < 8 && find.text('أذان صلاة العصر').hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0,-240));
      await tester.pump(const Duration(milliseconds:400));
    }
    expect(find.text('أذان صلاة العصر').hitTestable(), findsOneWidget);
    await tester.tap(find.text('أذان صلاة العصر').hitTestable());
    await tester.pump();
    await tester.tap(find.byTooltip('إغلاق أو مسح').last);
    await tester.pump(const Duration(milliseconds: 400));
    store.hold = null;
    gate.complete();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.isPrayerEnabled('العصر'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
