import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/mushaf/widgets/ayah_interaction.dart';
import 'package:almomin/core/services/quran_accessibility_service.dart';

void main() {
  test('verse speech contains only normalized text and number', () {
    expect(QuranAccessibilityService.buildAyahSemanticLabel(
      surahName: 'الإخلاص', ayahNumber: 1, uthmaniText: 'قُلْ هُوَ اللَّهُ أَحَدٌ',
    ), 'قُلْ هُوَ اللَّهُ أَحَدٌ 1');
    expect(QuranAccessibilityService.ayahSemanticHint, isEmpty);
  });

  Widget host(Widget child, {double scale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('each verse is one button, number and children do not split it', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(Column(children: [
      for (var n = 1; n <= 3; n++)
        AyahInteraction(
          key: ValueKey('verse-$n'),
          label: 'نص الآية $n',
          order: n.toDouble(),
          onTap: () {},
          onLongPress: () {},
          child: Row(children: [
            Text('نص الآية $n'),
            Text('﴿$n﴾'),
            IconButton(onPressed: () {}, icon: const Icon(Icons.bookmark), tooltip: 'إجراء داخلي'),
          ]),
        ),
    ])));
    for (var n = 1; n <= 3; n++) {
      final node = tester.getSemantics(find.byKey(ValueKey('verse-$n')));
      expect(node.label, 'نص الآية $n');
      expect(node.getSemanticsData().hint, isEmpty);
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
      expect((node.sortKey as OrdinalSortKey).order, n.toDouble());
      expect(node.childrenCount, 0);
    }
    expect(find.bySemanticsLabel('إجراء داخلي'), findsNothing);
    semantics.dispose();
  });

  testWidgets('tap and long press have separate callbacks', (tester) async {
    var taps = 0;
    var options = 0;
    await tester.pumpWidget(host(AyahInteraction(
      label: 'آية واحدة',
      onTap: () => taps++,
      onLongPress: () => options++,
      child: const SizedBox(width: 300, height: 80, child: Text('آية واحدة')),
    )));
    await tester.tap(find.byType(AyahInteraction));
    expect(taps, 1);
    expect(options, 0);
    await tester.longPress(find.byType(AyahInteraction));
    expect(taps, 1);
    expect(options, 1);
  });

  testWidgets('assistive actions use the same callbacks and selected state', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    var options = 0;
    await tester.pumpWidget(host(AyahInteraction(
      label: 'آية مسموعة',
      isPlaying: true,
      onTap: () => taps++,
      onLongPress: () => options++,
      child: const Text('آية مسموعة'),
    )));
    final node = tester.getSemantics(find.byType(AyahInteraction));
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(node.getSemanticsData().hint, isEmpty);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.tap);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.longPress);
    expect(taps, 1);
    expect(options, 1);
    semantics.dispose();
  });

  testWidgets('whole verse remains readable at 2x on narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(AyahInteraction(
      label: 'نص طويل',
      onTap: () {},
      onLongPress: () {},
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('نص تجريبي طويل لاختبار التفاف الآية ورقمها دون اقتصاص النص أو تقسيمه إلى عناصر مستقلة ﴿١﴾', style: TextStyle(fontSize: 24)),
      ),
    ), scale: 2));
    expect(tester.takeException(), isNull);
  });
}
