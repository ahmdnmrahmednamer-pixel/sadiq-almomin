import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    QuranRepository.resetCachesForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (m) async {
      final f = File(utf8.decode(m!.buffer.asUint8List()));
      return f.existsSync() ? ByteData.sublistView(f.readAsBytesSync()) : null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    QuranRepository.resetCachesForTesting();
  });

  testWidgets('save from ayah options, open it from the hub bookmarks tab, land on the same ayah', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final announcements = <String>[];
    t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      if (m is Map && m['type'] == 'announce') announcements.add((m['data'] as Map)['message'] as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
    final sem = t.ensureSemantics();
    // 1. Page of Surah 112 in page mode; long-press ayah 2 to open its options.
    final ayahs112 = await t.runAsync(() => QuranRepository.getAyahsForPage(604));
    expect(ayahs112!.any((a) => a.surahId == 112 && a.ayahNumber == 2), isTrue);
    await t.pumpWidget(const MaterialApp(home: PageModeMushafScreen(initialPage: 604)));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    // Ayah 2 of Surah 112 is the semantics node ending in its number and starting with its first word.
    SemanticsNode? ayah2;
    void walk(SemanticsNode n) {
      if (ayah2 == null && n.label.length > 6 && n.label.endsWith(' 2') && !n.label.contains('﴿')) ayah2 = n;
      n.visitChildren((c) { walk(c); return true; });
    }
    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(ayah2, isNotNull);
    // Semantics long-press on the ayah node opens the ayah options sheet.
    var rect = ayah2!.rect;
    for (SemanticsNode? n = ayah2; n != null; n = n.parent) {
      if (n.transform != null) rect = MatrixUtils.transformRect(n.transform!, rect);
    }
    final center = rect.center;
    final g = await t.startGesture(center);
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.up();
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    // 2. Save the bookmark from the options sheet.
    final save = find.byTooltip('حفظ في المفضلة');
    expect(save, findsOneWidget);
    await t.tap(save);
    await t.pump(const Duration(milliseconds: 200));
    expect(SettingsService.instance.bookmarks, ['112:2']);
    // The user dismisses the options sheet by tapping outside it (no app reset).
    await t.tapAt(const Offset(10, 10));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byTooltip('إزالة من المفضلة'), findsNothing);
    expect(find.byType(PageModeMushafScreen), findsOneWidget);
    // 3. Same app: open the hub bookmarks tab on top of the reader.
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const MushafScreen(initialTab: 3)));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    final tile = find.textContaining('الآية ٢');
    expect(tile, findsOneWidget);
    await t.tap(find.ancestor(of: tile, matching: find.byType(ListTile)), warnIfMissed: false);
    await t.pump();
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    // 4. Same page, with exactly that ayah marked.
    final screen = t.widget<PageModeMushafScreen>(find.byType(PageModeMushafScreen).last);
    expect((screen.initialPage, screen.highlightSurah, screen.highlightAyah), (604, 112, 2));
    final marked = <String>[];
    void scan(SemanticsNode n) {
      if (n.label.contains('العلامة المرجعية')) marked.add(n.label);
      n.visitChildren((c) { scan(c); return true; });
    }
    scan(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(announcements, contains('العلامة المرجعية: الآية 2'));
    expect(marked.length, 1);
    expect(marked.single.endsWith(' 2'), isTrue);
    sem.dispose();
  });

  testWidgets('long page: a bookmarked verse near the page bottom is revealed and holds focus', (t) async {
    t.view.physicalSize = const Size(360, 560);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final sem = t.ensureSemantics();
    final page = (await t.runAsync(() => QuranRepository.getAyahsForPage(2)))!;
    final last = page.last;
    await t.pumpWidget(MaterialApp(
        home: PageModeMushafScreen(initialPage: 2, highlightSurah: last.surahId, highlightAyah: last.ayahNumber)));
    for (var i = 0; i < 30; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 100));
    }
    SemanticsNode? target;
    void walk(SemanticsNode n) {
      if (n.label.startsWith('العلامة المرجعية.')) target = n;
      n.visitChildren((c) { walk(c); return true; });
    }
    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(target, isNotNull);
    expect(target!.label.endsWith(' ${last.ayahNumber}'), isTrue);
    var rect = target!.rect;
    for (SemanticsNode? n = target; n != null; n = n.parent) {
      if (n.transform != null) rect = MatrixUtils.transformRect(n.transform!, rect);
    }
    // The bookmarked verse must lie inside the visible screen, not below the fold.
    final view = t.getRect(find.byType(SingleChildScrollView).first);
    expect(rect.top >= view.top - 1 && rect.bottom <= view.bottom + 1, isTrue,
        reason: 'verse $rect must be inside the scroll viewport $view');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'reader-verses');
    sem.dispose();
  });
}
