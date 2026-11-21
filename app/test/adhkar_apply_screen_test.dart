import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PrayerNotificationService.instance;
  var fail = false;
  var attempts = 0;
  final eveningCalls = <Map>[];
  setUp(() async {
    fail = false;
    attempts = 0;
    eveningCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'initialize' ||
          call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications' ||
          call.method == 'requestNotificationsPermission' ||
          call.method == 'requestExactAlarmsPermission') return true;
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      if (call.method == 'zonedSchedule' &&
          (call.arguments as Map)['id'] == 802) {
        attempts++;
        if (fail) throw PlatformException(code: 'exact_alarms_not_permitted');
        eveningCalls.add(Map.of(call.arguments as Map));
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': true,
      'notif_evening_adhkar_enabled': false,
      'notif_evening_adhkar_hour': 20,
      'notif_evening_adhkar_minute': 0
    });
    await SettingsService.instance.init(forceReload: true);
    await service.init(forceReload: true);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('actual evening20 Apply failure and native retry at $scale',
        (t) async {
      await t.runAsync(() async {
        for (final family in ['Cairo', 'Amiri']) {
          await (FontLoader(family)
                ..addFont(Future.value(ByteData.sublistView(
                    File('assets/fonts/$family-Regular.ttf')
                        .readAsBytesSync()))))
              .load();
        }
        final icons = File(
            '${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
        await (FontLoader('MaterialIcons')
              ..addFont(
                  Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
            .load();
      });
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        final dir = Platform.environment['ADHKAR_SCREENSHOT_DIR'];
        if (dir == null) return;
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/$name-$scale.png')
              .writeAsBytes(data!.buffer.asUint8List());
        });
      }

      try {
        await t.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const SettingsScreen())));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('settings_category_3')));
        await t.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('setting_أذكار المساء'));
        await t.ensureVisible(toggle);
        await t.pumpAndSettle();
        fail = true;
        t.binding.performSemanticsAction(ui.SemanticsActionEvent(
            type: ui.SemanticsAction.tap,
            nodeId: t.getSemantics(toggle).id,
            viewId: t.view.viewId));
        await t.pumpAndSettle();
        expect(service.eveningAdhkarEnabled, isFalse,
            reason: 'Choice stays staged before Apply');
        await t.tap(find.byKey(const ValueKey('settings_apply')));
        await t.pumpAndSettle();
        expect(find.text('تم حفظ التغييرات'), findsNothing);
        final warning = find.textContaining('لم تكتمل كل التغييرات');
        expect(warning, findsOneWidget);
        expect(
            t
                .getSemantics(warning)
                .getSemanticsData()
                .flagsCollection.isLiveRegion,
            isTrue);
        expect(
            t
                .widget<FilledButton>(
                    find.byKey(const ValueKey('settings_apply')))
                .onPressed,
            isNotNull);
        expect(service.adhkarScheduleConfirmed('evening'), isFalse);
        final before = attempts;
        await capture('failed');
        fail = false;
        await t.tap(find.byKey(const ValueKey('settings_apply')));
        await t.pumpAndSettle();
        expect(attempts, greaterThan(before));
        expect(find.text('تم حفظ التغييرات'), findsOneWidget);
        expect(service.adhkarScheduleConfirmed('evening'), isTrue);
        expect(eveningCalls.last['scheduledDateTime'], contains('20:00:00'));
        expect(
            t
                .widget<FilledButton>(
                    find.byKey(const ValueKey('settings_apply')))
                .onPressed,
            isNull);
        expect(t.takeException(), isNull);
        await capture('saved');
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  }
}
