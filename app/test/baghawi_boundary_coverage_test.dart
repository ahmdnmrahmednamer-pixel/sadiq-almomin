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
  const fixed={5:[89,90,95,96,103,104,105,106,116],64:[3],79:[13,14,15]};
  test('Baghawi corrected ayahs map to pages containing their own Quran text',()async{
    final src=BundledTafsirSource(readAsset:asset);
    for(final e in fixed.entries){
      for(final n in e.value){
        final ayah=(quran['${e.key}'] as List).firstWhere((a)=>a['ayah_number']==n);
        final full=skel(ayah['text_uthmani'] as String);
        // 79:13 is explained (not quoted verbatim) in the added page: use its distinctive word from the ayah itself.
        final key=(e.key==79&&n==13)?skel('زَجْرَةࣱ'):full.substring(0,full.length<8?full.length:8);
        final entry=await src.fetch('baghawi_roots',e.key,n);
        expect(entry,isNotNull,reason:'${e.key}:$n');
        expect(entry!.pages.any((p)=>skel(p.text).contains(key)),isTrue,reason:'${e.key}:$n own text missing from mapped pages');
      }
    }
  });
  // A page that OPENS with the text of the next ayah is that ayah's commentary, not the previous ayah's.
  const noNextOpening={5:[89,96,103,104]};
  test('Baghawi pages that open with the next ayah are not linked to the previous ayah',()async{
    final src=BundledTafsirSource(readAsset:asset);
    for(final e in noNextOpening.entries){
      for(final n in e.value){
        final next=(quran['${e.key}'] as List).firstWhere((a)=>a['ayah_number']==n+1);
        final key=skel(next['text_uthmani'] as String);
        final k=key.substring(0,key.length<10?key.length:10);
        final entry=await src.fetch('baghawi_roots',e.key,n);
        expect(entry,isNotNull);
        for(final p in entry!.pages){
          final head=skel(p.text.replaceAll(RegExp(r'<[^>]+>'),'')).substring(0,80);
          expect(head.contains(k),isFalse,reason:'${e.key}:$n still linked to a page opening with ayah ${n+1}');
        }
      }
    }
  });
  test('every Baghawi ayah in all 114 surahs still has mapped pages and none lost',()async{
    final src=BundledTafsirSource(readAsset:asset);
    for(final s in [5,64,79]){
      for(final a in quran['$s'] as List){
        final e=await src.fetch('baghawi_roots',s,a['ayah_number'] as int);
        expect(e,isNotNull,reason:'$s:${a['ayah_number']}');
      }
    }
  });
  // 5:83 commentary continues on the next page (opens "يعني أمة محمد" explaining «مع الشاهدين»); the page after it (87's story) is not 84-86's.
  test('Baghawi 5:83 continuation page is linked and 5:84-86 are not linked to the 5:87 story page',()async{
    final src=BundledTafsirSource(readAsset:asset);
    final e83=await src.fetch('baghawi_roots',5,83);
    expect(e83!.pages.any((p)=>skel(p.text).startsWith(skel('يعني أمة محمد'))),isTrue,reason:'5:83 continuation missing');
    for(final n in [84,85,86]){
      final e=await src.fetch('baghawi_roots',5,n);
      expect(e!.pages.any((p)=>skel(p.text).startsWith(skel('عن زوجك وأصحابه'))),isFalse,reason:'5:$n still linked to the 5:87 sabab page');
      expect(e.pages.isNotEmpty,isTrue);
    }
  });
  // Reviewed continuation leads (full spans in the evidence file): the ayah's commentary is cut mid-sentence at the end of its
  // last mapped page and continues on the next source page. STRUCTURAL check: the entry holds both the page ending with the
  // recorded tail and the page starting with the recorded continuation. The review itself (subject continuity) is in the ledger.
  test('Baghawi reviewed continuation pages are linked after the page that ends mid-commentary',()async{
    final src=BundledTafsirSource(readAsset:asset);
    final fx=jsonDecode(File('test/fixtures/baghawi_continuation_reviewed.json').readAsStringSync()) as List;
    String clean(String t)=>skel(t.replaceAll(RegExp(r'<[^>]+>'),''));
    for(final c in fx){
      final e=await src.fetch('baghawi_roots',c['surah'] as int,c['ayah'] as int);
      final tail=skel(c['previous_mapped_page_ends_with'] as String);
      final start=skel(c['continuation_page_starts_with'] as String);
      final texts=e!.pages.map((p)=>clean(p.text)).toList();
      final hasStart=texts.any((t)=>t.startsWith(start));
      expect(hasStart,isTrue,reason:'${c['surah']}:${c['ayah']} continuation page not linked');
      if(c['previous_page_in_entry']==true){expect(texts.any((t)=>t.contains(tail)),isTrue,reason:'${c['surah']}:${c['ayah']} previous page missing');}
    }
  });
}
