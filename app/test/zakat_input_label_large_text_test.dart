import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/models/zakat_calculation.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/zakat_service.dart';
import 'package:almomin/features/zakat/zakat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
    await loader.load();
    final icons = Platform.environment['MATERIAL_ICONS_FONT'];
    if (icons != null)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  testWidgets(
      'large Zakat field labels wrap fully and retain editable field semantics',
      (tester) async {
    final draft = ZakatCalculation(
        cashOnHand: 400000,
        gold24Grams: 24,
        gold21Grams: 21,
        gold18Grams: 18,
        silverGrams: 50,
        tradeGoods: 777,
        debtsReceivable: 888,
        debtsPayable: 999,
        goldPricePerGram24: 4444,
        silverPricePerGram: 55,
        hawlDate: DateTime(2027, 4, 15));
    final fields = <String, String>{
      'الأموال النقدية والودائع والحسابات الجارية (ج.م)': '400000',
      'ذهب عيار 24 (جرام)': '24',
      'ذهب عيار 21 (جرام)': '21',
      'ذهب عيار 18 (جرام)': '18',
      'فضة خالصة (جرام)': '50',
      'قيمة البضائع والمخزون المعد للبيع بسعر السوق الحالي (ج.م)': '777',
      'ديون مرجوة السداد لك عند الآخرين (تضاف للوعاء)': '888',
      'ديون والتزامات حالّة واجبة السداد عليك فوراً (تخصم من الوعاء)': '999',
      'سعر جرام ذهب 24 (ج.م)': '4444',
      'سعر جرام الفضة (ج.م)': '55',
    };
    final semantics = tester.ensureSemantics();
    try {
      for (final width in [360.0, 412.0]) {
        for (final scale in [2.0, 1.0]) {
          SharedPreferences.setMockInitialValues({});
          await SettingsService.instance.init(forceReload: true);
          final service = ZakatService.instance;
          await service.init(forceReload: true);
          expect(await service.updateCalculation(draft), isTrue);
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          final boundary = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(fontFamily: 'Cairo'),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: const ZakatScreen())));
          await tester.pumpAndSettle();
          for (final entry in fields.entries) {
            final field = find.byWidgetPredicate((widget) =>
                widget is TextField && widget.controller?.text == entry.value);
            await tester.scrollUntilVisible(field,
                entry.value == '4444' || entry.value == '55' ? -200 : 200,
                scrollable: find.byType(Scrollable).first, maxScrolls: 40);
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
            final label = find.text(entry.key);
            final dir = Platform.environment['ZAKAT_LABEL_PIXELS'];
            if (dir != null &&
                (entry.value == '400000' ||
                    entry.value == '24' ||
                    entry.value == '999' ||
                    entry.value == '4444')) {
              await tester.ensureVisible(label);
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final image = await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('$dir/field-${entry.value}-$width-$scale.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
            }
            expect(label, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(label);
            if (scale == 2) {
              expect(paragraph.didExceedMaxLines, isFalse,
                  reason: '${entry.key} at $width/$scale must not ellipsize');
              expect(tester.getRect(label).left, greaterThanOrEqualTo(0));
              expect(tester.getRect(label).right, lessThanOrEqualTo(width));
            }
            await tester.tap(field);
            await tester.pumpAndSettle();
            final node = tester.getSemantics(find.descendant(
                of: field, matching: find.byType(EditableText)));
            expect(node.label, contains(entry.key));
            expect(node.flagsCollection.isTextField, isTrue);
            expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.setText),
                isTrue);
            final editable =
                find.descendant(of: field, matching: find.byType(EditableText));
            final state = tester.state<EditableTextState>(editable);
            final jsonKey = draft
                .toJson()
                .entries
                .firstWhere((item) =>
                    item.value is num &&
                    item.value.toString() == '${entry.value}.0')
                .key;
            final changed = double.parse(entry.value) + 0.5;
            await tester.enterText(editable, changed.toString());
            await tester.pumpAndSettle();
            final expected = draft.toJson()..[jsonKey] = changed;
            expect(service.exportData(), expected);
            await service.init(forceReload: true);
            expect(service.exportData(), expected);
            await tester.enterText(
                find.byWidgetPredicate((widget) =>
                    widget is EditableText &&
                    widget.controller == state.widget.controller),
                entry.value);
            await tester.pumpAndSettle();
            expect(service.exportData(), draft.toJson());
          }
          await service.init(forceReload: true);
          expect(service.exportData(), draft.toJson());
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
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
