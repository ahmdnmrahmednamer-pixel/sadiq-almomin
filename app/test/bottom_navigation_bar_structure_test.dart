import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/services/support_service.dart';
import 'package:almomin/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bottom Navigation Bar & Drawer Settings Tests', () {
    testWidgets('MainScaffold contains exactly 5 destinations (Settings removed from bottom bar)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: MainScaffold(
            child: Scaffold(
              body: Center(child: Text('محتوى الصفحة')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBarFinder = find.byType(NavigationBar);
      expect(navBarFinder, findsOneWidget);

      final navBar = tester.widget<NavigationBar>(navBarFinder);
      // Verify exactly 5 destinations
      expect(navBar.destinations.length, equals(5));

      // Check all 5 primary worship destinations are present
      expect(find.descendant(of: navBarFinder, matching: find.text('إشراقة اليوم')), findsOneWidget);
      expect(find.descendant(of: navBarFinder, matching: find.text('رحاب القرآن')), findsOneWidget);
      expect(find.descendant(of: navBarFinder, matching: find.text('محراب الصلاة')), findsOneWidget);
      expect(find.descendant(of: navBarFinder, matching: find.text('أُنس الذاكرين')), findsOneWidget);
      expect(find.descendant(of: navBarFinder, matching: find.text('رياض العلم')), findsOneWidget);

      // Verify that 'الإعدادات' is strictly NOT in the bottom navigation bar
      expect(find.descendant(of: navBarFinder, matching: find.text('الإعدادات')), findsNothing);
      expect(find.descendant(of: navBarFinder, matching: find.byIcon(Icons.settings_outlined)), findsNothing);
    });

    testWidgets('AppNavigationDrawer includes all 6 requested settings, developer, and social items', (tester) async {
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

      final scrollableFinder = find.byType(Scrollable).last;

      // 1. الإعدادات
      await tester.scrollUntilVisible(find.text('الإعدادات'), 200, scrollable: scrollableFinder);
      expect(find.text('الإعدادات'), findsOneWidget);

      // 2. عن التطبيق
      await tester.scrollUntilVisible(find.text('عن التطبيق'), 100, scrollable: scrollableFinder);
      expect(find.text('عن التطبيق'), findsOneWidget);

      // 3. عن المطور
      await tester.scrollUntilVisible(find.text('عن المطور'), 100, scrollable: scrollableFinder);
      expect(find.text('عن المطور'), findsOneWidget);

      // 4. تواصل مع المطور
      await tester.scrollUntilVisible(find.text('تواصل مع المطور'), 100, scrollable: scrollableFinder);
      expect(find.text('تواصل مع المطور'), findsOneWidget);

      // 5. برامج المطور على المتجر
      await tester.scrollUntilVisible(find.text('برامج المطور على المتجر'), 100, scrollable: scrollableFinder);
      expect(find.text('برامج المطور على المتجر'), findsOneWidget);

      // 6. حساب المطور على الفيس بوك
      await tester.scrollUntilVisible(find.text('حساب المطور على الفيس بوك'), 100, scrollable: scrollableFinder);
      expect(find.text('حساب المطور على الفيس بوك'), findsOneWidget);

      // Tribute banner remains intact
      expect(find.textContaining('الدعاء للمرحوم مؤمن'), findsOneWidget);
    });

    testWidgets('Tapping Play Store and Facebook items in drawer triggers launcher', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Uri? lastLaunchedUri;
      SupportService.urlLauncher = (Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
        lastLaunchedUri = uri;
        return true;
      };

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

      final scrollableFinder = find.byType(Scrollable).last;

      // Scroll to and tap 'برامج المطور على المتجر'
      final playStoreItem = find.text('برامج المطور على المتجر');
      await tester.scrollUntilVisible(playStoreItem, 150, scrollable: scrollableFinder);
      await tester.tap(playStoreItem);
      await tester.pumpAndSettle();

      expect(lastLaunchedUri, isNotNull);
      expect(
        lastLaunchedUri.toString().contains('play.google.com') ||
            lastLaunchedUri.toString().contains('market://'),
        isTrue,
      );

      // Open drawer again to test Facebook
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      final fbItem = find.text('حساب المطور على الفيس بوك');
      await tester.scrollUntilVisible(fbItem, 150, scrollable: scrollableFinder);
      await tester.tap(fbItem);
      await tester.pumpAndSettle();

      expect(lastLaunchedUri.toString(), contains('facebook.com'));
    });

    testWidgets('SettingsScreen renders clean header with navigation options', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Check AppBar Title
      expect(find.text('تهيئة الخشوع وإعدادات التطبيق'), findsOneWidget);
      // Check Home action button
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    });
  });
}
