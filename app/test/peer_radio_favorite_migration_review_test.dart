import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'curated_radio_defects_test.dart' show HeldPlayer;
class MigrationBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({'categories':[{'id':'c','title':'category','stations':[{'id':'54811ff480','title':'Minshawi','url':'https://example.test/a'}]}]}))));
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('removing an imported favorite stays removed when radio screen reopens', (t) async {
    SharedPreferences.setMockInitialValues({'islamic_radio_favorites':['radio_minshawi']});
    Future<void> open() async {
      await t.pumpWidget(MaterialApp(home: CuratedRadioScreen(playerFactory: HeldPlayer.new,bundle: MigrationBundle())));
      await t.pumpAndSettle();
    }
    await open();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('curated_radio_favorites'), contains('54811ff480'));
    await t.tap(find.byKey(const Key('curated_radio_cat_favorites')));await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_fav_54811ff480')));await t.pumpAndSettle();
    expect(prefs.getStringList('curated_radio_favorites'), isEmpty);
    await t.pumpWidget(const SizedBox());await t.pumpAndSettle();
    await open();await prefs.reload();
    expect(prefs.getStringList('curated_radio_favorites'), isEmpty, reason: 'Explicit removal must not be undone by replaying legacy migration');
  });
}
