import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/home/screens/app_screen_directory_screen.dart';
import 'package:almomin/features/home/widgets/home_shortcuts_list.dart';
import 'package:almomin/features/library/islamic_library_screen.dart';

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
      expect(find.text('رياض العلم'), findsOneWidget);

      // Check Portal Category Cards
      for (final title in ['المكتبة الشاملة', 'قصص الأنبياء', 'المواريث', 'الحج والعمرة', 'الإذاعة والتراث']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('رياض الصالحين وصحيح الحديث'), findsNothing);
      expect(find.text('المتون العلمية وأحكام التجويد'), findsNothing);
    });

    testWidgets('Renders HomeShortcutsList clean categorized grid with 7 retained spiritual doors', (tester) async {
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
      expect(find.textContaining('مجالس العلماء'), findsNothing);
      expect(find.textContaining('طِبّ القلوب'), findsOneWidget);
      expect(find.textContaining('رواتب الجنة'), findsOneWidget);
      expect(find.textContaining('بصائر المفسرين'), findsOneWidget);
      expect(find.textContaining('مدارج التدبر'), findsOneWidget);
      expect(find.textContaining('باب الريّان'), findsOneWidget);
      expect(find.textContaining('رحلة الحرمين'), findsOneWidget);
      expect(find.textContaining('مشكاة الحديث'), findsNothing);
      expect(find.textContaining('وِرد القرب'), findsOneWidget);

      // Check Daily Spotlight Card
      expect(find.text('قبس من قصص الوحي اليوم'), findsOneWidget);
    });

    testWidgets('Home radio banner has scoped button semantics with truthful concise labels and excluded decorative icons', (tester) async {
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

      // Scoped radio banner Semantics assertion using dedicated Key
      final radioSemanticsFinder = find.byKey(const Key('home_islamic_radio_banner_semantics'));
      expect(radioSemanticsFinder, findsOneWidget);

      final radioSemanticsWidget = tester.widget<Semantics>(radioSemanticsFinder);
      expect(radioSemanticsWidget.properties.button, isTrue);
      expect(radioSemanticsWidget.properties.label,
          equals('إذاعات القرآن الكريم، بث مباشر وتلاوات كبار القراء'));
      expect(radioSemanticsWidget.properties.hint, isNull,
          reason: 'Farag simplified secondary spoken hints, not the destination label');

      // Verify radio icon is explicitly excluded from semantics tree within the banner
      final bannerRadioIconFinder = find.descendant(
        of: radioSemanticsFinder,
        matching: find.byIcon(Icons.radio_rounded),
      );
      expect(bannerRadioIconFinder, findsOneWidget);
      final excludedRadioIcon = tester.widget<ExcludeSemantics>(
        find.ancestor(of: bannerRadioIconFinder, matching: find.byType(ExcludeSemantics)).first,
      );
      expect(excludedRadioIcon.excluding, isTrue);

      // Verify heritage banner semantics
      final egyptSemantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.textContaining('نسائم القاهرة'),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true),
        ),
      );
      expect(egyptSemantics.properties.button, isTrue);
      expect(egyptSemantics.properties.label, contains('نسائم القاهرة'));
      expect(egyptSemantics.properties.hint, isNull);

      // Verify decorative flag emoji is wrapped in ExcludeSemantics
      final emojiFinder = find.text('🇪🇬');
      expect(emojiFinder, findsOneWidget);
      final excludeEmoji = tester.widget<ExcludeSemantics>(
        find.ancestor(of: emojiFinder, matching: find.byType(ExcludeSemantics)).first,
      );
      expect(excludeEmoji.excluding, isTrue);
    });

    testWidgets('All 3 entry surfaces (home banner, drawer, directory) tap route to /islamic-radio', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Home banner tap test
      final bannerRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: SingleChildScrollView(
                child: HomeShortcutsList(prayerData: null),
              ),
            ),
          ),
          GoRoute(
            path: '/islamic-radio',
            builder: (context, state) => const Scaffold(
              body: Text('Target Islamic Radio Screen'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: bannerRouter));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إذاعات القرآن الكريم'));
      await tester.pumpAndSettle();
      expect(find.text('Target Islamic Radio Screen'), findsOneWidget);

      // 2. Navigation Drawer item tap test
      final drawerRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              drawer: AppNavigationDrawer(),
              body: Text('Home with Drawer'),
            ),
          ),
          GoRoute(
            path: '/islamic-radio',
            builder: (context, state) => const Scaffold(
              body: Text('Target Islamic Radio Screen'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: drawerRouter));
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      final drawerItemFinder = find.text('الإذاعة');
      await tester.scrollUntilVisible(
        drawerItemFinder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(drawerItemFinder);
      await tester.pumpAndSettle();
      expect(find.text('Target Islamic Radio Screen'), findsOneWidget);

      // 3. Screen Directory item tap test (filtered by search to guarantee top position)
      final directoryRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: AppScreenDirectoryScreen(),
            ),
          ),
          GoRoute(
            path: '/islamic-radio',
            builder: (context, state) => const Scaffold(
              body: Text('Target Islamic Radio Screen'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: directoryRouter));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'إذاعات');
      await tester.pumpAndSettle();

      final dirItemFinder = find.text('إذاعات القرآن الكريم (MP3Quran)');
      expect(dirItemFinder, findsOneWidget);
      await tester.tap(dirItemFinder);
      await tester.pumpAndSettle();
      expect(find.text('Target Islamic Radio Screen'), findsOneWidget);
    });
  });
}
