import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/bundled_tafsir_source.dart';

void main(){
 final data=utf8.encode(jsonEncode({'bookId':1,'sections':[{'id':'intro','title':'Synthetic section','pages':[{'id':1,'text':'SYNTHETIC_FIXTURE_ONLY','textFormat':'plain'}]}]}));
 final payload=base64Encode(GZipEncoder().encode(data));
 Map<String,dynamic> manifest()=>{'edition':'fixture','book':{'id':1},'surahs':{},'bookSections':{'parts':1,'sha256':sha256.convert(data).toString()}};
 test('same source recovers after one transient manifest read failure',()async{
  var reads=0;
  final source=BundledTafsirSource(readAsset:(path)async{
   if(path.endsWith('manifest.json')){if(++reads==1)throw StateError('Synthetic initial read failure');return jsonEncode(manifest());}return payload;
  });
  await expectLater(source.bookSections('fixture'),throwsStateError);
  expect((await source.bookSections('fixture')).single.id,'intro');expect(reads,2);
  expect((await source.bookSections('fixture')).single.id,'intro');expect(reads,2);
 });
 test('permanent manifest failure stays failed and retries do not fabricate source',()async{
  var reads=0;final source=BundledTafsirSource(readAsset:(path)async{reads++;throw StateError('Synthetic permanent failure');});
  for(var n=0;n<3;n++){await expectLater(source.bookSections('fixture'),throwsStateError);}
  expect(reads,3);
 });
 test('wrong manifest identity rejects on every attempt before payload access',()async{
  var reads=0;var payloadReads=0;final source=BundledTafsirSource(readAsset:(path)async{if(path.endsWith('manifest.json')){reads++;return jsonEncode(manifest()..['edition']='other');}payloadReads++;return payload;});
  for(var n=0;n<2;n++){await expectLater(source.bookSections('fixture'),throwsFormatException);}
  expect(reads,2);expect(payloadReads,0);
 });
 test('bad manifest JSON can be corrected without replacing source instance',()async{
  var reads=0;final source=BundledTafsirSource(readAsset:(path)async{if(path.endsWith('manifest.json'))return ++reads==1?'{':jsonEncode(manifest());return payload;});
  await expectLater(source.bookSections('fixture'),throwsFormatException);
  expect((await source.bookSections('fixture')).single.id,'intro');expect(reads,2);
 });
 test('permanent payload checksum failure remains fail closed on retry',()async{
  var manifestReads=0;var payloadReads=0;final source=BundledTafsirSource(readAsset:(path)async{
   if(path.endsWith('manifest.json')){manifestReads++;return jsonEncode(manifest());}
   payloadReads++;return base64Encode(GZipEncoder().encode(utf8.encode('{}')));
  });
  for(var n=0;n<2;n++){await expectLater(source.bookSections('fixture'),throwsFormatException);}
  expect(manifestReads,1);expect(payloadReads,2);
 });
 test('concurrent failed manifest requests share read then next attempt recovers',()async{
  var reads=0;final source=BundledTafsirSource(readAsset:(path)async{
   if(path.endsWith('manifest.json')){final n=++reads;await Future<void>.delayed(Duration.zero);if(n==1)throw StateError('Synthetic concurrent failure');return jsonEncode(manifest());}return payload;
  });
  await Future.wait([expectLater(source.bookSections('fixture'),throwsStateError),expectLater(source.bookSections('fixture'),throwsStateError)]);
  expect(reads,1);expect((await source.bookSections('fixture')).single.id,'intro');expect(reads,2);
 });
}
