import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/models/islamic_radio.dart';
import 'package:almomin/core/services/islamic_radio_service.dart';
import 'package:almomin/features/radio/islamic_radio_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IslamicRadioService Tests', () {
    test('Default stations catalog contains verified stations and Cairo radio', () {
      final stations = IslamicRadioService.defaultStations;
      expect(stations.isNotEmpty, isTrue);

      final cairo = stations.firstWhere((s) => s.id == 'radio_cairo_live');
      expect(cairo.name, contains('القاهرة'));
      expect(cairo.streamUrl, contains('radiojar.com'));
      expect(cairo.fallbackUrls.isNotEmpty, isTrue);
      expect(cairo.category, equals(IslamicRadioCategoryType.generalLive));
    });

    test('Categories contain all expected sections', () {
      final categories = IslamicRadioService.categories;
      expect(categories.length, greaterThanOrEqualTo(5));

      final reciters = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.reciters,
      );
      expect(reciters.title, contains('القراء'));

      final tafseer = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.tafseerFatwa,
      );
      expect(tafseer.title, contains('التفسير'));

      final adhkar = categories.firstWhere(
        (c) => c.type == IslamicRadioCategoryType.adhkarRoqyah,
      );
      expect(adhkar.title, contains('الأذكار'));
    });

    test('Filtering by category returns matching stations', () {
      final service = IslamicRadioService.instance;
      final reciterStations = service.getStations(
        category: IslamicRadioCategoryType.reciters,
      );
      expect(reciterStations.isNotEmpty, isTrue);
      for (final s in reciterStations) {
        expect(s.category, equals(IslamicRadioCategoryType.reciters));
      }
    });

    test('Search by reciter name matches correctly', () {
      final service = IslamicRadioService.instance;
      final results = service.getStations(query: 'المنشاوي');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, contains('المنشاوي'));
    });
  });

  group('IslamicRadioScreen Widget Tests', () {
    testWidgets('Renders screen with title, search, categories, and stations', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IslamicRadioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الإذاعات الإسلامية والبث المباشر'), findsOneWidget);
      expect(find.text('إذاعة القرآن الكريم من القاهرة'), findsWidgets);
      expect(find.text('جميع الإذاعات'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
