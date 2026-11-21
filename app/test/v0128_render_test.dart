import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../lib/features/mushaf/widgets/ayah_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/features/mushaf/page_mode_mushaf_screen.dart';
import '../lib/features/mushaf/widgets/ayah_interaction.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    QuranRepository.resetCachesForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List());
      final f = File(path);
      return f.existsSync() ? ByteData.sublistView(f.readAsBytesSync()) : null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    QuranRepository.resetCachesForTesting();
  });
  for (final cfg in const [(360.0, 560.0, 1.0), (360.0, 560.0, 2.0)]) {
    for (final menu in [false, true]) {
    testWidgets('page 2 bookmark ${cfg.$3}x menu=$menu', (t) async {
      t.view.physicalSize = Size(cfg.$1, cfg.$2); t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        await (FontLoader('Amiri')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync())))..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Bold.ttf').readAsBytesSync())))).load();
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
        await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync())))).load();
        await (FontLoader('KFGQPCHafs')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/KFGQPCHafs.otf').readAsBytesSync())))).load();
      });
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
        theme: ThemeData(fontFamily: 'Amiri'),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(cfg.$3)), child: w!),
        home: const PageModeMushafScreen(initialPage: 2, highlightSurah: 2, highlightAyah: 5))));
      for (var i = 0; i < 40; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); await t.pump(const Duration(milliseconds: 50)); }
      if (menu) {
        final m = find.byType(PopupMenuButton<int>);
        if (m.evaluate().isNotEmpty) { await t.tap(m.first); await t.pumpAndSettle(); }
      }
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final b = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('/downloads/v0128-page2-bookmark-${cfg.$1.toInt()}x${cfg.$2.toInt()}-${cfg.$3.toInt()}x${menu ? '-menu' : ''}.png').writeAsBytes(b!.buffer.asUint8List());
      });
      expect(t.takeException(), isNull);
    });
    }
  }
}
