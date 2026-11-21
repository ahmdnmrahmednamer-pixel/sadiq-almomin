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
import '../lib/features/mushaf/surah_reader_screen.dart';
import '../lib/features/mushaf/page_mode_mushaf_screen.dart';
import '../lib/features/mushaf/widgets/ayah_interaction.dart';

// Synthetic UI fixtures, not Quran content and never shipped in app assets.
const surah = Surah(id: 1, nameAr: 'سورة اختبارية', nameSimple: 'اختبار', revelationPlace: 'makkah', revelationOrder: 1, ayahCount: 3, hasBasmala: false, pageStart: 1, pageEnd: 1);
final rows = [for (var i = 1; i <= 3; i++) {
  'id': i, 'surah_id': 1, 'ayah_number': i, 'juz': 1, 'hizb': 1, 'rub': 1, 'page': 1,
  'text_uthmani': 'نص اختبار واجهة رقم $i', 'text_imlaei': 'نص اختبار واجهة رقم $i', 'text_search': 'اختبار',
}];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    rootBundle.clear(); // CachingAssetBundle keeps the first test's asset futures; clear so each test reads its own mock
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    QuranRepository.resetCachesForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List());
      Object? value;
      if (path == 'assets/data/quran_ayahs.json') value = {'1': rows};
      if (path == 'assets/data/surahs/1.json') value = rows;
      if (path == 'assets/data/surahs.json') value = [{'id':1,'name_ar':'سورة اختبارية','revelation_place':'makkah','revelation_order':1,'ayah_count':3,'has_basmala':0,'page_start':1,'page_end':1}];
      if (path == 'assets/data/juz.json') value = [];
      return value == null ? null : ByteData.sublistView(utf8.encode(jsonEncode(value)));
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    QuranRepository.resetCachesForTesting();
  });

  testWidgets('scoped playback bar render (synthetic fixture)', (t) async {
    t.view.physicalSize = const Size(412, 915); t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: ThemeData(fontFamily: 'Amiri'), home: const SurahReaderScreen(surah: surah))));
    await t.pumpAndSettle(const Duration(milliseconds: 200));
    await t.tap(find.byKey(const ValueKey('scoped-repeat')));
    await t.pump();
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final b = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('/downloads/v0125-scoped-playback-reader.png').writeAsBytes(b!.buffer.asUint8List());
    });
    final order = <String>[];
    final root = t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
    void walk(SemanticsNode n) { if (n.label.isNotEmpty || n.tooltip.isNotEmpty) order.add('${n.label}|${n.tooltip}'); n.visitChildren((c){walk(c);return true;}); }
    walk(root);
    File('/downloads/v0125-scoped-playback-semantics.txt').writeAsStringSync(order.join('\n'));
    expect(find.byKey(const ValueKey('scoped-play-pause')), findsOneWidget);
  });
}
