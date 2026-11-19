import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/features/mushaf/screens/qiraat_mushaf_screen.dart';

class RealLocalSource extends BudurSource {
  @override
  Future<String> load() async =>
      File(Platform.environment['BUDUR_REFERENCE_SOURCE']!).readAsStringSync();
}

void main() {
  testWidgets(
      'actual author reference opens original target with page and closes',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    QuranRepository.resetCachesForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (m) async {
      final path = utf8.decode(m!.buffer.asUint8List());
      final f = File(path);
      return f.existsSync() ? ByteData.sublistView(f.readAsBytesSync()) : null;
    });
    await t.runAsync(() async {
      for (final pair in [
        ['ArabicTest', 'assets/fonts/Amiri-Regular.ttf'],
        if (Platform.environment['READING_TEST_ICON_FONT'] != null)
          ['MaterialIcons', Platform.environment['READING_TEST_ICON_FONT']!]
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
    addTearDown(() {
      QuranRepository.resetCachesForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'ArabicTest'),
            home: QiraatMushafScreen(
                source: RealLocalSource(),
                initialSurah: 23,
                initialAyah: 21))));
    await t.runAsync(() async {
      for (var i = 0; i < 150; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
        if (find.text('فتح موضع إحالة المؤلف').evaluate().isNotEmpty) break;
      }
    });
    await t.pumpAndSettle();
    expect(find.text('فتح موضع إحالة المؤلف'), findsOneWidget);
    await t.tap(find.text('فتح موضع إحالة المؤلف'));
    await t.pump();
    await t.runAsync(() async {
      for (var i = 0; i < 300; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
        if (find.text('موضع الإحالة · النحل').evaluate().isNotEmpty) break;
      }
    });
    await t.pumpAndSettle();
    expect(find.text('موضع الإحالة · النحل'), findsOneWidget);
    expect(find.text('ص 180'), findsOneWidget);
    expect(
        find.textContaining('قرأ نافع والشامي وشعبة ويعقوب'), findsOneWidget);
    expect(t.takeException(), isNull);
    if (Platform.environment['BUDUR_REFERENCE_SCREENSHOT'] != null)
      await t.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(Platform.environment['BUDUR_REFERENCE_SCREENSHOT']!)
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    await t.tap(find.byTooltip('إغلاق'));
    await t.pumpAndSettle();
    expect(find.text('موضع الإحالة · النحل'), findsNothing);
    expect(find.text('فتح موضع إحالة المؤلف'), findsOneWidget);
  }, skip: Platform.environment['BUDUR_REFERENCE_SOURCE'] == null);
}
