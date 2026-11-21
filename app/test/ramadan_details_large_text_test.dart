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
      for (final input in ['semantics', 'touch']) {
        testWidgets(
            'Ramadan details stays readable and scrollable $width/$scale/$input',
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
                      File('assets/fonts/Cairo-Regular.ttf')
                          .readAsBytesSync()))))
                .load();
            const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
            if (icons.isNotEmpty)
              await (FontLoader('MaterialIcons')
                    ..addFont(Future.value(
                        ByteData.sublistView(File(icons).readAsBytesSync()))))
                  .load();
          });
          final semantics = tester.ensureSemantics();
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
          const directory = String.fromEnvironment('RAMADAN_DETAILS_PIXELS');
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

          final expected = RamadanService.instance.generateImsakiyyah().first;
          final nested = tester
              .state<NestedScrollViewState>(find.byType(NestedScrollView));
          nested.outerController
              .jumpTo(nested.outerController.position.maxScrollExtent);
          await tester.pumpAndSettle();
          final row = find.byKey(const ValueKey('ramadan_imsakiyyah_day_1'));
          final dayNode = tester.getSemantics(row);
          if (input == 'semantics') {
            dayNode.owner!.performAction(dayNode.id, SemanticsAction.tap);
          } else {
            await tester.tap(find.text('1').first);
          }
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture('top');
          final sheet = find.byType(BottomSheet);
          for (final label in [
            'الإمساك',
            'الفجر',
            'الشروق',
            'الظهر',
            'العصر',
            'المغرب (الإفطار)',
            'العشاء'
          ]) {
            final target =
                find.descendant(of: sheet, matching: find.text(label));
            expect(target, findsOneWidget);
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            final rect = tester.getRect(target);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          final duaa = find.descendant(
              of: sheet, matching: find.text(expected.dailyDuaa));
          await tester.ensureVisible(duaa);
          await tester.pumpAndSettle();
          await capture('footer');
          expect(tester.takeException(), isNull);
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await tester.pumpAndSettle();
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
