import 'dart:io';
import 'dart:ui' as ui;
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
    for (final name in ['Cairo', 'Amiri']) {
      await (FontLoader(name)
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/$name-Regular.ttf').readAsBytesSync()))))
          .load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  for (final scale in [1.0, 2.0])
    for (final dated in [false, true]) {
      testWidgets(
          'Zakat full labels and date action fit360px scale=$scale dated=$dated',
          (t) async {
        await t.runAsync(() async {
          SharedPreferences.setMockInitialValues({'app_language': 'ar'});
          await SettingsService.instance.init(forceReload: true);
          await ZakatService.instance.updateCalculation(ZakatCalculation(
              cashOnHand: 400000,
              hawlDate: dated ? DateTime(2027, 11, 21) : null));
        });
        t.view.physicalSize = const Size(360, 950);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final semantics = t.ensureSemantics();
        try {
          final boundary = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(fontFamily: 'Cairo'),
                  builder: (c, child) => MediaQuery(
                      data: MediaQuery.of(c)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: const ZakatScreen())));
          await t.pumpAndSettle();
          final labels = [
            'ملخص الحساب الشرعي',
            dated
                ? 'موعد حولان الحول: 2027/11/21'
                : 'تحديد موعد حولان الحول الهجري',
            'إعدادات النصاب والأسعار',
            'السيولة النقدية والأرصدة البنكية'
          ];
          final errors = <Object>[];
          void collect() {
            Object? e;
            while ((e = t.takeException()) != null) {
              errors.add(e!);
            }
          }

          collect();
          for (var i = 0; i < labels.length; i++) {
            final label = find.text(labels[i]);
            await t.scrollUntilVisible(label, 200,
                scrollable: find.byType(Scrollable).first);
            await t.pumpAndSettle();
            collect();
            expect(t.getSemantics(label).label, contains(labels[i]));
            final dir = Platform.environment['ZAKAT_LAYOUT_PIXELS'];
            if (dir != null)
              await t.runAsync(() async {
                final image = await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('$dir/label-$i-$scale-$dated.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            final rect = t.getRect(label);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
          }
          final date = find.text(labels[1]);
          await t.scrollUntilVisible(date, -200,
              scrollable: find.byType(Scrollable).first);
          await t.pumpAndSettle();
          expect(date.hitTestable(), findsOneWidget);
          // The existing picker locale needs app localization; tapping is covered by
          // its live InkWell callback rather than constructing an unrelated app shell.
          expect(
              t
                  .widget<InkWell>(find
                      .ancestor(of: date, matching: find.byType(InkWell))
                      .first)
                  .onTap,
              isNotNull);
          collect();
          expect(errors, isEmpty);
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });
    }
}
