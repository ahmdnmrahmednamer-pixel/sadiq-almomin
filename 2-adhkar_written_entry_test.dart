import 'dart:io';
import 'package:almomin/features/settings/settings_screen.dart';
import 'package:almomin/features/adhkar/tasbih_screen.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/adhkar/adhkar_screen.dart';
import 'package:almomin/features/adhkar/adhkar_hub_screen.dart';

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
  tearDown(() {
    PrayerService.instance.stopLiveTicker();
    appRouter.go('/momen-duaa');
  });
  Future<void> mount(WidgetTester tester,
      {double width = 412, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/adhkar-hub');
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('entry-pixels'),
        child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const out = String.fromEnvironment('ADHKAR_ENTRY_PIXELS_DIR');
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
      'written card opens actual indexed reader, preserves corpus and progress, returns to single hub',
      (tester) async {
    await mount(tester);
    final before = AdhkarService.instance.categories
        .map((c) => c.items.map((i) => i.text).toList())
        .toList();
    final card = find.text('الأذكار المكتوبة');
    final target = find.ancestor(of: card, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester
        .tap(find.ancestor(of: card, matching: find.byType(InkWell)).first);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarScreen), findsOneWidget);
    expect(
        GoRouterState.of(tester.element(find.byType(AdhkarScreen)))
            .uri
            .toString(),
        '/adhkar?index=0');
    expect(find.byType(AdhkarHubScreen), findsNothing);
    expect(AdhkarService.instance.categories, hasLength(10));
    expect(
        AdhkarService.instance.categories
            .map((c) => c.items.map((i) => i.text).toList())
            .toList(),
        before);
    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarHubScreen), findsOneWidget);
  });
  testWidgets(
      'semantic activation opens written reader rather than another hub',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    final node = tester
        .getSemantics(find.bySemanticsLabel(RegExp('^الأذكار المكتوبة،.*')));
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarScreen), findsOneWidget);
    expect(
        GoRouterState.of(tester.element(find.byType(AdhkarScreen)))
            .uri
            .toString(),
        '/adhkar?index=0');
    expect(find.byType(AdhkarHubScreen), findsNothing);
    semantics.dispose();
  });
  testWidgets(
      'loaded font entry and destination pixels at small and large text',
      (tester) async {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await mount(tester, width: width, scale: scale);
        final card = find.text('الأذكار المكتوبة');
        final target = find.ancestor(of: card, matching: find.byType(InkWell)).first;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await capture(tester, 'hub-${width.toInt()}-${scale.toInt()}');
        await tester
            .tap(find.ancestor(of: card, matching: find.byType(InkWell)).first);
        await tester.pumpAndSettle();
        expect(find.byType(AdhkarScreen), findsOneWidget);
        await capture(tester, 'reader-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('hub title wraps without truncation at narrow and enlarged text',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await mount(tester, width: width, scale: scale);
        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text('أُنس الذاكرين والتسبيح'),
        );
        expect(title, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(paragraph.didExceedMaxLines, isFalse);
        final titleRect = tester.getRect(title);
        final appBarRect = tester.getRect(find.byType(AppBar));
        expect(titleRect.left, greaterThanOrEqualTo(appBarRect.left));
        expect(titleRect.right, lessThanOrEqualTo(appBarRect.right));
        expect(titleRect.top, greaterThanOrEqualTo(appBarRect.top));
        expect(titleRect.bottom, lessThanOrEqualTo(appBarRect.bottom));
        expect(paragraph.textScaler.scale(1), scale);
        expect(find.bySemanticsLabel('أُنس الذاكرين والتسبيح'), findsOneWidget);
        for (final tooltip in ['open navigation menu', 'مواقيت تنبيهات الأذكار', 'السبحة الإلكترونية']) {
          final button = find.byTooltip(tooltip);
          expect(button.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(button);
          expect(bounds.top, greaterThanOrEqualTo(appBarRect.top));
          expect(bounds.bottom, lessThanOrEqualTo(appBarRect.bottom));
          expect(bounds.overlaps(titleRect), isFalse);
        }
        await capture(tester, 'title-${width.toInt()}-${scale.toInt()}');
        expect(tester.takeException(), isNull);
      }
    }
    await mount(tester, width: 320, scale: 1);
    await tester.tap(find.byTooltip('open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('مواقيت تنبيهات الأذكار'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(GoRouterState.of(tester.element(find.byType(SettingsScreen))).uri.path, '/settings');
    appRouter.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('السبحة الإلكترونية'));
    await tester.pumpAndSettle();
    expect(find.byType(TasbihScreen), findsOneWidget);
    expect(GoRouterState.of(tester.element(find.byType(TasbihScreen))).uri.path, '/tasbih');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

}
