import 'dart:convert';
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

// Read physical paint colors so any Material surface tint is included.
Color paintedBackground(WidgetTester tester, Finder finder) {
  var color = Colors.transparent;
  tester.element(finder).visitAncestorElements((element) {
    final widget = element.widget;
    Color? fill;
    if (widget is Container) {
      fill = widget.color;
      if (widget.decoration is BoxDecoration) {
        fill ??= (widget.decoration as BoxDecoration).color;
      }
    }
    if (widget is Ink && widget.decoration is ShapeDecoration) {
      fill = (widget.decoration as ShapeDecoration).color;
    }
    if (widget is PhysicalShape) fill = widget.color;
    if (widget is PhysicalModel) fill = widget.color;
    if (widget is Scaffold) {
      fill =
          widget.backgroundColor ?? Theme.of(element).scaffoldBackgroundColor;
    }
    if (fill != null) color = Color.alphaBlend(color, fill);
    return color.a < 1;
  });
  expect(color.a, 1, reason: 'An opaque painted background must be found');
  return color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = EgyptianHeritageService.instance;
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
    await service.init(forceReload: true);
  });

  for (final mode in AppThemeMode.values) {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fatwa badge and filters ${mode.name} $width/$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final boundary = GlobalKey();
          final rows = <Map<String, Object>>[];
          void measure(String label, Finder finder,
              {Color? foreground, double minimum = 4.5}) {
            final fg = foreground ??
                tester.renderObject<RenderParagraph>(finder).text.style!.color!;
            final bg = paintedBackground(tester, finder);
            final a = Color.alphaBlend(fg, bg).computeLuminance();
            final b = bg.computeLuminance();
            final ratio =
                (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
            rows.add({
              'label': label,
              'foreground': fg.toARGB32(),
              'background': bg.toARGB32(),
              'ratio': ratio,
              'minimum': minimum
            });
          }

          Future<void> capture(String suffix) async {
            const out = String.fromEnvironment('FATWA_CONTRAST_DIR');
            if (out.isEmpty) return;
            await tester.runAsync(() async {
              Directory(out).createSync(recursive: true);
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              File('$out/${mode.name}-$width-$scale-$suffix.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          Finder chip(String category) =>
              find.widgetWithText(ChoiceChip, category);
          Future<void> measureCheckmark(String category) async {
            final label = find.descendant(
                of: chip(category), matching: find.text(category));
            final labelRect = tester.getRect(label);
            final chipRect = tester.getRect(chip(category));
            // The screen is RTL. Isolate the painted selection mark to the
            // right of the label, excluding text, outline and rounded corners.
            final region = Rect.fromLTRB(
                labelRect.right + 2,
                chipRect.center.dy - 10,
                chipRect.right - 8,
                chipRect.center.dy + 10);
            expect(region.width, greaterThan(0));
            final viewport = tester.getRect(find
                .ancestor(
                    of: chip(category),
                    matching: find.byType(SingleChildScrollView))
                .first);
            expect(
                viewport.contains(region.topLeft) &&
                    viewport.contains(region.bottomRight),
                isTrue,
                reason:
                    'The checkmark sample must be inside the actual horizontal viewport');
            final bg = paintedBackground(tester, label).toARGB32();
            final histogram = <int, int>{};
            await tester.runAsync(() async {
              final root = boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
              final origin = root.localToGlobal(Offset.zero);
              final image = await root.toImage(pixelRatio: 1);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
              for (var y = (region.top - origin.dy).ceil();
                  y < (region.bottom - origin.dy).floor();
                  y++) {
                for (var x = (region.left - origin.dx).ceil();
                    x < (region.right - origin.dx).floor();
                    x++) {
                  final i = (y * image.width + x) * 4;
                  final value = Color.fromARGB(
                          bytes!.getUint8(i + 3),
                          bytes.getUint8(i),
                          bytes.getUint8(i + 1),
                          bytes.getUint8(i + 2))
                      .toARGB32();
                  if (value != bg) {
                    histogram.update(value, (n) => n + 1, ifAbsent: () => 1);
                  }
                }
              }
              image.dispose();
            });
            expect(histogram, isNotEmpty,
                reason: 'The selected checkmark must actually be painted');
            final peak =
                histogram.entries.reduce((a, b) => a.value > b.value ? a : b);
            measure('selected checkmark $category', label,
                foreground: Color(peak.key), minimum: 3);
            rows.last['sample_rect'] = [
              region.left,
              region.top,
              region.right,
              region.bottom
            ];
            rows.last['solid_stroke_pixels'] = peak.value;
          }

          final vertical = find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)
              .first;
          Future<void> show(Finder finder) async {
            await tester.scrollUntilVisible(finder, 300,
                scrollable: vertical, maxScrolls: 80);
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
          }

          try {
            await tester.pumpWidget(RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.of(mode),
                    home: const EgyptianHeritageScreen(initialTabIndex: 2),
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!))));
            await tester.pumpAndSettle();
            await show(chip('الكل'));
            measure('selected all filter',
                find.descendant(of: chip('الكل'), matching: find.text('الكل')));
            await measureCheckmark('الكل');
            await capture('filters');
            final category = service.fatwaCategories[1];
            measure(
                'unselected category filter',
                find.descendant(
                    of: chip(category), matching: find.text(category)));
            for (final (i, fatwa) in service.darAlIftaRulings.indexed) {
              final question = find.text('س: ${fatwa.question}');
              await show(question);
              final card =
                  find.ancestor(of: question, matching: find.byType(Card));
              final badge = find.descendant(
                  of: card, matching: find.text(fatwa.category));
              await tester.ensureVisible(badge);
              await tester.pumpAndSettle();
              measure('badge ${fatwa.id}', badge);
              final rect = tester.getRect(badge);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(915));
              if (i == 0) await capture('badge');
            }
            // Category selection stays a real filter, including screen-reader activation.
            await tester.drag(vertical, const Offset(0, 12000));
            await tester.pumpAndSettle();
            await show(chip(category));
            await tester.tap(chip(category));
            await tester.pumpAndSettle();
            await tester.ensureVisible(chip(category));
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(chip(category)).selected, isTrue);
            expect(
                tester
                    .getSemantics(chip(category))
                    .getSemanticsData()
                    .hasFlag(ui.SemanticsFlag.isSelected),
                isTrue);
            measure(
                'selected category filter',
                find.descendant(
                    of: chip(category), matching: find.text(category)));
            await measureCheckmark(category);
            await capture('selected-filter');
            final expected = service.searchFatwas('', category: category);
            for (final fatwa in expected) {
              await show(find.text('س: ${fatwa.question}'));
              expect(find.text('س: ${fatwa.question}'), findsOneWidget);
            }
            for (final fatwa in service.darAlIftaRulings
                .where((f) => f.category != category)) {
              expect(find.text('س: ${fatwa.question}'), findsNothing);
            }
            await tester.drag(vertical, const Offset(0, 12000));
            await tester.pumpAndSettle();
            await show(chip('الكل'));
            final node = tester.getSemantics(chip('الكل'));
            expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue);
            tester.binding.pipelineOwner.semanticsOwner!
                .performAction(node.id, ui.SemanticsAction.tap);
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(chip('الكل')).selected, isTrue);
            expect(
                tester
                    .getSemantics(chip('الكل'))
                    .getSemanticsData()
                    .hasFlag(ui.SemanticsFlag.isSelected),
                isTrue);
            expect(tester.takeException(), isNull);
            const out = String.fromEnvironment('FATWA_CONTRAST_DIR');
            if (out.isNotEmpty) {
              File('$out/${mode.name}-$width-$scale.json').writeAsStringSync(
                  const JsonEncoder.withIndent('  ').convert(rows));
            }
            expect(
                rows.where(
                    (r) => (r['ratio'] as double) < (r['minimum'] as double)),
                isEmpty,
                reason: jsonEncode(rows));
          } finally {
            await tester.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        });
      }
    }
  }
}
