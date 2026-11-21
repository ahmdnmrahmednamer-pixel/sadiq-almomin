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
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/adhan_sensor_gesture_service.dart';
import 'package:almomin/features/prayer/adhan_control_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    SharedPreferences.setMockInitialValues({'app_language': 'ar'});
    await SettingsService.instance.init(forceReload: true);
    await AdhanSensorGestureService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    AdhanSensorGestureService.instance.accelerometerStreamOverride =
        const Stream<AccelerometerEvent>.empty();
    await IslamicAudioService.instance.stop();
  });
  tearDown(() async {
    await IslamicAudioService.instance.stop();
    IslamicAudioService.instance.disableNativePlayerForTesting = false;
    AdhanSensorGestureService.instance.accelerometerStreamOverride = null;
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('options headings wrap with complete labels at $scale text',
        (t) async {
      t.view.physicalSize = const Size(360, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      try {
        final boundary = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const AdhanControlScreen(
                    prayerName: 'العصر', autoPlay: false))));
        await t.pump(const Duration(milliseconds: 100));
        await t.scrollUntilVisible(find.text('خيارات الأذان'), 250,
            scrollable: find.byType(Scrollable).first);
        await t.tap(find.text('خيارات الأذان'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        const headings = [
          'نمط صوت تنبيه الأذان',
          'خيارات الاهتزاز ومستشعرات الحركة',
          'تفعيل / إيقاف كل صلاة على حدة'
        ];
        for (var i = 0; i < headings.length; i++) {
          final heading = find.text(headings[i]);
          await t.scrollUntilVisible(heading, 200,
              scrollable: find.byType(Scrollable).last);
          await t.pump(const Duration(milliseconds: 500));
          final directory = Platform.environment['ADHAN_OPTIONS_PIXELS'];
          if (directory != null)
            await t.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$directory/header-$i-$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          expect(t.takeException(), isNull);
          final rect = t.getRect(heading);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(t.getSemantics(heading).label, contains(headings[i]));
          expect(t.widget<Text>(heading).maxLines, isNull);
        }
        final toggle =
            find.widgetWithText(SwitchListTile, 'إيقاف الأذان عند هز الهاتف');
        await t.scrollUntilVisible(toggle, -200,
            scrollable: find.byType(Scrollable).last);
        await t.pump(const Duration(milliseconds: 500));
        expect(toggle.hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  }
}
