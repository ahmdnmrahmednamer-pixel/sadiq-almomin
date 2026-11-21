import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/features/prayer/widgets/adhan_full_screen_access_card.dart';
import 'package:almomin/features/prayer/battery_reliability_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('FSI explanation and request readable at $scale', (t) async {
      const channel = MethodChannel('almomin/adhan_permissions');
      final m =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(channel, (call) async => false);
      addTearDown(() => m.setMockMethodCallHandler(channel, null));
      await t.runAsync(() async {
        await (FontLoader('Cairo')
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
            .load();
      });
      t.view.physicalSize = const Size(360, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: AdhanFullScreenAccessCard()))))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final dir = Platform.environment['FSI_SCREENSHOT_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/fsi-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      await t.ensureVisible(
          find.byKey(const ValueKey('adhan_full_screen_request')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'integrated battery guide reaches FSI card without permission requests at $scale',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      const fsi = MethodChannel('almomin/adhan_permissions');
      const permission =
          MethodChannel('flutter.baseflow.com/permissions/methods');
      final m =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var requests = 0;
      m.setMockMethodCallHandler(fsi, (call) async => false);
      m.setMockMethodCallHandler(permission, (call) async {
        if (call.method == 'checkPermissionStatus') return 0;
        requests++;
        return null;
      });
      addTearDown(() {
        m.setMockMethodCallHandler(fsi, null);
        m.setMockMethodCallHandler(permission, null);
      });
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              theme: ThemeData(fontFamily: 'Cairo'),
              home: const BatteryReliabilityScreen())));
      await t.pumpAndSettle();
      expect(requests, 0);
      expect(find.textContaining('١٠٠٪'), findsNothing);
      await t.scrollUntilVisible(find.byType(AdhanFullScreenAccessCard), 180,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
          t.element(find.text('شاشة الأذان الكاملة')),
          alignment: 0);
      await t.pumpAndSettle();
      final dir = Platform.environment['FSI_SCREENSHOT_DIR'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/integrated-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      await t.ensureVisible(
          find.byKey(const ValueKey('adhan_full_screen_request')));
      await t.pumpAndSettle();
      if (dir != null)
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/integrated-actions-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
      expect(find.text('شاشة الأذان الكاملة'), findsOneWidget);
      expect(requests, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
