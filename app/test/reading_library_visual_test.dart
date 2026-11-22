import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/ui/portal_category_card.dart';
import 'package:almomin/features/library/islamic_library_screen.dart';

void main() {
  testWidgets('library removes duplicate book cards, preserves existing sections and independent downloaded-book reader', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fontPath = Platform.environment['READING_TEST_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final iconPath = Platform.environment['READING_TEST_ICON_FONT'];
        if (iconPath != null) {
          await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await File(iconPath).readAsBytes())))).load();
        }
        for (final family in ['ArabicTest', 'Amiri']) {
          await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(await File(fontPath).readAsBytes())))).load();
        }
      });
    }
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'ArabicTest'),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      home: const IslamicLibraryScreen(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('رياض الصالحين وصحيح الحديث'), findsNothing);
    expect(find.text('المتون العلمية وأحكام التجويد'), findsNothing);
    expect(find.text('متابعة حفظ المتون العلمية'), findsNothing);
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final children = (list.childrenDelegate as SliverChildListDelegate).children;
    expect(children.whereType<PortalCategoryCard>().map((card) => card.title),
        equals(['المكتبة الشاملة', 'قارئ الكتب', 'قصص الأنبياء', 'المواريث', 'الحج والعمرة', 'التراث المصري']));
    expect(tester.takeException(), isNull);
    if (fontPath != null) {
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/next-library-large-text.png').writeAsBytes(data!.buffer.asUint8List());
      });
    }
  });
}
