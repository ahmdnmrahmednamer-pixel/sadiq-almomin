import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/services/bundled_tafsir_source.dart';
void main(){
 BundledTafsirSource fixture({bool goodHash=true,bool duplicatePage=false}){
  final section={'bookId':900001,'sections':[{'id':'intro','title':'Fixture section','pages':[{'id':1,'text':'Synthetic source text','textFormat':'plain'},if(duplicatePage){'id':1,'text':'Duplicate fixture','textFormat':'plain'}]}]};
  final data=utf8.encode(jsonEncode(section));
  final manifest={'edition':'fixture','book':{'id':900001},'surahs':{},'bookSections':{'parts':1,'sha256':goodHash?sha256.convert(data).toString():'invalid'}};
  return BundledTafsirSource(readAsset:(p)async=>p.endsWith('manifest.json')?jsonEncode(manifest):base64Encode(GZipEncoder().encode(data)));
 }
 test('synthetic book sections keep identity and source order',()async{
  final result=await fixture().bookSections('fixture');expect(result.single.id,'intro');expect(result.single.pages.single.sourceId,1);expect(result.single.pages.single.text,'Synthetic source text');expect(result.single.pages.single.verseIds,isEmpty);
 });
 test('checksum mismatch rejects before returning source',()async{await expectLater(fixture(goodHash:false).bookSections('fixture'),throwsFormatException);});
 test('duplicate source page IDs fail closed',()async{await expectLater(fixture(duplicatePage:true).bookSections('fixture'),throwsFormatException);});
 test('manifest without book sections stays compatible',()async{
  final source=BundledTafsirSource(readAsset:(p)async=>jsonEncode({'edition':'fixture','book':{'id':900001},'surahs':{}}));expect(await source.bookSections('fixture'),isEmpty);
 });
 test('invalid edition identifiers are rejected',()async{await expectLater(fixture().bookSections('../fixture'),throwsArgumentError);});
}
