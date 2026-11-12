import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/audio_tafsir_service.dart';
import 'package:almomin/core/services/qiraat_service.dart';
import 'package:almomin/core/services/tafsir_service.dart';
import 'package:almomin/features/library/screens/approved_sources_screen.dart';
import 'package:almomin/features/mushaf/screens/audio_tafsir_screen.dart';
import 'package:almomin/features/mushaf/screens/qiraat_mushaf_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Extracted Sources from Folder Unit & Widget Tests', () {
    test('AudioTafsirService contains all 3 scholars with 5 platform links from PDF', () {
      const scholars = AudioTafsirService.scholars;
      expect(scholars.length, 3);

      final asmari = AudioTafsirService.instance.getScholarById('asmari');
      expect(asmari, isNotNull);
      expect(asmari!.name, contains('عبد الله الأسمري'));
      expect(asmari.youtubePlaylistUrl, contains('youtube.com/playlist'));
      expect(asmari.applePodcastsUrl, contains('podcasts.apple.com'));
      expect(asmari.soundCloudUrl, contains('soundcloud.com'));
      expect(asmari.podbeanUrl, contains('podbean.com'));
      expect(asmari.telegramUrl, contains('t.me/MokhSound'));

      final ghamdi = AudioTafsirService.instance.getScholarById('ghamdi');
      expect(ghamdi, isNotNull);
      expect(ghamdi!.name, contains('ساعد الغامدي'));
      expect(ghamdi.youtubePlaylistUrl, contains('youtube.com/playlist'));

      final shaya = AudioTafsirService.instance.getScholarById('shaya');
      expect(shaya, isNotNull);
      expect(shaya!.name, contains('عبد الرحمن الشايع'));
      expect(shaya.youtubePlaylistUrl, contains('youtube.com/playlist'));
    });

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

      final audio = TafsirService.getEdition('almukhtasar_audio');
      expect(audio.id, 'almukhtasar_audio');
      expect(audio.nameAr, contains('المختصر الصوتي'));
    });

    testWidgets('ApprovedSourcesScreen renders all 3 authoritative sources cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: ApprovedSourcesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('المصادر والمراجع القرآنية المعتمدة'), findsAtLeastNWidgets(1));
      expect(find.textContaining('مصحف الصحابة في القراءات العشر المتواترة'), findsOneWidget);
      expect(find.textContaining('المختصر في تفسير القرآن الكريم صوتياً'), findsOneWidget);

      // Scroll to reveal third card if needed
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.textContaining('تفسير القرآن الكريم وإعرابه وبيانه'), findsOneWidget);
      expect(find.textContaining('محمد علي طه الدرة'), findsOneWidget);
    });

    testWidgets('QiraatMushafScreen renders tabs and reciters list', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: QiraatMushafScreen()));
      await tester.pumpAndSettle();

      expect(find.text('مصحف القراءات العشر المتواترة'), findsAtLeastNWidgets(1));
      expect(find.text('القراء العشرة ورواتهم'), findsOneWidget);
      expect(find.text('رموز الشاطبية والدرة'), findsOneWidget);
      expect(find.text('أصول القراءات'), findsOneWidget);
      expect(find.text('فرش الحروف والتوجيه'), findsOneWidget);
      expect(find.text('الإمام نافع المدني'), findsOneWidget);
    });

    testWidgets('AudioTafsirScreen renders 3 scholars and platform links', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: AudioTafsirScreen()));
      await tester.pumpAndSettle();

      expect(find.text('المختصر الصوتي في التفسير'), findsAtLeastNWidgets(1));
      expect(find.textContaining('عبد الله الأسمري'), findsAtLeastNWidgets(1));
      expect(find.textContaining('ساعد الغامدي'), findsAtLeastNWidgets(1));
      expect(find.textContaining('عبد الرحمن الشايع'), findsAtLeastNWidgets(1));

      // Scroll to reveal platform links
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('يوتيوب (YouTube)'), findsOneWidget);
      expect(find.text('أبل بودكاست (Apple Podcasts)'), findsOneWidget);
      expect(find.text('ساوند كلاود (SoundCloud)'), findsOneWidget);
    });
  });
}
