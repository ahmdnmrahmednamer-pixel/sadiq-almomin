import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/quran_english_source.dart';

// Expected values: per-verse SHA-256 of (translation NUL footnotes) taken from the
// upstream QuranEnc SQLite (download sha256 in the fixture), NOT from the bundle.
void main(){
  Future<String> asset(String p)=>File(p).readAsString();
  String h(String t,String f)=>sha256.convert(utf8.encode('$t\u0000$f')).toString();
  test('every shipped English verse and footnote equals the upstream SQLite row',()async{
    final fx=jsonDecode(await asset('test/fixtures/english_rwwad_upstream_row_sha256.json')) as Map;
    final manifest=jsonDecode(await asset('assets/data/english_rwwad_manifest.json')) as Map;
    expect(manifest['downloadSha256'],fx['upstreamDownloadSha256']);
    expect(manifest['version'],fx['version']);
    final rows=fx['rows'] as Map;expect(rows.length,6236);
    final source=QuranEnglishSource(readAsset:asset);
    for(final e in rows.entries){
      final p=e.key.split(':');
      final v=await source.fetch(int.parse(p[0]),int.parse(p[1]));
      expect(v,isNotNull,reason:e.key);
      expect(h(v!.text,v.footnotes),e.value,reason:e.key);
    }
  });
  test('negative control: a one-character change or dropped footnote is detected',()async{
    final fx=jsonDecode(await asset('test/fixtures/english_rwwad_upstream_row_sha256.json')) as Map;
    final source=QuranEnglishSource(readAsset:asset);
    final v=(await source.fetch(1,1))!;
    expect(h('${v.text}.',v.footnotes),isNot((fx['rows'] as Map)['1:1']));
    final k=(fx['rows'] as Map).keys.firstWhere((x)=>true);
    var withFoot;
    for(final e in (fx['rows'] as Map).keys){final p=e.split(':');final w=(await source.fetch(int.parse(p[0]),int.parse(p[1])))!;if(w.footnotes.isNotEmpty){withFoot=w;break;}}
    expect(h(withFoot.text,''),isNot(h(withFoot.text,withFoot.footnotes)));
    expect(k,isNotEmpty);
  });
}
