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
import 'voluntary_fasting_persistence_failure_test.dart'
    show RejectingFastStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = VoluntaryFastingService.instance;
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final f = File('assets/fonts/$family-$weight.ttf');
        if (f.existsSync())
          loader
              .addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      }
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty && File(icons).existsSync())
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'fasting storage feedback and protected reload fit dark=$dark scale=$scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final store = RejectingFastStore();
        SharedPreferencesStorePlatform.instance = store;
        await tester.runAsync(() async {
          await SettingsService.instance.init(forceReload: true);
          await service.init(forceReload: true);
        });
        Future<void> flushPlatform() async {
          // Bridge real provider futures and Flutter's fake clock explicitly.
          for (var tick = 0; tick < 12; tick++) {
            await tester.pump();
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            });
          }
          await tester.pumpAndSettle();
        }

        final boundary = GlobalKey();
        final semantics = tester.ensureSemantics();
        Future<void> capture(String name) async {
          final dir = Platform.environment['FAST_PERSIST_PIXELS'];
          if (dir == null) return;
          await tester.runAsync(() async {
            Directory(dir).createSync(recursive: true);
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$dir/$name-$dark-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: 'Cairo'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const VoluntaryFastingScreen(),
            )));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await flushPlatform();
        final actions =
            find.byKey(const ValueKey('fast_actions_monday_thursday'));
        final scroll = find.byType(Scrollable).first;
        Future<void> show(Finder f, {double step = 250}) async {
          await tester.scrollUntilVisible(f, step,
              scrollable: scroll, maxScrolls: 100);
          await tester.ensureVisible(f);
          await flushPlatform();
        }

        try {
          await show(actions);
          final confirm = find.descendant(
              of: actions, matching: find.byType(ElevatedButton));
          final undo =
              find.descendant(of: actions, matching: find.byType(IconButton));
          expect(
              tester
                  .getSemantics(confirm)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue);
          store.reject = true;
          await tester.runAsync(() async {
            await tester.tap(confirm);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flushPlatform();
          expect(service.getCountForType('monday_thursday'), 0);
          final confirmError =
              find.text('تعذر تأكيد حفظ تسجيل الصيام. حاول مرة أخرى.');
          expect(confirmError, findsOneWidget);
          expect(
              tester
                  .renderObject<RenderParagraph>(confirmError)
                  .didExceedMaxLines,
              isFalse);
          await capture('confirm-error');
          ScaffoldMessenger.of(tester.element(actions)).hideCurrentSnackBar();
          await flushPlatform();
          store.reject = false;
          await tester.runAsync(() async {
            await tester.tap(confirm);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flushPlatform();
          expect(service.getCountForType('monday_thursday'), 1);
          store.reject = true;
          await tester.runAsync(() async {
            await tester.tap(undo);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flushPlatform();
          expect(service.getCountForType('monday_thursday'), 1);
          final undoError =
              find.text('تعذر تأكيد حفظ تعديل الصيام. حاول مرة أخرى.');
          expect(undoError, findsOneWidget);
          expect(
              tester.renderObject<RenderParagraph>(undoError).didExceedMaxLines,
              isFalse);
          await capture('undo-error');
          ScaffoldMessenger.of(tester.element(actions)).hideCurrentSnackBar();
          await flushPlatform();
          const key = 'flutter.voluntary_fast_progress_v1';
          final saved = store.values[key]!;
          store.values[key] = '{bad';
          await tester.runAsync(() async {
            await service.init(forceReload: true);
          });
          await flushPlatform();
          expect(service.progressLoadFailed, isTrue);
          expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
          expect(tester.widget<IconButton>(undo).onPressed, isNull);
          const warning =
              'تعذر تحميل سجل الصيام المحفوظ. لم نؤكد الأعداد المعروضة.';
          await show(find.text(warning), step: -250);
          expect(
              tester
                  .renderObject<RenderParagraph>(find.text(warning))
                  .didExceedMaxLines,
              isFalse);
          final retry =
              find.widgetWithText(TextButton, 'إعادة تحميل سجل الصيام');
          expect(
              tester
                  .getSemantics(retry)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue);
          await capture('load-warning');
          store.reject = false;
          store.values[key] = saved;
          await tester.runAsync(() async {
            await tester.tap(retry);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flushPlatform();
          expect(service.progressLoadFailed, isFalse);
          expect(find.text(warning), findsNothing);
          expect(service.getCountForType('monday_thursday'), 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await flushPlatform();
          semantics.dispose();
        }
      });
    }
  }
}
