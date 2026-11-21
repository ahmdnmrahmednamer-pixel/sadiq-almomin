import 'dart:io';import 'dart:convert';import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/tafsir_service.dart';import '../lib/core/services/bundled_tafsir_source.dart';import '../lib/core/services/lubab_source.dart';import '../lib/core/services/quran_repository.dart';
class NoHttp extends HttpOverrides{int calls=0;@override HttpClient createHttpClient(SecurityContext? context){calls++;throw StateError('Offline integration forbids all HTTP');}}
void main(){TestWidgetsFlutterBinding.ensureInitialized();final noHttp=NoHttp();
 setUpAll((){HttpOverrides.global=noHttp;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});});
 tearDownAll((){HttpOverrides.global=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);QuranRepository.resetCachesForTesting();});
 test('actual activated Saadi TafsirService reaches exact prepared source at all6236ayahs offline',()async{
  final direct=BundledTafsirSource();final surahs=jsonDecode(File('assets/data/surahs.json').readAsStringSync())as List;var count=0;
  for(final s in surahs){for(var a=1;a<=s['ayah_count'];a++){
   final result=await TafsirService.getTafsir(surahId:s['id'],ayahNumber:a,editionId:'saadi');final expected=await direct.fetch('saadi_roots',s['id'],a);
   expect(result.hasSourceText,isTrue,reason:'${s['id']}:$a');expect(result.editionId,'saadi');expect(result.sourcePages.map((p)=>p.text),expected!.pages.map((p)=>p.text));expect(result.sourcePages.map((p)=>p.sourceId),expected.pages.map((p)=>p.sourceId));count++;
  }}expect(count,6236);expect(noHttp.calls,0);expect(await TafsirService.getBookSections('saadi'),isNotEmpty);
 });
 test('actual default Lubab bundle reaches every1314reviewed record without injected index or network',()async{
  final idx=jsonDecode(File('assets/data/lubab_verse_index.json').readAsStringSync());final source=LubabSource();final targets=<String>{};for(final r in idx['records']){targets.add('${r['surah']}:${r['ayah']}');}var count=0;
  for(final key in targets){final k=key.split(':').map(int.parse).toList();final entries=await source.fetch(k[0],k[1]);expect(entries,isNotEmpty,reason:key);count+=entries.length;}
  expect((idx['records']as List).length,1315);expect(targets.length,998);expect(count,1315);expect(noHttp.calls,0);
 });
 test('existing five tafsir routes remain separate from Saadi',()async{
  for(final edition in ['jalalayn','ibn_kathir','tabari','baghawi','qurtubi']){for(final s in [1,2,35,40,114]){final result=await TafsirService.getTafsir(surahId:s,ayahNumber:2,editionId:edition);expect(result.hasSourceText,isTrue,reason:'$edition:$s');expect(result.editionId,edition);}}
  expect(noHttp.calls,0);
 });
}
