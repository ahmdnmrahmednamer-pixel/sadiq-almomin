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
  Future<void> shot(WidgetTester t, GlobalKey k, String n) async {
    await t.runAsync(() async {
      final img = await (k.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final b = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('/downloads/$n.png').writeAsBytes(b!.buffer.asUint8List());
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('reader evidence 360x640 scale $scale: semantics, no gesture prose, tap opens options', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        await (FontLoader('Amiri')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync())))..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Bold.ttf').readAsBytesSync())))).load();
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
      });
      await t.runAsync(() async {
        // flutter_test resolves the default Material family (Roboto) to the square-glyph Ahem font; load a real face under that name so digits render.
        await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync())))).load();
      });
      await t.runAsync(() async {
        await (FontLoader('KFGQPCHafs')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/KFGQPCHafs.otf').readAsBytesSync())))).load();
      });
      final h = t.ensureSemantics();
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
        theme: ThemeData(fontFamily: 'Amiri'),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(accessibleNavigation: true, textScaler: TextScaler.linear(scale)), child: w!),
        home: const SurahReaderScreen(surah: surah))));
      for (var i = 0; i < 150 && find.byType(AyahInteraction).evaluate().isEmpty; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); await t.pump(const Duration(milliseconds: 50)); }
      expect(find.byType(AyahInteraction), findsAtLeastNWidgets(1));
      await shot(t, key, 'v2215-reader-360x640-${scale.toInt()}x');
      final dump = StringBuffer();
      for (final e in find.byType(AyahInteraction).evaluate()) {
        final n = t.getSemantics(find.byWidget(e.widget));
        expect(n.hint, isEmpty);
        dump.writeln('label=${n.label} | hint="${n.hint}" | button=${n.hasFlag(SemanticsFlag.isButton)} tap=${n.getSemanticsData().hasAction(SemanticsAction.tap)} longPress=${n.getSemanticsData().hasAction(SemanticsAction.longPress)}');
      }
      File('/downloads/v2215-reader-semantics-${scale.toInt()}x.txt').writeAsStringSync(dump.toString());
      expect(find.textContaining('اضغط'), findsNothing);
      expect(find.textContaining('اضغط مطولا'), findsNothing);
      await t.longPress(find.byType(AyahInteraction).first);
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
      expect(find.byType(AyahActionSheet), findsOneWidget);
      expect(find.byTooltip('إغلاق'), findsOneWidget);
      await shot(t, key, 'v2215-reader-options-360x640-${scale.toInt()}x');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      h.dispose();
    });
  }

  Future<void> fontsFor(WidgetTester t) async {
    await t.runAsync(() async {
      await (FontLoader('Amiri')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync())))).load();
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
    });
  }

  testWidgets('page-mode reader 360x640 scale 2.0: renders, verse node has empty hint and actions', (t) async {
    await fontsFor(t);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final h = t.ensureSemantics();
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
      theme: ThemeData(fontFamily: 'Amiri'),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(accessibleNavigation: true, textScaler: const TextScaler.linear(2.0)), child: w!),
      home: const PageModeMushafScreen())));
    for (var i = 0; i < 150 && find.byType(AyahInteraction).evaluate().isEmpty; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); await t.pump(const Duration(milliseconds: 50)); }
    expect(find.byType(AyahInteraction), findsAtLeastNWidgets(1));
    await shot(t, key, 'v2215-pagemode-360x640-2x');
    final n = t.getSemantics(find.byType(AyahInteraction).first);
    expect(n.hint, isEmpty);
    expect(n.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(n.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    expect(t.takeException(), isNull);
    h.dispose();
  });

  testWidgets('reader keyboard: Tab reaches the verses, ArrowDown moves the active verse, Enter opens its options', (t) async {
    await fontsFor(t);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(theme: ThemeData(fontFamily: 'Amiri'), home: const SurahReaderScreen(surah: surah))));
    for (var i = 0; i < 150 && find.textContaining('نص اختبار واجهة').evaluate().isEmpty; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); await t.pump(const Duration(milliseconds: 50)); }
    final order = <String>[];
    var reached = false;
    for (var i = 0; i < 12 && !reached; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(const Duration(milliseconds: 100));
      final label = FocusManager.instance.primaryFocus?.debugLabel ?? 'unlabelled';
      order.add(label);
      reached = label == 'reader-verses';
    }
    File('/downloads/v2215-reader-tab-order.txt').writeAsStringSync(order.join('\n'));
    expect(reached, isTrue, reason: 'Tab order: $order');
    await shot(t, key, 'v2215-reader-kb-verse1');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(const Duration(milliseconds: 300));
    await shot(t, key, 'v2215-reader-kb-verse2');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'reader-verses');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    expect(find.byType(AyahActionSheet), findsOneWidget);
    final sheet = t.widget<AyahActionSheet>(find.byType(AyahActionSheet));
    expect(sheet.ayah.ayahNumber, 2, reason: 'Enter opens options for the verse moved to with ArrowDown');
    expect(t.takeException(), isNull);
  });

  testWidgets('page-mode reader keyboard: Tab reaches verses, ArrowDown moves, Enter opens options', (t) async {
    await fontsFor(t);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Amiri'), home: const PageModeMushafScreen()));
    for (var i = 0; i < 150 && find.byType(RichText).evaluate().length < 3; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); await t.pump(const Duration(milliseconds: 50)); }
    var reached = false;
    final order = <String>[];
    for (var i = 0; i < 14 && !reached; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(const Duration(milliseconds: 100));
      order.add(FocusManager.instance.primaryFocus?.debugLabel ?? 'unlabelled');
      reached = order.last == 'reader-verses';
    }
    expect(reached, isTrue, reason: 'page mode Tab order: $order');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(const Duration(milliseconds: 200));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 20 && find.byType(AyahActionSheet).evaluate().isEmpty; i++) { await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); await t.pump(const Duration(milliseconds: 100)); }
    expect(find.byType(AyahActionSheet), findsOneWidget);
    expect(t.widget<AyahActionSheet>(find.byType(AyahActionSheet)).ayah.ayahNumber, 2);
    expect(t.takeException(), isNull);
  });
}
