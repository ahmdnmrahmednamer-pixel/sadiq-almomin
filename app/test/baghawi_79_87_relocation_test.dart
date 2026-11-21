import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';

String sk(String t){
  final b=StringBuffer();
  for(final r in t.runes){
    if((r>=0x064B&&r<=0x065F)||r==0x0670||r==0x0640||r==0x200A||r==0x2060||r==0x200F||(r>=0x06D6&&r<=0x06ED))continue;
    final c=String.fromCharCode(r);
    if(RegExp(r'[\u0621-\u064A\u0671\u06CC]').hasMatch(c)&&!'اأإآٱءويىیهةؤئ'.contains(c))b.write(c);
  }
  return b.toString();
}
void main(){
  final quran=jsonDecode(File('assets/data/quran_ayahs.json').readAsStringSync()) as Map<String,dynamic>;
  Future<String> asset(String p)async=>File('assets/data/${p.split('/').last}').readAsStringSync();
  String ayahText(int s,int n)=>sk((quran['$s'] as List).firstWhere((a)=>a['ayah_number']==n)['text_uthmani'] as String);
  test('Baghawi page that quotes 79:13-15 is in surah 79 for ayahs 12-15 and not in surah 87',()async{
    final src=BundledTafsirSource(readAsset:asset);
    final marker=ayahText(79,15);
    for(final n in [12,13,14,15]){
      final e=await src.fetch('baghawi_roots',79,n);
      expect(e!.pages.any((p)=>sk(p.text).contains(marker)),isTrue,reason:'79:$n');
    }
    for(var n=1;n<=19;n++){
      final e=await src.fetch('baghawi_roots',87,n);
      expect(e,isNotNull);
      expect(e!.pages.any((p)=>sk(p.text).contains(marker)),isFalse,reason:'87:$n still holds the 79 page');
    }
  });
}
