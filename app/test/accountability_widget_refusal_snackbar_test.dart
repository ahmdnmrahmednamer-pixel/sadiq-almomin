// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';
import 'package:almomin/features/mushaf/tadabbur_journal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkbox unchanged on refusal + SnackBar with exact Arabic copy', (tester) async {
    const malformedRaw = 'malformed_accountability_json';
    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': malformedRaw,
    });

    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const TadabburJournalScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify first checkbox tile is initially unchecked
    final tileFinder = find.byType(CheckboxListTile).first;
    expect(tileFinder, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(tileFinder).value, isFalse);

    // Tap to trigger toggle on corrupt host
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    // Checkbox remains unchecked (derived from published state only)
    expect(tester.widget<CheckboxListTile>(tileFinder).value, isFalse);

    // SnackBar appears on BODY Scaffold with verbatim Arabic refusal message
    const expectedArabic =
        'تعذرت قراءة بيانات محاسبة اليوم المحفوظة، لذلك لم يُنفَّذ التغيير. يمكنك الاستعادة من نسخة احتياطية سابقة إن رغبت.';
    expect(find.text(expectedArabic), findsOneWidget);

    // Host bytes pinned unchanged
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(malformedRaw));
  });
}
