import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/settings/widgets/sections/settings_prayer_and_fiqh_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'large-text prayer selector tiles expose name once, value, button action',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    final font = Platform.environment['SELECTOR_PREVIEW_FONT'];
    if (font != null) {
      await t.runAsync(() async {
        for (final family in ['Amiri', 'Cairo', 'Roboto']) {
          await (FontLoader(family)
                ..addFont(Future.value(
                    ByteData.sublistView(await File(font).readAsBytes()))))
              .load();
        }
      });
    }
    final preview = GlobalKey();
    final h = t.ensureSemantics();
    t.view.physicalSize = const Size(480, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
                body: RepaintBoundary(
                    key: preview,
                    child: ColoredBox(
                        color: Colors.white,
                        child: const SingleChildScrollView(
                            child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: SettingsPrayerAndFiqhSection()))))))));
    await t.pumpAndSettle();
    final out = <String>[];
    void walk(SemanticsNode n) {
      final d = n.getSemanticsData();
      if (d.label.contains('الاختيار الحالي')) {
        out.add(
            '${d.hasFlag(SemanticsFlag.isButton)}|${d.hasAction(SemanticsAction.tap)}|${d.label.replaceAll('\n', ' ')}');
      }
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    expect(out.length, 3, reason: out.join('\n'));
    for (final l in out) {
      expect(l, startsWith('true|true|'));
      final parts = l.split('|').last.split('، الاختيار الحالي: ');
      expect(parts.length, 2, reason: l);
      expect(parts[1].trim().isNotEmpty, isTrue);
      expect(l.split(parts[0]).length - 1, 1, reason: 'name repeated: $l');
      expect(l.split(parts[1].trim()).length - 1, 1,
          reason: 'value repeated: $l');
    }
    if (Platform.environment['SELECTOR_PREVIEW'] != null) {
      await t.runAsync(() async {
        final image = await (preview.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(Platform.environment['SELECTOR_PREVIEW']!)
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    final button = find.bySemanticsLabel(
        RegExp('الهيئة المعتمدة لحساب المواقيت، الاختيار الحالي:'));
    expect(button, findsOneWidget);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(SettingsService.instance.calculationMethod, 'egyptian');
    h.dispose();
  });
}
