import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/khatma_service.dart';
import 'package:almomin/features/khatma/widgets/khatma_progress_header_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final state in ['active', 'behind', 'complete']) {
        testWidgets(
            'Khatma header $state retains readable content at $width/$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Cairo')
                ..addFont(Future.value(ByteData.sublistView(
                    File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
              .load();
          const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
          if (icons.isNotEmpty)
            await (FontLoader('MaterialIcons')
                  ..addFont(Future.value(
                      ByteData.sublistView(File(icons).readAsBytesSync()))))
                .load();
          final semantics = tester.ensureSemantics();
          final plan = KhatmaPlan(
              id: 'header',
              title: 'ختمة القرآن الكريم والسكينة اليومية',
              targetDays: state == 'active' ? 730 : 30,
              startDate: state == 'behind'
                  ? DateTime.now().subtract(const Duration(days: 10))
                  : DateTime.now(),
              currentPage: state == 'complete' ? 604 : 1,
              isCompleted: state == 'complete',
              reminderEnabled: false);
          final boundary = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(fontFamily: 'Cairo'),
                  builder: (c, child) => MediaQuery(
                      data: MediaQuery.of(c)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: Scaffold(
                      body: Directionality(
                          textDirection: TextDirection.rtl,
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: KhatmaProgressHeaderCard(plan: plan)))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final title = tester.widget<Text>(find.text(plan.title));
          expect(title.overflow, isNot(TextOverflow.ellipsis));
          expect(
              MediaQuery.textScalerOf(tester.element(find.text(plan.title)))
                  .scale(16),
              16 * scale);
          for (final text in ['المتبقي', 'ورد اليوم', 'الأيام المتبقية']) {
            final target = find.text(text);
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            final rect = tester.getRect(target);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          if (state != 'active') {
            final action = find.text(state == 'complete'
                ? 'دعاء الختم'
                : 'تطبيق الجدولة التعويضية الآن');
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            expect(
                tester
                    .getSemantics(action)
                    .getSemanticsData()
                    .hasAction(ui.SemanticsAction.tap),
                isTrue);
          }
          expect(tester.takeException(), isNull);
          const directory = String.fromEnvironment('KHATMA_HEADER_PIXELS');
          if (directory.isNotEmpty)
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$directory/$state-$width-$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          if (directory.isNotEmpty) {
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$directory/top-$state-$width-$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          semantics.dispose();
        });
      }
    }
  }
}
