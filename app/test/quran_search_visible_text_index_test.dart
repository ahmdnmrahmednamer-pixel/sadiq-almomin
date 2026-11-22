import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/search/quran_search_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/core/text/arabic_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      final regular = File('assets/fonts/$family-Regular.ttf');
      expect(regular.existsSync(), isTrue);
      loader.addFont(
          Future.value(ByteData.sublistView(regular.readAsBytesSync())));
      final bold = File('assets/fonts/$family-Bold.ttf');
      if (bold.existsSync())
        loader.addFont(
            Future.value(ByteData.sublistView(bold.readAsBytesSync())));
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });

  late List<Ayah> corpus;
  late Map<int, String> originalRawText;
  const basmala = 'بسم الله الرحمن الرحيم';
  List<String> ids(List<AyahSearchResult> results) =>
      results.map((r) => '${r.ayah.surahId}:${r.ayah.ayahNumber}').toList();
  bool displayedMatch(Ayah ayah, String query) {
    final imlaei = ArabicNormalizer.normalizeForQuranSearch(query);
    final legacy = ArabicNormalizer.normalize(query, loose: true);
    return (imlaei.isNotEmpty &&
            ArabicNormalizer.normalizeForQuranSearch(ayah.cleanTextUthmani)
                .contains(imlaei)) ||
        (legacy.isNotEmpty &&
            ArabicNormalizer.normalize(
              ayah.cleanTextUthmani,
              loose: true,
            ).contains(legacy));
  }

  setUpAll(() async {
    QuranSearchService.resetCacheForTesting();
    corpus =
        (await QuranRepository.loadAllPages()).values.expand((x) => x).toList()
          ..sort(
            (a, b) => a.surahId != b.surahId
                ? a.surahId.compareTo(b.surahId)
                : a.ayahNumber.compareTo(b.ayahNumber),
          );
    expect(corpus, hasLength(6236));
    originalRawText = {for (final ayah in corpus) ayah.id: ayah.textUthmani};
  });
  test(
    'full basmala finds only displayed ayah text, not decorative prefixes',
    () async {
      final results = await QuranSearchService.instance.searchAyahs(
        basmala,
        limit: 10000,
      );
      expect(ids(results), ['1:1', '27:30']);
      expect(results.every((r) => displayedMatch(r.ayah, basmala)), isTrue);
    },
  );
  test(
      'Uthmani basmala retains both legitimate results through dual normalization',
      () async {
    final query = corpus
        .firstWhere((a) => a.surahId == 1 && a.ayahNumber == 1)
        .cleanTextUthmani;
    expect(
      ids(await QuranSearchService.instance.searchAyahs(query, limit: 10000)),
      ['1:1', '27:30'],
    );
  });
  test('mercy phrase retains the six actual displayed matches', () async {
    final results = await QuranSearchService.instance.searchAyahs(
      'الرحمن الرحيم',
      limit: 10000,
    );
    expect(ids(results), ['1:1', '1:3', '2:163', '27:30', '41:2', '59:22']);
  });
  test(
    'mercy word retains all forty-eight displayed matches in canonical order',
    () async {
      final expected = corpus
          .where((a) => displayedMatch(a, 'الرحمن'))
          .map((a) => '${a.surahId}:${a.ayahNumber}')
          .toList();
      expect(expected, hasLength(48));
      expect(
        ids(
          await QuranSearchService.instance.searchAyahs('الرحمن', limit: 10000),
        ),
        expected,
      );
    },
  );
  test(
    'surah filters exclude prefix-only first ayahs without hiding Naml30',
    () async {
      expect(
        await QuranSearchService.instance.searchAyahs(basmala, surahFilter: 2),
        isEmpty,
      );
      expect(
        ids(
          await QuranSearchService.instance.searchAyahs(
            basmala,
            surahFilter: 27,
          ),
        ),
        ['27:30'],
      );
    },
  );
  test(
    'common divine-name query matches displayed text for every returned ayah',
    () async {
      final expected = corpus
          .where((a) => displayedMatch(a, 'الله'))
          .map((a) => '${a.surahId}:${a.ayahNumber}')
          .toList();
      final results = await QuranSearchService.instance.searchAyahs(
        'الله',
        limit: 10000,
      );
      expect(ids(results), expected);
      expect(results.map((r) => r.ayah.id).toSet(), hasLength(results.length));
      expect(ids(results), isNot(contains('2:1')));
    },
  );
  test(
    'limit applies after prefix-only exclusions and retains result order',
    () async {
      expect(
        ids(await QuranSearchService.instance.searchAyahs(basmala, limit: 1)),
        ['1:1'],
      );
      expect(
        ids(await QuranSearchService.instance.searchAyahs(basmala, limit: 2)),
        ['1:1', '27:30'],
      );
    },
  );
  test(
    'surah without decorative prefix remains searchable unchanged',
    () async {
      final ayah = corpus.firstWhere(
        (a) => a.surahId == 9 && a.ayahNumber == 1,
      );
      expect(ayah.cleanTextUthmani, ayah.textUthmani);
      expect(
        ids(
          await QuranSearchService.instance.searchAyahs(
            ayah.cleanTextUthmani,
            surahFilter: 9,
          ),
        ),
        ['9:1'],
      );
    },
  );
  test('indexing preserves raw text, references and corpus identity', () async {
    await QuranSearchService.instance.searchAyahs(basmala, limit: 10000);
    expect({
      for (final ayah in corpus) ayah.id: ayah.textUthmani,
    }, originalRawText);
    final reference = await QuranSearchService.instance.parseReference('2:1');
    expect(reference?.surahId, 2);
    expect(reference?.ayahNumber, 1);
    final ayah = await QuranRepository.getAyah(2, 1);
    expect(ayah, isNotNull);
    expect(ayah!.textUthmani, isNot(ayah.cleanTextUthmani));
    expect(ayah.textUthmani, originalRawText[ayah.id]);
  });
  for (final sample in [(AppThemeMode.light, 1.0), (AppThemeMode.black, 2.0)]) {
    testWidgets(
        'visible search results follow displayed text ${sample.$1.name} ${sample.$2}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.of(sample.$1),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(sample.$2)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!)),
            home: const QuranSearchScreen(),
          )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), basmala);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final failures = <String>[];
      if (find.text('نتائج الآيات (2)').evaluate().length != 1)
        failures.add('Expected two displayed-text results');
      expect(find.text('سورة الفاتحة : آية 1'), findsOneWidget);
      Future<void> capture(String phase) async {
        final dir = Platform.environment['SEARCH_INDEX_PIXELS'];
        if (dir == null) return;
        await tester.runAsync(() async {
          Directory(dir).createSync(recursive: true);
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/${sample.$1.name}-${sample.$2}-$phase.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('top');
      await tester.scrollUntilVisible(
        find.text('سورة النمل : آية 30'),
        600,
        maxScrolls: 80,
        scrollable: find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      expect(find.text('سورة النمل : آية 30'), findsOneWidget);
      await tester.pumpAndSettle();
      await capture('naml');
      tester
          .widget<PopupMenuButton<int?>>(find.byType(PopupMenuButton<int?>))
          .onSelected!(2);
      await tester.pumpAndSettle();
      if (find.textContaining('لم يتم العثور على نتائج').evaluate().length != 1)
        failures.add('Filtered prefix-only result was not excluded');
      if (find.text('سورة البقرة : آية 1').evaluate().isNotEmpty)
        failures.add('Hidden-prefix-only card remains');
      await capture('filtered');
      final error = tester.takeException();
      if (error != null) failures.add('$error');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
