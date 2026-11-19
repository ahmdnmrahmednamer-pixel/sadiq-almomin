import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/models/islamic_radio.dart';
import 'package:almomin/core/services/islamic_radio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/radio/islamic_radio_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final radio = IslamicRadioService.instance;
  final audio = FastAudioService.instance;

  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
            Future.value(ByteData.sublistView(File(icons).readAsBytesSync())));
      await loader.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'islamic_radio_favorites': ['radio_minshawi', 'radio_saheh_bokharee']
    });
    await SettingsService.instance.init(forceReload: true);
    await radio.init(forceReload: true);
    audio.resetForTesting();
  });
  tearDown(() {
    audio.resetForTesting();
  });

  test(
      'all search/category/favorite paths expose only Quran while legacy catalog and favorite IDs survive',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getStringList('islamic_radio_favorites');
    expect(IslamicRadioService.defaultStations.length, 43);
    expect(radio.getStations().length, 29);
    for (final category in IslamicRadioCategoryType.values) {
      for (final query in ['', 'القرآن', 'البخاري', 'الرقية']) {
        for (final favoritesOnly in [false, true]) {
          final stations = radio.getStations(
              category: category, query: query, favoritesOnly: favoritesOnly);
          expect(
              stations.every(
                  (s) => IslamicRadioService.isQuranCategory(s.category)),
              isTrue);
        }
      }
    }
    expect(radio.getStations(query: 'المنشاوي'), isNotEmpty);
    expect(radio.getStations(query: 'عبد الباسط'), isNotEmpty);
    expect(radio.getStations(query: 'الحصري'), isNotEmpty);
    expect(radio.favoriteIds, contains('radio_saheh_bokharee'));
    expect(prefs.getStringList('islamic_radio_favorites'), before);
  });

  test(
      'official Cairo source dispatch is HTTPS HLS and live without alternate-station substitution',
      () async {
    final cairo = IslamicRadioService.defaultStations
        .singleWhere((s) => s.id == 'radio_cairo_live');
    final seen = <String>[];
    audio.getFastAudioSourceOverride = (url,
        {required cacheKey,
        localDownloadedPath,
        bool isLiveStream = false}) async {
      seen.add(url);
      expect(isLiveStream, isTrue);
      expect(localDownloadedPath, isNull);
      return AudioSource.uri(Uri.parse(url));
    };
    audio.setAudioSourceOverride = (_, source) async {};
    expect(
        await audio.playLiveRadio(
            primaryUrl: cairo.streamUrl, fallbackUrls: cairo.fallbackUrls),
        isTrue);
    expect(seen, [cairo.streamUrl]);
    expect(Uri.parse(seen.single).scheme, 'https');
    expect(seen.single, endsWith('.m3u8'));
    seen.clear();
    audio.getFastAudioSourceOverride = (url,
        {required cacheKey,
        localDownloadedPath,
        bool isLiveStream = false}) async {
      seen.add(url);
      throw StateError('source unavailable');
    };
    expect(
        await audio.playLiveRadio(
            primaryUrl: cairo.streamUrl, fallbackUrls: cairo.fallbackUrls),
        isFalse);
    expect(seen, [cairo.streamUrl]);
  });

  testWidgets(
      'Cairo semantic activation dispatches the exact source and failure stays explicit',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final seen = <String>[];
    audio.getFastAudioSourceOverride = (url,
        {required cacheKey,
        localDownloadedPath,
        bool isLiveStream = false}) async {
      seen.add(url);
      throw StateError('network unavailable');
    };
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const IslamicRadioScreen(
            playerStateStreamOverride: Stream<PlayerState>.empty())));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(ElevatedButton, 'استماع للبث');
    final node = tester.getSemantics(button);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    final cairo = IslamicRadioService.defaultStations
        .singleWhere((s) => s.id == 'radio_cairo_live');
    expect(seen, [cairo.streamUrl]);
    expect(find.textContaining('تعذر تشغيل إذاعة'), findsOneWidget);
    expect(find.text('استماع متواصل'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
      'Quran radio current source is accessible and layout works at 320/360/412, 1x/2x',
      (tester) async {
    final semantics = tester.ensureSemantics();

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = size;
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const IslamicRadioScreen(),
            )));
        await tester.pumpAndSettle();
        expect(find.textContaining('غير مدعوم على أندرويد'), findsNothing);
        expect(find.text('الموقع الرسمي'), findsOneWidget);
        final searchField = find.byKey(const Key('quran_radio_search'));
        final searchSemantics = tester
            .getSemantics(find.descendant(
                of: searchField, matching: find.byType(EditableText)))
            .getSemanticsData();
        expect(searchSemantics.hasFlag(ui.SemanticsFlag.isTextField), isTrue);
        expect(searchSemantics.label, contains('ابحث عن إذاعة'));
        final editable = tester
            .state<EditableTextState>(find.descendant(
                of: searchField, matching: find.byType(EditableText)))
            .renderEditable;
        expect(editable.size.height,
            greaterThanOrEqualTo(editable.preferredLineHeight));
        final inputRect = tester.getRect(searchField);
        expect(inputRect.height,
            greaterThanOrEqualTo(editable.preferredLineHeight + 20));

        expect(find.text('السنة النبوية والحديث'), findsNothing);
        expect(find.text('الأذكار والرقية الشرعية'), findsNothing);
        expect(tester.takeException(), isNull);
        const dir = String.fromEnvironment('RADIO_PIXELS_DIR');
        if (dir.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            Directory(dir).createSync(recursive: true);
            File('$dir/radio_${size.width.toInt()}_${scale.toInt()}x.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (size.width == 412 && scale == 2) {
          for (final query in ['المنشاوي', 'عبد الباسط', 'الحصري']) {
            await tester.enterText(searchField, query);
            await tester.pumpAndSettle();
            expect(find.textContaining(query), findsWidgets);
            expect(tester.takeException(), isNull);
            if (dir.isNotEmpty) {
              await tester.runAsync(() async {
                final image = await (boundary.currentContext!
                        .findRenderObject()! as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                File('$dir/reader_${query.hashCode}_412_2x.png')
                    .writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
    semantics.dispose();
  });
}
