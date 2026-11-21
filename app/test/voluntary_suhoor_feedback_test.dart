import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/voluntary_fasting_service.dart';
import 'package:almomin/features/prayer/voluntary_fasting_screen.dart';
import 'ramadan_tracker_persistence_test.dart' show RamadanProbeStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Narrow phone card-row overflow is tracked separately from this save feedback.
  for (final (width, scale) in [(600.0, 1.0), (1000.0, 2.0)]) {
    testWidgets('suhoor failed preference feedback and retry $width/$scale',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late RamadanProbeStore store;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await SettingsService.instance.init();
        store = RamadanProbeStore();
        SharedPreferencesStorePlatform.instance = store;
        await VoluntaryFastingService.instance.init(forceReload: true);
        await (FontLoader('Cairo')
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
            .load();
        await (FontLoader('Amiri')
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync()))))
            .load();
        const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
        if (icons.isNotEmpty)
          await (FontLoader('MaterialIcons')
                ..addFont(Future.value(
                    ByteData.sublistView(File(icons).readAsBytesSync()))))
              .load();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Cairo'),
            builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const VoluntaryFastingScreen(),
          )));
      await tester.pumpAndSettle();
      final action = find.byType(SwitchListTile);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      store.reject = true;
      await tester.tap(action);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(VoluntaryFastingService.instance.suhoorReminderEnabled, isTrue);
      expect(
          find.text(
              'تعذر تأكيد حفظ اختيار تذكير السحور. يرجى المحاولة مرة أخرى.'),
          findsOneWidget);
      const directory = String.fromEnvironment('SUHOOR_PIXELS');
      if (directory.isNotEmpty)
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/failure-$width-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      store.reject = false;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(VoluntaryFastingService.instance.suhoorReminderEnabled, isFalse);
      final pending = Completer<void>();
      store.gate = pending;
      store.reject = true;
      final dynamic callback = tester.widget<SwitchListTile>(action).onChanged;
      late Future<void> pendingAction;
      await tester.runAsync(() async {
        pendingAction = callback(true) as Future<void>;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        pending.complete();
        await pendingAction;
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
