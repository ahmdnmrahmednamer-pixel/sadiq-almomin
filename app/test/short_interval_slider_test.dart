import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/settings_screen.dart';
import 'package:almomin/features/settings/widgets/short_reminder_interval_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = <int, Map>{};
  var fail = false;
  setUp(() async {
    pending.clear();
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (call.method == 'periodicallyShowWithDuration') {
        if (fail) throw PlatformException(code: 'schedule_failed');
        final args = Map.of(call.arguments as Map);
        pending[args['id'] as int] = args;
      }
      if (call.method == 'cancel')
        pending.remove((call.arguments as Map)['id']);
      if (call.method == 'getNotificationAppLaunchDetails')
        return {'notificationLaunchedApp': false};
      if (call.method == 'initialize' ||
          call.method == 'areNotificationsEnabled' ||
          call.method == 'canScheduleExactNotifications') return true;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'),
            (_) async => 'Africa/Cairo');
    SharedPreferences.setMockInitialValues({'notif_master_enabled': true});
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init(forceReload: true);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'active adhkar category exposes freely chosen minute sliders at $scale',
        (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const SettingsScreen()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('settings_category_3')));
      await t.pumpAndSettle();
      for (final key in ['salawat', 'istighfar']) {
        final slider = find.byKey(ValueKey('short_interval_slider_$key'));
        await t.scrollUntilVisible(slider, 200,
            scrollable: find.byType(Scrollable).first);
        expect(slider, findsOneWidget);
        final widget = t.widget<Slider>(slider);
        expect(widget.min, 1);
        expect(widget.max, 1440);
        expect(widget.divisions, 1439);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'one minute semantic slider precise entry Apply retry and Discard at $scale',
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
      t.view.physicalSize = Size(scale == 2 ? 320 : 360, 915);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        final dir = Platform.environment['SHORT_INTERVAL_PIXELS'];
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
        final enabled =
            find.byKey(const ValueKey('short_interval_enabled_salawat'));
        await t.scrollUntilVisible(enabled, 180,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        t.binding.performSemanticsAction(ui.SemanticsActionEvent(
            type: ui.SemanticsAction.tap,
            nodeId: t.getSemantics(enabled).id,
            viewId: t.view.viewId));
        await t.pumpAndSettle();
        final edit = find.byKey(const ValueKey('short_interval_edit_salawat'));
        await t.ensureVisible(edit);
        await t.pumpAndSettle();
        await t.tap(edit);
        await t.pumpAndSettle();
        final input =
            find.byKey(const ValueKey('short_interval_minutes_input'));
        await t.enterText(input, '0');
        await t.tap(find.byKey(const ValueKey('short_interval_confirm')));
        await t.pumpAndSettle();
        expect(find.textContaining('أدخل عدداً صحيحاً'), findsOneWidget);
        expect(pending[805], isNull);
        await capture('invalid');
        await t.enterText(input, '١');
        await t.tap(find.byKey(const ValueKey('short_interval_confirm')));
        await t.pumpAndSettle();
        final slider =
            find.byKey(const ValueKey('short_interval_slider_salawat'));
        await t.ensureVisible(slider);
        await t.pumpAndSettle();
        expect(t.widget<Slider>(slider).value, 1);
        final node = t.getSemantics(slider);
        expect(node.getSemanticsData().label, contains('الصلاة على النبي'));
        t.binding.performSemanticsAction(ui.SemanticsActionEvent(
            type: ui.SemanticsAction.increase,
            nodeId: node.id,
            viewId: t.view.viewId));
        await t.pumpAndSettle();
        expect(t.widget<Slider>(slider).value, 2);
        t.binding.performSemanticsAction(ui.SemanticsActionEvent(
            type: ui.SemanticsAction.decrease,
            nodeId: t.getSemantics(slider).id,
            viewId: t.view.viewId));
        await t.pumpAndSettle();
        expect(t.widget<Slider>(slider).value, 1);
        expect(pending[805], isNull);
        expect(
            PrayerNotificationService.instance.shortInterval('salawat').enabled,
            isFalse);
        await t.ensureVisible(enabled);
        await t.pumpAndSettle();
        await capture('staged');
        fail = true;
        await t.tap(find.byKey(const ValueKey('settings_apply')));
        await t.pumpAndSettle();
        expect(find.text('تم حفظ التغييرات'), findsNothing);
        expect(find.textContaining('لم تكتمل كل التغييرات'), findsOneWidget);
        await capture('failed');
        fail = false;
        await t.tap(find.byKey(const ValueKey('settings_apply')));
        await t.pumpAndSettle();
        expect(pending[805]?['repeatIntervalMilliseconds'], 60000);
        expect(find.text('تم حفظ التغييرات'), findsOneWidget);
        await t.ensureVisible(enabled);
        await t.pumpAndSettle();
        await capture('saved');
        await t.ensureVisible(edit);
        await t.pumpAndSettle();
        await t.tap(edit);
        await t.pumpAndSettle();
        await t.enterText(input, '7');
        await t.tap(find.byKey(const ValueKey('short_interval_confirm')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('settings_discard')));
        await t.pumpAndSettle();
        expect(t.widget<Slider>(slider).value, 1);
        expect(pending[805]?['repeatIntervalMilliseconds'], 60000);
        await t.ensureVisible(enabled);
        await t.pumpAndSettle();
        await t.tap(enabled);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('settings_apply')));
        await t.pumpAndSettle();
        expect(pending[805], isNull);
        expect(
            (await SharedPreferences.getInstance())
                .getString('notif_short_salawat_frequency'),
            'off:1');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
      'slider bounds and busy state expose only supported semantic actions',
      (t) async {
    final semantics = t.ensureSemantics();
    try {
      for (final state in [
        (minutes: 1, busy: false),
        (minutes: 1440, busy: false),
        (minutes: 7, busy: true)
      ]) {
        await t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ShortReminderIntervalControl(
                    reminderKey: 'salawat',
                    label: 'الصلاة على النبي',
                    value: (enabled: true, minutes: state.minutes),
                    busy: state.busy,
                    onChanged: (_) {},
                    translate: (ar, en) => ar))));
        await t.pumpAndSettle();
        final slider =
            find.byKey(const ValueKey('short_interval_slider_salawat'));
        final data = t.getSemantics(slider).getSemanticsData();
        expect(data.hasAction(ui.SemanticsAction.increase),
            !state.busy && state.minutes < 1440);
        expect(data.hasAction(ui.SemanticsAction.decrease),
            !state.busy && state.minutes > 1);
        expect(t.widget<Slider>(slider).onChanged == null, state.busy);
      }
    } finally {
      semantics.dispose();
    }
  });
}
