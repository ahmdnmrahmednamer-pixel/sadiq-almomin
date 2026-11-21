import 'dart:io';import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/budur_source.dart';import '../lib/core/services/jadwal_source.dart';
class DenyInstallationHttp extends HttpOverrides{int calls=0;@override HttpClient createHttpClient(SecurityContext?context){calls++;throw StateError('Network denied');}}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();final denied=DenyInstallationHttp();var corrupt='';
 setUpAll((){HttpOverrides.global=denied;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',(m)async{final p=utf8.decode(m!.buffer.asUint8List());if(p==corrupt)return ByteData.sublistView(Uint8List.fromList([1,2,3]));final f=File(p);return f.existsSync()?ByteData.sublistView(f.readAsBytesSync()):null;});});
 tearDownAll(()=>HttpOverrides.global=null);
 test('default two installed readers fail closed then retry damaged book assets without network',()async{
  final budur=BudurSource();corrupt='assets/data/budur-original.gz';await expectLater(budur.load(),throwsFormatException);corrupt='';final text=await budur.load();expect(text,contains('عبد الفتاح'));expect(text,contains('الشاطبية'));expect(text,contains('الدرة'));expect(text, isNot(contains('تصويبات للشيخ')));
  final jadwal=JadwalSource(storageDirectory:()async=>throw StateError('No initial local copy allowed'));expect(jadwal.isBundled,isTrue);corrupt='assets/data/jadwal-original.gz';await expectLater(jadwal.fetch(1,1),throwsFormatException);corrupt='';expect((await jadwal.fetch(1,1))!.pages,isNotEmpty);expect(await jadwal.offlineSavedAt(),isNull);await expectLater(jadwal.downloadForOffline(),throwsStateError);await expectLater(jadwal.deleteOffline(),throwsStateError);expect(denied.calls,0);
 });
 test('default installed Jadwal resolves all6236locations and preserves exact page checks and known gaps',()async{
  final source=JadwalSource(storageDirectory:()async=>throw StateError('No initial cache allowed'));var count=0,expected=0;final first=int.parse(Platform.environment['JADWAL_TEST_FIRST']??'1');final last=int.parse(Platform.environment['JADWAL_TEST_LAST']??'114');for(var s=first;s<=last;s++){
   final rows=jsonDecode(File('assets/data/surahs/$s.json').readAsStringSync())as List;expected+=rows.length;
   for(var a=1;a<=rows.length;a++){final r=await source.fetch(s,a);expect(r,isNotNull,reason:'$s:$a');expect(r!.pages,isNotEmpty,reason:'$s:$a');count++;}
  }expect(count,expected);print('JADWAL_DEFAULT_PARTITION $first $last $count');for(final a in [3,4]){final e=(await source.fetch(35,a))!;expect(e.notice,contains('دار الرشيد'));expect(e.notice,isNot(contains('الصفحة غير متوفرة')));expect(e.pages.single.text,File('test/data/jadwal_fatir_35_3_4_recovered.txt').readAsStringSync().trimRight());}expect((await source.fetch(40,10))!.pages.single.text,File('test/data/jadwal_ghafir_40_10_recovered.txt').readAsStringSync().trimRight());expect((await source.fetch(40,9))!.pages.last.text,contains('حُجب'));expect(denied.calls,0);
 },timeout:const Timeout(Duration(minutes:4)));
}
