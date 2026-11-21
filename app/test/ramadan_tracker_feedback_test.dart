import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/ramadan_service.dart';
import 'package:almomin/core/services/prayer_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/ramadan/ramadan_screen.dart';
import 'ramadan_tracker_persistence_test.dart' show RamadanProbeStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final tooltip in [
    'صمت هذا اليوم',
    'صليت التراويح / القيام',
    'قرأت الورد القرآني',
    'dispose'
  ]) {
    const scale = 1.0;
    testWidgets('Ramadan failed save feedback and retry for $tooltip',
        (tester) async {
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late RamadanProbeStore store;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          PrayerService.locationSourceKey: PrayerService.locationSourceGps,
          PrayerService.locationUpdatedAtMsKey:
              DateTime.now().toUtc().millisecondsSinceEpoch,
          'last_latitude': 24.7136,
          'last_longitude': 46.6753,
          'last_city': 'الرياض',
        });
        await SettingsService.instance.init();
        await PrayerService.instance.init(forceReload: true);
        store = RamadanProbeStore();
        SharedPreferencesStorePlatform.instance = store;
        await RamadanService.instance.init(forceReload: true);
        await (FontLoader('Cairo')
              ..addFont(Future.value(ByteData.sublistView(
                  File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
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
            home: const RamadanScreen(),
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابع الصيام والعبادات'));
      await tester.pumpAndSettle();
      final action = find
          .byTooltip(tooltip == 'dispose' ? 'صمت هذا اليوم' : tooltip)
          .first;
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      store.reject = true;
      if (tooltip == 'dispose') {
        final pending = Completer<void>();
        store.gate = pending;
        await tester.tap(action);
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
      await tester.tap(action);
      await tester.pumpAndSettle();
      bool checked() => switch (tooltip) {
            'صمت هذا اليوم' => RamadanService.instance.isDayFasted(1),
            'صليت التراويح / القيام' =>
              RamadanService.instance.isTaraweehCompleted(1),
            _ => RamadanService.instance.isQuranCompleted(1),
          };
      expect(checked(), isFalse);
      expect(find.text('تعذر تأكيد حفظ سجل العبادة. يرجى المحاولة مرة أخرى.'),
          findsOneWidget);
      const directory = String.fromEnvironment('RAMADAN_PIXELS');
      if (directory.isNotEmpty)
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/failure-${tooltip.hashCode}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      store.reject = false;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(checked(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
