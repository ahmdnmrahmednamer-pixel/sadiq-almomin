import 'dart:io';import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';
void main(){
 test('appendix title30000056 is heading context on3:1 only, never a gloss for3:2-6',()async{
  final src=BundledTafsirSource(readAsset:(p)async=>File(p).readAsStringSync());
  final first=await src.fetch('saadi_roots',3,1);
  final h=first!.pages.singleWhere((p)=>p.sourceId==30000056);
  expect(h.verseIds,isEmpty);expect(h.sourceLabel,contains('ليس تفسيرًا'));expect(h.text.trim(),'تفسير سورة آل عمران وهي مدنية');
  for(var a=2;a<=6;a++){final v=await src.fetch('saadi_roots',3,a);expect(v!.pages.any((p)=>p.sourceId==30000056),isFalse,reason:'3:$a');}
 });
}
