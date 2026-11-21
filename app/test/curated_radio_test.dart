import 'dart:async';
import 'dart:convert';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fake implements CuratedRadioPlayer {
  final List<String> log;
  final StreamController<Object> errs = StreamController<Object>.broadcast();
  bool failNext = false;
  _Fake(this.log);
  @override
  Future<void> play(String url) async {
    if (failNext) throw StateError('x');
    log.add('play $url');
  }

  @override
  Future<void> stop() async => log.add('stop');
  @override
  Stream<Object> get errors => errs.stream;
  @override
  void dispose() => errs.close();
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.json);
  final String json;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(utf8.encode(json)));
}

String _small() => jsonEncode({
      'categories': [
        {
          'id': 'c1',
          'title': 'الفئة الأولى',
          'stations': [
            {'id': 'a1', 'title': 'محطة أ', 'url': 'https://example.test/a'},
            {'id': 'a2', 'title': 'محطة ب', 'url': 'http://example.test/b'},
          ]
        },
        {
          'id': 'c2',
          'title': 'الفئة الثانية',
          'stations': [
            {'id': 'b1', 'title': 'محطة ج', 'url': 'https://example.test/c'}
          ]
        },
      ]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Expected values are typed from the recovered list's own category headings and counts
  // (the markdown that came with the data), not computed from the bundled asset.
  test('bundled asset matches the recovered list: nine categories, 145 stations, exact headings and counts', () async {
    final cats = await loadCuratedCategories();
    expect(cats.map((c) => c.title).toList(), [
      'إذاعات إسلامية متنوعة',
      'إذاعات القراء',
      'القراءات العشر',
      'تلاوات متميزة',
      'الأدعية والأذكار',
      'الفتاوى',
      'السيرة والقصص',
      'تفسير القرآن الكريم',
      'مواسم الخير',
    ]);
    expect(cats.map((c) => c.stations.length).toList(), [49, 59, 18, 5, 3, 2, 3, 2, 4]);
    expect(cats.expand((c) => c.stations).length, 145);
    expect(cats.first.stations.first.name, 'إذاعة القرآن الكريم من نابلِس');
    expect(cats.first.stations.first.url, 'http://www.quran-radio.org:8002/;stream.mp3');
    final tal = cats.firstWhere((c) => c.title == 'تلاوات متميزة').stations.map((s) => s.name).toList();
    expect(tal, [
      'تراتيل قصيرة متميزة',
      'سورة البقرة - لعدد من القراء',
      'الإذاعة العامة - اذاعة متنوعة لمختلف القراء',
      'تلاوات خاشعة',
      'محمد أيوب',
    ]);
    final readers = cats[1].stations.map((s) => s.name).toList();
    expect(readers, contains('إذاعة الشيخ سعود الشريم'));
    expect(cats.expand((c) => c.stations).any((s) => RegExp(r'^[-\s]|[-\s]$').hasMatch(s.name)), isFalse, reason: 'no decorative dashes or stray spaces at title edges');
    final tarateel = cats.firstWhere((c) => c.title == 'تلاوات متميزة').stations.map((s) => s.url).toList();
    expect(tarateel, [
      'https://backup.qurango.net/radio/tarateel',
      'https://backup.qurango.net/radio/albaqarah',
      'https://backup.qurango.net/radio/mix',
      'https://backup.qurango.net/radio/salma',
      'https://backup.qurango.net/radio/ayyoub2',
    ]);
  });

  test('loader rejects a duplicate id and a non-http url', () async {
    final dup = jsonEncode({
      'categories': [
        {
          'id': 'c',
          'title': 't',
          'stations': [
            {'id': 'x', 'title': 'a', 'url': 'https://e.test/a'},
            {'id': 'x', 'title': 'b', 'url': 'https://e.test/b'}
          ]
        }
      ]
    });
    final bad = jsonEncode({
      'categories': [
        {
          'id': 'c',
          'title': 't',
          'stations': [
            {'id': 'y', 'title': 'a', 'url': 'file:///etc/passwd'}
          ]
        }
      ]
    });
    await expectLater(loadCuratedCategories(bundle: _Bundle(dup)), throwsFormatException);
    await expectLater(loadCuratedCategories(bundle: _Bundle(bad)), throwsFormatException);
  });

  Future<void> pumpScreen(WidgetTester t, _Fake f) async {
    await t.pumpWidget(MaterialApp(home: CuratedRadioScreen(playerFactory: () => f, bundle: _Bundle(_small()))));
    await t.pump();
    await t.pump();
  }

  testWidgets('categories list, open one, play/switch/stop with one station at a time, no hints', (t) async {
    final log = <String>[];
    final f = _Fake(log);
    await pumpScreen(t, f);
    expect(find.text('الفئة الأولى'), findsOneWidget);
    expect(find.text('الفئة الثانية'), findsOneWidget);
    expect(find.text('المفضلة'), findsOneWidget);
    await t.tap(find.byKey(const Key('curated_radio_cat_c1')));
    await t.pumpAndSettle();
    expect(find.text('تشغيل'), findsNWidgets(2));
    await t.tap(find.byKey(const Key('curated_radio_a1')));
    await t.pump();
    expect(log, ['play https://example.test/a']);
    expect(find.text('إيقاف'), findsOneWidget);
    await t.tap(find.byKey(const Key('curated_radio_a2')));
    await t.pump();
    expect(find.text('إيقاف'), findsOneWidget);
    expect(log.last, 'play http://example.test/b');
    await t.tap(find.byKey(const Key('curated_radio_a2')));
    await t.pump();
    expect(log.last, 'stop');
    expect(find.text('تشغيل'), findsNWidgets(2));
    final h = t.ensureSemantics();
    for (final n in [find.byKey(const Key('curated_radio_a1')), find.byKey(const Key('curated_radio_fav_a1'))]) {
      expect(t.getSemantics(n).hint, isEmpty);
    }
    expect(find.byTooltip('إضافة محطة أ إلى المفضلة'), findsOneWidget);
    expect(find.byTooltip('إضافة محطة ب إلى المفضلة'), findsOneWidget);
    h.dispose();
  });

  testWidgets('start failure and later playback error both show «تعذر التشغيل» and clear the playing state', (t) async {
    final f = _Fake([]);
    await pumpScreen(t, f);
    await t.tap(find.byKey(const Key('curated_radio_cat_c1')));
    await t.pumpAndSettle();
    f.failNext = true;
    await t.tap(find.byKey(const Key('curated_radio_a1')));
    await t.pump();
    expect(find.text('تعذر التشغيل'), findsOneWidget);
    expect(find.text('تشغيل'), findsNWidgets(2));
    f.failNext = false;
    await t.tap(find.byKey(const Key('curated_radio_a1')));
    await t.pump();
    expect(find.text('تعذر التشغيل'), findsNothing);
    expect(find.text('إيقاف'), findsOneWidget);
    f.errs.add(StateError('dropped'));
    await t.pump();
    await t.pump();
    expect(find.text('تعذر التشغيل'), findsOneWidget);
    expect(find.text('إيقاف'), findsNothing);
  });

  testWidgets('favorites: empty state, add from a category, persists, listed, removable', (t) async {
    final f = _Fake([]);
    await pumpScreen(t, f);
    await t.tap(find.byKey(const Key('curated_radio_cat_favorites')));
    await t.pumpAndSettle();
    expect(find.text('لا توجد إذاعات مفضلة.'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_c2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_fav_b1')));
    await t.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('curated_radio_favorites'), ['b1']);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('curated_radio_cat_favorites')));
    await t.pumpAndSettle();
    expect(find.text('محطة ج'), findsOneWidget);
    await t.tap(find.byKey(const Key('curated_radio_fav_b1')));
    await t.pump();
    expect(find.text('لا توجد إذاعات مفضلة.'), findsOneWidget);
    expect(prefs.getStringList('curated_radio_favorites'), isEmpty);
  });

  testWidgets('load failure shows a message with retry', (t) async {
    await t.pumpWidget(MaterialApp(home: CuratedRadioScreen(playerFactory: () => _Fake([]), bundle: _Bundle('not json'))));
    await t.pump();
    await t.pump();
    expect(find.text('تعذر تحميل قائمة الإذاعات.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}
