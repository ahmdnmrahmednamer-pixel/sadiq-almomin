import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/models/surah.dart';
import '../lib/core/services/quran_repository.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/features/mushaf/surah_reader_screen.dart';
import '../lib/features/mushaf/page_mode_mushaf_screen.dart';
import '../lib/features/mushaf/widgets/ayah_interaction.dart';

// Synthetic UI fixtures, not Quran content and never shipped in app assets.
const surah = Surah(id: 1, nameAr: 'سورة اختبارية', nameSimple: 'اختبار', revelationPlace: 'makkah', revelationOrder: 1, ayahCount: 3, hasBasmala: false, pageStart: 1, pageEnd: 1);
final rows = [for (var i = 1; i <= 3; i++) {
  'id': i, 'surah_id': 1, 'ayah_number': i, 'juz': 1, 'hizb': 1, 'rub': 1, 'page': 1,
  'text_uthmani': 'نص اختبار واجهة رقم $i', 'text_imlaei': 'نص اختبار واجهة رقم $i', 'text_search': 'اختبار',
}];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    QuranRepository.resetCachesForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List());
      Object? value;
      if (path == 'assets/data/quran_ayahs.json') value = {'1': rows};
      if (path == 'assets/data/surahs/1.json') value = rows;
      if (path == 'assets/data/surahs.json') value = [{'id':1,'name_ar':'سورة اختبارية','revelation_place':'makkah','revelation_order':1,'ayah_count':3,'has_basmala':0,'page_start':1,'page_end':1}];
      if (path == 'assets/data/juz.json') value = [];
      return value == null ? null : ByteData.sublistView(utf8.encode(jsonEncode(value)));
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    QuranRepository.resetCachesForTesting();
  });
  for (final pageMode in [false, true]) {
    testWidgets('${pageMode ? "page" : "surah"} reader uses one complete verse button in accessible mode', (tester) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(accessibleNavigation: true), child: child!),
        home: pageMode ? const PageModeMushafScreen() : const SurahReaderScreen(surah: surah),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AyahInteraction), findsNWidgets(3));
      final nodes = find.byType(AyahInteraction).evaluate().map((e) => tester.getSemantics(find.byWidget(e.widget))).toList();
      for (var i = 0; i < nodes.length; i++) {
        expect(nodes[i].label, contains('نص اختبار واجهة رقم ${i+1}'));
        expect(nodes[i].hasFlag(SemanticsFlag.isButton), isTrue);
        expect(nodes[i].getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(nodes[i].getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
        expect(nodes[i].childrenCount, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
