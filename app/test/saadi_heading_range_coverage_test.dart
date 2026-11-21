import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';

// Independent oracle: Quran text in quran_ayahs.json. Pages must contain the
// opening words of the ayah itself (diacritics, alef/yaa/waw/hamza forms ignored).
String skel(String t){
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
  // Saadi ayahs whose commentary sits on a source page whose label lags the printed heading / content.
  const fixed={9:[12],11:[23],13:[11],16:[117],18:[75,76,77,78,79,80,81],37:[113],72:[2],28:[5]};
  test('Saadi corrected ayahs map to pages covering the ayah own text (independent Quran oracle)',()async{
    final src=BundledTafsirSource(readAsset:asset);
    for(final e in fixed.entries){
      for(final n in e.value){
        final ayah=(quran['${e.key}'] as List).firstWhere((a)=>a['ayah_number']==n);
        final sk=skel(ayah['text_uthmani'] as String);
        final entry=await src.fetch('saadi_roots',e.key,n);
        expect(entry,isNotNull,reason:'${e.key}:$n');
        final all=entry!.pages.map((p)=>skel(p.text)).join(' ');
        var hit=0,tot=0;
        for(var i=0;i+6<=sk.length;i++){tot++;if(all.contains(sk.substring(i,i+6)))hit++;}
        expect(tot==0||hit/tot>=0.5,isTrue,reason:'${e.key}:$n own-text coverage ${hit}/$tot');
      }
    }
  });
}
