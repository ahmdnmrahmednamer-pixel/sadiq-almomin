import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/audio/fast_audio_service.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/theme/app_theme.dart';
import 'package:almomin/features/audio/audio_screen.dart';
import 'package:almomin/core/services/audio_download_service.dart';
import 'quran_audio_download_race_test.dart' as http;
import 'quran_listening_entry_restoration_test.dart' show ListeningProbePlayer;

Color background(WidgetTester tester, Finder finder) {
  var color = Colors.transparent;
  tester.element(finder).visitAncestorElements((element) {
    final widget = element.widget;
    Color? fill;
    if (widget is ListTile) fill = widget.tileColor;
    if (widget is InputDecorator) fill = widget.decoration.filled == true ? widget.decoration.fillColor : null;
    if (widget is Container) {
      fill = widget.color;
      if (widget.decoration is BoxDecoration) fill ??= (widget.decoration as BoxDecoration).color;
    }
    if (widget is Material) fill = widget.color;
    if (widget is Scaffold) fill = widget.backgroundColor ?? Theme.of(element).scaffoldBackgroundColor;
    if (fill != null) color = Color.alphaBlend(color, fill);
    return color.a < 1;
  });
  expect(color.a, 1);
  return color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  HttpOverrides? previous;
  final downloads = AudioDownloadService.instance;
  final requests = <Uri>[];
  final engine = FastAudioService.instance;
  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('audio-contrast-');
    previous = HttpOverrides.current;
    HttpOverrides.global = http.DynamicHttpOverrides();
    http.DynamicHttpOverrides.activeHandler = (_, uri, request) async {
      requests.add(uri);
      return http.TestHttpClientResponse(Stream.value(Uint8List.fromList(List<int>.filled(4096,1))),contentLength:4096);
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => temp.path);
    for (final family in ['Cairo', 'Amiri']) {
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$family-Regular.ttf').readAsBytesSync())))).load();
    }
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File(icons).readAsBytesSync())))).load();
    await QuranRepository.loadSurahs();
    await downloads.init();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init(forceReload: true);
    engine.resetForTesting();
    requests.clear();
  });
  tearDown(() async {
    engine.resetForTesting();
    await downloads.deleteDownloadedSurah(SettingsService.instance.currentReciter.id,1);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    HttpOverrides.global = previous;
    http.DynamicHttpOverrides.activeHandler = null;
    temp.deleteSync(recursive: true);
  });

  for (final mode in [AppThemeMode.dark, AppThemeMode.black]) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('listening contrast ${mode.name} $width/$scale', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final player = ListeningProbePlayer();
          final boundary = GlobalKey();
          final measures = <Map<String, Object>>[];
          void measure(String label, Finder finder, {double minimum = 4.5}) {
            final fg = tester.renderObject<RenderParagraph>(finder).text.style!.color!;
            final bg = background(tester, finder);
            final a = Color.alphaBlend(fg, bg).computeLuminance();
            final b = bg.computeLuminance();
            final ratio = (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
            measures.add({'label':label,'foreground':fg.toARGB32(),'background':bg.toARGB32(),'ratio':ratio,'minimum':minimum});
          }
          Finder icon(IconData data) => find.descendant(of: find.byIcon(data).first, matching: find.byType(RichText)).first;
          await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(debugShowCheckedModeBanner:false, theme:AppTheme.of(mode), builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)), child:Directionality(textDirection:TextDirection.rtl,child:child!)), home:AudioScreen(player:player,loadSource:(url,key)async=>AudioSource.uri(Uri.parse(url))))));
          await tester.pumpAndSettle();
          measure('search icon', icon(Icons.search),minimum:3);
          final first = find.text('سورة الفاتحة');
          await tester.scrollUntilVisible(first,200,scrollable:find.byType(Scrollable).first,maxScrolls:30);
          await tester.ensureVisible(first);
          await tester.pumpAndSettle();
          final initialRow=find.ancestor(of:first,matching:find.byType(ListTile));
          for(final data in [Icons.play_circle_fill,Icons.download_for_offline_outlined]) {
            final control=find.descendant(of:initialRow,matching:find.byIcon(data));
            measure(data==Icons.play_circle_fill ? 'unselected play' : 'download',find.descendant(of:control,matching:find.byType(RichText)).first,minimum:3);
          }
          await tester.tap(first);
          await tester.pumpAndSettle();
          await tester.ensureVisible(first.first);
          await tester.pumpAndSettle();
          final row=find.ancestor(of:first.first,matching:find.byType(ListTile));
          measure('selected surah',find.descendant(of:row,matching:find.text('سورة الفاتحة')));
          measure('surah details',find.descendant(of:row,matching:find.byType(Text)).at(2));
          measure('loaded reciter',find.text(SettingsService.instance.currentReciter.nameAr));
          measure('playback speed',find.text('1.0x'));
          for(final time in find.text('00:00').evaluate()) {measure('elapsed time',find.byElementPredicate((e)=>identical(e,time)));}
          measure('selected pause',icon(Icons.pause_circle_filled),minimum:3);
          measure('mini-player pause',find.descendant(of:find.byIcon(Icons.pause_circle_filled).last,matching:find.byType(RichText)).first,minimum:3);
          measure('playback notice',find.textContaining('بدء تشغيل سورة'));
          await tester.pump(const Duration(seconds:3));
          await tester.pumpAndSettle();
          measure('repeat',icon(Icons.repeat),minimum:3);
          expect(player.starts,1);
          expect(tester.takeException(),isNull);
          const output=String.fromEnvironment('AUDIO_CONTRAST_DIR');
          if(output.isNotEmpty) { await tester.runAsync(()async{
            Directory(output).createSync(recursive:true);
            final name='${mode.name}-$width-$scale';
            File('$output/$name.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(measures));
            final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
            final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();
          }); }
          // Complete the real screen's download flow, without a second play.
          final download = find.descendant(of: row, matching: find.byTooltip('تحميل للاستماع بدون إنترنت'));
          await tester.ensureVisible(download);
          await tester.tap(download);
          for(var i=0;i<10 && !downloads.isDownloaded(SettingsService.instance.currentReciter.id,1);i++) {
            await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));
            await tester.pump(const Duration(milliseconds:100));
          }
          expect(downloads.isDownloaded(SettingsService.instance.currentReciter.id,1),isTrue);
          final reciter=SettingsService.instance.currentReciter.id;
          final downloadUrl=SettingsService.instance.getSurahAudioUrl(1,reciter);
          final prefetchUrl=SettingsService.instance.getSurahAudioUrl(2,reciter);
          expect(requests.where((u)=>u.toString()==downloadUrl),hasLength(1));
          expect(requests.every((u)=>u.toString()==downloadUrl || u.toString()==prefetchUrl),isTrue,reason:'The existing player may prefetch surah2; downloading surah1 must remain separate');
          final notice=find.text('تم اكتمال تحميل سورة الفاتحة بنجاح ✓');
          for(var i=0;i<12 && notice.evaluate().isEmpty;i++) {
            await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));
            await tester.pump(const Duration(milliseconds:500));
          }
          await tester.pumpAndSettle();
          expect(notice,findsOneWidget);
          measure('download completion notice',notice);
          expect(player.starts,1,reason:'A completed download must not start another playback');
          if(output.isNotEmpty) { await tester.runAsync(()async{
            final name='${mode.name}-$width-$scale-download';
            File('$output/$name.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(measures));
            final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
            final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
            File('$output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();
          }); }
          await tester.pumpWidget(const SizedBox());
          expect(measures.where((m)=>(m['ratio'] as double)<(m['minimum'] as double)),isEmpty,reason:jsonEncode(measures));
        });
      }
    }
  }
}
