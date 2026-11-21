import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/features/prayer/fajr_qiyam_alarm_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'wake_pre_fajr_enabled': true,
      'wake_qiyam_enabled': true,
      'wake_qiyam_mode': 'before_fajr'
    });
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await SettingsService.instance.init(forceReload: true);
    await PrayerService.instance.init(forceReload: true);
    await FajrQiyamAlarmService.instance.init(forceReload: true);
  });
  testWidgets(
      'missing dates disclose unavailable schedule, not a GPS diagnosis',
      (t) async {
    await t.runAsync(() async {
      for (final pair in [
        ['ArabicTest', 'assets/fonts/Amiri-Regular.ttf'],
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
    t.view.physicalSize = const Size(480, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'ArabicTest'),
            home: const FajrQiyamAlarmScreen())));
    await t.pumpAndSettle();
    expect(find.textContaining('لن يُجدول هذا المنبّه'), findsOneWidget);
    expect(find.text('يتطلب GPS'), findsNothing);
    expect(t.takeException(), isNull);
    if (Platform.environment['FAJR_SCREENSHOT'] != null) {
      await t.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(Platform.environment['FAJR_SCREENSHOT']!)
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await t.pumpWidget(const SizedBox());
  });
}
