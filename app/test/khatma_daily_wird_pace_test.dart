import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/khatma_service.dart';
import 'package:almomin/features/khatma/widgets/khatma_manual_adjust_dialogs.dart';
import 'package:almomin/features/khatma/widgets/khatma_new_plan_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Khatma Daily Wird Planning & Dynamic Pace Tests', () {
    late KhatmaService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = KhatmaService.instance;
      await service.init();
    });

    test('Creating a Khatma by specifying daily wird pace (pages per day)', () async {
      // 1 Juz per day = 20 pages/day
      await service.createPlan(
        title: 'ختمة جزء يومياً',
        targetDays: 31,
        customDailyPace: 20,
        startingPage: 1,
      );

      final plan = service.activePlan;
      expect(plan, isNotNull);
      expect(plan!.customDailyPace, 20);
      expect(plan.pagesPerDay, 20);
      expect(plan.pagesPerPrayer, 4); // 20 / 5 = 4 pages per prayer
      expect(plan.daysRemaining, (604 / 20).ceil()); // 31 days
    });

    test('Creating a Khatma with half Juz daily wird (10 pages per day)', () async {
      await service.createPlan(
        title: 'ختمة نصف جزء يومياً',
        targetDays: 61,
        customDailyPace: 10,
        startingPage: 1,
      );

      final plan = service.activePlan;
      expect(plan, isNotNull);
      expect(plan!.customDailyPace, 10);
      expect(plan.pagesPerDay, 10);
      expect(plan.pagesPerPrayer, 2); // 10 / 5 = 2 pages per prayer
      expect(plan.daysRemaining, 61); // 604 / 10 = 60.4 -> 61 days
    });

    test('Dynamically updating daily wird pace on an active Khatma', () async {
      // Start with 20 pages/day
      await service.createPlan(
        title: 'ختمة قابلة للتعديل',
        targetDays: 30,
        customDailyPace: 20,
        startingPage: 1,
      );

      expect(service.activePlan!.pagesPerDay, 20);

      // User adjusts pace to 15 pages per day
      await service.updateDailyWirdPace(15);
      expect(service.activePlan!.customDailyPace, 15);
      expect(service.activePlan!.pagesPerDay, 15);
      expect(service.activePlan!.pagesPerPrayer, 3); // 15 / 5 = 3

      // User adjusts pace to 5 pages per day (1 Hizb)
      await service.updateDailyWirdPace(5);
      expect(service.activePlan!.customDailyPace, 5);
      expect(service.activePlan!.pagesPerDay, 5);
      expect(service.activePlan!.pagesPerPrayer, 1); // 5 / 5 = 1
    });

    testWidgets('showKhatmaNewPlanDialog renders daily wird planning toggle and chips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showKhatmaNewPlanDialog(context),
                  child: const Text('فتح'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();

      // Mode toggles should be visible
      expect(find.text('📖 تحديد الورد اليومي'), findsOneWidget);
      expect(find.text('⏳ تحديد مدة الختمة'), findsOneWidget);

      // Presets for daily wird
      expect(find.text('جزء كامل (٢٠ صفحة)'), findsOneWidget);
      expect(find.text('نصف جزء (١٠ صفحات)'), findsOneWidget);
      expect(find.text('حزب / ربع جزء (٥ صفحات)'), findsOneWidget);

      // Tap نصف جزء (١٠ صفحات)
      await tester.tap(find.text('نصف جزء (١٠ صفحات)'));
      await tester.pumpAndSettle();

      // Submit plan
      await tester.tap(find.text('بدء الختمة المباركة'));
      await tester.pumpAndSettle();

      expect(service.activePlan, isNotNull);
      expect(service.activePlan!.pagesPerDay, 10);
    });

    testWidgets('showKhatmaDailyWirdAdjustDialog allows adjusting active daily wird', (tester) async {
      await service.createPlan(
        title: 'ختمة تجريبية',
        targetDays: 30,
        customDailyPace: 20,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showKhatmaDailyWirdAdjustDialog(context, service.activePlan!),
                  child: const Text('تعديل الورد'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('تعديل الورد'));
      await tester.pumpAndSettle();

      expect(find.text('تحديد وتعديل الورد اليومي'), findsOneWidget);
      expect(find.text('نصف جزء (١٠ صفحات)'), findsOneWidget);

      // Select 10 pages
      await tester.tap(find.text('نصف جزء (١٠ صفحات)'));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('حفظ الورد الجديد'));
      await tester.pumpAndSettle();

      expect(service.activePlan!.pagesPerDay, 10);
    });
  });
}
