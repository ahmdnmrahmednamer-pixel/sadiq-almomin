// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';
import 'package:almomin/features/mushaf/tadabbur_journal_screen.dart';

class MockFailureStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  int? failSetValueCount;
  bool returnFalseOnSetValue = false;
  bool throwOnSetValue = false;
  bool throwOnGetAll = false;
  Map<String, Object>? overrideGetAllData;

  MockFailureStorePlatform(this.delegate);

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() {
    if (throwOnGetAll) {
      throw Exception('Simulated platform host read/reload failure');
    }
    if (overrideGetAllData != null) {
      return Future.value(Map<String, Object>.from(overrideGetAllData!));
    }
    return delegate.getAll();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) {
    if (throwOnGetAll) {
      throw Exception('Simulated platform host read/reload failure');
    }
    if (overrideGetAllData != null) {
      return Future.value(Map<String, Object>.from(overrideGetAllData!));
    }
    return delegate.getAllWithParameters(parameters);
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failSetValueCount != null) {
      if (failSetValueCount! > 0) {
        failSetValueCount = failSetValueCount! - 1;
        if (throwOnSetValue) {
          throw Exception('Simulated platform setValue exception');
        }
        return Future.value(false);
      }
      return delegate.setValue(valueType, key, value);
    }
    if (throwOnSetValue) {
      throw Exception('Simulated platform setValue exception');
    }
    if (returnFalseOnSetValue) {
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

      final robotoLoader = FontLoader('Roboto');
      robotoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await robotoLoader.load();
    }
    final amiriFile = File('assets/fonts/Amiri-Regular.ttf');
    if (amiriFile.existsSync()) {
      final bytes = await amiriFile.readAsBytes();
      final amiriLoader = FontLoader('Amiri');
      amiriLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await amiriLoader.load();
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await loadArabicFonts();
  });

  group('TadabburJournalScreen Widget Tests', () {
    testWidgets('TadabburJournalScreen add dialog failure preserves dialog, input, and displays exact Arabic snackbar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      tester.view.devicePixelRatio = 1.0;
      final originalPlatform = SharedPreferencesStorePlatform.instance;
      final mockPlatform = MockFailureStorePlatform(originalPlatform);
      SharedPreferencesStorePlatform.instance = mockPlatform;

      addTearDown(() async {
        tester.view.resetDevicePixelRatio();
        SharedPreferencesStorePlatform.instance = originalPlatform;
        await tester.binding.setSurfaceSize(null);
      });

      // Part A: Refused unreadable failure
      mockPlatform.overrideGetAllData = {
        'flutter.tadabbur_journal_entries_v1': 'malformed_json',
      };
      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.isReadable, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const TadabburJournalScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Open add reflection dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Verify dialog is open
      expect(find.text('حفظ بطاقة التدبر والعمل'), findsOneWidget);

      // Enter input in text fields
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(3));
      await tester.enterText(textFields.at(0), 'خاطرة إيمانية اختبارية');
      await tester.enterText(textFields.at(1), 'عمل تطبيقي اختباري');
      await tester.enterText(textFields.at(2), 'دعاء اختباري');
      await tester.pump();

      // Tap save
      await tester.tap(find.text('حفظ بطاقة التدبر والعمل'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Assert dialog is preserved (not popped)
      expect(find.text('حفظ بطاقة التدبر والعمل'), findsOneWidget);
      // Assert typed inputs are preserved
      expect(find.text('خاطرة إيمانية اختبارية'), findsOneWidget);
      expect(find.text('عمل تطبيقي اختباري'), findsOneWidget);
      expect(find.text('دعاء اختباري'), findsOneWidget);

      // Assert exact Arabic snackbar copy for unreadable
      expect(
        find.text('تعذرت قراءة بيانات التدبر المحفوظة، لذلك لم يُنفَّذ الحفظ. يمكنك الاستعادة من نسخة احتياطية سابقة إن رغبت.'),
        findsOneWidget,
      );
      // Assert error text is findable INSIDE the open sheet
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('تعذرت قراءة بيانات التدبر المحفوظة، لذلك لم يُنفَّذ الحفظ. يمكنك الاستعادة من نسخة احتياطية سابقة إن رغبت.'),
        ),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/part_a_compact.png'),
      );

      // Clear SnackBars before Part B
      ScaffoldMessenger.of(tester.element(find.text('حفظ بطاقة التدبر والعمل'))).clearSnackBars();
      await tester.pumpAndSettle();

      // Part B: Write unconfirmed failure
      // Unblock service readability but make setValue return false
      mockPlatform.overrideGetAllData = {
        'flutter.tadabbur_journal_entries_v1': '[]',
      };
      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.isReadable, isTrue);
      mockPlatform.returnFalseOnSetValue = true;

      // Tap save again with inputs still in dialog
      await tester.tap(find.text('حفظ بطاقة التدبر والعمل'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Assert dialog and inputs still preserved
      expect(find.text('حفظ بطاقة التدبر والعمل'), findsOneWidget);
      expect(find.text('خاطرة إيمانية اختبارية'), findsOneWidget);

      // Assert exact Arabic snackbar copy for write unconfirmed
      expect(
        find.text('تعذر تأكيد حفظ الخاطرة. أعد المحاولة لاحقًا.'),
        findsOneWidget,
      );
      // Assert error text is findable INSIDE the open sheet
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('تعذر تأكيد حفظ الخاطرة. أعد المحاولة لاحقًا.'),
        ),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/part_b_compact.png'),
      );

      // Part C: Persisted success pops dialog
      mockPlatform.overrideGetAllData = null;
      mockPlatform.returnFalseOnSetValue = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tadabbur_journal_entries_v1', '[]');
      await TadabburJournalService.instance.init(forceReload: true);

      ScaffoldMessenger.of(tester.element(find.text('حفظ بطاقة التدبر والعمل'))).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ بطاقة التدبر والعمل'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Dialog is popped on persisted
      expect(find.text('حفظ بطاقة التدبر والعمل'), findsNothing);

      // Cleanup
      SharedPreferencesStorePlatform.instance = originalPlatform;
      await TadabburJournalService.instance.init(forceReload: true);
      await tester.pumpAndSettle();
    });
  });
}
