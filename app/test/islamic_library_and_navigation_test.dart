import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/library/islamic_library_screen.dart';
import 'package:almomin/features/home/widgets/home_shortcuts_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Islamic Library Hub & Navigation Hub Tests', () {
    testWidgets('Renders IslamicLibraryScreen with tribute, sections, and feature cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const IslamicLibraryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Check AppBar Title
      expect(find.text('المكتبة الإسلامية ورياض العلم'), findsOneWidget);

      // Check Portal Category Cards
      expect(find.text('رياض الصالحين وصحيح الحديث'), findsOneWidget);
      expect(find.text('قصص الأنبياء المسموعة والمقروءة'), findsOneWidget);
      expect(find.text('المتون العلمية وأحكام التجويد'), findsOneWidget);
    });

    testWidgets('Renders HomeShortcutsList clean categorized grid with 9 spiritual doors', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: HomeShortcutsList(prayerData: null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Egyptian heritage banner
      expect(find.textContaining('نسائم القاهرة'), findsOneWidget);

      // Check key spiritual door tiles
      expect(find.textContaining('مجالس العلماء'), findsOneWidget);
      expect(find.textContaining('طِبّ القلوب'), findsOneWidget);
      expect(find.textContaining('رواتب الجنة'), findsOneWidget);
      expect(find.textContaining('بصائر المفسرين'), findsOneWidget);
      expect(find.textContaining('مدارج التدبر'), findsOneWidget);
      expect(find.textContaining('باب الريّان'), findsOneWidget);
      expect(find.textContaining('رحلة الحرمين'), findsOneWidget);
      expect(find.textContaining('مشكاة الحديث'), findsOneWidget);
      expect(find.textContaining('وِرد القرب'), findsOneWidget);

      // Check Daily Spotlight Card
      expect(find.text('قبس من قصص الوحي اليوم'), findsOneWidget);
    });

    testWidgets('Home banners have explicit button semantics and excluded decorative emojis', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: HomeShortcutsList(prayerData: null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check radio banner semantics
      final radioSemantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.text('إذاعات القرآن الكريم والتسجيلات'),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true),
        ),
      );
      expect(radioSemantics.properties.button, isTrue);

      // Check Egyptian heritage banner semantics
      final egyptSemantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.textContaining('نسائم القاهرة'),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true),
        ),
      );
      expect(egyptSemantics.properties.button, isTrue);

      // Verify decorative emoji is wrapped in ExcludeSemantics
      final emojiFinder = find.text('🇪🇬');
      expect(emojiFinder, findsOneWidget);
      final excludeEmoji = tester.widget<ExcludeSemantics>(
        find.ancestor(of: emojiFinder, matching: find.byType(ExcludeSemantics)).first,
      );
      expect(excludeEmoji.excluding, isTrue);
    });
  });
}
