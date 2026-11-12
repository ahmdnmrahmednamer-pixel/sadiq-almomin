import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/features/home/screens/app_screen_directory_screen.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/app/theme/app_theme.dart';
import 'package:almomin/app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('Accessibility & Scaled Text & Token Tests', () {
    testWidgets('AppTheme default font is Cairo and colors align with design system', (tester) async {
      final theme = AppTheme.lightTheme;
      expect(AppTheme.uiFont, 'Cairo');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
      expect(theme.colorScheme.primary, AppColors.emerald700);
    });

    testWidgets('AppNavigationDrawer renders without overflow with 150% Large Text Scale in Light Theme', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0; // Logical size 540x1200
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              drawer: AppNavigationDrawer(),
              body: Center(child: Text('Body')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Check header tribute text rendered
      expect(find.textContaining('الدعاء للمرحوم مؤمن'), findsOneWidget);

      // Verify version updated to v1.3.0
      await tester.scrollUntilVisible(
        find.textContaining('v1.3.0'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('إصدار رسمي v1.3.0'), findsOneWidget);
    });

    testWidgets('AppNavigationDrawer renders without overflow with 150% Large Text Scale in Dark Theme', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              drawer: AppNavigationDrawer(),
              body: Center(child: Text('Body')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.textContaining('الدعاء للمرحوم مؤمن'), findsOneWidget);
      expect(find.text('المصحف الشريف وتلاوة الآيات'), findsOneWidget);
    });

    testWidgets('AppScreenDirectoryScreen renders search and cards with 150% Large Text Scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.5),
            ),
            child: AppScreenDirectoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فهرس ودليل الشاشات الشامل'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('إشراقة اليوم'), findsWidgets);

      // Search filter test
      await tester.enterText(find.byType(TextField), 'أذان');
      await tester.pumpAndSettle();

      expect(find.textContaining('التحكم في الأذان والتنبيهات'), findsWidgets);
    });
  });
}
