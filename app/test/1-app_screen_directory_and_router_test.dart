import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/home/screens/app_screen_directory_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppScreenDirectory & Architecture Tests', () {
    testWidgets('Renders AppScreenDirectoryScreen with search, category chips and items',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AppScreenDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Screen Title
      expect(find.text('فهرس ودليل الشاشات الشامل'), findsOneWidget);

      // Verify Search TextField
      expect(find.byType(TextField), findsOneWidget);

      // Verify Category Chips
      expect(find.byType(ChoiceChip), findsAtLeastNWidgets(5));
      // The all-categories total must agree with the independently visible category totals.
      // Retired entries must not force the old hard-coded catalogue count to return.
      final labels = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data!).toList();
      final counts = labels.map((label) => int.parse(
          RegExp(r'\((\d+)\)$').firstMatch(label)!.group(1)!)).toList();
      expect(labels.first, startsWith('الكل ('));
      expect(counts.first, greaterThan(0));
      expect(counts.first, counts.skip(1).fold<int>(0, (sum, value) => sum + value));
      expect(find.textContaining('إشراقة اليوم'), findsAtLeastNWidgets(1));
      expect(find.textContaining('رحاب القرآن'), findsAtLeastNWidgets(1));
      expect(find.textContaining('محراب الصلاة'), findsAtLeastNWidgets(1));
      expect(find.textContaining('أُنس الذاكرين'), findsAtLeastNWidgets(1));
      expect(find.textContaining('رياض العلم'), findsAtLeastNWidgets(1));
      expect(find.textContaining('العناية والإعدادات'), findsAtLeastNWidgets(1));
    });

    testWidgets('Filters AppScreenDirectory items using search input',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AppScreenDirectoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search term 'مواريث'
      await tester.enterText(find.byType(TextField), 'مواريث');
      await tester.pumpAndSettle();

      // Should find Mawarith item
      expect(find.text('ميزان الفرائض والمواريث الشرعية'), findsAtLeastNWidgets(1));

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Search for Adhkar item
      await tester.enterText(find.byType(TextField), 'أذكار');
      await tester.pumpAndSettle();

      expect(find.textContaining('أذكار'), findsAtLeastNWidgets(1));

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Search for Developer item
      await tester.enterText(find.byType(TextField), 'المطور');
      await tester.pumpAndSettle();

      expect(find.textContaining('عن المطور'), findsAtLeastNWidgets(1));
    });
  });
}
