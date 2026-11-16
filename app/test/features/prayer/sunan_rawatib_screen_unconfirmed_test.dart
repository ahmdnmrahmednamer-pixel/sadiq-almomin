// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';
import 'package:almomin/features/prayer/sunan_rawatib_screen.dart';

class UnconfirmedStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;

  UnconfirmedStorePlatform(this.delegate);

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) =>
      delegate.getAllWithParameters(parameters);

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key.endsWith('sunan_rawatib_logs_v1')) {
      return Future.value(false);
    }
    return delegate.setValue(valueType, key, value);
  }
}

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

  testWidgets('Test B: drive the service into writeUnconfirmed, expect unconfirmed SnackBar and checkbox consistent with published state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final originalPlatform = SharedPreferencesStorePlatform.instance;
    final mockPlatform = UnconfirmedStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });

    final keyB = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: keyB,
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

    const expectedUnconfirmedArabic =
        'تعذر تأكيد حفظ سجل السنن الرواتب لليوم. أعد المحاولة لاحقًا.';
    expect(find.text(expectedUnconfirmedArabic), findsOneWidget);

    final hostEntries = await originalPlatform.getAll();
    expect(hostEntries.keys.where((k) => k.endsWith('sunan_rawatib_logs_v1')), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sunan_rawatib_logs_v1'), isNull);

    await tester.runAsync(() async {
      final boundary = keyB.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final file = File(r'C:\Users\Dell\.gemini\antigravity\brain\23979155-c5d8-4466-be37-e513a0e4ad49\sunan_unconfirmed_snackbar.png');
      await file.writeAsBytes(bytes);
    });

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
