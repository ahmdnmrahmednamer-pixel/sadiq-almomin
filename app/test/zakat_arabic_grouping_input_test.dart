import 'package:flutter/material.dart';
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
  });
  final inputs = [
    ('Arabic grouping and decimal', '١٬٢٣٤٫٥٠'),
    ('Persian digits and Arabic grouping', '۱٬۲۳۴٫۵۰'),
    ('Western digits and Arabic grouping', '1٬234.50'),
    ('existing Western grouping', '1,234.50'),
    ('existing Arabic comma grouping', '١،٢٣٤٫٥٠'),
    ('existing Arabic decimal', '١٢٣٤٫٥٠'),
  ];
  final draft = ZakatCalculation(
      cashOnHand: 20,
      gold24Grams: 3,
      silverGrams: 6,
      tradeGoods: 50,
      debtsReceivable: 60,
      debtsPayable: 10,
      goldPricePerGram24: 4000,
      silverPricePerGram: 55,
      currency: '€',
      nisabBasis: ZakatNisabBasis.silver,
      hawlDate: DateTime(2027, 4, 15));
  testWidgets(
      'grouped inputs preserve numeric values and unrelated saved fields in eight scenarios',
      (tester) async {
    const onlyCase =
        int.fromEnvironment('ZAKAT_GROUPING_CASE', defaultValue: -1);
    var caseIndex = -1;
    for (final field in ['cash', 'gold-price', 'silver-price']) {
      for (final input in field == 'cash' ? inputs : inputs.take(1)) {
        caseIndex++;
        if (onlyCase >= 0 && onlyCase != caseIndex) continue;
        final service = ZakatService.instance;
        SharedPreferences.setMockInitialValues({});
        await SettingsService.instance.init(forceReload: true);
        await service.init(forceReload: true);
        expect(await service.updateCalculation(draft), isTrue);
        tester.view.physicalSize = const Size(420, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(fontFamily: 'Cairo'),
              home: const ZakatScreen()));
          await tester.pumpAndSettle();
          final label = field == 'cash'
              ? 'الأموال النقدية'
              : field == 'gold-price'
                  ? 'سعر جرام ذهب'
                  : 'سعر جرام الفضة';
          final target = find.byWidgetPredicate((widget) =>
              widget is TextField &&
              (widget.decoration?.labelText?.contains(label) ?? false));
          await tester.scrollUntilVisible(target, 200,
              scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          await tester.enterText(target, input.$2);
          await tester.pumpAndSettle();
          final expected = switch (field) {
            'cash' => draft.copyWith(cashOnHand: 1234.5),
            'gold-price' => draft.copyWith(goldPricePerGram24: 1234.5),
            _ => draft.copyWith(silverPricePerGram: 1234.5),
          };
          expect(service.exportData(), expected.toJson());
          await service.init(forceReload: true);
          expect(service.exportData(), expected.toJson());
          expect(tester.widget<TextField>(target).controller!.text, input.$2);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    }
  });
}
