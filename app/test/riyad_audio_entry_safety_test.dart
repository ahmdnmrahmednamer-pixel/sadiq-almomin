import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/adhkar_service.dart';
import 'package:almomin/core/services/islamic_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/adhkar/adhkar_audio_screen.dart';

import 'package:almomin/features/library/screens/riyad_alsalihin_screen.dart';
import 'package:almomin/core/services/riyad_alsalihin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory isolated;
  setUpAll(() async {
    isolated = Directory.systemTemp.createTempSync('riyad_safety_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => isolated.path);
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
    if (icons.isNotEmpty) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
    }
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    isolated.deleteSync(recursive: true);
  });
  String? copied;
  setUp(() async {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'has_completed_onboarding': true,
      'show_tutorial_screens': false,
      'riyad_bookmarks_v1': ['dua_1']
    });
    await SettingsService.instance.init(forceReload: true);
    await AdhkarService.instance.init(forceReload: true);
    IslamicAudioService.instance.disableNativePlayerForTesting = true;
    await IslamicAudioService.instance.stop();
    await RiyadAlSalihinService.instance.init(forceReload: true);
  });

  Future<void> mount(WidgetTester tester,
      {Widget child = const RiyadAlSalihinScreen(),
      double width = 320,
      double scale = 2,
      bool dark = false}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('separation-pixels'),
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Scaffold(body: child),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const dir = String.fromEnvironment('RIYAD_SAFETY_PIXELS_DIR');
    if (dir.isEmpty) return;
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('separation-pixels')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'all three written entries open independent safe audio without direct playback',
      (tester) async {
    for (final id in ['hisn_3', 'dua_1', 'dua_2']) {
      for (final dark in [false, true]) {
        final entry =
            RiyadAlSalihinService.allEntries.firstWhere((e) => e.id == id);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await mount(tester,
            child: RiyadAlSalihinScreen(
                initialEncyclopediaId: entry.encyclopediaId),
            dark: dark);
        await tester.scrollUntilVisible(find.byType(TextField), 300,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await tester.enterText(find.byType(TextField), entry.chapterTitle);
        await tester.pumpAndSettle();
        final open = find.widgetWithText(TextButton, 'فتح الأذكار المسموعة');
        await tester.scrollUntilVisible(open, 500,
            maxScrolls: 100,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await tester.pumpAndSettle();
        expect(find.text('قسم صوتي مستقل، وليس تسجيلاً لهذا النص.'),
            findsOneWidget);
        expect(find.text('استماع صوتي HD'), findsNothing);
        await capture(tester, '$id-320-2-$dark');
        final before = IslamicAudioService.instance.currentTrack;
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(find.byType(AdhkarAudioScreen), findsOneWidget);
        expect(IslamicAudioService.instance.currentTrack, before);
        final play = find.widgetWithText(FilledButton, 'استمع: أذكار الصباح');
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(IslamicAudioService.instance.queue.map((t) => t.id),
            AdhkarAudioScreen.tracks.map((t) => t.id));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(RiyadAlSalihinScreen), findsOneWidget);
        final copy = find.widgetWithText(TextButton, 'نسخ');
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(copied,
            '${entry.chapterTitle}\n\n${entry.arabicMatn}\n[${entry.sourceAndGrade}]\n\n💡 الفوائد: ${entry.sharhAndBenefits}\n— تطبيق صديق المؤمن');
        expect(RiyadAlSalihinService.instance.bookmarkedIds, {'dua_1'});
        expect(find.widgetWithText(TextButton, 'نسخ'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'مشاركة'), findsOneWidget);
        await IslamicAudioService.instance.stop();
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('unchanged Prophet ligature font comparison', (tester) async {
    const text = 'جمع النبي ﷺ في هذين الدعاءين';
    await mount(tester,
        dark: true,
        child: const Scaffold(
            body: Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  Text('Cairo'),
                  Text(text,
                      style: TextStyle(fontSize: 18, fontFamily: 'Cairo')),
                  Text('Amiri'),
                  Text(text,
                      style: TextStyle(fontSize: 18, fontFamily: 'Amiri')),
                ]))));
    await capture(tester, 'prophet-ligature-comparison');
    expect(tester.takeException(), isNull);
  });
}
