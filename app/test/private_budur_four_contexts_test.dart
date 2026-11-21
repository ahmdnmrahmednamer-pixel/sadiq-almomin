import 'dart:io';import 'dart:convert';
import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';import 'package:crypto/crypto.dart';
import '../lib/core/services/budur_source.dart';import '../lib/core/services/budur_shared_contexts.dart';
import '../lib/core/models/surah.dart';import '../lib/core/models/ayah.dart';
class DenyBudurHttp extends HttpOverrides{@override HttpClient createHttpClient(SecurityContext?context)=>throw StateError('network prohibited');}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll((){HttpOverrides.global=DenyBudurHttp();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final f=File(utf8.decode(m!.buffer.asUint8List()));return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});});
 tearDownAll((){HttpOverrides.global=null;});
 test('four exact bundled sections resolve offline and retain source scope discrepancy',()async{
  final source=await BudurSource().load();final expected=jsonDecode(File('test/fixtures/budur_four_contexts_expected.json').readAsStringSync())as List;
  for(final row in expected){final g=budurSharedContextGrants.singleWhere((g)=>g.start==row['start']);final raw=source.substring(g.start,g.end);expect(sha256.convert(utf8.encode(raw)).toString(),row['sha256']);
   for(final range in g.ranges){for(var ayah=range.$2;ayah<=range.$3;ayah++){
    final p=BudurSource.sharedContexts(source,surahId:range.$1,ayahNumber:ayah).single;expect(p.text,raw.replaceAll(RegExp(r'\s*الجزء:\s*\d+\s*¦\s*الصفحة:\s*\d+\s*'),'\n\n').trim());expect(p.contextNote,row['note']);expect(p.ayahs,isEmpty);
   }}
   final physical=(jsonDecode(File('assets/data/surahs.json').readAsStringSync())as List).map((r)=>Surah.fromJson(Map<String,dynamic>.from(r))).singleWhere((s)=>s.id==g.physicalSurah);
   final ayahs=(jsonDecode(File('assets/data/surahs/${g.physicalSurah}.json').readAsStringSync())as List).map((r)=>Ayah.fromRow(Map<String,dynamic>.from(r))).toList();
   final paragraphs=BudurSource.passages(source,physical,ayahs);for(final p in paragraphs){if(g.physicalSurah==100&&p.text.startsWith('" رآه "'))expect(p.ayahs,isEmpty);}
  }
  final at9=BudurSource.sharedContexts(source,surahId:100,ayahNumber:9).single;expect(at9.contextNote,contains('11'));expect(at9.contextNote,contains('العاديات 9'));expect(at9.text,contains('الخير لشديد'));expect(at9.text,contains('علم بالقلم'));
  final at101=BudurSource.sharedContexts(source,surahId:101,ayahNumber:1).single;expect(at101.text,isNot(at9.text));expect(at101.contextNote,contains('بالقارعة'));
  final at79=BudurSource.sharedContexts(source,surahId:79,ayahNumber:46).single;expect(at79.text,contains('أوضحاها'));expect(at79.contextNote,contains('لم نغير رسمها'));
 });
}
