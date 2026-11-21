import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('only nine exact source-backed mechanical primary repairs; all other 6227 texts unchanged',(){
  final fixture=jsonDecode(File('test/fixtures/muyassar-primary-baseline-sha256.json').readAsStringSync()) as Map;
  final hashes=fixture['hashes'] as Map;final originals=fixture['repaired_originals'] as Map;
  const fixes={'9:25':['اليوم0','اليوم'],'60:8':['الذين550','الذين'],'3:119':['هوذا','هو ذا'],'4:170':['خيرلكم','خير لكم'],'6:8':['ولوأنزلنا','ولو أنزلنا'],'9:39':['إذ ا','إذا'],'43:28':['في مَن','فيمَن'],'39:6':['ذكر‌ًا','ذكرًا'],'71:11':['مالكم','ما لكم']};
  var count=0;
  for(var s=1;s<=114;s++){
   final rows=jsonDecode(File('assets/data/surahs/$s.json').readAsStringSync()) as List;
   for(final row in rows){final key='$s:${row['ayah_number']}';final text=row['tafseer'] as String;final fix=fixes[key];
    if(fix!=null){final old=originals[key] as String;expect(fix[0].allMatches(old).length,1,reason:key);expect(text,old.replaceFirst(fix[0],fix[1]),reason:key);}
    else {expect(sha256.convert(utf8.encode(text)).toString(),hashes[key],reason:key);}count++;
   }
  }
  expect(count,6236);expect(fixes.length,9);
 });
}
