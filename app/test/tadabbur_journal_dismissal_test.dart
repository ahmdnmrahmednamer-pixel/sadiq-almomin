// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';
import 'package:almomin/features/mushaf/tadabbur_journal_screen.dart';

class MockDismissalStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  Completer<bool>? setValueCompleter;
  Map<String, Object>? overrideGetAllData;

  MockDismissalStorePlatform(this.delegate);

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() {
    if (overrideGetAllData != null) {
      return Future.value(Map<String, Object>.from(overrideGetAllData!));
    }
    return delegate.getAll();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) {
    if (overrideGetAllData != null) {
      return Future.value(Map<String, Object>.from(overrideGetAllData!));
    }
    return delegate.getAllWithParameters(parameters);
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (setValueCompleter != null) {
      return setValueCompleter!.future;
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await QuranRepository.getAyahsForSurah(1);
  });

  group('TadabburJournalScreen Dismissal Mid-Pending Regression', () {
    testWidgets('dismissing sheet while addReflection is pending does not throw on failure and preserves service state', (tester) async {
      final originalPlatform = SharedPreferencesStorePlatform.instance;
      final mockPlatform = MockDismissalStorePlatform(originalPlatform);
      SharedPreferencesStorePlatform.instance = mockPlatform;

      addTearDown(() {
        if (mockPlatform.setValueCompleter != null && !mockPlatform.setValueCompleter!.isCompleted) {
          mockPlatform.setValueCompleter!.complete(false);
        }
        SharedPreferencesStorePlatform.instance = originalPlatform;
      });

      mockPlatform.overrideGetAllData = {
        'flutter.tadabbur_journal_entries_v1': '[]',
      };
      await TadabburJournalService.instance.init(forceReload: true);
      expect(TadabburJournalService.instance.isReadable, isTrue);
      expect(TadabburJournalService.instance.entries, isEmpty);

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

      expect(find.text('حفظ بطاقة التدبر والعمل'), findsOneWidget);

      // Setup completer so setValue remains pending
      final completer = Completer<bool>();
      mockPlatform.setValueCompleter = completer;

      // Tap save button - triggers addReflection which pauses awaiting setValue
      await tester.tap(find.text('حفظ بطاقة التدبر والعمل'));
      await tester.pump();

      // Dismiss the sheet mid-pending
      Navigator.of(tester.element(find.text('حفظ بطاقة التدبر والعمل'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify the sheet is dismissed
      expect(find.text('حفظ بطاقة التدبر والعمل'), findsNothing);

      // Now let the pending operation resolve with failure
      completer.complete(false);
      await tester.pumpAndSettle();

      // Expect no exception was thrown (e.g. setState() called after dispose())
      expect(tester.takeException(), isNull);

      // Verify service outcome: failed save not published, latch unchanged
      expect(TadabburJournalService.instance.entries, isEmpty);
      expect(TadabburJournalService.instance.isReadable, isTrue);

      // Verify parent screen is still mounted and intact
      expect(find.byType(TadabburJournalScreen), findsOneWidget);

      // Cleanup
      SharedPreferencesStorePlatform.instance = originalPlatform;
      await TadabburJournalService.instance.init(forceReload: true);
      await tester.pumpAndSettle();
    });
  });
}
