import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/adhkar/widgets/tasbih_stats_bar.dart';
import 'package:almomin/features/adhkar/widgets/tasbih_main_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/$family-Regular.ttf').readAsBytesSync())))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(
        File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf').readAsBytesSync())))).load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('TASBIH_PIXELS');
    if (dir.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('tasbih-pixels')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }
  testWidgets('large text counter and stats remain reachable with actual taps', (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    await SettingsService.instance.init(forceReload: true);
    await AdhkarService.instance.init(forceReload: true);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final viewport in [const Size(320, 915), const Size(360, 640), const Size(412, 915)]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
        tester.view.physicalSize = viewport;
        appRouter.go('/tasbih');
        await tester.pumpWidget(RepaintBoundary(key: const ValueKey('tasbih-pixels'), child: MaterialApp.router(
          theme: AppTheme.lightTheme, routerConfig: appRouter,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),child: child!),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final title = find.text('مسبحة الأُنس والتسبيح');
        expect(title, findsOneWidget);
        final titleParagraph = tester.renderObject<RenderParagraph>(title);
        expect(titleParagraph.didExceedMaxLines, isFalse);
        expect(titleParagraph.textScaler.scale(1), scale);
        await capture(tester, 'top-${viewport.width.toInt()}-${viewport.height.toInt()}-${scale.toInt()}');
        await tester.tap(find.byTooltip('صوت التسبيح مفعل'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        final counter = find.byKey(const Key('tasbih_main_button'));
        final valueText = find.descendant(of: counter,
            matching: find.text('${AdhkarService.instance.tasbihCount}'));
        await Scrollable.ensureVisible(tester.element(valueText), alignment: 0.5);
        await tester.pumpAndSettle();
        await capture(tester, 'counter-${viewport.width.toInt()}-${viewport.height.toInt()}-${scale.toInt()}');
        expect(valueText.hitTestable(), findsOneWidget);
        expect(tester.getSemantics(counter).getSemanticsData()
            .hasAction(ui.SemanticsAction.tap), isTrue);
        expect(tester.renderObject<RenderParagraph>(valueText).textScaler.scale(1), scale);
        final before = AdhkarService.instance.tasbihCount;
        await tester.tapAt(tester.getCenter(valueText)); await tester.pumpAndSettle();
        expect(AdhkarService.instance.tasbihCount, before + 1);
        final counterNode = tester.getSemantics(counter);
        tester.binding.pipelineOwner.semanticsOwner!
            .performAction(counterNode.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(AdhkarService.instance.tasbihCount, before + 2);
        final stats = find.byType(TasbihStatsBar);
        for (final label in ['الدورات المكتملة', 'مجموع اليوم']) {
          final text = find.descendant(of: stats, matching: find.text(label));
          await Scrollable.ensureVisible(tester.element(text), alignment: 0.5);
          await tester.pumpAndSettle();
          final labelRect = tester.getRect(text);
          final scroll = find.byKey(const ValueKey('tasbih_accessible_scroll'));
          final visibleTop = scroll.evaluate().isEmpty ? 0.0 : tester.getRect(scroll).top;
          expect(labelRect.top, greaterThanOrEqualTo(visibleTop));
          expect(labelRect.bottom, lessThanOrEqualTo(viewport.height));
          expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
        }
        await Scrollable.ensureVisible(tester.element(stats), alignment: 1); await tester.pumpAndSettle();
        final rect = tester.getRect(stats);
        expect(rect.bottom, lessThanOrEqualTo(viewport.height));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(find.byTooltip('تصفير العداد').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'stats-${viewport.width.toInt()}-${viewport.height.toInt()}-${scale.toInt()}');
        await tester.tap(find.byTooltip('تصفير العداد'));
        await tester.pumpAndSettle();
        expect(find.text('تصفير عداد الجلسة'), findsOneWidget);
        await tester.tap(find.text('تصفير'));
        await tester.pumpAndSettle();
        expect(AdhkarService.instance.tasbihCount, 0);
        expect(tester.takeException(), isNull);
      }
    }
    semantics.dispose();
  });
  testWidgets('large counter preserves finite and unlimited target content', (tester) async {
    tester.view.physicalSize = const Size(320, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final target in [0, 1000]) {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
        home: MediaQuery(data: const MediaQueryData(size: Size(320, 915),
          textScaler: TextScaler.linear(3)), child: Scaffold(
          body: SingleChildScrollView(child: TasbihMainButton(
            onTap: () => taps++, scaleAnimation: const AlwaysStoppedAnimation(1),
            count: 9999, target: target, currentInCycle: 999, progress: 0.999,
            isDark: false, buttonSize: 288, ringSize: 266))))));
      await tester.pumpAndSettle();
      final count = find.text('9999');
      await tester.ensureVisible(count); await tester.pumpAndSettle();
      await tester.tap(count); await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.text(target == 0 ? 'تسبيح مفتوح' : 'الدورة: 999 / 1000'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), target == 0 ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

}
