import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/ui/app_dropdown_field.dart';
import 'package:almomin/features/adhkar/tasbih_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Cairo', 'Amiri']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-Regular.ttf')))
          .load();
    }
    final icons = Platform.environment['MATERIAL_ICONS_FONT'];
    if (icons != null)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  testWidgets(
      'custom target matches selected option after dialog save and reload; presets stay unchanged',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'tasbih_target': 7, 'tasbih_count': 3, 'tasbih_haptic': false});
    await SettingsService.instance.init(forceReload: true);
    final service = AdhkarService.instance;
    await service.init(forceReload: true);
    final boundary = GlobalKey();
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(412, 950);
    tester.view.devicePixelRatio = 1;
    Finder getDropdown() => find.byWidgetPredicate(
        (w) => w is AppDropdownField<int> && w.label == 'هدف دورة التسبيح');
    Future<void> check(int target) async {
      final dropdown = tester.widget<AppDropdownField<int>>(getDropdown());
      expect(dropdown.value, target);
      expect(dropdown.options.where((o) => o.value == target), hasLength(1));
      final selected = dropdown.options.singleWhere((o) => o.value == target);
      expect(selected.label, contains('$target'));
      final native = find.descendant(
          of: getDropdown(),
          matching: find.byType(DropdownButtonFormField<int>));
      expect(tester.state<FormFieldState<int>>(native).value, target);
      final selectedText = find
          .descendant(of: getDropdown(), matching: find.text(selected.label))
          .first;
      final paragraph = tester.renderObject<RenderParagraph>(selectedText);
      expect(paragraph.didExceedMaxLines, isFalse);
      final node = tester.getSemantics(find.descendant(
          of: getDropdown(), matching: find.byType(DropdownButton<int>)));
      expect(node.label, contains(selected.label));
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      expect(service.tasbihTarget, target);
      expect(service.tasbihCount, 3);
    }

    Future<void> capture(String name) async {
      final dir = Platform.environment['TARGET_PIXELS'];
      if (dir == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    try {
      for (final scale in [1.0, 2.0]) {
        await service.setTasbihTarget(7);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const TasbihScreen())));
        await tester.pumpAndSettle();
        await capture('custom7-$scale');
        await check(7);
        await tester.tap(find.byTooltip('تحديد هدف مخصص'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.descendant(
                of: find.byType(AlertDialog), matching: find.byType(TextField)),
            '57');
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
        await check(57);
        await capture('custom57-$scale');
        await service.init(forceReload: true);
        await tester.pumpAndSettle();
        await check(57);
        final dropdown = tester.widget<AppDropdownField<int>>(getDropdown());
        expect(
            dropdown.options.where((o) => [33, 100, 1000, 0].contains(o.value)),
            hasLength(4));
        final button = find.descendant(
            of: getDropdown(), matching: find.byType(DropdownButton<int>));
        await tester.tap(button);
        await tester.pumpAndSettle();
        final preset = find.text('١٠٠ تسبيحة (الورد اليومي)').last;
        await tester.tap(preset);
        await tester.pumpAndSettle();
        expect(service.tasbihTarget, 100);
        expect(tester.widget<AppDropdownField<int>>(getDropdown()).options,
            hasLength(4));
        await capture('preset100-$scale');
        for (final presetTarget in [33, 1000, 0, -1]) {
          await service.setTasbihTarget(presetTarget);
          await tester.pumpAndSettle();
          final options = tester.widget<AppDropdownField<int>>(getDropdown());
          expect(options.value, presetTarget < 0 ? 33 : presetTarget);
          expect(options.options, hasLength(4));
          expect(service.tasbihTarget, presetTarget);
          expect(service.tasbihCount, 3);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
