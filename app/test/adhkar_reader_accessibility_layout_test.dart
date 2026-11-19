import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/adhkar/adhkar_screen.dart';

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
    SharedPreferences.setMockInitialValues(
        {'has_completed_onboarding': true, 'show_tutorial_screens': false});
    await SettingsService.instance.init(forceReload: true);
    await AdhkarService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
  });
  Future<void> mount(WidgetTester tester,
      {double width = 412, double scale = 1, bool dark = false}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('entry-pixels'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: const AdhkarScreen(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const out = String.fromEnvironment('ADHKAR_READER_PIXELS_DIR');
    if (out.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('entry-pixels')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      File('$out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'loaded font entry and destination pixels at small and large text',
      (tester) async {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await mount(tester, width: width, scale: scale);
        expect(find.byType(AdhkarScreen), findsOneWidget);
        await capture(tester, 'reader-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
      'large text category labels retain semantic selection and actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, width: 320, scale: 2);
    final category = AdhkarService.instance.categories[1];
    final tab = find.widgetWithText(Tab, category.title);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(tab);
    expect(node.getSemanticsData().label, contains(category.title));
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'استمع إلى أذكار المساء'),
        findsNothing);
    expect(find.byTooltip('المكتبة الصوتية للأذكار والأذان'), findsNothing);
    expect(find.byTooltip('السبحة الإلكترونية'), findsOneWidget);
    await capture(tester, 'evening-320-2');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets(
      '2x counter semantic activation increments and reset preserves original text',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, width: 320, scale: 2);
    final item = AdhkarService.instance.categories.first.items.first;
    final originalText = item.text;
    final counterWidget = find
        .byWidgetPredicate((widget) =>
            widget is Semantics &&
            (widget.properties.label
                    ?.startsWith('اضغط للعد: 0 من ${item.targetCount}،') ??
                false))
        .first;
    await tester.ensureVisible(counterWidget);
    await tester.pumpAndSettle();
    await capture(tester, 'counter-320-2');
    final node = tester.getSemantics(counterWidget);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(item.currentCount, 1);
    expect(item.text, originalText);
    expect(find.byTooltip('نسخ الذكر'), findsWidgets);
    expect(find.byTooltip('مشاركة'), findsWidgets);
    final reset = find.byTooltip('تصفير العداد').first;
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(item.currentCount, 0);
    expect(item.text, originalText);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets('dark 2x completed counter and category reset confirmation',
      (tester) async {
    await mount(tester, width: 320, scale: 2, dark: true);
    final category = AdhkarService.instance.categories.first;
    final item = category.items.first;
    final original = item.text;
    AdhkarService.instance.incrementDhikr(item);
    await tester.pumpAndSettle();
    final counter = find
        .byWidgetPredicate((widget) =>
            widget is Semantics &&
            (widget.properties.label?.startsWith('اكتمل بحمد الله') ?? false))
        .first;
    await tester.ensureVisible(counter);
    await tester.pumpAndSettle();
    await capture(tester, 'completed-dark-320-2');
    expect(item.isCompleted, isTrue);
    expect(item.text, original);
    final list = Scrollable.of(tester.element(counter));
    list.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('إعادة ضبط كل أذكار هذه القائمة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(item.isCompleted, isTrue);
    await tester.tap(find.byTooltip('إعادة ضبط كل أذكار هذه القائمة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(item.currentCount, 0);
    expect(item.text, original);
    expect(tester.takeException(), isNull);
  });
  testWidgets('written reader has no audio player or mixed sheet entry',
      (tester) async {
    await mount(tester, width: 320, scale: 2);
    expect(find.byTooltip('المكتبة الصوتية للأذكار والأذان'), findsNothing);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            (widget.properties.label?.startsWith('استمع إلى') ?? false)),
        findsNothing);
    expect(find.byTooltip('إعادة ضبط كل أذكار هذه القائمة'), findsWidgets);
    expect(AdhkarService.instance.categories.length, 10);
  });
}
