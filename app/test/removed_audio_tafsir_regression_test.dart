import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('removed Mukhtasar audio feature has no route, entry point, service or screen left in lib',(){
  final files=Directory('lib').listSync(recursive:true).whereType<File>().where((f)=>f.path.endsWith('.dart'));
  final hits=<String>[];
  for(final f in files){
   final t=f.readAsStringSync();
   for(final k in ['/audio-tafsir','AudioTafsirScreen','AudioTafsirService','audio_tafsir_screen','المختصر الصوتي','فتح التفسير الصوتي','almukhtasar_audio']){
    if(t.contains(k))hits.add('${f.path}: $k');
   }
  }
  expect(hits,isEmpty);
  expect(File('lib/features/mushaf/screens/audio_tafsir_screen.dart').existsSync(),isFalse);
 });
 test('shaarawi tafsir id is not referenced as an edition anywhere in lib/features or tafsir service',(){
  for(final p in ['lib/core/services/tafsir_service.dart','lib/features/mushaf/comparative_tafsir_screen.dart','lib/features/mushaf/widgets/tafsir_viewer_sheet.dart']){
   expect(File(p).readAsStringSync().contains("'shaarawi'"),isFalse,reason:p);
  }
 });
}
