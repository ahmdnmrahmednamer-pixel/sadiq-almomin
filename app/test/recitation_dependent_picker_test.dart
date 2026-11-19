import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'package:almomin/features/audio/widgets/recitation_reciter_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const catalog = SettingsService.availableReciters;
  Finder fields() => find.byType(DropdownButtonFormField<String>);

  Future<void> fonts() async {
    for (final family in ['Amiri', 'Cairo']) {
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
  }

  Future<void> capture(
      WidgetTester tester, GlobalKey boundary, String name) async {
    const dir = String.fromEnvironment('RECITATION_PIXELS_DIR');
    if (dir.isEmpty) return;
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(WidgetTester tester,
      {ReciterInfo? initial,
      ValueChanged<ReciterInfo>? changed,
      VoidCallback? preview,
      bool isPreviewing = false,
      Size size = const Size(360, 800),
      double scale = 1,
      GlobalKey? boundary,
      bool fullPage = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    ReciterInfo selected = initial ?? SettingsService.instance.currentReciter;
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child:
              Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: fullPage
            ? const AudioScreen()
            : Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(builder: (context, setState) {
                    return RecitationReciterSelector(
                      reciter: selected,
                      isPreviewing: isPreviewing,
                      onChanged: (r) {
                        setState(() => selected = r);
                        changed?.call(r);
                      },
                      onPreview: preview ?? () {},
                    );
                  }),
                ),
              ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> chooseStyle(WidgetTester tester, String style) async {
    await tester.tap(fields().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(style).last);
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    await fonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
  });

  testWidgets(
      'all catalog categories filter exact reciter IDs without silently changing saved selection',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <String>[];
    await mount(tester, changed: (r) => changes.add(r.id));
    expect(fields(), findsNWidgets(2));
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>).first)
            .items!
            .map((i) => i.value)
            .toSet(),
        catalog.map((r) => r.style).toSet());
    for (final style in catalog.map((r) => r.style).toSet()) {
      await chooseStyle(tester, style);
      final field =
          tester.widget<DropdownButtonFormField<String>>(fields().last);
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byType(DropdownButton<String>).last)
              .items!
              .map((i) => i.value),
          catalog.where((r) => r.style == style).map((r) => r.id));
      if (style != catalog.first.style) {
        expect(field.initialValue, isNull);
        expect(find.text('اختر القارئ'), findsOneWidget);
        expect(
            tester
                .widget<FilledButton>(
                    find.byKey(const ValueKey('recitation_preview_button')))
                .onPressed,
            isNull);
      }
    }
    expect(changes, isEmpty);
    expect(SettingsService.instance.selectedReciterId, catalog.first.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'explicit matching selection persists and reopening derives its style; preview remains actionable',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int previews = 0;
    await mount(tester,
        changed: (r) => SettingsService.instance.setSelectedReciter(r.id),
        preview: () => previews++);
    await chooseStyle(tester, 'مجود');
    await tester.tap(fields().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('محمد صديق المنشاوي').last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.selectedReciterId, 'minshawi_mujawwad');
    await tester.tap(find.byKey(const ValueKey('recitation_preview_button')));
    expect(previews, 1);
    await tester.pumpWidget(const SizedBox());
    await SettingsService.instance.init(forceReload: true);
    await mount(tester);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(fields().first)
            .initialValue,
        'مجود');
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(fields().last)
            .initialValue,
        'minshawi_mujawwad');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'actual inline selector persists explicit choice without starting surah playback',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, fullPage: true);
    await chooseStyle(tester, 'مجود');
    expect(SettingsService.instance.selectedReciterId, catalog.first.id);
    await tester.tap(fields().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('محمد صديق المنشاوي').last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.selectedReciterId, 'minshawi_mujawwad');
    expect(
        tester
            .widget<RecitationReciterSelector>(
                find.byType(RecitationReciterSelector))
            .reciter
            .id,
        'minshawi_mujawwad');
    expect(find.byTooltip('إيقاف التلاوة'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await mount(tester, fullPage: true);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(fields().first)
            .initialValue,
        'مجود');
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(fields().last)
            .initialValue,
        'minshawi_mujawwad');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'native dropdown semantics opens category then matching reciter menu, no chips or long count labels',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    final category = tester.semantics
        .simulatedAccessibilityTraversal()
        .firstWhere((n) =>
            n.getSemanticsData().label.contains('نوع التلاوة') &&
            n.getSemanticsData().hasAction(SemanticsAction.tap));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(category.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.text('مجود'), findsWidgets);
    final choice = tester.semantics
        .simulatedAccessibilityTraversal()
        .firstWhere((n) =>
            n.getSemanticsData().label == 'مجود' &&
            n.getSemanticsData().hasAction(SemanticsAction.tap));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(choice.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    final reciter = tester.semantics
        .simulatedAccessibilityTraversal()
        .firstWhere((n) =>
            n.getSemanticsData().label.contains('القارئ') &&
            n.getSemanticsData().hasAction(SemanticsAction.tap));
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(reciter.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.text('محمد صديق المنشاوي'), findsWidgets);
    expect(find.text('رعد محمد الكردي'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.textContaining('٦١'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets(
      'active preview can still be stopped while browsing another category',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int stops = 0;
    await mount(tester, isPreviewing: true, preview: () => stops++);
    await chooseStyle(tester, 'مجود');
    expect(find.text('إيقاف العينة'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recitation_preview_button')));
    expect(stops, 1);
    expect(SettingsService.instance.selectedReciterId, catalog.first.id);
  });

  testWidgets(
      'long catalog names and menus fit real-font narrow layouts at 1x and 2x',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longest =
        catalog.reduce((a, b) => a.nameAr.length > b.nameAr.length ? a : b);
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      for (final scale in [1.0, 2.0]) {
        final key = GlobalKey();
        await mount(tester,
            size: size, scale: scale, initial: longest, boundary: key);
        expect(tester.takeException(), isNull);
        for (final field in fields().evaluate()) {
          final rect = tester.getRect(find.byWidget(field.widget));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
        }
        await capture(
            tester, key, 'selector_${size.width.toInt()}_${scale.toInt()}x');
        await tester.tap(fields().last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
            tester, key, 'menu_${size.width.toInt()}_${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
      'actual audio page keeps both dependent selectors, sleep timer and download entry at narrow sizes',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 640),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      for (final scale in [1.0, 2.0]) {
        final key = GlobalKey();
        await mount(tester,
            size: size, scale: scale, boundary: key, fullPage: true);
        expect(find.byType(RecitationReciterSelector), findsOneWidget);
        expect(find.text('التلاوات'), findsOneWidget);
        expect(find.byTooltip('مؤقت النوم'), findsOneWidget);
        expect(find.byTooltip('التنزيلات'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
            tester, key, 'page_${size.width.toInt()}_${scale.toInt()}x');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -340));
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsWidgets);
        final firstRow = find.byType(ListTile).first;
        await tester.ensureVisible(firstRow);
        await tester.pumpAndSettle();
        expect(tester.getRect(firstRow).bottom, lessThanOrEqualTo(size.height));
        await capture(
            tester, key, 'surahs_${size.width.toInt()}_${scale.toInt()}x');
        await tester.tap(find.byTooltip('تغيير القارئ'));
        await tester.pumpAndSettle();
        expect(
            find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(RecitationReciterSelector)),
            findsOneWidget);
        final modal =
            find.descendant(of: find.byType(BottomSheet), matching: fields());
        await tester.tap(modal.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('مجود').last);
        await tester.pumpAndSettle();
        final modalReciter =
            tester.widget<DropdownButtonFormField<String>>(modal.last);
        expect(modalReciter.initialValue, isNull);
        expect(SettingsService.instance.selectedReciterId, catalog.first.id);
        expect(tester.takeException(), isNull);
        await capture(
            tester, key, 'modal_${size.width.toInt()}_${scale.toInt()}x');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });
}
