// Test-only storage fault injection through shared_preferences' existing platform dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/app/router.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/widgets/sections/settings_adhkar_reminders_section.dart';

class FailingPreferences extends InMemorySharedPreferencesStore {
  FailingPreferences() : super.withData({'flutter.notif_master_enabled': true});
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail) return false;
    return super.setValue(type, key, value);
  }
}

class ReminderPlayer extends AudioPlayer {
  bool disposed = false, active = false, failLoad = false, failStop = false;
  int plays = 0, stops = 0;
  Completer<void>? loadGate, stopGate;
  final paths = <String>[];
  @override
  bool get playing => active;
  @override
  Future<Duration?> setAsset(String path,
      {String? package,
      bool preload = true,
      Duration? initialPosition,
      dynamic tag}) async {
    paths.add(path);
    if (loadGate != null) await loadGate!.future;
    if (failLoad) throw StateError('load');
    return const Duration(seconds: 6);
  }

  @override
  Future<void> play() async {
    plays++;
    active = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
    if (failStop) throw StateError('stop');
    active = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    active = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final pending = <int, Map<dynamic, dynamic>>{};
  bool permission = true, failCancel = false, failSchedule = false;
  Completer<void>? cancelGate;
  final service = PrayerNotificationService.instance;
  setUpAll(() async {
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    }
  });
  Future<void> mount(WidgetTester tester,
      {ReminderPlayer? player,
      bool dark = false,
      double width = 320,
      double scale = 2}) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('frequency-pixels'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: SettingsAdhkarRemindersSection(
                        previewPlayerFactory:
                            player == null ? null : () => player))),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('FREQUENCY_PIXELS_DIR');
    if (dir.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('frequency-pixels')))
            as RenderRepaintBoundary;
    boundary.markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  setUp(() async {
    FastAudioService.instance.resetForTesting();
    calls.clear();
    pending.clear();
    permission = true;
    failCancel = false;
    failSchedule = false;
    cancelGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments;
      if (call.method == 'initialize') return true;
      if (call.method == 'areNotificationsEnabled') return permission;
      if (call.method == 'cancel') {
        final id = args['id'] as int;
        if (id == 805 && cancelGate != null) await cancelGate!.future;
        if (failCancel && id == 805) {
          throw PlatformException(code: 'cancel-failed');
        }
        pending.remove(id);
      }
      if (call.method == 'cancelAll') pending.clear();
      if (call.method == 'periodicallyShowWithDuration') {
        if (failSchedule) throw PlatformException(code: 'schedule-failed');
        pending[args['id'] as int] = Map<dynamic, dynamic>.of(args);
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'notif_master_enabled': true});
    await service.init(forceReload: true);
    await service.scheduleAdhkarReminders();
    calls.clear();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
      'new defaults off and invalid stored frequency off without touching unrelated IDs',
      () async {
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.off);
    expect(service.shortFrequency('istighfar'), ShortReminderFrequency.off);
    pending[801] = {'existing': true};
    pending[100] = {'existing': true};
    await service.scheduleShortReminders();
    expect(pending.keys, containsAll([801, 100]));
    expect(calls.where((c) => c.method == 'periodicallyShow'), isEmpty);
    SharedPreferences.setMockInitialValues(
        {'notif_short_salawat_frequency': 'everySecond'});
    await service.init(forceReload: true);
    await service.scheduleAdhkarReminders();
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.off);
  });
  test(
      'independent hourly and daily actual plugin payload, raw sounds and persisted reload',
      () async {
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    await service.setShortReminderFrequency(
        'istighfar', ShortReminderFrequency.daily);
    expect(pending[805]?['repeatIntervalMilliseconds'], 3600000);
    expect(pending[806]?['repeatIntervalMilliseconds'], 86400000);
    expect(pending[805]?['calledAt'], isA<int>());
    expect((pending[805]?['platformSpecifics'] as Map?)?['scheduleMode'],
        'inexactAllowWhileIdle');
    expect((pending[805]?['platformSpecifics'] as Map?)?['sound'],
        'reminder_salawat');
    expect((pending[806]?['platformSpecifics'] as Map?)?['sound'],
        'reminder_istighfar');
    expect((pending[805]?['platformSpecifics'] as Map?)?['channelId'],
        'short_salawat_reminder_v1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notif_short_salawat_frequency'), 'hourly');
    await service.init(forceReload: true);
    await service.scheduleAdhkarReminders();
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.hourly);
    expect(service.shortFrequency('istighfar'), ShortReminderFrequency.daily);
  });
  test(
      'permission denial and scheduling and cancellation errors remain truthful and retryable',
      () async {
    permission = false;
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    expect(pending[805], isNull);
    expect(service.shortReminderError('salawat'), contains('اسمح'));
    permission = true;
    failSchedule = true;
    await service.scheduleShortReminders();
    expect(service.shortReminderError('salawat'), contains('تعذر'));
    failSchedule = false;
    await service.scheduleShortReminders();
    expect(pending[805], isNotNull);
    failCancel = true;
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.off);
    expect(pending[805], isNotNull);
    expect(service.shortReminderError('salawat'), contains('السابق'));
    failCancel = false;
    await service.scheduleShortReminders();
    expect(pending[805], isNull);
    expect(service.shortReminderError('salawat'), isNull);
  });
  test('delayed cancellation cannot reinstall stale frequency after later off',
      () async {
    cancelGate = Completer<void>();
    final old = service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    await Future<void>.delayed(Duration.zero);
    final latest = service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.off);
    await Future<void>.delayed(Duration.zero);
    cancelGate!.complete();
    await old;
    await latest;
    expect(pending[805], isNull);
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.off);
    expect(service.shortReminderBusy, isFalse);
  });
  test(
      'master off pending cancellation followed by on preserves latest enabled intent',
      () async {
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    cancelGate = Completer<void>();
    final heldCancel = service.scheduleShortReminders();
    await Future<void>.delayed(Duration.zero);
    final off = service.toggleMaster(false);
    await Future<void>.delayed(Duration.zero);
    final on = service.toggleMaster(true);
    await Future<void>.delayed(Duration.zero);
    cancelGate!.complete();
    await heldCancel;
    await off;
    await on;
    await service.scheduleAdhkarReminders();
    expect(service.masterEnabled, isTrue);
    expect(pending[805], isNotNull);
  });
  test('all supported duration choices use two stable notification channel IDs',
      () async {
    for (final entry in {
      ShortReminderFrequency.halfHourly: 1800000,
      ShortReminderFrequency.hourly: 3600000,
      ShortReminderFrequency.twoHourly: 7200000,
      ShortReminderFrequency.daily: 86400000
    }.entries) {
      await service.setShortReminderFrequency('salawat', entry.key);
      expect(pending[805]?['repeatIntervalMilliseconds'], entry.value);
      expect((pending[805]?['platformSpecifics'] as Map?)?['channelId'],
          'short_salawat_reminder_v1');
    }
    expect(pending.keys.where((id) => id >= 805 && id <= 806), [805]);
  });
  test(
      'master rapid on off on and retry after plugin error is not a poisoned queue',
      () async {
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    failSchedule = true;
    await service.toggleMaster(true);
    expect(service.shortReminderError('salawat'), isNotNull);
    failSchedule = false;
    await Future.wait([
      service.toggleMaster(true),
      service.toggleMaster(false),
      service.toggleMaster(true)
    ]);
    await service.scheduleAdhkarReminders();
    expect(service.masterEnabled, isTrue);
    expect(pending[805], isNotNull);
    expect(service.shortReminderError('salawat'), isNull);
    expect(
        (await SharedPreferences.getInstance()).getBool('notif_master_enabled'),
        isTrue);
    await service.toggleMaster(false);
    expect(pending, isEmpty);
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.hourly);
  });
  testWidgets(
      'preview owns focus, explicit stop, load failure and dismiss dispose',
      (tester) async {
    final player = ReminderPlayer();
    final prior = ReminderPlayer()..active = true;
    FastAudioService.instance
        .registerAudioFocus(player: prior, onStopOther: prior.stop);
    await mount(tester, player: player);
    await tester.ensureVisible(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    expect(prior.active, isFalse);
    expect(player.paths, ['assets/audio/reminder_salawat.mp3']);
    expect(player.active, isTrue);
    await tester.tap(find.text('إيقاف المعاينة'));
    await tester.pumpAndSettle();
    expect(player.active, isFalse);
    player.failLoad = true;
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تشغيل المعاينة.'), findsOneWidget);
    await capture(tester, 'preview-load-failure-320-2');
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
    await tester.pumpWidget(const SizedBox());
    await prior.dispose();
  });
  testWidgets('pending stop blocks new play and repeated stop until completion', (tester) async {
    final player = ReminderPlayer();
    await mount(tester, player: player, scale: 1, width: 500);
    await tester.ensureVisible(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    player.stopGate = Completer<void>();
    final stops = player.stops;
    await tester.tap(find.text('إيقاف المعاينة'));
    await tester.pump();
    expect(player.active, isTrue);
    expect(player.stops, stops + 1);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'تشغيل المعاينة')).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'إيقاف المعاينة')).onPressed, isNull);
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.tap(find.text('إيقاف المعاينة'));
    await tester.pump();
    expect(player.plays, 1);
    expect(player.stops, stops + 1);
    await capture(tester, 'preview-pending-stop');
    player.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(player.active, isFalse);
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    expect(player.plays, 2);
    expect(player.active, isTrue);
    expect(find.text('تعذر إيقاف المعاينة. أعد محاولة الإيقاف.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('keyboard and descendant focus traversal keeps preview playing', (tester) async {
    final player = ReminderPlayer();
    await mount(tester, player: player, scale: 1, width: 500);
    await tester.ensureVisible(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    final stops = player.stops;
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(player.active, isTrue);
      expect(player.stops, stops);
    }
    for (final label in ['تشغيل المعاينة', 'إيقاف المعاينة', 'إغلاق']) {
      final context = tester.element(find.text(label));
      final node = Focus.of(context);
      expect(node.canRequestFocus, isTrue);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      expect(player.active, isTrue);
      expect(player.stops, stops);
    }
    await tester.tap(find.text('إيقاف المعاينة'));
    await tester.pumpAndSettle();
    expect(player.active, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('dismiss during load cannot later play', (tester) async {
    final player = ReminderPlayer()..loadGate = Completer<void>();
    await mount(tester, player: player, scale: 1, width: 500);
    await tester.ensureVisible(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pump();
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    player.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(player.plays, 0);
    expect(player.disposed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('preview stops on navigation cover and app pause',
      (tester) async {
    final player = ReminderPlayer();
    await mount(tester, player: player, width: 500, scale: 1);
    await tester.ensureVisible(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    expect(player.active, isTrue);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next')))));
    await tester.pumpAndSettle();
    expect(player.active, isFalse);
    nav.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(player.active, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(player.disposed, isTrue);
  });
  testWidgets(
      'frequency cards remain readable in light dark at320 and2x with error and selected semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    permission = false;
    await service.setShortReminderFrequency(
        'istighfar', ShortReminderFrequency.halfHourly);
    for (final dark in [false, true]) {
      await mount(tester, dark: dark);
      await capture(tester, 'inherited-clock-after-$dark-320-2');
      await tester.ensureVisible(find.text('التذكير الصوتي القصير'));
      await tester.pumpAndSettle();
      await capture(tester, 'frequency-top-$dark-320-2');
      await tester.ensureVisible(find.text('الاستغفار والحوقلة'));
      await tester.pumpAndSettle();
      await capture(tester, 'frequency-adhkar-$dark-320-2');
      expect(find.bySemanticsLabel('الاستغفار والحوقلة، كل ٣٠ دقيقة'),
          findsOneWidget);
      expect(find.textContaining('اسمح بإشعارات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
  test('short notification tap opens settings, never adhan autoplay', () async {
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    final payload = pending[805]!['payload'];
    expect(payload, 'type=short_reminder&kind=salawat');
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec()
                .encodeMethodCall(MethodCall('didReceiveNotificationResponse', {
              'notificationResponseType': 0,
              'id': 805,
              'payload': payload,
            })),
            (_) => done.complete());
    await done.future;
    await Future<void>.delayed(Duration.zero);
    expect(appRouter.routeInformationProvider.value.uri.path, '/settings');
    expect(
        appRouter
            .routeInformationProvider.value.uri.queryParameters['autoPlay'],
        isNull);
    appRouter.go('/home');
  });
  test(
      'failed preference save leaves state and persisted cache truthful and does not poison either queue',
      () async {
    final backend = FailingPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    await expectLater(service.toggleMaster(false), throwsStateError);
    expect(service.masterEnabled, isTrue);
    expect(
        (await SharedPreferences.getInstance()).getBool('notif_master_enabled'),
        isTrue);
    await expectLater(
        service.setShortReminderFrequency(
            'salawat', ShortReminderFrequency.hourly),
        throwsStateError);
    expect(service.shortFrequency('salawat'), ShortReminderFrequency.off);
    expect(
        (await SharedPreferences.getInstance())
            .getString('notif_short_salawat_frequency'),
        isNull);
    backend.fail = false;
    await service.toggleMaster(false);
    await service.toggleMaster(true);
    await service.setShortReminderFrequency(
        'salawat', ShortReminderFrequency.hourly);
    expect(service.masterEnabled, isTrue);
    expect(pending[805], isNotNull);
  });
  testWidgets(
      'preview stop failure is visible, blocks restart, retries and closes after success',
      (tester) async {
    final player = ReminderPlayer();
    await mount(tester, player: player);
    await tester.ensureVisible(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('استماع إلى الصوت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تشغيل المعاينة'));
    await tester.pumpAndSettle();
    player.failStop = true;
    await tester.tap(find.text('إيقاف المعاينة'));
    await tester.pumpAndSettle();
    expect(
        find.text('تعذر إيقاف المعاينة. أعد محاولة الإيقاف.'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'تشغيل المعاينة'))
            .onPressed,
        isNull);
    await capture(tester, 'preview-stop-failure-320-2');
    player.failStop = false;
    await tester.tap(find.text('إيقاف المعاينة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
  });
  testWidgets(
      'accurate labels and permission error are visible with no success claim',
      (tester) async {
    permission = false;
    await service.setShortReminderFrequency(
        'istighfar', ShortReminderFrequency.hourly);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SettingsAdhkarRemindersSection()))));
    await tester.ensureVisible(find.text('الاستغفار والحوقلة'));
    await tester.pumpAndSettle();
    expect(find.text('الاستغفار والحوقلة'), findsOneWidget);
    expect(find.textContaining('اسمح بإشعارات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
