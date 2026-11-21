import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/prayer/adhan_control_screen.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('almomin/active_prayer_alert');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
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
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    AdhanSensorGestureService.instance.accelerometerStreamOverride =
        const Stream<AccelerometerEvent>.empty();
    await IslamicAudioService.instance.stop();
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await IslamicAudioService.instance.stop();
    IslamicAudioService.instance.disableNativePlayerForTesting = false;
    AdhanSensorGestureService.instance.accelerometerStreamOverride = null;
  });
  Widget app(Widget home, {double scale = 1, GlobalKey? boundary}) =>
      RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: home));
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'adhan screen fits 360px at $scale and explicit play works with no track',
        (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(app(
          const AdhanControlScreen(prayerName: 'العصر', autoPlay: false),
          scale: scale,
          boundary: key));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      final dir = Platform.environment['ADHAN_SCREENSHOT_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/adhan-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      final resume = find.widgetWithText(OutlinedButton, 'تشغيل الأذان الآن');
      await t.scrollUntilVisible(resume, 300,
          scrollable: find.byType(Scrollable).first);
      await t.pump(const Duration(milliseconds: 100));
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/adhan-controls-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      await t.tap(resume);
      await t.pump(const Duration(milliseconds: 200));
      expect(IslamicAudioService.instance.currentTrack, isNotNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'notification entry is silent in Flutter and semantic Close stops exact captured alert before pop',
      (t) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'capture'
          ? {'id': 100, 'key': 'original', 'postTime': 77}
          : 'stopped';
    });
    final semantics = t.ensureSemantics();
    await t.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const AdhanControlScreen(
                            prayerName: 'العصر',
                            autoPlay: false,
                            nativeNotificationId: 100))),
                child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(IslamicAudioService.instance.currentTrack, isNull);
    expect(calls.map((c) => c.method), ['capture']);
    final close = find.byTooltip('إيقاف الصوت والإغلاق');
    t.binding.performSemanticsAction(ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        nodeId: t.getSemantics(close).id,
        viewId: t.view.viewId));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(calls.map((c) => c.method), ['capture', 'stopCaptured']);
    expect(
        calls.last.arguments, {'id': 100, 'key': 'original', 'postTime': 77});
    expect(find.text('open'), findsOneWidget);
    semantics.dispose();
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('failed native stop leaves screen open and never claims success',
      (t) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'capture')
        return {'id': 100, 'key': 'original', 'postTime': 77};
      throw PlatformException(code: 'stop_failed');
    });
    await t.pumpWidget(app(const AdhanControlScreen(
        prayerName: 'العصر', autoPlay: false, nativeNotificationId: 100)));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byTooltip('إيقاف الصوت والإغلاق'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(AdhanControlScreen), findsOneWidget);
    expect(find.textContaining('تعذر تأكيد إيقاف الصوت'), findsOneWidget);
    expect(find.text('تم إيقاف الأذان بنجاح ⏹️'), findsNothing);
    expect(IslamicAudioService.instance.currentTrack, isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('native stop failure also blocks explicit second recording',
      (t) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'capture')
        return {'id': 100, 'key': 'original', 'postTime': 77};
      throw PlatformException(code: 'stop_failed');
    });
    await t.pumpWidget(app(const AdhanControlScreen(
        prayerName: 'العصر', autoPlay: false, nativeNotificationId: 100)));
    await t.pump(const Duration(milliseconds: 100));
    final play = find.widgetWithText(OutlinedButton, 'تشغيل الأذان الآن');
    await t.scrollUntilVisible(play, 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(play);
    await t.pump(const Duration(milliseconds: 200));
    expect(IslamicAudioService.instance.currentTrack, isNull);
    expect(find.textContaining('لم يبدأ صوت آخر'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('replacement alert blocks a second player', (t) async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture'
            ? {'id': 100, 'key': 'original', 'postTime': 77}
            : 'replaced');
    await t.pumpWidget(app(const AdhanControlScreen(
        prayerName: 'العصر', autoPlay: false, nativeNotificationId: 100)));
    await t.pump(const Duration(milliseconds: 100));
    final play = find.widgetWithText(OutlinedButton, 'تشغيل الأذان الآن');
    await t.scrollUntilVisible(play, 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(play);
    await t.pump(const Duration(milliseconds: 200));
    expect(IslamicAudioService.instance.currentTrack, isNull);
    expect(find.textContaining('لم يبدأ صوت آخر'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'explicit Stop confirms captured alert and then shows stopped state',
      (t) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'capture'
          ? {'id': 100, 'key': 'original', 'postTime': 77}
          : 'stopped';
    });
    await t.pumpWidget(app(const AdhanControlScreen(
        prayerName: 'العصر', autoPlay: false, nativeNotificationId: 100)));
    await t.pump(const Duration(milliseconds: 100));
    final stop = find.widgetWithText(ElevatedButton, 'إيقاف الأذان فوراً');
    await t.scrollUntilVisible(stop, 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(stop);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(calls, ['capture', 'stopCaptured']);
    expect(find.text('تم إيقاف الأذان بنجاح ⏹️'), findsOneWidget);
    expect(IslamicAudioService.instance.currentTrack, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'closing while explicit playback awaits native stop cannot start late audio',
      (t) async {
    final pending = Completer<String>();
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'capture')
        return {'id': 100, 'key': 'original', 'postTime': 77};
      stops++;
      return stops == 1 ? pending.future : 'stopped';
    });
    await t.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const AdhanControlScreen(
                            prayerName: 'العصر',
                            autoPlay: false,
                            nativeNotificationId: 100))),
                child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final play = find.widgetWithText(OutlinedButton, 'تشغيل الأذان الآن');
    await t.scrollUntilVisible(play, 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(play);
    await t.pump();
    await t.tap(find.byTooltip('إيقاف الصوت والإغلاق'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('open'), findsOneWidget);
    pending.complete('stopped');
    await t.pump(const Duration(milliseconds: 100));
    expect(IslamicAudioService.instance.currentTrack, isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('pre-reminder is not mislabeled as prayer time or preview',
      (t) async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    await t.pumpWidget(app(const AdhanControlScreen(
        prayerName: 'العصر',
        autoPlay: false,
        nativeNotificationId: 100,
        notificationKind: 'prereminder')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('تذكير قبل صلاة العصر'), findsOneWidget);
    expect(find.textContaining('حان الآن'), findsNothing);
    expect(IslamicAudioService.instance.currentTrack, isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'an unknown saved voice is not silently replaced during explicit playback',
      (t) async {
    const notifications =
        MethodChannel('dexterous.com/flutter/local_notifications');
    messenger.setMockMethodCallHandler(
        notifications,
        (call) async =>
            call.method == 'getNotificationAppLaunchDetails' ? null : true);
    addTearDown(() => messenger.setMockMethodCallHandler(notifications, null));
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': false,
      'notif_prayer_voice_العصر': 'unknown-old-voice',
      'notif_morning_adhkar_enabled': false,
      'notif_evening_adhkar_enabled': false,
      'notif_sleep_adhkar_enabled': false
    });
    await t.runAsync(
        () => PrayerNotificationService.instance.init(forceReload: true));
    await t.pumpWidget(
        app(const AdhanControlScreen(prayerName: 'العصر', autoPlay: false)));
    await t.pump(const Duration(milliseconds: 100));
    final play = find.widgetWithText(OutlinedButton, 'تشغيل الأذان الآن');
    await t.scrollUntilVisible(play, 300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(play);
    await t.pump(const Duration(milliseconds: 200));
    expect(IslamicAudioService.instance.currentTrack, isNull);
    expect(find.textContaining('التسجيل المحفوظ غير متاح'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notif_prayer_voice_العصر'), 'unknown-old-voice');
    await t.pumpWidget(const SizedBox());
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(
        () => PrayerNotificationService.instance.init(forceReload: true));
  });
}
