import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/quran_english_source.dart';
import '../lib/features/mushaf/screens/quran_english_screen.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<String> asset(String p)=>File(p).readAsString();
  test('all 6236 bundled verses and footnotes preserve source rows, no network',()async {
    final manifest=jsonDecode(await asset('assets/data/english_rwwad_manifest.json'));
    final parts=await Future.wait([for(var i=1;i<=manifest['parts'];i++)asset('assets/data/english_rwwad_$i.b64')]);
    final rows=jsonDecode(utf8.decode(GZipDecoder().decodeBytes(base64Decode(parts.map((x)=>x.trim()).join()))))['rows'];
    final source=QuranEnglishSource(readAsset:asset);
    final counts=jsonDecode(await asset('assets/data/quran_ayahs.json')) as Map;
    var n=0;
    for(final row in rows){
      final v=await source.fetch(row['sura'],row['aya']);
      expect(v, isNotNull);expect(v!.text,row['translation']);expect(v.footnotes,row['footnotes']);n++;
    }
    for(final s in counts.keys){for(var a=1;a<=(counts[s] as List).length;a++){expect(await source.fetch(int.parse(s),a),isNotNull);}}
    expect(n,6236);expect(await source.fetch(115,1),isNull);expect(await source.fetch(1,8),isNull);
  });
  test('payload corruption or false version fails closed',()async{
    final source=QuranEnglishSource(readAsset:(p)async {
      final text=await asset(p);
      if(!p.endsWith('manifest.json'))return text;
      final meta=jsonDecode(text);meta['payloadSha256']='bad';return jsonEncode(meta);
    });
    expect(()=>source.fetch(1,1),throwsFormatException);
    final wrong=QuranEnglishSource(readAsset:(p)async{final s=await asset(p);if(!p.endsWith('manifest.json'))return s;final m=jsonDecode(s);m['version']='0';return jsonEncode(m);});
    expect(()=>wrong.fetch(1,1),throwsFormatException);
  });
  testWidgets('selected verse, its footnotes and navigation are English LTR', (t)async{
    final font=Platform.environment['READING_TEST_FONT'];
    if(font!=null)await t.runAsync(()async{
      await(FontLoader('ArabicTest')..addFont(Future.value(ByteData.sublistView(await File(font).readAsBytes())))).load();
      final latin=Platform.environment['READING_TEST_LATIN_FONT'];if(latin!=null)await(FontLoader('LatinTest')..addFont(Future.value(ByteData.sublistView(await File(latin).readAsBytes())))).load();
      final icons=Platform.environment['READING_TEST_ICON_FONT'];if(icons!=null)await(FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await File(icons).readAsBytes())))).load();
    });
    final source=QuranEnglishSource(readAsset:asset);await t.runAsync(()=>source.fetch(1,2));
    t.view.physicalSize=Size(double.parse(Platform.environment['ENGLISH_TEST_WIDTH']??'480'),1100);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    final key=GlobalKey();
    await t.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData(fontFamily:'ArabicTest',fontFamilyFallback:['LatinTest']),home:QuranEnglishScreen(surah:1,ayah:2,ayahCount:7,source:source))));
    await t.runAsync(()async{await Future<void>.delayed(const Duration(milliseconds:100));await t.pump();});await t.pumpAndSettle();expect(find.text('Translation 1:2'),findsOneWidget);expect(find.text('Footnotes'),findsOneWidget);
    final verse=find.byType(SelectableText).first;expect(Directionality.of(t.element(verse)),TextDirection.ltr);
    if(font!=null)await t.runAsync(()async{final image=await(key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await File('/tmp/quran-english-ui-${Platform.environment['ENGLISH_TEST_WIDTH']??'480'}.png').writeAsBytes(bytes!.buffer.asUint8List());});
    await t.tap(find.byTooltip('الآية التالية'));await t.runAsync(()async{await Future<void>.delayed(const Duration(milliseconds:100));await t.pump();});await t.pumpAndSettle();expect(find.text('Translation 1:3'),findsOneWidget);expect(find.text('Translation 1:2'),findsNothing);expect(t.takeException(),isNull);
  });
}
