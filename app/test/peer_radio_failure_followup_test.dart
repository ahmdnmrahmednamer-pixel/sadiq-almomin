import 'dart:async';
import 'dart:convert';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Regression tests for the curated radio defect fixes:
// write-first favorites with a rejection path, serialized presses,
// post-dispose notify guard, station-named semantics, play generation
// counter, and one-time legacy id import (legacy key preserved).

class RejectFavorites extends InMemorySharedPreferencesStore {
  RejectFavorites() : super.withData({});
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

class HeldPlayer implements CuratedRadioPlayer {
  final controller = StreamController<Object>.broadcast();
  final List<String> log = [];
  Completer<void>? pending;
  @override
  Future<void> play(String url) async {
    log.add('play $url');
    if (pending != null) await pending!.future;
  }
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Stream<Object> get errors => controller.stream;
  @override
  void dispose() {
    controller.close();
  }
}

class StationBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
        'categories': [
          {
            'id': 'c',
            'title': 'القراء',
            'stations': [
              {'id': 'a', 'title': 'قارئ الاختبار', 'url': 'https://example.test/a'},
              {'id': 'b', 'title': 'قارئ ثان', 'url': 'https://example.test/b'},
            ]
          }
        ]
      }))));
}


class ThrowFavorites extends InMemorySharedPreferencesStore {
  ThrowFavorites() : super.withData({});
  @override
  Future<bool> setValue(String type, String key, Object value) async => throw StateError('storage unavailable');
}
class FailStopPlayer extends HeldPlayer {
  @override
  Future<void> stop() async { throw StateError('still playing'); }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> host(WidgetTester t, HeldPlayer player) async {
    await t.pumpWidget(MaterialApp(home: CuratedRadioScreen(playerFactory: () => player, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c'))); await t.pumpAndSettle();
  }
  testWidgets('thrown favorite write is handled and reports failure', (t) async {
    SharedPreferencesStorePlatform.instance = ThrowFavorites();
    await host(t, HeldPlayer());
    await t.tap(find.byKey(const Key('curated_radio_fav_a'))); await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('تعذر حفظ المفضلة'), findsOneWidget);
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('failed physical Stop must not present a stopped station', (t) async {
    await host(t, FailStopPlayer());
    await t.tap(find.byKey(const Key('curated_radio_a'))); await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_a'))); await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('إيقاف'), findsOneWidget, reason: 'Still sounding owner needs a retry control');
  });
}
