import 'dart:io';
import 'package:flutter/services.dart';
import 'package:almomin/core/models/surah.dart';
import 'package:almomin/core/models/ayah.dart';
import 'package:almomin/features/mushaf/widgets/ayah_card_widget.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/ayah_card_service.dart';

class _EncodingImage implements ui.Image {
  _EncodingImage(this.fail);
  final bool fail;
  int disposals = 0;
  @override
  Future<ByteData?> toByteData(
      {ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba}) async {
    if (fail) throw StateError('encoding failure');
    return null;
  }

  @override
  void dispose() {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Boundary extends SingleChildRenderObjectWidget {
  const _Boundary({super.key, required this.image});
  final ui.Image image;
  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderBoundary(image);
}

class _RenderBoundary extends RenderRepaintBoundary {
  _RenderBoundary(this.image);
  final ui.Image image;
  @override
  Future<ui.Image> toImage({double pixelRatio = 1}) async => image;
}

void main() {
  setUpAll(() async {
    for (final family in ['Cairo', 'Roboto', 'Amiri']) {
      final loader = FontLoader(family);
      loader.addFont(rootBundle.load(family == 'Amiri'
          ? 'assets/fonts/Amiri-Regular.ttf'
          : 'assets/fonts/Cairo-Regular.ttf'));
      await loader.load();
    }
  });
  for (final theme in AyahCardTheme.availableThemes) {
    testWidgets('exported card PNG remains valid for ${theme.id.name}',
        (tester) async {
      final key = GlobalKey();
      const surah = Surah(
          id: 112,
          nameAr: 'الإخلاص',
          nameSimple: 'Al-Ikhlas',
          revelationPlace: 'makkah',
          revelationOrder: 22,
          ayahCount: 4,
          hasBasmala: true,
          pageStart: 604,
          pageEnd: 604);
      const ayah = Ayah(
          id: 6222,
          surahId: 112,
          ayahNumber: 1,
          juz: 30,
          hizb: 60,
          rub: 240,
          page: 604,
          sajdah: 0,
          textUthmani: 'قُلْ هُوَ اللَّهُ أَحَدٌ',
          textImlaei: 'قل هو الله أحد',
          textSearch: 'قل هو الله احد');
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
              body: Center(
                  child: RepaintBoundary(
                      key: key,
                      child: SizedBox(
                          width: 400,
                          child: AyahIslamicCardWidget(
                              surah: surah,
                              ayah: ayah,
                              theme: theme,
                              includeTafsir: false)))))));
      await tester.pumpAndSettle();
      final bytes = await tester
          .runAsync(() => AyahCardService.captureWidgetToBytes(key));
      expect(bytes, isNotNull);
      expect(ByteData.sublistView(bytes!).getUint32(16), 1200);
      const directory = String.fromEnvironment('CARD_CAPTURE_PIXEL_DIR');
      if (directory.isNotEmpty) {
        Directory(directory).createSync(recursive: true);
        File('$directory/${theme.id.name}.png').writeAsBytesSync(bytes);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
      'repeated capture releases each high resolution image and keeps PNG bytes valid',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: key,
                child: const SizedBox(
                    width: 40,
                    height: 20,
                    child: ColoredBox(color: Colors.green))))));
    final images = <ui.Image>[];
    final previous = ui.Image.onCreate;
    ui.Image.onCreate = (image) {
      previous?.call(image);
      images.add(image);
    };
    try {
      for (var i = 0; i < 3; i++) {
        final bytes = await tester
            .runAsync(() => AyahCardService.captureWidgetToBytes(key));
        expect(bytes, isNotNull);
        expect(bytes!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), 120);
        expect(header.getUint32(20), 60);
      }
      expect(images, hasLength(3));
      expect(images.every((image) => image.debugDisposed), isTrue);
      expect(
          images
              .every((image) => image.debugGetOpenHandleStackTraces()!.isEmpty),
          isTrue);
    } finally {
      ui.Image.onCreate = previous;
      for (final image in images) {
        if (!image.debugDisposed) image.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  for (final fail in [false, true]) {
    testWidgets(
        'capture releases owned image when encoding ${fail ? 'throws' : 'returns null'}',
        (tester) async {
      final key = GlobalKey();
      final image = _EncodingImage(fail);
      await tester
          .pumpWidget(MaterialApp(home: _Boundary(key: key, image: image)));
      final bytes = await AyahCardService.captureWidgetToBytes(key);
      expect(bytes, isNull);
      expect(image.disposals, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('missing capture boundary keeps null fallback', () async {
    expect(await AyahCardService.captureWidgetToBytes(GlobalKey()), isNull);
  });
}
