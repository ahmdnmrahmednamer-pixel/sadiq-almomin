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
  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Ramadan title tabs and tracker fit $width/$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
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
        expect(tester.takeException(), isNull);
        const directory = String.fromEnvironment('RAMADAN_LAYOUT_PIXELS');
        Future<void> capture(String state) async {
          if (directory.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$directory/$state-$width-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('top');
        await tester.ensureVisible(find.text('متابع الصيام والعبادات'));
        await tester.tap(find.text('متابع الصيام والعبادات'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('tracker');
        await tester.ensureVisible(find.text('سجل إنجاز العبادات الرمضانية'));
        await tester.pumpAndSettle();
        await capture('summary');
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -650));
        await tester.pumpAndSettle();
        final action = find.byTooltip('صمت هذا اليوم').first;
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await capture('days');
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(RamadanService.instance.totalFastedCount, 1);
        final tabs = tester.widget<TabBar>(find.byType(TabBar));
        for (final index in [2, 0, 1]) {
          final label = [
            'الإمساكية (٣٠ يوماً)',
            'متابع الصيام والعبادات',
            'أدعية وسنن الصائم'
          ][index];
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(tabs.controller!.index, index);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
