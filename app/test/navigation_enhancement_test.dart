import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/features/home/home_screen.dart';
import 'package:almomin/features/home/widgets/home_quick_sections_grid.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'has_completed_onboarding': true,
    });
    await SettingsService.instance.init();
  });

  tearDown(() {
    PrayerService.instance.stopLiveTicker();
  });

  group('Navigation Architecture & Organization Tests', () {
    testWidgets('HomeScreen renders cleaned HomeQuickSectionsGrid without directory clutter', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(PrayerService.instance.stopLiveTicker);

      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // Verify cleaned header and absence of directory clutter
      expect(find.text('الأقسام الرئيسية'), findsOneWidget);
      expect(find.byType(HomeQuickSectionsGrid), findsOneWidget);
      expect(find.text('دليل الشاشات الشامل'), findsNothing);
      expect(find.text('عرض الفهرس الكامل'), findsNothing);

      // Verify core feature access cards exist
      expect(find.text('المصحف الشريف'), findsOneWidget);
      expect(find.text('الصلاة والقبلة'), findsOneWidget);
      expect(find.text('الأذكار والسبحة'), findsOneWidget);
      expect(find.text('المكتبة والحديث'), findsOneWidget);
      expect(find.text('كبار العلماء'), findsNothing);
      expect(find.text('ختمة القرآن'), findsOneWidget);

      PrayerService.instance.stopLiveTicker();
    });

    testWidgets('AppNavigationDrawer search filter narrows navigation options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            drawer: AppNavigationDrawer(),
            body: Center(child: Text('الرئيسية')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Verify search input field exists
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('ابحث عن أي قسم أو خدمة في التطبيق...'), findsOneWidget);

      // Enter search query "تفسير"
      await tester.enterText(find.byType(TextField), 'تفسير');
      await tester.pumpAndSettle();

      // Verify matching results appear
      expect(find.textContaining('تفسير'), findsWidgets);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // All sections are back
      expect(find.text('المصحف الشريف وتلاوة الآيات'), findsOneWidget);
    });

    testWidgets('AppNavigationDrawer category filter chips filter by section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            drawer: AppNavigationDrawer(),
            body: Center(child: Text('الرئيسية')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Find '📖 القرآن' choice chip which is adjacent to 'الكل'
      final quranChip = find.widgetWithText(ChoiceChip, '📖 القرآن');
      expect(quranChip, findsOneWidget);

      await tester.tap(quranChip);
      await tester.pumpAndSettle();

      // Verify Quran tile exists
      expect(find.text('المصحف الشريف وتلاوة الآيات'), findsOneWidget);

      // Verify Prayer tile is filtered out
      expect(find.text('أصوات الأذان والمؤذنون الـ 7 🕌'), findsNothing);
    });
  });
}
