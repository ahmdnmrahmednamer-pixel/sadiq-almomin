// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/features/prayer/sunan_rawatib_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> loadArabicFonts() async {
    final cairoFile = File('assets/fonts/Cairo-Regular.ttf');
    if (cairoFile.existsSync()) {
      final bytes = await cairoFile.readAsBytes();
      final cairoLoader = FontLoader('Cairo');
      cairoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await cairoLoader.load();
    }
  }

  setUp(() async {
    await loadArabicFonts();
  });

  testWidgets('Test A: drive the service into writeRefusedUnreadable, expect refusal SnackBar and checkbox remains untoggled', (tester) async {
    const malformedRaw = 'malformed_sunan_rawatib_json';
    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': malformedRaw,
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });

    final keyA = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: keyA,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SunanRawatibScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byType(CheckboxListTile).first;
    expect(tileFinder, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(tileFinder).value, isFalse);

    await tester.ensureVisible(tileFinder);
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(tileFinder).value, isFalse);

    const expectedRefusalArabic =
        'تعذرت قراءة سجل السنن الرواتب المحفوظ، لذلك لم يُنفَّذ التغيير. يمكنك الاستعادة من نسخة احتياطية سابقة إن رغبت.';
    expect(find.text(expectedRefusalArabic), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sunan_rawatib_logs_v1'), equals(malformedRaw));

    await tester.runAsync(() async {
      final boundary = keyA.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final file = File(r'C:\Users\Dell\.gemini\antigravity\brain\23979155-c5d8-4466-be37-e513a0e4ad49\sunan_refusal_snackbar.png');
      await file.writeAsBytes(bytes);
    });

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
