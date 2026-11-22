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
      {AppThemeMode mode = AppThemeMode.light}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shaarawi-layout-pixels'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(mode),
        home: const EgyptianHeritageScreen(initialTabIndex: 0),
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
    const out = String.fromEnvironment('SHAARAWI_REVIEW_DIR');
    if (out.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('shaarawi-layout-pixels')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final mode in AppThemeMode.values) {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('all Shaarawi headers fit ${mode.name} $width/$scale', (tester) async {
          final errors = <String>[];
          final originalHandler = FlutterError.onError;
          FlutterError.onError = (error) => errors.add(error.exceptionAsString());
          final semantics = tester.ensureSemantics();
          try {
            await mount(tester, width, scale, mode: mode);
            final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
            for (final (i, item) in EgyptianHeritageService.instance.shaarawiReflections.indexed) {
              final title = find.text(item.title);
              await tester.scrollUntilVisible(title, 300, scrollable: vertical, maxScrolls: 100);
              await tester.ensureVisible(title);
              await tester.pumpAndSettle();
              final card = find.ancestor(of: title, matching: find.byType(Card));
              if (i == 0 || i == 4) {
                await capture(tester, '${mode.name}-${width.toInt()}-$scale-$i-before-checks');
              }
              final topic = find.descendant(of: card, matching: find.text(item.topic));
              final favorite = find.descendant(of: card, matching: find.byTooltip('حفظ في المفضلة'));
              final play = find.descendant(of: card, matching: find.byTooltip('تشغيل أو إيقاف الصوت'));
              for (final text in [title, topic]) {
                final paragraph = tester.renderObject<RenderParagraph>(text);
                expect(paragraph.didExceedMaxLines, isFalse);
                final rect = tester.getRect(text);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
                expect(rect.width, greaterThan(30));
              }
              for (final button in [favorite, play]) {
                await tester.ensureVisible(button);
                await tester.pumpAndSettle();
                final rect = tester.getRect(button);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(rect.bottom, lessThanOrEqualTo(915));
                expect(rect.width, greaterThanOrEqualTo(40));
                expect(rect.height, greaterThanOrEqualTo(40));
                expect(tester.getSemantics(button).getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
              }
              expect(tester.getRect(title).overlaps(tester.getRect(favorite)), isFalse);
              expect(tester.getRect(title).overlaps(tester.getRect(play)), isFalse);
              expect(tester.getRect(topic).overlaps(tester.getRect(favorite)), isFalse);
              expect(tester.getRect(topic).overlaps(tester.getRect(play)), isFalse);
              if (i == 0 || i == 4) {
                await tester.ensureVisible(topic);
                await tester.pumpAndSettle();
                await capture(tester, '${mode.name}-${width.toInt()}-$scale-$i');
              }
            }
            final first = EgyptianHeritageService.instance.shaarawiReflections.first;
            final firstCard = find.ancestor(of: find.text(first.title), matching: find.byType(Card));
            final favorite = find.descendant(of: firstCard, matching: find.byTooltip('حفظ في المفضلة'));
            await tester.scrollUntilVisible(favorite, -300, scrollable: vertical, maxScrolls: 100);
            await tester.ensureVisible(favorite);
            await tester.pumpAndSettle();
            final node = tester.getSemantics(favorite);
            await tester.runAsync(() async {
              tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, ui.SemanticsAction.tap);
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
            await tester.pumpAndSettle();
            expect(EgyptianHeritageService.instance.isFavorite(first.id), isTrue);
            await tester.runAsync(() => EgyptianHeritageService.instance.init(forceReload: true));
            expect(EgyptianHeritageService.instance.isFavorite(first.id), isTrue);
          } finally {
            FlutterError.onError = originalHandler;
            await tester.pumpWidget(const SizedBox());
            semantics.dispose();
          }
          expect(errors, isEmpty, reason: errors.join('\n'));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
