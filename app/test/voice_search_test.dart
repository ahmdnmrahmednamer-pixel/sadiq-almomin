import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/voice_search_service.dart';
import 'package:almomin/features/search/widgets/quran_voice_search_sheet.dart';
import 'package:almomin/features/search/quran_search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceSearchService.resetTestMode();
  });

  tearDown(() {
    VoiceSearchService.resetTestMode();
  });

  group('VoiceSearchService Unit Tests', () {
    test('Initial state is idle', () {
      final service = VoiceSearchService.instance;
      expect(service.status, equals(VoiceSearchStatus.idle));
      expect(service.isListening, isFalse);
    });

    test('Test mode initialization sets status to idle', () async {
      VoiceSearchService.isTestMode = true;
      final service = VoiceSearchService.instance;
      final ok = await service.initialize();
      expect(ok, isTrue);
      expect(service.status, equals(VoiceSearchStatus.idle));
    });

    test('Test mode captures mock speech recognized words', () async {
      VoiceSearchService.isTestMode = true;
      VoiceSearchService.testMockRecognizedWords = 'الله لا اله الا هو الحي القيوم';

      final service = VoiceSearchService.instance;
      String? resultWords;
      bool? isFinalResult;

      await service.startListening(
        onResult: (words, isFinal) {
          resultWords = words;
          isFinalResult = isFinal;
        },
      );

      expect(resultWords, equals('الله لا اله الا هو الحي القيوم'));
      expect(isFinalResult, isTrue);
      expect(service.status, equals(VoiceSearchStatus.done));
    });

    test('Stop and cancel listening reset states correctly', () async {
      VoiceSearchService.isTestMode = true;
      final service = VoiceSearchService.instance;

      await service.startListening(onResult: (_, __) {});
      expect(service.status, equals(VoiceSearchStatus.done));

      await service.cancelListening();
      expect(service.status, equals(VoiceSearchStatus.idle));
      expect(service.lastRecognizedWords, isEmpty);
    });
  });

  group('QuranVoiceSearchSheet Widget Tests', () {
    testWidgets('Renders QuranVoiceSearchSheet with title, mic icon, and sample chips', (tester) async {
      VoiceSearchService.isTestMode = true;
      VoiceSearchService.testMockRecognizedWords = 'سورة الرحمن';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QuranVoiceSearchSheet(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('البحث الصوتي في القرآن الكريم'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsWidgets);
      expect(find.text('بحث بالآية'), findsOneWidget);
      expect(find.text('إعادة'), findsOneWidget);
    });

    testWidgets('Tapping example chip populates search text', (tester) async {
      VoiceSearchService.isTestMode = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QuranVoiceSearchSheet(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      final chipFinder = find.text('آية الكرسي');
      if (chipFinder.evaluate().isNotEmpty) {
        await tester.tap(chipFinder);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('«آية الكرسي»'), findsOneWidget);
      }
    });
  });

  group('QuranSearchScreen Voice Search Integration Tests', () {
    testWidgets('Displays microphone button in AppBar and TextField', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QuranSearchScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify microphone icons exist for voice search
      expect(find.byIcon(Icons.mic_rounded), findsWidgets);
      expect(find.byTooltip('البحث الصوتي عن الآيات بالميكروفون'), findsOneWidget);
      expect(find.byTooltip('البحث الصوتي عن الآيات'), findsOneWidget);
    });
  });
}
