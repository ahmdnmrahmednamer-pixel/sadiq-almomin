import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/features/egypt/egyptian_heritage_screen.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/egyptian_heritage_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';

class HeritageStore extends InMemorySharedPreferencesStore {
  HeritageStore()
      : super.withData({
          'flutter.egyptian_heritage_favorites': <String>['old']
        });
  bool reject = false, throwing = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.egyptian_heritage_favorites') {
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
  final dynamic service = EgyptianHeritageService.instance;
  late HeritageStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = HeritageStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  for (final throwing in [false, true]) {
    test('failed favorite keeps confirmed state throw=$throwing', () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.toggleFavorite('new'), false);
      expect(service.favoriteIds, {'old'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('egyptian_heritage_favorites'), ['old']);
    });
    for (final replace in [false, true])
      test(
          'backup failed favorite import remains truthful replace=$replace throw=$throwing',
          () async {
        store.reject = !throwing;
        store.throwing = throwing;
        final success = await BackupRestoreService.instance.restoreBackup({
          'app': 'AlMomin',
          'schema_version': 1,
          'data': {
            'egyptian_heritage_favorites': ['new']
          }
        }, replaceMode: replace);
        expect(success, false);
        expect(service.favoriteIds, {'old'});
      });
  }

  test('concurrent different favorites serialize and survive reload', () async {
    store.gate = Completer<void>();
    final first = service.toggleFavorite('a');
    final second = service.toggleFavorite('b');
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.favoriteIds, {'old'});
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    await service.init(forceReload: true);
    expect(service.favoriteIds, {'old', 'a', 'b'});
  });
  test('same favorite toggles publish in confirmed order', () async {
    store.gate = Completer<void>();
    final seen = <bool>[];
    void listener() => seen.add(service.isFavorite('a') as bool);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    final first = service.toggleFavorite('a');
    final second = service.toggleFavorite('a');
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    expect(seen, [true, false]);
    expect(service.favoriteIds, {'old'});
  });
  test('reload waits for admitted save', () async {
    store.gate = Completer<void>();
    final saved = service.toggleFavorite('a');
    final reloaded = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(service.favoriteIds, {'old'});
    store.gate!.complete();
    expect(await saved, true);
    await reloaded;
    expect(service.favoriteIds, {'old', 'a'});
  });
  test('failed write does not notify and retry confirms durable favorites',
      () async {
    var changes = 0;
    void listener() => changes++;
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    store.reject = true;
    expect(await service.toggleFavorite('a'), false);
    expect(changes, 0);
    store.reject = false;
    expect(await service.toggleFavorite('a'), true);
    expect(changes, 1);
    await service.init(forceReload: true);
    expect(service.favoriteIds, {'old', 'a'});
  });
  for (final replace in [false, true])
    test('successful import preserves merge choice replace=$replace', () async {
      await service.importFavorites(<String>['a', 'a'], replace: replace);
      await service.init(forceReload: true);
      expect(service.favoriteIds, replace ? {'a'} : {'old', 'a'});
    });
  test('queued import snapshots mutable caller list', () async {
    store.gate = Completer<void>();
    final save = service.toggleFavorite('a');
    final incoming = <String>['b'];
    final imported = service.importFavorites(incoming, replace: false);
    incoming.clear();
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    expect(await save, true);
    await imported;
    expect(service.favoriteIds, {'old', 'a', 'b'});
  });
  test('malformed reload keeps confirmed favorites', () async {
    await store.setValue(
        'String', 'flutter.egyptian_heritage_favorites', 'wrong');
    await service.init(forceReload: true);
    expect(service.favoriteIds, {'old'});
  });
  test('missing reload clears stale favorites', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('egyptian_heritage_favorites');
    await service.init(forceReload: true);
    expect(service.favoriteIds, isEmpty);
  });
  for (final scale in [1.0, 2.0])
    testWidgets('actual favorite rejects and retries at $scale', (t) async {
      await t.runAsync(() async {
        await SettingsService.instance.init(forceReload: true);
        for (final name in ['Cairo', 'Amiri'])
          await (FontLoader(name)
                ..addFont(Future.value(ByteData.sublistView(
                    File('assets/fonts/$name-Regular.ttf').readAsBytesSync()))))
              .load();
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
                home: const EgyptianHeritageScreen(initialTabIndex: 2))));
        await t.pumpAndSettle();
        final favorite = find.byTooltip('حفظ في المفضلة').first;
        await t.scrollUntilVisible(favorite, 200,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await t.pumpAndSettle();
        store.reject = true;
        await t.tap(favorite);
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpAndSettle();
        expect(
            service.isFavorite(
                EgyptianHeritageService.instance.historicMosques.first.id),
            false);
        await t.scrollUntilVisible(find.text('إعادة محاولة الحفظ'), -200,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await t.pumpAndSettle();
        await t.drag(find.byType(ListView).first, const Offset(0, 3000));
        await t.pumpAndSettle();
        expect(find.textContaining('لم يتم حفظ تغيير المفضلة'), findsOneWidget);
        expect(
            find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true),
            findsAtLeastNWidgets(1));
        final dir = Platform.environment['EGYPT_PIXELS'];
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
        await t.pump();
        expect(
            service.isFavorite(
                EgyptianHeritageService.instance.historicMosques.first.id),
            true);
        expect(find.textContaining('لم يتم حفظ تغيير المفضلة'), findsNothing);
        await t.scrollUntilVisible(
            find.byTooltip('إزالة من المفضلة').first, 200,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await t.pumpAndSettle();
        expect(find.byTooltip('إزالة من المفضلة').first.hitTestable(),
            findsOneWidget);
        if (dir != null)
          await t.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$dir/success-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });

  test('malformed gold reload cannot partially publish favorites', () async {
    await store.setValue(
        'StringList', 'flutter.egyptian_heritage_favorites', <String>['new']);
    await store.setValue('Int', 'flutter.egyptian_preferred_gold_karat', 123);
    await service.init(forceReload: true);
    expect(service.favoriteIds, {'old'});
    expect(service.selectedGoldKarat, '21');
  });
  test('default import replaces while explicit merge retains favorites',
      () async {
    await service.importFavorites(<String>['new']);
    expect(service.favoriteIds, {'new'});
    await service.importFavorites(<String>['more'], replace: false);
    await service.init(forceReload: true);
    expect(service.favoriteIds, {'new', 'more'});
  });
  testWidgets('pending favorite disables repeat tap until durable completion',
      (t) async {
    await t.pumpWidget(
        const MaterialApp(home: EgyptianHeritageScreen(initialTabIndex: 2)));
    await t.pumpAndSettle();
    final favorite = find.byTooltip('حفظ في المفضلة').first;
    await t.scrollUntilVisible(favorite, 200,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first);
    await t.runAsync(() async {
      store.gate = Completer<void>();
      await t.tap(favorite);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
    final pending = find.byTooltip('جارٍ حفظ المفضلة').first;
    expect(
        t
            .widget<IconButton>(find
                .ancestor(of: pending, matching: find.byType(IconButton))
                .first)
            .onPressed,
        isNull);
    expect(
        service.isFavorite(
            EgyptianHeritageService.instance.historicMosques.first.id),
        false);
    await t.tap(pending);
    expect(store.writes, 1);
    await t.runAsync(() async {
      store.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
    expect(
        service.isFavorite(
            EgyptianHeritageService.instance.historicMosques.first.id),
        true);
    await t.pumpWidget(const SizedBox());
  });

  for (final kind in ['radio', 'ibtihal', 'shaarawi', 'mosque', 'fatwa']) {
    testWidgets('actual $kind favorite saves and removes durably', (t) async {
      final heritage = EgyptianHeritageService.instance;
      final data = switch (kind) {
        'radio' => (
            0,
            heritage.radioStations.first.id,
            heritage.radioStations.first.name
          ),
        'ibtihal' => (
            1,
            heritage.ibtihalat.first.id,
            heritage.ibtihalat.first.title
          ),
        'shaarawi' => (
            1,
            heritage.shaarawiReflections.first.id,
            heritage.shaarawiReflections.first.title
          ),
        'mosque' => (
            2,
            heritage.historicMosques.first.id,
            heritage.historicMosques.first.name
          ),
        _ => (
            3,
            heritage.darAlIftaRulings.first.id,
            'س: ${heritage.darAlIftaRulings.first.question}'
          ),
      };
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
          MaterialApp(home: EgyptianHeritageScreen(initialTabIndex: data.$1)));
      await t.pumpAndSettle();
      final vertical = find
          .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first;
      await t.scrollUntilVisible(find.text(data.$3).last, 400,
          scrollable: vertical, maxScrolls: 100);
      final card = find
          .ancestor(of: find.text(data.$3).last, matching: find.byType(Card))
          .first;
      var button =
          find.descendant(of: card, matching: find.byTooltip('حفظ في المفضلة'));
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pumpAndSettle();
      expect(service.isFavorite(data.$2), true);
      await t.runAsync(() => service.init(forceReload: true));
      expect(service.isFavorite(data.$2), true);
      button = find.descendant(
          of: card, matching: find.byTooltip('إزالة من المفضلة'));
      await t.tap(button);
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pumpAndSettle();
      await t.runAsync(() => service.init(forceReload: true));
      expect(service.isFavorite(data.$2), false);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final throwing in [false, true]) {
    test('failed removal preserves durable favorite throw=$throwing', () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.toggleFavorite('old'), false);
      expect(service.favoriteIds, {'old'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('egyptian_heritage_favorites'), ['old']);
    });
  }
}
