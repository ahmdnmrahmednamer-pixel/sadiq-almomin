import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/widgets/app_navigation_drawer.dart';
import 'package:almomin/core/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('Comprehensive AppNavigationDrawer Tests', () {
    testWidgets('Drawer renders all user-requested sections and features', (tester) async {
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

      // Verify Header & Tribute
      expect(find.textContaining('الدعاء للمرحوم مؤمن'), findsOneWidget);

      // Verify Quran & Reciters
      expect(find.text('المصحف الشريف وتلاوة الآيات'), findsOneWidget);
      expect(find.text('قراء القرآن الكريم والاستماع (61 قارئاً) 🎧'), findsOneWidget);

      // Verify Adhan & 7 Muezzins & Sha'rawi Duaa
      await tester.scrollUntilVisible(
        find.text('أصوات الأذان والمؤذنون الـ 7 🕌'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('أصوات الأذان والمؤذنون الـ 7 🕌'), findsOneWidget);
      expect(find.text('دعاء الشيخ الشعراوي بعد الأذان 🎧'), findsOneWidget);

      // Verify Scholars Audio Library
      await tester.scrollUntilVisible(
        find.text('مكتبة كبار العلماء والدروس الإسلامية 🎙️'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('مكتبة كبار العلماء والدروس الإسلامية 🎙️'), findsOneWidget);

      // Verify Adhkar & Tasbih
      await tester.scrollUntilVisible(
        find.text('أذكار المسلم وحصن المسلم 🤲'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('أذكار المسلم وحصن المسلم 🤲'), findsOneWidget);
      expect(find.text('السبحة الإلكترونية الذكية 📿'), findsOneWidget);

      // Verify Settings & Support
      await tester.scrollUntilVisible(
        find.text('تهيئة الخشوع وإعدادات التطبيق'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('تهيئة الخشوع وإعدادات التطبيق'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('التواصل والمقترحات'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('التواصل والمقترحات'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('رسالة التطبيق'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('رسالة التطبيق'), findsOneWidget);
    });
  });
}
