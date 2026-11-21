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
      testWidgets(
          'Ramadan table headers and times retain one line $width/$scale',
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
        const directory = String.fromEnvironment('RAMADAN_TABLE_PIXELS');
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

        final headers = [
          'رمضان',
          'التاريخ واليوم',
          'الإمساك',
          'الفجر',
          'الإفطار',
          'العشاء'
        ];
        final expected = RamadanService.instance.generateImsakiyyah().first;
        final times = [
          expected.imsakTime,
          expected.fajrTime,
          expected.maghribTime,
          expected.ishaTime
        ];
        for (final label in [...headers, ...times]) {
          final target = find.text(label).first;
          final paragraph = tester.renderObject<RenderParagraph>(target);
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length));
          expect(boxes.map((b) => b.top).toSet().length, 1, reason: label);
          expect(
              boxes.every((b) =>
                  b.left >= -0.1 && b.right <= paragraph.size.width + 0.1),
              isTrue,
              reason: label);
        }
        final nested =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        nested.outerController
            .jumpTo(nested.outerController.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final row = find
            .ancestor(of: find.text('1').first, matching: find.byType(InkWell))
            .first;
        expect(tester.widget<InkWell>(row).onTap, isNotNull);
        expect(
            tester
                .getSemantics(row)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue);
        final rowSemantics = tester.getSemantics(row);
        final spoken = rowSemantics.getSemanticsData().label;
        for (final value in [
          '1',
          expected.dayName,
          '${expected.gregorianDate.day}/${expected.gregorianDate.month}',
          ...times
        ]) {
          expect(spoken, contains(value),
              reason: 'row must keep each time with its day');
        }
        await capture('start');
        final horizontal =
            find.byKey(const ValueKey('ramadan_imsakiyyah_horizontal'));
        expect(horizontal, findsOneWidget);
        final scroll = tester.widget<SingleChildScrollView>(horizontal);
        final controller = scroll.controller!;
        expect(controller.position.maxScrollExtent, greaterThan(0));
        await tester.drag(
            horizontal, Offset(controller.position.maxScrollExtent + 100, 0));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(0));
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(row).getSemanticsData().label, spoken);
        await capture('end');
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
