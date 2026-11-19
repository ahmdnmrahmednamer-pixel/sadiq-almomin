import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/features/library/islamic_library_screen.dart';

void main() {
  testWidgets(
      'Existing library keeps its sections and opens Shamela via its own card',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const IslamicLibraryScreen()));
    await t.pump();
    expect(find.text('المكتبة الشاملة'), findsOneWidget);
    final entry = find.text('المكتبة الشاملة');
    await t.ensureVisible(entry);
    await t.tap(entry);
    await t.pumpAndSettle();
    expect(find.text('المكتبة الشاملة'), findsOneWidget);
    expect(find.text('كتبي المحفوظة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
