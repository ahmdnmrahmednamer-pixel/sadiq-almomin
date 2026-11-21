import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/mushaf_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('initialTab 3 opens the bookmarks list; default opens surahs', (t) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    for (final (tab, idx) in [(3, 3), (0, 0)]) {
      await t.pumpWidget(MaterialApp(home: MushafScreen(initialTab: tab, key: ValueKey(tab))));
      await t.pump(const Duration(milliseconds: 300));
      final bar = t.widget<TabBar>(find.byType(TabBar));
      expect(bar.controller!.index, idx);
    }
  });
}
