import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'package:almomin/core/text/arabic_normalizer.dart';
import 'package:almomin/core/theme/app_theme.dart' as core_theme;
import 'package:almomin/features/mushaf/page_mode_mushaf_screen.dart';
import 'package:almomin/features/mushaf/surah_reader_screen.dart';
import 'package:almomin/features/mushaf/widgets/tafsir_viewer_sheet.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

const bool _kCapturePixels = bool.fromEnvironment(
  'CAPTURE_REPAIR14_PIXELS',
  defaultValue: false,
);
const String _kCaptureOutDir = String.fromEnvironment(
  'CAPTURE_REPAIR14_OUT_DIR',
  defaultValue: '',
);
const String _kMaterialIconsFontPath = String.fromEnvironment(
  'MATERIAL_ICONS_FONT',
  defaultValue: '',
);

final GlobalKey _kBoundaryKey = GlobalKey();

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Future<void> _loadRealFonts() async {
  final cairo = File('assets/fonts/Cairo-Regular.ttf');
  if (cairo.existsSync()) {
    final bytes = cairo.readAsBytesSync();
    for (final family in ['Cairo', 'Roboto']) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  final amiri = FontLoader('Amiri');
  for (final path in ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']) {
    final f = File(path);
    if (f.existsSync()) {
      amiri.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  await amiri.load();
  final iconCandidates = <String>[
    if (_kMaterialIconsFontPath.isNotEmpty) _kMaterialIconsFontPath,
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final path in iconCandidates) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await loader.load();
      break;
    }
  }
}

Future<void> _capturePng(WidgetTester tester, String fileName) async {
  if (!_kCapturePixels || _kCaptureOutDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        _kBoundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_kCaptureOutDir).createSync(recursive: true);
    File('$_kCaptureOutDir/$fileName').writeAsBytesSync(
      byteData!.buffer.asUint8List(),
    );
  });
}

Future<void> _settleSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  for (int i = 0; i < 25; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty && i >= 1) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 100));
}

Widget _buildHost({
  double textScale = 1.0,
  double keyboardBottom = 0,
  String? initialQuery,
}) {
  return RepaintBoundary(
    key: _kBoundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardBottom),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        );
      },
      home: QuranSearchScreen(initialQuery: initialQuery),
    ),
  );
}

SemanticsNode _findTappableNode(WidgetTester tester, String target) {
  final matches = <SemanticsNode>[];
  for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
    final data = node.getSemanticsData();
    if ((data.label == target ||
            data.tooltip == target ||
            data.label.contains(target)) &&
        data.hasAction(SemanticsAction.tap)) {
      matches.add(node);
    }
  }
  expect(matches, isNotEmpty, reason: 'Expected tappable semantic node "$target"');
  return matches.first;
}

typedef _ExpectedUnresolvedDestinationOverflow = ({
  String sourceLocation,
  String direction,
  int roundedPixels,
});

/// Strictly verifies that destination errors match the EXACT expected multiset of
/// unresolved out-of-scope RenderFlex overflows for this destination/matrix cell:
/// - Must be a RenderFlex overflow (`A RenderFlex overflowed by <N> pixels on the <dir>.`)
/// - Must NOT mention search files (`quran_search_screen.dart` / `quran_voice_search_sheet.dart`)
/// - Exact owning `file.dart:line:col` location, direction, rounded pixel count, and total count
/// Fails immediately on ANY unexpected exception, extra error, missing error, or changed count/location.
/// Documented as unresolved out-of-scope findings (NOT resolved or assumed preexisting).
void _assertOnlyKnownOutOfScopeDestinationOverflows(
  List<FlutterErrorDetails> destErrors, {
  required String destinationName,
  required List<_ExpectedUnresolvedDestinationOverflow> expectedMultiset,
}) {
  final overflowPattern = RegExp(
    r'A RenderFlex overflowed by ([0-9]+(?:\.[0-9]+)?) pixels on the (right|left|top|bottom)\.',
  );
  final locationPattern = RegExp(r'([a-zA-Z0-9_]+\.dart:\d+:\d+)');

  final actualSignatures = <String>[];
  for (final err in destErrors) {
    final full = err.toString();
    final msg = err.exceptionAsString();
    final mentionsSearchFiles =
        full.contains('quran_search_screen.dart') ||
        full.contains('quran_voice_search_sheet.dart');
    if (mentionsSearchFiles) {
      fail('Search-owned FlutterError in destination [$destinationName]: $msg\n$full');
    }
    final ov = overflowPattern.firstMatch(msg);
    final loc = locationPattern.firstMatch(full);
    if (ov == null || loc == null) {
      fail(
        'Unexpected non-RenderFlex or unlocated FlutterError in destination [$destinationName]: $msg\n$full',
      );
    }
    final roundedPx = double.parse(ov.group(1)!).round();
    final dir = ov.group(2)!;
    final srcLoc = loc.group(1)!;
    actualSignatures.add('RenderFlex|$dir|$roundedPx|$srcLoc');
    debugPrint(
      'UNRESOLVED_OUT_OF_SCOPE_DEST_OVERFLOW[$destinationName]: $msg | LOC=$srcLoc',
    );
  }

  final expectedSignatures = expectedMultiset
      .map((e) => 'RenderFlex|${e.direction}|${e.roundedPixels}|${e.sourceLocation}')
      .toList()
    ..sort();
  final sortedActual = List<String>.from(actualSignatures)..sort();

  expect(
    sortedActual,
    equals(expectedSignatures),
    reason:
        '[$destinationName] Destination error multiset mismatch. Expected exact unresolved out-of-scope multiset $expectedSignatures, got $sortedActual',
  );
}

void _expectFullyVisibleAboveKeyboard(
  WidgetTester tester,
  Finder target,
  Size viewportSize,
  double keyboardBottom,
  String label,
) {
  expect(target, findsOneWidget, reason: '[$label] target must exist');
  final rect = tester.getRect(target);
  final visibleBottom = viewportSize.height - keyboardBottom;
  expect(
    rect.left,
    greaterThanOrEqualTo(-0.5),
    reason: '[$label] left (${rect.left}) clipped',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(viewportSize.width + 0.5),
    reason: '[$label] right (${rect.right}) exceeded viewport (${viewportSize.width})',
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(-0.5),
    reason: '[$label] top (${rect.top}) scrolled off-screen above viewport',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(visibleBottom + 1.0),
    reason:
        '[$label] bottom (${rect.bottom}) must be fully visible above keyboard ($visibleBottom)',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await QuranSearchService.instance.clearHistory();
    VoiceSearchService.resetTestMode();
    VoiceSearchService.isTestMode = true;
  });

  tearDown(() {
    VoiceSearchService.resetTestMode();
  });

  group('Real Shipping Corpus Functional Search Regressions (Zero Corpus Mocks)', () {
    test('Dual-key search: all 31 everyday Imlaei queries, preserved legacy Uthmani-stripped queries, dedup/order/limits, all 10 app chips, filters, and unrelated negative controls', () async {
      final surahs = await QuranRepository.loadSurahs();
      final pages = await QuranRepository.loadAllPages();
      expect(surahs.length, 114);
      expect(pages.values.where((l) => l.isNotEmpty).length, 604);
      expect(pages.values.fold<int>(0, (s, l) => s + l.length), 6236);

      // Base ArabicNormalizer.normalize() golden behavior preserved untouched
      expect(ArabicNormalizer.normalize('الرَّحْمَٰنِ'), 'الرحمن');
      expect(ArabicNormalizer.normalize('مُوسَىٰ'), 'موسي');
      expect(ArabicNormalizer.normalize('ءَايَةٌ'), 'ءايه');

      // 1. All new everyday Imlaei Arabic queries (previously broken 0-result regressions)
      const everydayAyahQueries = <(String, int, int, int)>[
        ('الحمد لله رب العالمين', 6, 1, 2),
        ('مالك يوم الدين', 1, 1, 4),
        ('اهدنا الصراط المستقيم', 1, 1, 6),
        ('صراط الذين انعمت عليهم', 1, 1, 7),
        ('ذلك الكتاب لا ريب فيه', 1, 2, 2),
        ('الكتاب', 100, 2, 2),
        ('الصلاة', 61, 2, 3),
        ('الزكاة', 28, 2, 43),
        ('الحياة الدنيا', 61, 2, 85),
        ('السماوات والارض', 100, 2, 33),
        ('سماوات', 100, 2, 29),
        ('السموات', 100, 2, 33),
        ('ابراهيم', 63, 2, 124),
        ('اسماعيل', 12, 2, 125),
        ('اسحاق', 16, 2, 133),
        ('يعقوب', 16, 2, 132),
        ('سليمان', 16, 2, 102),
        ('داود', 16, 2, 251),
        ('هارون', 20, 2, 248),
        ('الشيطان', 56, 2, 36),
        ('القرآن', 50, 2, 185),
        ('القران', 50, 2, 185),
        ('يا ايها الذين امنوا', 89, 2, 104),
        ('يا أيها الذين آمنوا', 89, 2, 104),
        ('سبحان الله', 9, 12, 108),
        ('استغفر الله', 1, 4, 106),
        ('لا اله الا الله', 2, 37, 35),
        ('حسبنا الله ونعم الوكيل', 1, 3, 173),
        ('ربنا اتنا في الدنيا حسنة', 1, 2, 201),
        ('الله نور السماوات', 1, 24, 35),
      ];

      for (final q in everydayAyahQueries) {
        final results = await QuranSearchService.instance.searchAyahs(q.$1);
        expect(
          results.length,
          greaterThanOrEqualTo(q.$2),
          reason: 'Expected >= ${q.$2} Ayah matches for "${q.$1}", got ${results.length}',
        );
        expect(
          results.any((r) => r.ayah.surahId == q.$3 && r.ayah.ayahNumber == q.$4),
          isTrue,
          reason: 'Expected "${q.$1}" to include ${q.$3}:${q.$4}',
        );
        // Verify strict deduplication (unique ayah IDs) and canonical (surahId, ayahNumber) order
        final ids = results.map((r) => r.ayah.id).toSet();
        expect(ids.length, results.length, reason: 'Duplicate Ayahs returned for "${q.$1}"');
        for (int i = 1; i < results.length; i++) {
          final prev = results[i - 1].ayah;
          final curr = results[i].ayah;
          final ordered = (curr.surahId > prev.surahId) ||
              (curr.surahId == prev.surahId && curr.ayahNumber > prev.ayahNumber);
          expect(ordered, isTrue, reason: 'Out-of-order Ayahs returned for "${q.$1}"');
        }
      }

      // 2. Preserved legacy Uthmani-stripped queries (must STILL match via dual-key index!)
      const legacyPreservedQueries = <(String, int, int, int)>[
        ('ملك يوم الدين', 1, 1, 4),
        ('الكتب', 100, 2, 2),
        ('الصبر', 19, 2, 45),
        ('العلمين', 6, 1, 2),
        ('الرحمن الرحيم', 100, 1, 1),
        ('الرحمن', 100, 1, 1),
        ('موسى', 100, 2, 51),
      ];
      for (final lq in legacyPreservedQueries) {
        final results = await QuranSearchService.instance.searchAyahs(lq.$1);
        expect(
          results.length,
          greaterThanOrEqualTo(lq.$2),
          reason: 'Legacy query "${lq.$1}" regressed: expected >= ${lq.$2}, got ${results.length}',
        );
        expect(
          results.any((r) => r.ayah.surahId == lq.$3 && r.ayah.ayahNumber == lq.$4),
          isTrue,
          reason: 'Legacy query "${lq.$1}" must include ${lq.$3}:${lq.$4}',
        );
        expect(
          results.map((r) => r.ayah.id).toSet().length,
          results.length,
          reason: 'Legacy query "${lq.$1}" returned duplicate Ayahs',
        );
      }

      // 3. Explicit limit enforcement check
      final limited5 = await QuranSearchService.instance.searchAyahs('الكتاب', limit: 5);
      expect(limited5.length, 5);
      expect(limited5.map((r) => r.ayah.id).toSet().length, 5);

      // 4. Surah queries with optional 'سورة ' prefix (including all app chips!)
      const surahQueries = <(String, int)>[
        ('سورة الكهف', 18),
        ('سورة الملك', 67),
        ('سورة يس', 36),
        ('سورة البقرة', 2),
        ('سورة الفاتحة', 1),
        ('سورة الرحمن', 55),
        ('سورة الاخلاص', 112),
        ('الملك', 67),
        ('الكهف', 18),
      ];
      for (final sq in surahQueries) {
        final found = await QuranRepository.searchSurahs(sq.$1);
        expect(
          found.any((s) => s.id == sq.$2),
          isTrue,
          reason: 'Expected Surah ${sq.$2} for query "${sq.$1}", got ${found.map((s) => s.id).toList()}',
        );
      }

      // 5. All 10 app Suggested + Voice chips produce real matches
      const allAppChips = [
        'آية الكرسي',
        'الرحمن الرحيم',
        'سورة الكهف',
        'خواتيم البقرة',
        'الله نور السماوات',
        'آية الدين',
        'سورة الملك',
        'سورة يس',
        'قل هو الله أحد',
        'إن مع العسر يسرا',
      ];
      for (final chip in allAppChips) {
        final ref = await QuranSearchService.instance.parseReference(chip);
        final sur = await QuranRepository.searchSurahs(chip);
        final ay = await QuranSearchService.instance.searchAyahs(chip);
        expect(
          ref != null || sur.isNotEmpty || ay.isNotEmpty,
          isTrue,
          reason: 'App chip "$chip" returned zero results!',
        );
      }

      // 6. Surah filter precision checks
      final mulkAll = await QuranSearchService.instance.searchAyahs('الملك');
      final mulk67 = await QuranSearchService.instance.searchAyahs('الملك', surahFilter: 67);
      final mulk2 = await QuranSearchService.instance.searchAyahs('الملك', surahFilter: 2);
      expect(mulkAll.length, 29);
      expect(mulk67.length, 1);
      expect(mulk2.length, 4);

      // 7. Real unrelated negative controls (must stay strictly 0 — no unbounded fuzzy false positives)
      expect(await QuranSearchService.instance.searchAyahs('الكتابة'), isEmpty);
      expect(await QuranSearchService.instance.searchAyahs('كلمةغيرموجودةابدا'), isEmpty);
      expect(await QuranSearchService.instance.searchAyahs('تطبيق الهاتف الذكي'), isEmpty);
      expect(await QuranSearchService.instance.searchAyahs('برمجة الحاسوب'), isEmpty);
    });

    testWidgets(
      'Transient corpus-load error renders distinct error state (NOT empty) and recovers cleanly without poisoned cache',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        late ByteData realSurahsBytes;
        late ByteData realAyahsBytes;
        await tester.runAsync(() async {
          realSurahsBytes = await rootBundle.load('assets/data/surahs.json');
          realAyahsBytes = await rootBundle.load('assets/data/quran_ayahs.json');
        });

        QuranRepository.resetCachesForTesting();
        QuranSearchService.resetCacheForTesting();
        rootBundle.evict('assets/data/quran_ayahs.json');

        bool failAyahsAsset = true;
        messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'assets/data/surahs.json') return realSurahsBytes;
          if (key == 'assets/data/quran_ayahs.json') {
            if (failAyahsAsset) {
              return ByteData.sublistView(Uint8List.fromList(utf8.encode('{CORRUPTED_JSON')));
            }
            return realAyahsBytes;
          }
          return null;
        });

        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _buildHost(textScale: 2.0, initialQuery: 'قل هو الله أحد'),
          );
          await _settleSearch(tester);

          // Distinct error state shown; MUST NOT masquerade as true empty no-results
          expect(find.byKey(const ValueKey('search_error_scroll_view')), findsOneWidget);
          expect(find.textContaining('تعذر تحميل بيانات المصحف'), findsOneWidget);
          expect(find.text('إعادة المحاولة'), findsOneWidget);
          expect(find.textContaining('لم يتم العثور على نتائج'), findsNothing);

          // Contrast check on retry button
          final retryLabel = tester.widget<Text>(find.text('إعادة المحاولة'));
          expect(
            _contrastRatio(retryLabel.style!.color!, core_theme.AppColors.primaryGreen),
            greaterThanOrEqualTo(4.5),
          );

          await _capturePng(tester, 'repair14_after_08_error_state_retry_360x800_2x.png');

          // Restore asset and tap retry via SemanticsAction.tap -> must recover without poisoned cache!
          failAyahsAsset = false;
          rootBundle.evict('assets/data/quran_ayahs.json');
          final retryNode = _findTappableNode(tester, 'إعادة المحاولة');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            retryNode.id,
            SemanticsAction.tap,
          );
          await _settleSearch(tester);

          expect(find.byKey(const ValueKey('search_error_scroll_view')), findsNothing);
          expect(find.text('نتائج الآيات (1)'), findsOneWidget);
          expect(find.text('سورة الإخلاص : آية 1'), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        } finally {
          semantics.dispose();
          messenger.setMockMessageHandler('flutter/assets', null);
          rootBundle.evict('assets/data/quran_ayahs.json');
          QuranRepository.resetCachesForTesting();
          QuranSearchService.resetCacheForTesting();
        }
      },
    );

    testWidgets(
      'Real UI end-to-end: typed ordinary queries, suggested chip سورة الكهف semantic activation, voice ordinary follow-ups (سورة الملك & الحمد لله رب العالمين), and scope filter (no blank screen)',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final errors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d);
        final semantics = tester.ensureSemantics();

        try {
          // 1. Typed ordinary query 'الحمد لله رب العالمين' at 360x800 @ 1.0x -> 6 Ayahs rendered
          tester.view.physicalSize = const Size(360, 800);
          await tester.pumpWidget(_buildHost(textScale: 1.0));
          await _settleSearch(tester);
          await tester.enterText(find.byType(TextField), 'الحمد لله رب العالمين');
          await _settleSearch(tester);
          expect(find.text('نتائج الآيات (6)'), findsOneWidget);
          expect(find.text('سورة الفاتحة : آية 2'), findsOneWidget);
          await _capturePng(tester, 'repair14_after_01_fatiha_alameen_360x800_1x.png');

          // 2. Typed ordinary query 'القرآن' at 360x800 @ 1.0x -> 50 Ayahs rendered
          await tester.enterText(find.byType(TextField), 'القرآن');
          await _settleSearch(tester);
          expect(find.text('نتائج الآيات (50)'), findsOneWidget);
          expect(find.text('سورة البقرة : آية 185'), findsOneWidget);
          await _capturePng(tester, 'repair14_after_02_alquran_360x800_1x.png');

          // 3. Scope filter: 'الرحمن الرحيم' -> switch to 'السور' -> NO blank screen (shows No Results!)
          await tester.enterText(find.byType(TextField), 'الرحمن الرحيم');
          await _settleSearch(tester);
          expect(find.text('نتائج الآيات (100)'), findsOneWidget);
          final surahScopeNode = _findTappableNode(tester, 'السور');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            surahScopeNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(find.textContaining('لم يتم العثور على نتائج'), findsOneWidget);
          await _capturePng(tester, 'repair14_after_05_scope_filter_no_blank_360x800_1x.png');

          // Switch back to 'الكل'
          final allScopeNode = _findTappableNode(tester, 'الكل');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            allScopeNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          expect(find.text('نتائج الآيات (100)'), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));

          // 4. Tapping app's OWN Suggested Chip 'سورة الكهف' -> renders Surah card + semantic activation opens SurahReaderScreen(18)!
          await tester.pumpWidget(_buildHost(textScale: 1.0));
          await _settleSearch(tester);
          final kahfChip = find.descendant(
            of: find.byType(ActionChip),
            matching: find.text('سورة الكهف'),
          );
          expect(kahfChip, findsOneWidget);
          final kahfChipNode = tester.getSemantics(kahfChip);
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            kahfChipNode.id,
            SemanticsAction.tap,
          );
          await _settleSearch(tester);
          expect(find.text('نتائج السور (1)'), findsOneWidget);
          final kahfTile = find.widgetWithText(ListTile, 'سورة الكهف');
          expect(kahfTile, findsOneWidget);
          await _capturePng(tester, 'repair14_after_03_suggested_chip_surah_kahf_360x800_1x.png');

          // Assert ZERO FlutterErrors on QuranSearchScreen before pushing out-of-scope SurahReaderScreen
          expect(
            errors,
            isEmpty,
            reason:
                'Expected zero FlutterErrors on QuranSearchScreen before opening destination, got: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
          );

          // Semantic activation of Surah result card -> pushes SurahReaderScreen(surah.id == 18)
          final destErrors = <FlutterErrorDetails>[];
          FlutterError.onError = (d) => destErrors.add(d);
          final kahfTileNode = tester.getSemantics(kahfTile);
          expect(kahfTileNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            kahfTileNode.id,
            SemanticsAction.tap,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(SurahReaderScreen), findsOneWidget);
          expect(
            tester.widget<SurahReaderScreen>(find.byType(SurahReaderScreen)).surah.id,
            18,
          );
          _assertOnlyKnownOutOfScopeDestinationOverflows(
            destErrors,
            destinationName: 'SurahReaderScreen(18)',
            expectedMultiset: const [
              (
                sourceLocation: 'surah_reader_screen.dart:123:15',
                direction: 'right',
                roundedPixels: 132,
              ),
            ],
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
          FlutterError.onError = (d) => errors.add(d);

          // 5. Voice follow-up with ordinary Surah phrase 'سورة الملك' (NO alias!)
          VoiceSearchService.testMockRecognizedWords = 'سورة الملك';
          await tester.pumpWidget(_buildHost(textScale: 1.0));
          await _settleSearch(tester);
          final voiceBtn1 = _findTappableNode(tester, 'البحث الصوتي عن الآيات بالميكروفون');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            voiceBtn1.id,
            SemanticsAction.tap,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          final submit1 = _findTappableNode(tester, 'بحث بالآية');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            submit1.id,
            SemanticsAction.tap,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await _settleSearch(tester);
          expect(find.text('نتائج السور (1)'), findsOneWidget);
          expect(find.widgetWithText(ListTile, 'سورة الملك'), findsOneWidget);
          await _capturePng(tester, 'repair14_after_04_voice_followup_surah_mulk_360x800_1x.png');

          // 6. Voice follow-up with ordinary verse phrase 'الحمد لله رب العالمين' at 360x800 @ 2.0x
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
          VoiceSearchService.testMockRecognizedWords = 'الحمد لله رب العالمين';
          await tester.pumpWidget(_buildHost(textScale: 2.0));
          await _settleSearch(tester);
          final voiceBtn2 = _findTappableNode(tester, 'البحث الصوتي عن الآيات بالميكروفون');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            voiceBtn2.id,
            SemanticsAction.tap,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          final submit2 = _findTappableNode(tester, 'بحث بالآية');
          tester.binding.pipelineOwner.semanticsOwner!.performAction(
            submit2.id,
            SemanticsAction.tap,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await _settleSearch(tester);
          expect(find.text('نتائج الآيات (6)'), findsOneWidget);
          expect(find.text('سورة الفاتحة : آية 2'), findsOneWidget);
          await _capturePng(tester, 'repair14_after_06_fatiha_alameen_360x800_2x.png');

          expect(
            errors,
            isEmpty,
            reason:
                'Expected zero FlutterErrors across real-corpus functional UI flow, got: ${errors.map((e) => e.exceptionAsString()).join(" | ")}',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 250));
        } finally {
          semantics.dispose();
          FlutterError.onError = prevOnError;
        }
      },
    );

    testWidgets(
      'Ordinary Ayah Mushaf & Tafsir actions semantic activation + full action button scroll-above-keyboard reachability across 360x800 & 412x915 at 1.0x/2.0x + 300px keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const matrix = <(Size, double, double, String)>[
          (Size(360, 800), 1.0, 300, '360_1x_kb'),
          (Size(360, 800), 2.0, 300, '360_2x_kb'),
          (Size(412, 915), 1.0, 300, '412_1x_kb'),
          (Size(412, 915), 2.0, 300, '412_2x_kb'),
        ];

        final semantics = tester.ensureSemantics();
        final prevOnError = FlutterError.onError;

        try {
          for (final entry in matrix) {
            final size = entry.$1;
            final scale = entry.$2;
            final kb = entry.$3;
            final label = entry.$4;

            // --- Part A: Scroll 'المصحف' action button FULLY above keyboard & semantically activate -> PageModeMushafScreen(initialPage: 1) ---
            final searchErrorsA = <FlutterErrorDetails>[];
            FlutterError.onError = (d) => searchErrorsA.add(d);

            tester.view.physicalSize = size;
            await tester.pumpWidget(
              _buildHost(
                textScale: scale,
                keyboardBottom: kb,
                initialQuery: 'الحمد لله رب العالمين',
              ),
            );
            await _settleSearch(tester);

            expect(find.text('نتائج الآيات (6)'), findsOneWidget);
            expect(find.text('سورة الفاتحة : آية 2'), findsOneWidget);

            final firstCardA = find.byType(Card).first;
            final mushafBtnFinder = find.descendant(
              of: firstCardA,
              matching: find.ancestor(
                of: find.text('المصحف'),
                matching: find.byType(TextButton),
              ),
            );
            await tester.scrollUntilVisible(
              mushafBtnFinder,
              80,
              scrollable: find.descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              ).first,
            );
            await tester.pump();

            // Verify FULL 'المصحف' button rect is visible above the 300px keyboard
            _expectFullyVisibleAboveKeyboard(
              tester,
              mushafBtnFinder,
              size,
              kb,
              '$label/MushafAction',
            );

            if (label == '412_2x_kb') {
              await _capturePng(tester, 'repair14_after_07_fatiha_alameen_412x915_2x_kb.png');
            }
            if (label == '360_2x_kb') {
              await _capturePng(tester, 'repair14_after_09_ayah_actions_above_kb_360x800_2x_kb.png');
            }

            // ZERO errors allowed on QuranSearchScreen before destination push
            expect(
              searchErrorsA,
              isEmpty,
              reason:
                  '[$label/Mushaf] Expected zero FlutterErrors on QuranSearchScreen, got: ${searchErrorsA.map((e) => e.exceptionAsString()).join(" | ")}',
            );

            // Semantically activate 'المصحف' -> opens PageModeMushafScreen(initialPage: 1)
            final mushafDestErrors = <FlutterErrorDetails>[];
            FlutterError.onError = (d) => mushafDestErrors.add(d);
            final mushafNode = tester.getSemantics(mushafBtnFinder);
            expect(mushafNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            tester.binding.pipelineOwner.semanticsOwner!.performAction(
              mushafNode.id,
              SemanticsAction.tap,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));

            expect(
              find.byType(PageModeMushafScreen),
              findsOneWidget,
              reason: '[$label] Activating Ayah المصحف must open PageModeMushafScreen',
            );
            expect(
              tester.widget<PageModeMushafScreen>(find.byType(PageModeMushafScreen)).initialPage,
              1,
              reason: '[$label] PageModeMushafScreen must open at exact page 1 for Al-Fatihah 1:2',
            );
            const expectedPageModeOverflows = <String, List<_ExpectedUnresolvedDestinationOverflow>>{
              '360_1x_kb': [],
              '360_2x_kb': [
                (
                  sourceLocation: 'page_mode_mushaf_screen.dart:206:15',
                  direction: 'right',
                  roundedPixels: 22,
                ),
              ],
              '412_1x_kb': [],
              '412_2x_kb': [],
            };
            _assertOnlyKnownOutOfScopeDestinationOverflows(
              mushafDestErrors,
              destinationName: 'PageModeMushafScreen($label)',
              expectedMultiset: expectedPageModeOverflows[label]!,
            );

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));

            // --- Part B: Scroll 'التفسير' action button FULLY above keyboard & semantically activate -> TafsirViewerSheet(surah: 1, ayah: 2) ---
            final searchErrorsB = <FlutterErrorDetails>[];
            FlutterError.onError = (d) => searchErrorsB.add(d);

            await tester.pumpWidget(
              _buildHost(
                textScale: scale,
                keyboardBottom: kb,
                initialQuery: 'الحمد لله رب العالمين',
              ),
            );
            await _settleSearch(tester);

            final firstCardB = find.byType(Card).first;
            final tafsirBtnFinder = find.descendant(
              of: firstCardB,
              matching: find.ancestor(
                of: find.text('التفسير'),
                matching: find.byType(TextButton),
              ),
            );
            await tester.scrollUntilVisible(
              tafsirBtnFinder,
              80,
              scrollable: find.descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              ).first,
            );
            await tester.pump();

            // Verify FULL 'التفسير' button rect is visible above the 300px keyboard
            _expectFullyVisibleAboveKeyboard(
              tester,
              tafsirBtnFinder,
              size,
              kb,
              '$label/TafsirAction',
            );

            expect(
              searchErrorsB,
              isEmpty,
              reason:
                  '[$label/Tafsir] Expected zero FlutterErrors on QuranSearchScreen, got: ${searchErrorsB.map((e) => e.exceptionAsString()).join(" | ")}',
            );

            // Semantically activate 'التفسير' -> opens TafsirViewerSheet(surahId: 1, ayahNumber: 2)
            final tafsirDestErrors = <FlutterErrorDetails>[];
            FlutterError.onError = (d) => tafsirDestErrors.add(d);
            final tafsirNode = tester.getSemantics(tafsirBtnFinder);
            expect(tafsirNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            tester.binding.pipelineOwner.semanticsOwner!.performAction(
              tafsirNode.id,
              SemanticsAction.tap,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));

            expect(
              find.byType(TafsirViewerSheet),
              findsOneWidget,
              reason: '[$label] Activating Ayah التفسير must open TafsirViewerSheet',
            );
            final tafsirWidget = tester.widget<TafsirViewerSheet>(find.byType(TafsirViewerSheet));
            expect(tafsirWidget.surah.id, 1);
            expect(tafsirWidget.initialAyah.ayahNumber, 2);
            expect(tafsirWidget.initialAyah.page, 1);
            const expectedTafsirOverflows = <String, List<_ExpectedUnresolvedDestinationOverflow>>{
              '360_1x_kb': [
                (
                  sourceLocation: 'tafsir_viewer_sheet.dart:136:22',
                  direction: 'right',
                  roundedPixels: 72,
                ),
              ],
              '360_2x_kb': [
                (
                  sourceLocation: 'tafsir_viewer_sheet.dart:136:22',
                  direction: 'right',
                  roundedPixels: 236,
                ),
                (
                  sourceLocation: 'tafsir_viewer_sheet.dart:345:24',
                  direction: 'right',
                  roundedPixels: 131,
                ),
              ],
              '412_1x_kb': [
                (
                  sourceLocation: 'tafsir_viewer_sheet.dart:136:22',
                  direction: 'right',
                  roundedPixels: 20,
                ),
              ],
              '412_2x_kb': [
                (
                  sourceLocation: 'tafsir_viewer_sheet.dart:136:22',
                  direction: 'right',
                  roundedPixels: 184,
                ),
                (
                  sourceLocation: 'tafsir_viewer_sheet.dart:345:24',
                  direction: 'right',
                  roundedPixels: 79,
                ),
              ],
            };
            _assertOnlyKnownOutOfScopeDestinationOverflows(
              tafsirDestErrors,
              destinationName: 'TafsirViewerSheet($label)',
              expectedMultiset: expectedTafsirOverflows[label]!,
            );

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));
          }
        } finally {
          semantics.dispose();
          FlutterError.onError = prevOnError;
        }
      },
    );
  });
}
