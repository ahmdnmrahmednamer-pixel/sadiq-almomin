import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/notifications/prayer_notification_service.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_master_enabled': false,
      'notif_prayer_الفجر': false,
      'notif_pre_reminder_prayer_الفجر': false
    });
    await SettingsService.instance.init(forceReload: true);
    await PrayerNotificationService.instance.init(forceReload: true);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('five prayer choices remain staged and readable at $scale',
        (t) async {
      await t.runAsync(() async {
        for (final pair in [
          ['Cairo', 'assets/fonts/Cairo-Regular.ttf'],
          ['Amiri', 'assets/fonts/Amiri-Regular.ttf'],
          if (Platform.environment['FLUTTER_ROOT'] != null)
            [
              'MaterialIcons',
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
            ],
        ]) {
          await (FontLoader(pair[0])
                ..addFont(Future.value(
                    ByteData.sublistView(File(pair[1]).readAsBytesSync()))))
              .load();
        }
      });
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      try {
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const SettingsScreen())));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('settings_category_4')));
        await t.pumpAndSettle();
        final group = find.byKey(const ValueKey('prayer_settings_الفجر'));
        await t.scrollUntilVisible(group, 180,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        final groupLabel = find.text('إعدادات صلاة الفجر');
        t.binding.performSemanticsAction(ui.SemanticsActionEvent(
            type: ui.SemanticsAction.tap,
            nodeId: t.getSemantics(groupLabel).id,
            viewId: t.view.viewId));
        await t.pumpAndSettle();
        final flag = find.byKey(const ValueKey('setting_أذان صلاة الفجر'));
        await t.ensureVisible(flag);
        await t.pumpAndSettle();
        expect(t.getSemantics(flag).getSemanticsData().label,
            contains('أذان صلاة الفجر'));
        expect(t.widget<SwitchListTile>(flag).value, isFalse);
        t.binding.performSemanticsAction(ui.SemanticsActionEvent(
            type: ui.SemanticsAction.tap,
            nodeId: t.getSemantics(flag).id,
            viewId: t.view.viewId));
        await t.pumpAndSettle();
        expect(t.widget<SwitchListTile>(flag).value, isTrue,
            reason: 'Semantic action must actually stage the change');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('notif_prayer_الفجر'), isFalse);
        expect(PrayerNotificationService.instance.isPrayerEnabled('الفجر'),
            isFalse);
        final voice = find.byKey(const ValueKey('prayer_voice_الفجر'));
        await t.ensureVisible(voice);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final dir = Platform.environment['PRAYER_SETTINGS_SCREENSHOT_DIR'];
        if (dir != null)
          await t.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$dir/per-prayer-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        await t.tap(find.byKey(const ValueKey('settings_discard')));
        await t.pumpAndSettle();
        expect(prefs.getBool('notif_prayer_الفجر'), isFalse);
        for (final prayer in ['الظهر', 'العصر', 'المغرب', 'العشاء']) {
          await t
              .ensureVisible(find.byKey(ValueKey('prayer_settings_$prayer')));
          await t.pumpAndSettle();
          expect(find.text('إعدادات صلاة $prayer'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  }
}
