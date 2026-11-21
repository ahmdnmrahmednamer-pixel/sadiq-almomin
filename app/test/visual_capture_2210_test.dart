import 'dart:async';
import 'package:almomin/core/services/quran_english_source.dart';
import 'package:almomin/features/mushaf/screens/quran_english_screen.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/services/lubab_source.dart';
import 'package:almomin/core/services/quran_linguistics_service.dart';
import 'package:almomin/features/mushaf/widgets/ayah_action_sheet.dart';
import 'package:almomin/features/mushaf/widgets/ayah_interaction.dart';
import 'package:almomin/features/mushaf/widgets/ayah_linguistics_sheet.dart';
import 'package:almomin/core/services/jadwal_source.dart';
import 'package:almomin/features/mushaf/screens/quran_irab_screen.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Empty extends LubabSource {
  @override
  Future<List<LubabEntry>> fetch(int surah, int ayah) async => [];
}

class _FakeEn extends QuranEnglishSource {
  _FakeEn(this.c);
  final Completer<QuranEnglishVerse?> c;
  @override
  Future<QuranEnglishVerse?> fetch(int surah, int ayah) => c.future;
}

class _NoIrab extends JadwalSource {
  _NoIrab() : super(useBundled: false);
  @override
  Future<JadwalEntry?> fetch(int surah, int ayah) async => null;
  @override
  Future<DateTime?> offlineSavedAt() async => null;
}

class _P implements CuratedRadioPlayer {
  @override
  Future<void> play(String url) async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<Object> get errors => const Stream<Object>.empty();
  @override
  void dispose() {}
}

Future<void> _shot(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/downloads/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> fonts(WidgetTester t) async {
    await t.runAsync(() async {
      await (FontLoader('Amiri')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync())))).load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(File('/home/sandbox/flutter-product/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync()))))
          .load();
    });
  }

  const surah = Surah(id: 112, nameAr: 'الإخلاص', nameSimple: 'Al-Ikhlas', revelationPlace: 'makkah', revelationOrder: 22, ayahCount: 4, hasBasmala: true, pageStart: 604, pageEnd: 604);
  const ayah = Ayah(id: 6222, surahId: 112, ayahNumber: 1, juz: 30, hizb: 60, rub: 240, page: 604, sajdah: 0, textUthmani: 'قُلْ هُوَ اللَّهُ أَحَدٌ', textImlaei: 'قل هو الله أحد', textSearch: 'قل هو الله احد');

  Future<void> shoot(WidgetTester t, Widget w, String name, {Size size = const Size(420, 900)}) async {
    await fonts(t);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'Amiri'), home: w)));
    await t.pumpAndSettle();
    await _shot(t, key, name);
  }

  testWidgets('capture: ayah options sheet', (t) async {
    final h = t.ensureSemantics();
    await shoot(t, const Scaffold(body: AyahActionSheet(surah: surah, ayah: ayah)), 'v2210-ayah-options');
    final labels = <String>[];
    void walk(SemanticsNode n) {
      if (n.label.isNotEmpty) labels.add('${n.label}${n.hint.isNotEmpty ? ' [HINT:${n.hint}]' : ''}');
      n.visitChildren((c) { walk(c); return true; });
    }
    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    File('/downloads/v2210-ayah-options-semantics.txt').writeAsStringSync(labels.join('\n'));
    expect(labels.where((l) => l.contains('HINT:')), isEmpty);
    h.dispose();
  });

  testWidgets('capture: asbab single section, no tabs', (t) async {
    QuranLinguisticsService.setSourceForTesting(_Empty());
    addTearDown(() => QuranLinguisticsService.setSourceForTesting(null));
    await shoot(t, const Scaffold(body: AyahLinguisticsSheet(surah: surah, ayah: ayah, initialTabIndex: 1, focusedSection: true)), 'v2210-asbab-single');
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('capture: ayah with no spoken hint', (t) async {
    await shoot(t, Scaffold(body: Center(child: AyahInteraction(label: 'آية ١', onTap: () {}, onLongPress: () {}, child: const Text('قُلْ هُوَ اللَّهُ أَحَدٌ')))), 'v2210-ayah-focus', size: const Size(420, 300));
  });

  testWidgets('capture: curated radio screen', (t) async {
    await fonts(t);
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'Amiri'), home: CuratedRadioScreen(playerFactory: () => _P()))));
    for (var i = 0; i < 100 && find.text('القراءات العشر').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('القراءات العشر'), findsOneWidget);
    await _shot(t, key, 'v2344-radio-categories');
    await t.tap(find.text('القراءات العشر'));
    await t.pumpAndSettle();
    await _shot(t, key, 'v2344-radio-stations');
  });

  testWidgets('reach: options sheet bottom actions at 360x640, text scale 2.0', (t) async {
    await fonts(t);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'Amiri'), builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: w!), home: const Scaffold(body: AyahActionSheet(surah: surah, ayah: ayah)))));
    await t.pumpAndSettle();
    final closeBottom = t.getRect(find.byTooltip('إغلاق')).bottom;
    expect(closeBottom < 640 * 0.2, isTrue, reason: 'pinned header must stay compact at 2x, bottom=$closeBottom');
    expect(find.text('سورة الإخلاص — آية 1'), findsOneWidget);
    await _shot(t, key, 'v2210-options-top-360x640-2x');
    final before = find.text('مشاركة');
    await t.scrollUntilVisible(before, 300, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(before, findsOneWidget);
    final r = t.getRect(before);
    expect(r.bottom <= 640 && r.top >= 0, isTrue, reason: 'last action visible after scroll: $r');
    await _shot(t, key, 'v2210-options-scrolled-360x640-2x');
  });

  testWidgets('capture: irab empty state', (t) async {
    final h = t.ensureSemantics();
    await shoot(t, QuranIrabScreen(initialSurahId: 1, initialAyah: 1, source: _NoIrab()), 'v2210-irab-empty', size: const Size(420, 700));
    expect(find.text('لا يوجد حاليا نص إعراب مرتبط بهذه الآية.'), findsOneWidget);
    h.dispose();
  });


  testWidgets('translation: loading is deterministic, then fixture verse, semantics and nav', (t) async {
    final h = t.ensureSemantics();
    final c = Completer<QuranEnglishVerse?>();
    final w = QuranEnglishScreen(surah: 1, ayah: 1, ayahCount: 7, source: _FakeEn(c));
    await fonts(t);
    t.view.physicalSize = const Size(420, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'Amiri'), home: w)));
    await t.pump(const Duration(milliseconds: 100));
    // loading state: spinner present with its label; pumpAndSettle would never settle here by design
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('قراءة الترجمة'), findsOneWidget);
    c.complete(const QuranEnglishVerse('In the name of Allah.', 'Fixture footnote.'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('In the name of Allah.'), findsOneWidget);
    expect(find.byTooltip('الآية السابقة'), findsOneWidget);
    expect(find.byTooltip('الآية التالية'), findsOneWidget);
    final prev = t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_back));
    expect(prev.onPressed, isNull);
    expect(t.getSemantics(find.text('Translation 1:1')).flagsCollection.isHeader, isTrue);
    await _shot(t, key, 'v2210-translation');
    h.dispose();
  });

  testWidgets('translation: real bundled source loads (real async, bounded pumps)', (t) async {
    final h = t.ensureSemantics();
    await fonts(t);
    t.view.physicalSize = const Size(420, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: QuranEnglishScreen(surah: 1, ayah: 1, ayahCount: 7)));
    var loaded = false;
    for (var i = 0; i < 60 && !loaded; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 50));
      loaded = find.byType(CircularProgressIndicator).evaluate().isEmpty;
    }
    expect(loaded, isTrue, reason: 'bundled translation did not finish loading in 15s');
    expect(find.textContaining('Translation 1:1'), findsOneWidget);
    expect(find.text('تعذر قراءة حزمة الترجمة المضمّنة. لا تُعرض ترجمة بديلة.'), findsNothing);
    h.dispose();
  });

  testWidgets('keyboard: Tab traversal reaches the lower share action and scrolls it into view (360x640, 2x)', (t) async {
    await fonts(t);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: w!), home: const Scaffold(body: AyahActionSheet(surah: surah, ayah: ayah))));
    await t.pumpAndSettle();
    var reached = false;
    var steps = 0;
    for (; steps < 80 && !reached; steps++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(const Duration(milliseconds: 400));
      final f = FocusManager.instance.primaryFocus;
      final ctx = f?.context;
      if (ctx != null && find.descendant(of: find.byWidget(ctx.widget), matching: find.text('مشاركة')).evaluate().isNotEmpty) reached = true;
    }
    expect(reached, isTrue, reason: 'Tab never focused the share action in $steps steps');
    final r = t.getRect(find.text('مشاركة'));
    expect(r.top >= 0 && r.bottom <= 640, isTrue, reason: 'focused share action in view: $r');
  });
}
