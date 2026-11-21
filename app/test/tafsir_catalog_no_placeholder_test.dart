import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/tafsir_service.dart';
void main(){
 test('every visible tafsir edition has bundled or live text routing; removed placeholders absent',()async{
  final ids=TafsirService.availableEditions.map((e)=>e.id).toList();
  expect(ids.length,9);
  expect(ids,isNot(contains('shaarawi')));expect(ids,isNot(contains('almukhtasar_audio')));
  final r=await TafsirService.getTafsir(surahId:1,ayahNumber:1,editionId:'saadi');
  expect(r.tafsirText,isNot(contains('لم يُربط نص هذا التفسير')));
 });
 test('stale saved default of a removed edition falls back to muyassar',()async{
  for(final stale in ['shaarawi','almukhtasar_audio']){
   SharedPreferences.setMockInitialValues({'default_tafsir_edition':stale});
   await SettingsService.instance.init(forceReload:true);
   expect(SettingsService.instance.defaultTafsirEdition,'muyassar');
  }
 });
}
