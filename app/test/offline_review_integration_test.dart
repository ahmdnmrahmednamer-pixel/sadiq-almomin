// Requires the separately approved local source assets listed in REVIEW.md.
// No source/book text is contained in this test.
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/tafsir_service.dart';
import 'package:almomin/core/services/bundled_tafsir_source.dart';
import 'package:almomin/core/services/lubab_source.dart';
import 'package:almomin/core/services/quran_repository.dart';
class DenyHttp extends HttpOverrides{
 int attempts=0;
 @override HttpClient createHttpClient(SecurityContext? context){attempts++;throw StateError('HTTP forbidden in offline review');}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();final denied=DenyHttp();
 setUpAll((){
  HttpOverrides.global=denied;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(message)async{
   final path=utf8.decode(message!.buffer.asUint8List());final file=File(path);
   return file.existsSync()?ByteData.sublistView(file.readAsBytesSync()):null;
  });
 });
 tearDownAll((){HttpOverrides.global=null;QuranRepository.resetCachesForTesting();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',null);});
 test('all Saadi ayah service results match exact bundled rows offline',()async{
  final direct=BundledTafsirSource();final surahs=jsonDecode(File('assets/data/surahs.json').readAsStringSync())as List;var count=0;
  for(final surah in surahs){for(var ayah=1;ayah<=surah['ayah_count'];ayah++){
   final result=await TafsirService.getTafsir(surahId:surah['id'],ayahNumber:ayah,editionId:'saadi');final expected=await direct.fetch('saadi_roots',surah['id'],ayah);
   expect(result.hasSourceText,isTrue,reason:'${surah['id']}:$ayah');expect(result.editionId,'saadi');expect(result.sourcePages.map((p)=>p.text),expected!.pages.map((p)=>p.text));expect(result.sourcePages.map((p)=>p.sourceId),expected.pages.map((p)=>p.sourceId));count++;
  }}expect(count,6236);expect(await TafsirService.getBookSections('saadi'),isNotEmpty);expect(denied.attempts,0);
 });
 test('default Lubab reader resolves every indexed record offline',()async{
  final index=jsonDecode(File('assets/data/lubab_verse_index.json').readAsStringSync());final source=LubabSource();final targets=<String>{};for(final row in index['records']){targets.add('${row['surah']}:${row['ayah']}');}var count=0;
  final expected=jsonDecode(File('test/fixtures/private_lubab_expected.json').readAsStringSync())as Map;
  for(final target in targets){final key=target.split(':').map(int.parse).toList();final entries=await source.fetch(key[0],key[1]);expect(entries,isNotEmpty,reason:target);final rows=expected[target]as List;expect(entries.length,rows.length,reason:target);
   for(var n=0;n<entries.length;n++){expect(sha256.convert(utf8.encode(entries[n].text)).toString(),rows[n]['sha256'],reason:'$target:$n');expect(entries[n].contextNote,rows[n]['contextNote']);expect(entries[n].pages,rows[n]['pages']);}
   count+=entries.length;}
  expect(count,(index['records']as List).length);expect(count,1315);expect(denied.attempts,0);
 });
 test('five existing tafsir routes remain distinct in regression samples',()async{
  for(final edition in ['jalalayn','ibn_kathir','tabari','baghawi','qurtubi']){for(final surah in [1,2,35,40,114]){final result=await TafsirService.getTafsir(surahId:surah,ayahNumber:2,editionId:edition);expect(result.hasSourceText,isTrue,reason:'$edition:$surah');expect(result.editionId,edition);}}
  expect(denied.attempts,0);
 });
}
