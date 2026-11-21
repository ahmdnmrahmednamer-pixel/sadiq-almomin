import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/features/wird/daily_wird_screen.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/daily_wird_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';

class WirdStore extends InMemorySharedPreferencesStore {
  WirdStore(Map<String, Object> data) : super.withData(data);
  bool reject = false, throwing = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.daily_wird_records_v1') {
      writes++;
      if (gate != null)
        return gate!.future.then((_) async =>
            reject ? false : await super.setValue(type, key, value));
      if (throwing) throw PlatformException(code: 'storage');
      if (reject) return Future.value(false);
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dynamic service = DailyWirdService.instance;
  final day = DateTime(2026, 11, 21);
  final initial = {
    '2026-11-21': ['wird_fajr_sunnah']
  };
  late WirdStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = WirdStore({'flutter.daily_wird_records_v1': jsonEncode(initial)});
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  for (final throwing in [false, true]) {
    test('toggle failure keeps live and cached durable record throw=$throwing',
        () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.toggleTask('wird_quran_portion', day), false);
      expect(service.exportData(), initial);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('daily_wird_records_v1')!), initial);
      await prefs.reload();
      expect(jsonDecode(prefs.getString('daily_wird_records_v1')!), initial);
    });
    for (final replace in [false, true])
      test(
          'backup import failure keeps live record replace=$replace throw=$throwing',
          () async {
        store.reject = !throwing;
        store.throwing = throwing;
        final success = await BackupRestoreService.instance.restoreBackup({
          'app': 'AlMomin',
          'schema_version': 1,
          'data': {
            'daily_wird_records': {
              '2026-11-22': ['wird_quran_portion']
            }
          }
        }, replaceMode: replace);
        expect(success, false);
        expect(service.exportData(), initial);
      });
  }

  test('concurrent different toggles serialize without losing either task',
      () async {
    store.gate = Completer<void>();
    final first = service.toggleTask('wird_quran_portion', day);
    final second = service.toggleTask('wird_morning_adhkar', day);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.exportData(), initial);
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    await service.init(forceReload: true);
    expect(service.getCompletedToday(day),
        {'wird_fajr_sunnah', 'wird_quran_portion', 'wird_morning_adhkar'});
  });
  test('two queued toggles of same task cancel only after both saves',
      () async {
    store.gate = Completer<void>();
    final seen = <bool>[];
    void listener() =>
        seen.add(service.isCompleted('wird_quran_portion', day) as bool);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    final a = service.toggleTask('wird_quran_portion', day);
    final b = service.toggleTask('wird_quran_portion', day);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    store.gate!.complete();
    expect(await a, true);
    expect(await b, true);
    expect(seen, [true, false]);
    expect(service.exportData(), initial);
  });
  test('reload queues behind admitted write', () async {
    store.gate = Completer<void>();
    final saved = service.toggleTask('wird_quran_portion', day);
    final reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(service.exportData(), initial);
    store.gate!.complete();
    expect(await saved, true);
    await reload;
    expect(service.isCompleted('wird_quran_portion', day), true);
  });
  test('failed save does not notify progress and later retry is durable',
      () async {
    var changes = 0;
    void listener() => changes++;
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    store.reject = true;
    expect(await service.toggleTask('wird_quran_portion', day), false);
    expect(changes, 0);
    expect(service.getTodayPoints(day), 20);
    store.reject = false;
    expect(await service.toggleTask('wird_quran_portion', day), true);
    expect(changes, 1);
    await service.init(forceReload: true);
    expect(service.getTodayPoints(day), 45);
    expect(service.getTodayCompletionRatio(day), .25);
  });
  for (final replace in [false, true])
    test('successful import preserves merge choice replace=$replace', () async {
      await service.importData({
        '2026-11-21': ['wird_quran_portion'],
        '2026-11-22': ['wird_morning_adhkar']
      }, replace: replace);
      await service.init(forceReload: true);
      expect(
          service.getCompletedToday(day),
          replace
              ? {'wird_quran_portion'}
              : {'wird_fajr_sunnah', 'wird_quran_portion'});
      expect(service.getCompletedToday(DateTime(2026, 11, 22)),
          {'wird_morning_adhkar'});
    });
  test('queued import snapshots caller data before waiting', () async {
    store.gate = Completer<void>();
    final toggle = service.toggleTask('wird_quran_portion', day);
    final incoming = <String, dynamic>{
      '2026-11-21': ['wird_morning_adhkar']
    };
    final imported = service.importData(incoming);
    (incoming['2026-11-21'] as List).clear();
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    expect(await toggle, true);
    await imported;
    expect(service.getCompletedToday(day),
        {'wird_fajr_sunnah', 'wird_quran_portion', 'wird_morning_adhkar'});
  });
  test('malformed reload preserves complete confirmed records', () async {
    await store.setValue('String', 'flutter.daily_wird_records_v1', '{bad');
    await service.init(forceReload: true);
    expect(service.exportData(), initial);
  });
  test('missing and empty forced reload clear stale records', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('daily_wird_records_v1');
    await service.init(forceReload: true);
    expect(service.exportData(), isEmpty);
    await service.toggleTask('wird_quran_portion', day);
    await prefs.setString('daily_wird_records_v1', '');
    await service.init(forceReload: true);
    expect(service.exportData(), isEmpty);
  });
  for (final scale in [1.0, 2.0])
    testWidgets('actual task rejects then saves retry at $scale', (t) async {
      await t.runAsync(() async {
        await SettingsService.instance.init(forceReload: true);
        await service.importData(<String, dynamic>{}, replace: true);
        for (final name in ['Cairo', 'Amiri']) {
          await (FontLoader(name)
                ..addFont(Future.value(ByteData.sublistView(
                    File('assets/fonts/$name-Regular.ttf').readAsBytesSync()))))
              .load();
        }
        const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
        if (icons.isNotEmpty)
          await (FontLoader('MaterialIcons')
                ..addFont(Future.value(
                    ByteData.sublistView(File(icons).readAsBytesSync()))))
              .load();
      });
      t.view.physicalSize = const Size(420, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      try {
        final boundary = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: const DailyWirdScreen())));
        await t.pumpAndSettle();
        final task = find.text(DailyWirdService.defaultTasks.first.title);
        await t.scrollUntilVisible(task, 200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        store.reject = true;
        await t.tap(task);
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpAndSettle();
        expect(service.getCompletedToday(), isEmpty);
        expect(service.getTodayPoints(), 0);
        await t.drag(find.byType(ListView).first, const Offset(0, 1800));
        await t.pumpAndSettle();
        expect(find.textContaining('لم يتم حفظ تغيير الورد'), findsOneWidget);
        expect(
            find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true),
            findsAtLeastNWidgets(1));
        final dir = Platform.environment['WIRD_PIXELS'];
        if (dir != null)
          await t.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$dir/retry-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        store.reject = false;
        await t.tap(find.text('إعادة محاولة الحفظ'));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpAndSettle();
        await t.runAsync(() => service.init(forceReload: true));
        expect(service.isCompleted('wird_fajr_sunnah'), true);
        expect(service.getTodayPoints(), 20);
        expect(find.textContaining('لم يتم حفظ تغيير الورد'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  testWidgets('pending task cannot be double submitted or publish points early',
      (t) async {
    await t
        .runAsync(() => service.importData(<String, dynamic>{}, replace: true));
    await t.pumpWidget(const MaterialApp(home: DailyWirdScreen()));
    await t.pumpAndSettle();
    final task = find.text(DailyWirdService.defaultTasks.first.title);
    await t.scrollUntilVisible(task, 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    store.gate = Completer<void>();
    final before = store.writes;
    await t.runAsync(() async {
      await t.tap(task);
      await Future<void>.delayed(Duration.zero);
      await t.tap(task);
      await Future<void>.delayed(Duration.zero);
    });
    await t.pump();
    expect(store.writes, before + 1);
    expect(service.getTodayPoints(), 0);
    store.gate!.complete();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
    expect(store.writes, before + 1);
    expect(service.getTodayPoints(), 20);
    await t.pumpWidget(const SizedBox());
  });
}
