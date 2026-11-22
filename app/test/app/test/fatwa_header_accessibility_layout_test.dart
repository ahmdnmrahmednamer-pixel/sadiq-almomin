import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/egyptian_heritage_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/egypt/egyptian_heritage_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    await EgyptianHeritageService.instance.init(forceReload: true);
  });

  Future<void> mount(WidgetTester tester, double width, double scale,
      {bool dark = false}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('fatwa-layout-pixels'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: const EgyptianHeritageScreen(initialTabIndex: 2),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const out = String.fromEnvironment('HERITAGE_REVIEW_DIR');
    if (out.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('fatwa-layout-pixels')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('all fatwa headers fit at $width/$scale dark=$dark',
            (tester) async {
          final errors = <String>[];
          final originalHandler = FlutterError.onError;
          FlutterError.onError =
              (error) => errors.add(error.exceptionAsString());
          try {
            await mount(tester, width, scale, dark: dark);
            for (final (i, fatwa)
                in EgyptianHeritageService.instance.darAlIftaRulings.indexed) {
              final question = find.text('س: ${fatwa.question}');
              await tester.scrollUntilVisible(question, 350,
                  scrollable: find
                      .byWidgetPredicate((widget) =>
                          widget is Scrollable &&
                          widget.axisDirection == AxisDirection.down)
                      .first,
                  maxScrolls: 80);
              final card =
                  find.ancestor(of: question, matching: find.byType(Card));
              final copy = find.descendant(
                  of: card, matching: find.byTooltip('نسخ الفتوى'));
              await tester.ensureVisible(card);
              await tester.pumpAndSettle();
              final rect = tester.getRect(copy);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.width, greaterThanOrEqualTo(40));
              expect(rect.height, greaterThanOrEqualTo(40));
              if (i == 0 && scale == 2) {
                await capture(tester,
                    'fatwa-header-${width.toInt()}-2-${dark ? 'dark' : 'light'}');
              }
            }
          } finally {
            FlutterError.onError = originalHandler;
          }
          expect(errors, isEmpty, reason: errors.join('\n'));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('fatwa copy and saved favorite keep semantic activation at 2x',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await mount(tester, 320, 2, dark: true);
      final first = EgyptianHeritageService.instance.darAlIftaRulings.first;
      final copy = find.byTooltip('نسخ الفتوى').first;
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      final copyNode = tester.getSemantics(copy);
      expect(copyNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue);
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(copyNode.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(copied,
          'السؤال: ${first.question}\n\nالجواب: ${first.rulingSummary}\n\nالمصدر: ${first.sourceAuthority} (${first.referenceNote})');
      final firstCard = find.ancestor(
        of: find.text('س: ${first.question}'),
        matching: find.byType(Card),
      );
      final favorite = find.descendant(
        of: firstCard,
        matching: find.byTooltip('حفظ في المفضلة'),
      );
      final favoriteRect = tester.getRect(favorite);
      expect(favoriteRect.left, greaterThanOrEqualTo(0));
      expect(favoriteRect.right, lessThanOrEqualTo(320));
      final favoriteNode = tester.getSemantics(favorite);
      expect(favoriteNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue);
      await tester.runAsync(() async {
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(favoriteNode.id, ui.SemanticsAction.tap);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(EgyptianHeritageService.instance.isFavorite(first.id), isTrue);
      await tester.runAsync(
        () => EgyptianHeritageService.instance.init(forceReload: true),
      );
      expect(EgyptianHeritageService.instance.isFavorite(first.id), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
