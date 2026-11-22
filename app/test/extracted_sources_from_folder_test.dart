import 'package:flutter/material.dart';
import 'package:almomin/core/services/budur_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/qiraat_service.dart';
import 'package:almomin/core/services/tafsir_service.dart';
import 'package:almomin/features/library/screens/approved_sources_screen.dart';
import 'package:almomin/features/mushaf/screens/qiraat_mushaf_screen.dart';

class UnavailableBudur extends BudurSource {
  int calls = 0;
  @override
  Future<String> load() async {
    calls++;
    throw const FormatException('synthetic source unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Extracted Sources from Folder Unit & Widget Tests', () {
    test('QiraatService contains 10 canonical reciters, 20 narrators, symbols and usul from مصحف القراءات', () {
      expect(QiraatService.reciters.length, 10);
      expect(QiraatService.reciters.first.name, contains('نافع المدني'));
      expect(QiraatService.reciters.first.narrators.length, 2);
      expect(QiraatService.reciters.first.narrators[0].name, 'قالون');
      expect(QiraatService.reciters.first.narrators[1].name, 'ورش');

      expect(QiraatService.symbols.length, greaterThanOrEqualTo(10));
      expect(QiraatService.usulRules.length, greaterThanOrEqualTo(5));
      expect(QiraatService.famousDifferences.length, greaterThanOrEqualTo(4));
    });

    test('TafsirService contains Sheikh Muhammad Ali Taha Al-Durrah and Al-Mukhtasar Audio editions', () {
      final durrah = TafsirService.getEdition('al_durrah');
      expect(durrah.id, 'al_durrah');
      expect(durrah.nameAr, contains('تفسير القرآن الكريم وإعرابه وبيانه'));
      expect(durrah.authorAr, contains('محمد علي طه الدرة'));

      final ids = TafsirService.availableEditions.map((e) => e.id).toSet();
      expect(ids.contains('almukhtasar_audio'), isFalse);
      expect(ids.contains('shaarawi'), isFalse);
    });

    testWidgets('Sources screen attributes connected grammar and keeps source limitations', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: ApprovedSourcesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('المصادر'), findsOneWidget);
      expect(find.text('البدور الزاهرة، عبد الفتاح القاضي'), findsOneWidget);
      expect(find.text('الميسر، الجلالين، القرطبي، البغوي'), findsOneWidget);
      expect(find.text('لباب النقول، جلال الدين السيوطي'), findsOneWidget);
      expect(find.text('الجدول في إعراب القرآن الكريم، محمود صافي'), findsOneWidget);
      expect(find.text('https://api.quranpedia.net/v1/book/1772'), findsOneWidget);
      expect(find.textContaining('فاطر ٣–٤ وغافر ١٠'), findsOneWidget);
      expect(find.textContaining('وأي اختلاف موضح في موضعه'), findsOneWidget);
      expect(find.textContaining('بقية الاختيارات لم تُربط بعد'), findsOneWidget);
      expect(find.textContaining('المواضع غير المحسومة لا تُنسب تلقائيًا'), findsOneWidget);
      expect(find.text('المختصر في تفسير القرآن الكريم'), findsNothing);
      expect(find.text('فتح القراءات'), findsOneWidget);
      expect(find.text('فتح الإعراب'), findsOneWidget);
      expect(find.text('فتح التفسير الصوتي'), findsNothing);
    });

    testWidgets('Qiraat source failure exposes retry without invented reciter tabs', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = UnavailableBudur();
      await tester.pumpWidget(MaterialApp(home: QiraatMushafScreen(source: source)));
      await tester.pumpAndSettle();
      expect(source.calls, 1);
      expect(find.text('القراءات'), findsOneWidget);
      expect(find.text('البدور الزاهرة'), findsOneWidget);
      expect(find.text('عبد الفتاح القاضي · الشاطبية والدرة'), findsOneWidget);
      expect(find.text(BudurSource.bookUrl), findsOneWidget);
      expect(find.text('تعذر قراءة نص البدور الزاهرة المدمج. أعد المحاولة.'), findsOneWidget);
      expect(find.text('القراء العشرة ورواتهم'), findsNothing);
      expect(find.text('الإمام نافع المدني'), findsNothing);
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(source.calls, 2);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

  });
}
