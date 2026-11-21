import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/radio/islamic_radio_screen.dart';

void main() {
  testWidgets('radio screen pixels and semantics', (t) async {
    await t.runAsync(() async {
      for (final item in {
        'Amiri': 'assets/fonts/Amiri-Regular.ttf',
        'MaterialIcons': '/home/sandbox/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      }.entries) {
        await (FontLoader(item.key)..addFont(Future.value(ByteData.sublistView(File(item.value).readAsBytesSync())))).load();
      }
    });
    final h = t.ensureSemantics();
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final w in [360.0, 720.0]) {
      t.view.physicalSize = Size(w, 900);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(fontFamily: 'Amiri'), home: const Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: IslamicRadioScreen())))));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final b = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/downloads/radio-screen-${w.toInt()}.png').writeAsBytesSync(b!.buffer.asUint8List());
      });
      final out = StringBuffer();
      void walk(SemanticsNode n) {
        final d = n.getSemanticsData();
        if (d.label.isNotEmpty || d.hint.isNotEmpty) out.writeln('${d.label} | ${d.hint} | ${d.hasFlag(SemanticsFlag.isButton) ? "button" : ""}');
        n.visitChildren((c) { walk(c); return true; });
      }
      walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      File('/downloads/radio-semantics-${w.toInt()}.txt').writeAsStringSync(out.toString());
    }
    h.dispose();
  });
}
