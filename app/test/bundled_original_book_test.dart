import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_original_book.dart';
import '../lib/core/services/budur_source.dart';
import '../lib/core/services/jadwal_source.dart';

class DenyBookNetwork implements HttpClientAdapter {
  int calls=0;
  @override Future<ResponseBody> fetch(RequestOptions options,Stream<Uint8List>? stream,Future<dynamic>? cancel) async {
    calls++;
    throw StateError('No network permitted in installation corpus test');
  }
  @override void close({bool force=false}){}
}
void main(){
  test('packed book checks both hashes, exact size and reuses concurrent reads',()async{
    final bytes=utf8.encode('original book\r\n');
    final packed=Uint8List.fromList(GZipEncoder().encode(bytes));var calls=0;
    final book=BundledOriginalBook(assetPath:'fixture',compressedSha256:sha256.convert(packed).toString(),originalSha256:sha256.convert(bytes).toString(),originalBytes:bytes.length,readAsset:(_)async{calls++;return packed;});
    expect(await Future.wait([book.load(),book.load()]),['original book\r\n','original book\r\n']);expect(calls,1);
    for(final type in ['packed','original','size']){
      final bad=BundledOriginalBook(assetPath:'fixture',compressedSha256:type=='packed'?'invalid':sha256.convert(packed).toString(),originalSha256:type=='original'?'invalid':sha256.convert(bytes).toString(),originalBytes:type=='size'?bytes.length+1:bytes.length,readAsset:(_)async=>packed);
      await expectLater(bad.load(),throwsFormatException);
    }
  });
  final root=Platform.environment['PRIVATE_CORPUS_PREPARATION'];
  test('original Jadwal and Budur load from private install candidates without any network',()async{
    final manifest=jsonDecode(File('$root/manifest.json').readAsStringSync());
    BundledOriginalBook book(String key){
      final row=(manifest['sources']as List).singleWhere((s)=>s['key']==key);
      return BundledOriginalBook(assetPath:row['packedFile'],compressedSha256:row['packedSha256'],originalSha256:row['originalSha256'],originalBytes:row['originalBytes'],readAsset:(p)=>File('$root/$p').readAsBytes());
    }
    final deny=DenyBookNetwork();final dio=Dio()..httpClientAdapter=deny;
    final budur=BudurSource(dio:dio,bundledOriginal:book('budur'));
    final loaded=await budur.load();final original=File('/tmp/budur-reference-text.txt').readAsStringSync();
    expect(loaded,original.substring(0,original.indexOf('تصويبات للشيخ')));
    expect(BudurSource.sharedContexts(loaded,surahId:75,ayahNumber:40),hasLength(1));
    final index=jsonDecode(File('/tmp/jadwal-preparation/jadwal_verse_index.json').readAsStringSync()) as Map<String,dynamic>;
    final jadwal=JadwalSource(dio:dio,bundledOriginal:book('jadwal'),
      loadIndex:()async=>index,
      storageDirectory:()async=>throw StateError('No first-run saved copy permitted'));
    for(final v in [(1,1),(2,255),(35,3),(35,4),(40,10),(114,6)]){
      final entry=await jadwal.fetch(v.$1,v.$2);expect(entry,isNotNull);expect(entry!.pages,isNotEmpty);
      if(v.$1==35)expect(entry.notice,contains('غير كامل'));
    }
    var total=0;
    for(final r in index['records'] as List){
      for(var a=r['ayahFrom'] as int;a<=r['ayahTo'];a++){
        expect((await jadwal.fetch(r['surah'],a))!.pages,isNotEmpty);total++;
      }
    }
    expect(total,6236);
    expect(await jadwal.offlineSavedAt(),isNull);
    await expectLater(jadwal.downloadForOffline(),throwsStateError);
    await expectLater(jadwal.deleteOffline(),throwsStateError);
    expect(deny.calls,0);
  },timeout:const Timeout(Duration(minutes:3)),skip:root==null?'Set PRIVATE_CORPUS_PREPARATION to private nonshipping payload directory':false);
}
