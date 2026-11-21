import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/voluntary_fasting_service.dart';
import 'package:almomin/features/prayer/voluntary_fasting_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all fasting card actions fit $width/$scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          await SettingsService.instance.init();
          await VoluntaryFastingService.instance.init(forceReload: true);
          for (final font in ['Cairo', 'Amiri']) {
            await (FontLoader(font)
                  ..addFont(Future.value(ByteData.sublistView(
                      File('assets/fonts/$font-Regular.ttf')
                          .readAsBytesSync()))))
                .load();
          }
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
              home: const VoluntaryFastingScreen(),
            )));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pumpAndSettle();
        final scrollable = find.byType(Scrollable).first;
        for (final fast in VoluntaryFastingService.fastTypes) {
          final actions = find.byKey(ValueKey('fast_actions_${fast.id}'));
          await tester.scrollUntilVisible(actions, 250, scrollable: scrollable);
          await tester.ensureVisible(actions);
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(actions);
          for (final child in find
              .descendant(of: actions, matching: find.byType(Text))
              .evaluate()) {
            final childRect = tester.getRect(find
                .byElementPredicate((element) => identical(element, child)));
            expect(childRect.left, greaterThanOrEqualTo(rect.left - 1));
            expect(childRect.right, lessThanOrEqualTo(rect.right + 1));
          }
          final confirm = find.descendant(
              of: actions, matching: find.byType(ElevatedButton));
          final confirmNode = tester.getSemantics(confirm);
          expect(confirmNode.label, contains('صمتُ هذا اليوم'));
          expect(
              confirmNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          debugPrint('confirm ${fast.id}: ${confirmNode.label}');
          await tester.runAsync(() async {
            await tester.tap(confirm);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await tester.pumpAndSettle();
          expect(VoluntaryFastingService.instance.getCountForType(fast.id), 1);
          final undo =
              find.descendant(of: actions, matching: find.byTooltip('إنقاص'));
          final undoNode = tester.getSemantics(undo);
          debugPrint(undoNode.toStringDeep());
          expect(undoNode.getSemanticsData().tooltip, contains('إنقاص'));
          expect(undoNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          await tester.runAsync(() async {
            await tester.tap(undo);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await tester.pumpAndSettle();
          expect(VoluntaryFastingService.instance.getCountForType(fast.id), 0);
          expect(tester.takeException(), isNull);
          if (fast.id == 'monday_thursday' || fast.id == 'shaban_fasting') {
            const directory = String.fromEnvironment('FAST_LAYOUT_PIXELS');
            if (directory.isNotEmpty)
              await tester.runAsync(() async {
                final image = await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('$directory/${fast.id}-$width-$scale.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
          }
        }
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pumpAndSettle();
      });
    }
  }
}
