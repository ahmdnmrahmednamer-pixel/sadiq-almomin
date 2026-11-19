import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/lubab_source.dart';
class LubabAdapter implements HttpClientAdapter {
 final Map<String,dynamic> content;
 final int author;
 LubabAdapter(this.content,{this.author=14264});
 @override Future<ResponseBody> fetch(RequestOptions o,Stream<Uint8List>? s,Future<dynamic>? c)async=>ResponseBody.fromString(jsonEncode(o.uri.path=='/v1/book/69'?{'id':69,'type':'asbab','author':{'id':author}}:content),200,headers:{Headers.contentTypeHeader:['application/json']});
 @override void close({bool force=false}){}
}
void main(){
 const text='قوله تعالى لفظ تجريبي SOURCE\nتتمة وحاشية محفوظتان';
 Map<String,dynamic> index()=>{'bookId':69,'provider':'quranpedia.net','linkType':'explicit_heading_quote','records':[{'surah':2,'ayah':3,'segments':[{'id':1,'from':0,'to':text.runes.length}]}],'pages':[{'id':1,'page':7,'sha256':sha256.convert(utf8.encode(text)).toString()}]};
 LubabSource source({String value=text,int author=14264,Map<String,dynamic>? custom})=>LubabSource(dio:Dio()..httpClientAdapter=LubabAdapter({'contents':[{'id':1,'text':value}]},author:author),loadIndex:()async=>custom??index());
 test('returns verbatim source entry with notes and printed page',()async{final p=await source().fetch(2,3);expect(p.single.text,text);expect(p.single.pages,[7]);});
 test('does not reuse adjacent verse or return unindexed content',()async{expect(await source().fetch(2,4),isEmpty);});
 test('fails closed on source correction rather than using stale offsets',()async{expect(()=>source(value:'changed').fetch(2,3),throwsFormatException);});
 test('rejects a different author even with same title',()async{expect(()=>source(author:1).fetch(2,3),throwsFormatException);});
 test('rejects invalid span',()async{final i=index();i['records'][0]['segments'][0]['to']=999;expect(()=>source(custom:i).fetch(2,3),throwsFormatException);});
 test('HTML line and paragraph boundaries remain visible',(){expect(LubabSource.plain('<p>one</p>two<br />three'),'\none\ntwo\nthree');});
}
