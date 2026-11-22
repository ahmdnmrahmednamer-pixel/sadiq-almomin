import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/adhkar/widgets/tasbih_custom_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Cairo', 'Amiri']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-Regular.ttf')))
          .load();
    }
  });
  testWidgets(
      'invalid custom target stays open with accessible error; valid digits save and cancel preserves count',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'tasbih_target': 7, 'tasbih_count': 3, 'tasbih_haptic': false});
    await SettingsService.instance.init(forceReload: true);
    final service = AdhkarService.instance;
    await service.init(forceReload: true);
    final controller = TextEditingController();
    final semantics = tester.ensureSemantics();
    final boundary = GlobalKey();
    tester.view.physicalSize = const Size(412, 950);
    tester.view.devicePixelRatio = 1;
    const error = 'أدخل عددًا صحيحًا أكبر من صفر';
    Future<void> capture(String name) async {
      final dir = Platform.environment['TARGET_VALIDATION_PIXELS'];
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
                home: Builder(
                    builder: (context) => Scaffold(
                        body: Center(
                            child: FilledButton(
                                onPressed: () => showTasbihCustomTargetDialog(
                                    context,
                                    controller: controller),
                                child: const Text('فتح'))))))));
        await tester.tap(find.text('فتح'));
        await tester.pumpAndSettle();
        await capture('valid-$scale');
        for (final value in [
          '',
          '0',
          '-5',
          'abc',
          '1.5',
          '999999999999999999999999999'
        ]) {
          await tester.enterText(find.byType(TextField), value);
          await tester.tap(find.text('حفظ'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget,
              reason: 'Invalid $value must not dismiss as if saved');
          expect(find.text(error), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp(error)), findsWidgets);
          final errorNode = tester.getSemantics(find.text(error));
          expect(errorNode.getSemanticsData().flagsCollection.isLiveRegion,
              isTrue);
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(error));
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(service.tasbihTarget, 7);
          expect(service.tasbihCount, 3);
          expect(
              (await SharedPreferences.getInstance()).getInt('tasbih_target'),
              7);
          expect(tester.takeException(), isNull);
        }
        await capture('invalid-$scale');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getBottomRight(find.text(error)).dy, lessThan(650));
        expect(tester.getBottomRight(find.text('حفظ')).dy, lessThan(650));
        await capture('keyboard-$scale');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '٥٧');
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await service.init(forceReload: true);
        expect(service.tasbihTarget, 57);
        expect(service.tasbihCount, 3);
        for (final value in ['۱۲۳', '100', '1,000']) {
          await tester.tap(find.text('فتح'));
          await tester.pumpAndSettle();
          expect(find.text(error), findsNothing);
          await tester.enterText(find.byType(TextField), value);
          await tester.tap(find.text('حفظ'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(service.tasbihTarget,
              {'۱۲۳': 123, '100': 100, '1,000': 1000}[value]);
        }
        await tester.tap(find.text('فتح'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '0');
        await tester.tap(find.text('حفظ'));
        await tester.pumpAndSettle();
        expect(find.text(error), findsOneWidget);
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.tasbihTarget, 1000);
        expect(service.tasbihCount, 3);
        await tester.tap(find.text('فتح'));
        await tester.pumpAndSettle();
        expect(find.text(error), findsNothing);
        expect(controller.text, '1000');
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        await service.setTasbihTarget(0);
        await tester.tap(find.text('فتح'));
        await tester.pumpAndSettle();
        expect(controller.text, '33');
        expect(find.text(error), findsNothing);
        await tester.tap(find.text('إلغاء'));
        await tester.pumpAndSettle();
        expect(service.tasbihTarget, 0);
        expect(service.tasbihCount, 3);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      semantics.dispose();
      controller.dispose();
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
