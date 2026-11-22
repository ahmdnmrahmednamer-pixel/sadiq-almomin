import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/features/search/quran_search_screen.dart';
import 'quran_search_history_failure_test.dart' show RejectingHistoryStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Cairo', 'Amiri']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        final file = File('assets/fonts/$family-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty && File(icons).existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });
  testWidgets('history completion after disposal does not update a dead screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RejectingHistoryStore();
    const key = 'flutter.quran_search_history_v1';
    store.values[key] = <String>['saved query'];
    SharedPreferencesStorePlatform.instance = store;
    await tester.pumpWidget(const MaterialApp(home: QuranSearchScreen()));
    for (var tick = 0; tick < 8; tick++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
    }
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    store.gate = gate;
    store.entered = Completer<void>();
    try {
      await tester.runAsync(() async {
        await tester.tap(find.text('مسح السجل'));
      });
      for (var tick = 0; tick < 20 && !store.entered!.isCompleted; tick++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
      }
      expect(store.entered!.isCompleted, isTrue);
      await tester.pumpWidget(const SizedBox());
    } finally {
      gate.complete();
    }
    for (var tick = 0; tick < 12; tick++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
    }
    await tester.pumpAndSettle();
    expect(store.values[key], isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'history failures keep history and Quran results dark=$dark scale=$scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final store = RejectingHistoryStore();
        const key = 'flutter.quran_search_history_v1';
        store.values[key] = <String>['بحث محفوظ'];
        SharedPreferencesStorePlatform.instance = store;
        final boundary = GlobalKey();
        final semantics = tester.ensureSemantics();
        Future<void> flush() async {
          for (var tick = 0; tick < 80; tick++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            });
            if (tick >= 5 &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty)
              break;
          }
          await tester.pumpAndSettle();
        }

        Future<void> open() async {
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
                    child: Directionality(
                        textDirection: TextDirection.rtl, child: child!)),
                home: const QuranSearchScreen(),
              )));
          await flush();
        }

        Future<void> capture(String name) async {
          final dir = Platform.environment['HISTORY_FAILURE_PIXELS'];
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

        void expectMessage(String message) {
          final text = find.text(message);
          expect(text, findsOneWidget);
          expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
              isFalse);
        }

        Future<void> dismiss() async {
          ScaffoldMessenger.of(tester.element(find.byType(QuranSearchScreen)))
              .hideCurrentSnackBar();
          await flush();
        }

        try {
          await open();
          expect(find.text('بحث محفوظ'), findsOneWidget);
          store.reject = true;
          await tester.runAsync(() async {
            await tester.tap(find.text('مسح السجل'));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flush();
          expectMessage('تعذر تأكيد حفظ مسح سجل البحث. حاول مرة أخرى.');
          expect(find.text('بحث محفوظ'), findsOneWidget);
          expect(store.values[key], ['بحث محفوظ']);
          await capture('clear-error');
          await dismiss();
          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('Delete'));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flush();
          expectMessage('تعذر تأكيد حفظ حذف البحث من السجل. حاول مرة أخرى.');
          expect(find.text('بحث محفوظ'), findsOneWidget);
          expect(store.values[key], ['بحث محفوظ']);
          await capture('remove-error');
          await dismiss();
          store.reject = false;
          store.throwing = true;
          await tester.enterText(find.byType(TextField), 'الإخلاص');
          await tester.runAsync(() async {
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flush();
          expectMessage('تعذر تأكيد حفظ سجل البحث. يمكنك متابعة البحث.');
          expect(find.text('سورة الإخلاص'), findsOneWidget);
          expect(
              find.text(
                  'تعذر تحميل بيانات المصحف للبحث. يرجى المحاولة مرة أخرى.'),
              findsNothing);
          expect(store.values[key], ['بحث محفوظ']);
          await capture('search-error');
          await dismiss();
          store.throwing = false;
          store.failReadsAfterWrite = true;
          await tester.enterText(find.byType(TextField), 'الفلق');
          await tester.runAsync(() async {
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flush();
          expectMessage('تعذر تحميل سجل البحث المحفوظ. يمكنك متابعة البحث.');
          expect(find.text('سورة الفلق'), findsOneWidget);
          expect(
              find.text(
                  'تعذر تحميل بيانات المصحف للبحث. يرجى المحاولة مرة أخرى.'),
              findsNothing);
          expect(store.values[key], ['الفلق', 'بحث محفوظ']);
          await capture('search-read-error');
          await tester.pumpWidget(const SizedBox());
          await flush();
          store.failReadsAfterWrite = false;
          store.throwing = false;
          store.failReads = true;
          await open();
          expectMessage('تعذر تحميل سجل البحث المحفوظ. يمكنك متابعة البحث.');
          expect(find.text('عمليات بحث مقترحة'), findsOneWidget);
          expect(find.byType(TextField), findsOneWidget);
          await capture('load-error');
          store.failReads = false;
          await tester.pumpWidget(const SizedBox());
          await flush();
          await open();
          expect(find.text('بحث محفوظ'), findsOneWidget);
          await tester.runAsync(() async {
            await tester.tap(find.text('مسح السجل'));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await flush();
          expect(find.text('سجل البحث الأخير'), findsNothing);
          expect(find.text('عمليات بحث مقترحة'), findsOneWidget);
          expect(store.values[key], isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await flush();
          semantics.dispose();
        }
      });
    }
  }
}
