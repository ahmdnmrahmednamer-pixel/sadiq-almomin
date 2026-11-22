import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_library_loader.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/adhkar/adhkar_library_screen.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/features/adhkar/adhkar_hub_screen.dart';

class _InvalidBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

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
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    await SettingsService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
  });
  tearDown(() {
    PrayerService.instance.stopLiveTicker();
    appRouter.go('/momen-duaa');
  });

  Future<void> mount(WidgetTester tester,
      {double width = 412,
      double scale = 1,
      bool dark = false,
      AssetBundle? bundle}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('library-pixels'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: AdhkarLibraryScreen(assetBundle: bundle),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const out = String.fromEnvironment('ADHKAR_LIBRARY_PIXELS_DIR');
    if (out.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('library-pixels')))
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
      'search and semantic activation open the source category with original text',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    expect(find.text('عدد الفئات: 132'), findsOneWidget);
    final first = find.byKey(const ValueKey('source-category-1'));
    final node = tester.getSemantics(first);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarLibraryCategoryScreen), findsOneWidget);
    final source = await AdhkarLibraryLoader.load();
    expect(find.text(source.categories.first.items.first.text), findsOneWidget);
    expect(find.text('عدد التكرار: 1'), findsWidgets);
    expect(find.byType(TabBar), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'normalized Arabic search matches category titles and item wording',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'الاستيقاظ من النوم');
    await tester.pumpAndSettle();
    expect(find.text('أذكار الاستيقاظ من النوم'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'لايوجدهذانصاختبار');
    await tester.pumpAndSettle();
    expect(find.text('لا توجد نتائج.'), findsOneWidget);
    await tester.tap(find.byTooltip('مسح البحث'));
    await tester.pumpAndSettle();
    expect(find.text('عدد الفئات: 132'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'سيد الاستغفار');
    await tester.pumpAndSettle();
    // Use an actual phrase from the pinned corpus rather than inventing a synonym.
    final source = await AdhkarLibraryLoader.load();
    final phrase = source.categories.first.items.first.text.substring(0, 24);
    await tester.enterText(find.byType(TextField), phrase);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-category-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'source and retry are explicit, and no new playback control is exposed',
      (tester) async {
    await mount(tester);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    await tester.tap(find.byTooltip('مصدر المكتبة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('هذه مرحلة النصوص.'), findsOneWidget);
    expect(find.text('https://github.com/rn0x/Adhkar-json'), findsOneWidget);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await mount(tester, bundle: _InvalidBundle());
    expect(find.text('تعذر تحميل مكتبة الأذكار.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل مكتبة الأذكار.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy reports only confirmed clipboard success', (tester) async {
    String? copied;
    var fail = false;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (fail) throw PlatformException(code: 'clipboard-unavailable');
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('source-category-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نسخ الذكر رقم 1'));
    await tester.pumpAndSettle();
    final source = await AdhkarLibraryLoader.load();
    expect(copied, source.categories.first.items.first.text);
    expect(find.text('تم نسخ الذكر.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.byTooltip('نسخ الذكر رقم 1'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر نسخ الذكر.'), findsOneWidget);
    expect(find.text('تم نسخ الذكر.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'hub semantic route opens library and returns without replacing quick reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    appRouter.go('/adhkar-hub');
    await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.lightTheme, routerConfig: appRouter));
    await tester.pumpAndSettle();
    final card = find.bySemanticsLabel('مكتبة حصن المسلم، ١٣٢ فئة');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(card);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarLibraryScreen), findsOneWidget);
    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarHubScreen), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('الأذكار المكتوبة'), findsOneWidget);
    appRouter.go('/adhkar-library');
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarLibraryScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('isolated_direct_back_home_button')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'directory source search opens the same library with semantic activation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    appRouter.go('/app-directory');
    await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.lightTheme, routerConfig: appRouter));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Adhkar-json');
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(ListTile, 'مكتبة حصن المسلم');
    expect(entry, findsOneWidget);
    final node = tester.getSemantics(entry);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarLibraryScreen), findsOneWidget);
    expect(find.text('عدد الفئات: 132'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('real fonts remain readable at320 and2x in light and dark',
      (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await mount(tester, width: 320, scale: 2, dark: dark);
      await capture(tester,
          dark ? 'library-list-dark-320-2' : 'library-list-light-320-2');
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text('مكتبة حصن المسلم'));
      expect(title.maxLines, greaterThan(1));
      if (dark) {
        await tester.tap(find.byTooltip('مصدر المكتبة'));
        await tester.pumpAndSettle();
        await capture(tester, 'library-source-dark-320-2');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('إغلاق'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'أذكار النوم');
      await tester.pumpAndSettle();
      final category = find.byKey(const ValueKey('source-category-2'));
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await capture(tester,
          dark ? 'library-reader-dark-320-2' : 'library-reader-light-320-2');
      expect(tester.takeException(), isNull);
    }
  });
}
