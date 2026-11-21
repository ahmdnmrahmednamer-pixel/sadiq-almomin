import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/khatma_service.dart';
import 'package:almomin/features/khatma/widgets/khatma_progress_header_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('persisted 730 day plan renders duration and one page daily pace',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = KhatmaPlan(
        id: 'saved',
        title: 'ختمة طويلة',
        targetDays: 730,
        startDate: DateTime.now(),
        reminderEnabled: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_khatma_plan', jsonEncode(original.toJson()));
    final plan = KhatmaPlan.fromJson(
        jsonDecode(prefs.getString('active_khatma_plan')!)
            as Map<String, dynamic>);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader('Cairo')
          ..addFont(Future.value(ByteData.sublistView(
              File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
        .load();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Cairo'),
            home: Scaffold(
                body: Directionality(
                    textDirection: TextDirection.rtl,
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: KhatmaProgressHeaderCard(plan: plan)))))));
    await tester.pumpAndSettle();
    expect(find.text('المدة: ٧٣٠ يوماً'), findsOneWidget);
    expect(find.text('١ صفحة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    const directory = String.fromEnvironment('KHATMA_DURATION_PIXELS');
    if (directory.isNotEmpty)
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$directory/long-duration-card.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
