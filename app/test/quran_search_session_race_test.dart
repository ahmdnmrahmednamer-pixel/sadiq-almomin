import 'dart:async';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/quran_search_service.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

class SearchHistoryGate extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  Completer<void>? gate;
  int writes = 0;
  bool failPending = false;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    final wait = gate;
    gate = null;
    if (wait != null) {
      await wait.future;
      if (failPending) throw StateError('synthetic retired write failure');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    QuranRepository.resetCachesForTesting();
    QuranSearchService.resetCacheForTesting();
  });
  for (final scenario in [
    'clear',
    'newer reference',
    'typing',
    'dispose',
    'retired failure'
  ]) {
    final clear = scenario == 'clear' || scenario == 'retired failure';
    testWidgets('retired search completion cannot overwrite $scenario',
        (tester) async {
      final store = SearchHistoryGate();
      SharedPreferencesStorePlatform.instance = store;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await SharedPreferences.getInstance();
      await tester.runAsync(() async {
        await QuranRepository.loadSurahs();
        await QuranRepository.getAyah(2, 255);
        await QuranSearchService.instance.searchAyahs('الصمد');
      });
      await tester.pumpWidget(const MaterialApp(home: QuranSearchScreen()));
      await tester.pumpAndSettle();
      final pending = Completer<void>();
      store.gate = pending;
      final input = find.byType(TextField);
      await tester.enterText(input, 'الصمد');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(store.writes, 1);
      if (clear) {
        await tester.tap(find.byTooltip('إغلاق أو مسح'));
      } else if (scenario == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else if (scenario == 'typing') {
        await tester.enterText(input, '2:255');
      } else {
        await tester.enterText(input, '2:255');
        await tester.testTextInput.receiveAction(TextInputAction.search);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      if (scenario == 'newer reference')
        expect(find.text('مرجع مباشر: 2:255'), findsOneWidget);
      store.failPending = scenario == 'retired failure';
      pending.complete();
      await tester.pump();
      if (scenario != 'typing') await tester.pumpAndSettle();
      if (clear) {
        expect(find.text('سجل البحث الأخير'), findsOneWidget);
      } else if (scenario == 'typing') {
        expect(find.text('مرجع مباشر: 2:255'), findsNothing);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(find.text('مرجع مباشر: 2:255'), findsOneWidget);
      } else if (scenario == 'newer reference') {
        expect(find.text('مرجع مباشر: 2:255'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    });
  }
}
