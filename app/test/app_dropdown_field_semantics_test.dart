import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/settings_service.dart';
import '../lib/core/ui/app_dropdown_field.dart';

List<String> dump(WidgetTester t) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    final d = n.getSemanticsData();
    final a = [if (d.hasAction(SemanticsAction.tap)) 'tap', if (d.hasFlag(SemanticsFlag.isButton)) 'button'];
    if (d.label.isNotEmpty || a.isNotEmpty) out.add('[${a.join(',')}] ${d.label.replaceAll('\n', ' ')}|${d.value}');
    n.visitChildren((c) { walk(c); return true; });
  }
  walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<List<String>> pump(WidgetTester t, Widget w, {double scale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    final h = t.ensureSemantics();
    await t.pumpWidget(MaterialApp(home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)), child: Scaffold(body: Directionality(textDirection: TextDirection.rtl, child: w)))));
    await t.pumpAndSettle();
    final r = dump(t);
    h.dispose();
    return r;
  }
  AppDropdownField<int> f({int value = 2, bool dense = false, String? helper, IconData? icon, List<AppDropdownOption<int>>? opts}) =>
      AppDropdownField<int>(label: 'الطريقة', value: value, dense: dense, helperText: helper, prefixIcon: icon, onChanged: (_) {}, options: opts ?? const [AppDropdownOption(value: 1, label: 'أولى'), AppDropdownOption(value: 2, label: 'ثانية', subtitle: 'فرعي')]);
  for (final c in <String, List<dynamic>>{
    'normal': [() => f(), 1.0],
    'dense': [() => f(dense: true), 1.0],
    'helper+icon': [() => f(helper: 'تنبيه مساعد', icon: Icons.mosque), 1.0],
    'largeText': [() => f(), 2.0],
    'duplicate options': [() => f(opts: const [AppDropdownOption(value: 2, label: 'ثانية'), AppDropdownOption(value: 2, label: 'مكررة')]), 1.0],
    'value not in options': [() => f(value: 9), 1.0],
  }.entries) {
    testWidgets('AppDropdownField ${c.key}: name, value, action kept once', (t) async {
      final tree = await pump(t, (c.value[0] as Widget Function())(), scale: c.value[1] as double);
      final all = tree.join('\n');
      final actionNodes = tree.where((l) => l.startsWith('[tap,button]')).toList();
      expect(actionNodes.length, 1, reason: all);
      final n = actionNodes.first;
      expect(n, contains('الطريقة'), reason: all);
      final expectedValue = c.key == 'value not in options' || c.key == 'duplicate options' ? (c.key == 'duplicate options' ? 'ثانية' : 'أولى') : 'ثانية';
      expect(n, contains(expectedValue), reason: all);
      expect('الطريقة'.allMatches(all).length, 1, reason: all);
      expect(all.contains('الاختيار الحالي'), isFalse, reason: all);
      if (c.key == 'helper+icon') expect(all, contains('تنبيه مساعد'));
    });
  }
  testWidgets('AppDropdownField empty options does not throw', (t) async {
    final tree = await pump(t, f(opts: const []));
    expect(t.takeException(), isNull, reason: tree.join('\n'));
  });
}
