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

class RamadanRouteProbe extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Ramadan row speaks named times and day $width/$scale',
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
        final routeProbe = RamadanRouteProbe();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorObservers: [routeProbe],
              theme: ThemeData(fontFamily: 'Cairo'),
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const RamadanScreen(),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const directory = String.fromEnvironment('RAMADAN_SEMANTICS_PIXELS');
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
        final nested =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        nested.outerController
            .jumpTo(nested.outerController.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final row = find
            .ancestor(of: find.text('1').first, matching: find.byType(InkWell))
            .first;
        final spoken = tester.getSemantics(row).getSemanticsData();
        expect(spoken.label, contains('اليوم 1 من رمضان'));
        expect(spoken.label, contains(expected.dayName));
        expect(
            spoken.label,
            contains(
                '${expected.gregorianDate.day}/${expected.gregorianDate.month}'));
        for (final pair in [
          'الإمساك ${expected.imsakTime}',
          'الفجر ${expected.fajrTime}',
          'الإفطار ${expected.maghribTime}',
          'العشاء ${expected.ishaTime}',
        ]) {
          expect(spoken.label, contains(pair));
          expect(spoken.label.split(pair).length, 2, reason: 'one spoken copy');
        }
        expect(spoken.hasAction(SemanticsAction.tap), isTrue);
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
        expect(tester.getSemantics(row).getSemanticsData().label, spoken.label);
        await capture('end');
        expect(tester.takeException(), isNull);
        // Check navigation dispatch only. Rendering the existing details sheet
        // is outside this semantics-only regression.
        final dayNode = tester.getSemantics(row);
        dayNode.owner!.performAction(dayNode.id, SemanticsAction.tap);
        expect(routeProbe.pushed.last, isA<ModalBottomSheetRoute<dynamic>>());
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
