import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'curated_radio_defects_test.dart' show HeldPlayer;
import 'peer_radio_favorite_migration_review_test.dart' show MigrationBundle;
class RejectOneKey extends InMemorySharedPreferencesStore {
  RejectOneKey():super.withData({'flutter.islamic_radio_favorites':['radio_minshawi'],'flutter.curated_radio_favorites':['54811ff480']});
  String? reject;
  @override
  Future<bool> setValue(String type,String key,Object value) async {
    if(key == reject) return false;
    return super.setValue(type,key,value);
  }
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  for(final reject in ['flutter.islamic_radio_favorites','flutter.curated_radio_favorites']){
    testWidgets('mapped removal stays visible and retryable when $reject rejects', (t)async{
      SharedPreferences.setMockInitialValues({});
      final store=RejectOneKey();SharedPreferencesStorePlatform.instance=store;
      Future<void> open()async{await t.pumpWidget(MaterialApp(home:CuratedRadioScreen(playerFactory:HeldPlayer.new,bundle:MigrationBundle())));await t.pumpAndSettle();await t.tap(find.byKey(const Key('curated_radio_cat_favorites')));await t.pumpAndSettle();}
      await open();store.reject=reject;
      await t.tap(find.byKey(const Key('curated_radio_fav_54811ff480')));await t.pumpAndSettle();
      expect(find.text('تعذر حفظ المفضلة'),findsOneWidget);
      expect(find.byKey(const Key('curated_radio_fav_54811ff480')),findsOneWidget);
      final prefs=await SharedPreferences.getInstance();await prefs.reload();
      expect(prefs.getStringList('curated_radio_favorites'),contains('54811ff480'));
      await t.pumpWidget(const SizedBox());await t.pumpAndSettle();await open();
      expect(find.byKey(const Key('curated_radio_fav_54811ff480')),findsOneWidget);
      store.reject=null;await t.tap(find.byKey(const Key('curated_radio_fav_54811ff480')));await t.pumpAndSettle();
      await prefs.reload();expect(prefs.getStringList('curated_radio_favorites'),isEmpty);expect(prefs.getStringList('islamic_radio_favorites'),isNot(contains('radio_minshawi')));
      SharedPreferences.setMockInitialValues({});
    });
  }
}
