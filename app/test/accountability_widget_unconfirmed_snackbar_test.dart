// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';
import 'package:almomin/features/mushaf/tadabbur_journal_screen.dart';

class UnconfirmedWidgetStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;

  UnconfirmedWidgetStorePlatform(this.delegate);

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
    if (key.endsWith('tadabbur_daily_accountability_v1')) {
      return Future.value(false);
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkbox unchanged on writeUnconfirmed + SnackBar with exact Arabic copy', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = UnconfirmedWidgetStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
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

    // Tap to trigger toggle on failing host write fixture
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    // Checkbox remains unchecked (derived from published state only)
    expect(tester.widget<CheckboxListTile>(tileFinder).value, isFalse);

    // SnackBar appears on BODY Scaffold with verbatim Arabic unconfirmed message
    const expectedArabic = 'تعذر تأكيد حفظ محاسبة اليوم. أعد المحاولة لاحقًا.';
    expect(find.text(expectedArabic), findsOneWidget);
  });
}
