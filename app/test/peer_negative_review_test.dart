import 'dart:async';
import 'dart:convert';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class RejectFavorites extends InMemorySharedPreferencesStore {
  RejectFavorites() : super.withData({});
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}
class HeldPlayer implements CuratedRadioPlayer {
  final controller = StreamController<Object>.broadcast();
  Completer<void>? pending;
  @override
  Future<void> play(String url) async { if (pending != null) await pending!.future; }
  @override
  Future<void> stop() async {}
  @override
  Stream<Object> get errors => controller.stream;
  @override
  void dispose() { controller.close(); }
}
class StationBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
    'categories': [{'id':'c','title':'القراء','stations':[{'id':'a','title':'قارئ الاختبار','url':'https://example.test/a'}]}]
  }))));
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { SharedPreferences.setMockInitialValues({}); });
  Future<void> host(WidgetTester t, HeldPlayer player) async {
    await t.pumpWidget(MaterialApp(home: CuratedRadioScreen(playerFactory: () => player, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c'))); await t.pumpAndSettle();
  }
  testWidgets('rejected favorite persistence must not present a saved favorite', (t) async {
    SharedPreferencesStorePlatform.instance = RejectFavorites();
    await host(t, HeldPlayer());
    await t.tap(find.byKey(const Key('curated_radio_fav_a'))); await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance(); await prefs.reload();
    expect(prefs.getStringList('curated_radio_favorites'), isNull);
    expect(find.byIcon(Icons.star), findsNothing, reason:'Rejected write must not publish saved favorite');
  });
  testWidgets('leaving during pending start must not notify a disposed controller', (t) async {
    final player = HeldPlayer()..pending = Completer<void>();
    await host(t, player);
    await t.tap(find.byKey(const Key('curated_radio_a'))); await t.pump();
    await t.pumpWidget(const SizedBox());
    player.pending!.complete(); await t.pump();
    expect(t.takeException(), isNull);
  });
  testWidgets('station play action must identify the station to a screen reader', (t) async {
    final semantics = t.ensureSemantics();
    try {
      await host(t, HeldPlayer());
      expect(t.getSemantics(find.byKey(const Key('curated_radio_a'))).getSemanticsData().label,
        contains('قارئ الاختبار'));
    } finally { semantics.dispose(); }
  });
}
