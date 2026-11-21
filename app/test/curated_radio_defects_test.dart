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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<HeldPlayer> host(WidgetTester t, [HeldPlayer? player]) async {
    final p = player ?? HeldPlayer();
    await t.pumpWidget(MaterialApp(
        home: CuratedRadioScreen(playerFactory: () => p, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c')));
    await t.pumpAndSettle();
    return p;
  }

  testWidgets('rejected favorite write publishes no favorite and says so', (t) async {
    SharedPreferencesStorePlatform.instance = RejectFavorites();
    await host(t);
    await t.tap(find.byKey(const Key('curated_radio_fav_a')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('curated_radio_favorites'), isNull);
    expect(find.byIcon(Icons.star), findsNothing,
        reason: 'a rejected write must not present a saved favorite');
    expect(find.text('تعذر حفظ المفضلة'), findsOneWidget);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('leaving during a pending start never notifies a disposed controller', (t) async {
    final player = HeldPlayer()..pending = Completer<void>();
    await host(t, player);
    await t.tap(find.byKey(const Key('curated_radio_a')));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    player.pending!.complete();
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('play and favorite actions name their station to a screen reader', (t) async {
    final semantics = t.ensureSemantics();
    try {
      await host(t);
      expect(
          t.getSemantics(find.byKey(const Key('curated_radio_a'))).getSemanticsData().label,
          contains('قارئ الاختبار'));
      // IconButton exposes its tooltip as the semantics tooltip, not label.
      expect(
          t.getSemantics(find.byKey(const Key('curated_radio_fav_a'))).getSemanticsData().tooltip,
          contains('قارئ الاختبار'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('rapid presses settle on the last station; stale completion does not clobber', (t) async {
    final player = HeldPlayer()..pending = Completer<void>();
    await host(t, player);
    await t.tap(find.byKey(const Key('curated_radio_a')));
    await t.pump();
    await t.tap(find.byKey(const Key('curated_radio_b')));
    await t.pump();
    expect(player.log, ['play https://example.test/a', 'play https://example.test/b']);
    player.pending!.complete();
    await t.pump();
    // The first play's late completion must not change the state: b plays on.
    expect(find.text('إيقاف'), findsOneWidget);
    expect(find.text('تعذر التشغيل'), findsNothing);
  });

  testWidgets('rapid favorite taps serialize; final persisted state matches the last press', (t) async {
    await host(t);
    await t.tap(find.byKey(const Key('curated_radio_fav_a')));
    await t.tap(find.byKey(const Key('curated_radio_fav_a')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('curated_radio_favorites'), isEmpty,
        reason: 'add then remove must persist as removed, not interleave');
    expect(find.byIcon(Icons.star), findsNothing);
    await t.tap(find.byKey(const Key('curated_radio_fav_a')));
    await t.tap(find.byKey(const Key('curated_radio_fav_b')));
    await t.pumpAndSettle();
    expect(prefs.getStringList('curated_radio_favorites'), containsAll(['a', 'b']));
  });

  testWidgets('legacy favorites import through the exact-URL slug map, keep the legacy key', (t) async {
    SharedPreferences.setMockInitialValues({
      'islamic_radio_favorites': ['radio_minshawi', 'radio_husary'],
    });
    await host(t);
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('curated_radio_favorites'), ['54811ff480'],
        reason: 'radio_minshawi maps by an identical stream URL; radio_husary has no exact URL match and is not invented');
    expect(prefs.getStringList('islamic_radio_favorites'),
        ['radio_minshawi', 'radio_husary'],
        reason: 'the legacy key is never deleted, so unmapped slugs are preserved');
  });
  integrationTests();
}

// PR132 FastAudioService integration contract, exercised through the real
// screen with a stubbed service seam.
void integrationTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('rejected focus claim (false) marks failure, never falls back', (t) async {
    var calls = 0;
    final player = FastAudioRadioPlayer(
      playFn: (url, onStop) async {
        calls++;
        return false; // service rejected the claim
      },
      stopFn: () async {},
    );
    await t.pumpWidget(MaterialApp(
        home: CuratedRadioScreen(playerFactory: () => player, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_a')));
    await t.pumpAndSettle();
    expect(calls, 1, reason: 'exactly one service attempt, no fallback replay');
    expect(find.text('تعذر التشغيل'), findsOneWidget);
    expect(find.text('إيقاف'), findsNothing);
  });

  testWidgets('external focus loss clears playing state without a failure message', (t) async {
    Future<void> Function()? stopped;
    final player = FastAudioRadioPlayer(
      playFn: (url, onStop) async {
        stopped = onStop;
        return true;
      },
      stopFn: () async {},
    );
    await t.pumpWidget(MaterialApp(
        home: CuratedRadioScreen(playerFactory: () => player, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_a')));
    await t.pumpAndSettle();
    expect(find.text('إيقاف'), findsOneWidget);
    await stopped!();
    await t.pumpAndSettle();
    expect(find.text('إيقاف'), findsNothing);
    expect(find.text('تعذر التشغيل'), findsNothing,
        reason: 'another owner taking focus is not a playback failure');
  });

  testWidgets('leaving the screen while playing stops the central service', (t) async {
    var stops = 0;
    final player = FastAudioRadioPlayer(
      playFn: (url, onStop) async => true,
      stopFn: () async => stops++,
    );
    await t.pumpWidget(MaterialApp(
        home: CuratedRadioScreen(playerFactory: () => player, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_a')));
    await t.pumpAndSettle();
    expect(stops, 0);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(stops, greaterThan(0),
        reason: 'dispose while playing releases the central audio service');
  });

  testWidgets('unmapped legacy favorite stays visible, playable, removable by the user', (t) async {
    SharedPreferences.setMockInitialValues({
      'islamic_radio_favorites': ['radio_husary'],
    });
    final player = HeldPlayer();
    await t.pumpWidget(MaterialApp(
        home: CuratedRadioScreen(playerFactory: () => player, bundle: StationBundle())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_favorites')));
    await t.pumpAndSettle();
    expect(find.text('إذاعة الشيخ محمود خليل الحصري'), findsOneWidget,
        reason: 'a legacy favorite with no grounded replacement remains visible');
    expect(find.byIcon(Icons.star), findsOneWidget);
    final semantics = t.ensureSemantics();
    try {
      expect(
          t.getSemantics(find.byKey(const Key('curated_radio_legacy:radio_husary')))
              .getSemanticsData().label,
          contains('الحصري'));
    } finally {
      semantics.dispose();
    }
    await t.tap(find.byKey(const Key('curated_radio_legacy:radio_husary')));
    await t.pump();
    expect(player.log, ['play https://qurango.net/radio/mahmoud_khalil_alhussary_mojawwad']);
    await t.tap(find.byKey(const Key('curated_radio_fav_legacy:radio_husary')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('islamic_radio_favorites'), isEmpty,
        reason: 'user-initiated removal updates the legacy key, nothing else');
    expect(find.text('إذاعة الشيخ محمود خليل الحصري'), findsNothing);
    expect(find.text('لا توجد إذاعات مفضلة.'), findsOneWidget);
  });
}
