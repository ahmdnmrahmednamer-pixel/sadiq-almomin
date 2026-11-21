import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/features/hadith/hadith_library_screen.dart';
import 'package:almomin/features/hadith/hadith_detail_screen.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/hadith_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';

class HadithStore extends InMemorySharedPreferencesStore {
  HadithStore()
      : super.withData({
          'flutter.hadith_favorite_ids': <String>['999']
        });
  bool reject = false, throwing = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.hadith_favorite_ids') {
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
  final dynamic service = HadithService.instance;
  late HadithStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = HadithStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  for (final throwing in [false, true]) {
    test('failed favorite keeps confirmed state throw=$throwing', () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.toggleFavorite(3), false);
      expect(service.favoriteIds, {999});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('hadith_favorite_ids'), ['999']);
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
            'hadith_favorites': [3]
          }
        }, replaceMode: replace);
        expect(success, false);
        expect(service.favoriteIds, {999});
      });
  }

  test('concurrent different favorites serialize and survive reload', () async {
    store.gate = Completer<void>();
    final first = service.toggleFavorite(1);
    final second = service.toggleFavorite(2);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.favoriteIds, {999});
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    await service.init(forceReload: true);
    expect(service.favoriteIds, {999, 1, 2});
  });
  test('same favorite toggles publish in confirmed order', () async {
    store.gate = Completer<void>();
    final seen = <bool>[];
    void listener() => seen.add(service.isFavorite(1) as bool);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    final first = service.toggleFavorite(1);
    final second = service.toggleFavorite(1);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    expect(seen, [true, false]);
    expect(service.favoriteIds, {999});
  });
  test('reload waits for admitted save', () async {
    store.gate = Completer<void>();
    final saved = service.toggleFavorite(1);
    final reloaded = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(service.favoriteIds, {999});
    store.gate!.complete();
    expect(await saved, true);
    await reloaded;
    expect(service.favoriteIds, {999, 1});
  });
  test('failed write does not notify and retry confirms durable favorites',
      () async {
    var changes = 0;
    void listener() => changes++;
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    store.reject = true;
    expect(await service.toggleFavorite(1), false);
    expect(changes, 0);
    store.reject = false;
    expect(await service.toggleFavorite(1), true);
    expect(changes, 1);
    await service.init(forceReload: true);
    expect(service.favoriteIds, {999, 1});
  });
  for (final replace in [false, true])
    test('successful import preserves merge choice replace=$replace', () async {
      await service.importFavorites(<int>[1, 1], replace: replace);
      await service.init(forceReload: true);
      expect(service.favoriteIds, replace ? {1} : {999, 1});
    });
  test('queued import snapshots mutable caller list', () async {
    store.gate = Completer<void>();
    final save = service.toggleFavorite(1);
    final incoming = <int>[2];
    final imported = service.importFavorites(incoming);
    incoming.clear();
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    expect(await save, true);
    await imported;
    expect(service.favoriteIds, {999, 1, 2});
  });
  test('malformed reload keeps confirmed favorites', () async {
    await store.setValue('String', 'flutter.hadith_favorite_ids', 'wrong');
    await service.init(forceReload: true);
    expect(service.favoriteIds, {999});
  });
  test('missing reload clears stale favorites', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hadith_favorite_ids');
    await service.init(forceReload: true);
    expect(service.favoriteIds, isEmpty);
  });
  for (final detail in [false, true])
    for (final scale in [1.0, 2.0])
      testWidgets(
          'actual favorite rejects and retries detail=$detail scale=$scale',
          (t) async {
        await t.runAsync(() async {
          await SettingsService.instance.init(forceReload: true);
          for (final name in ['Cairo', 'Amiri'])
            await (FontLoader(name)
                  ..addFont(Future.value(ByteData.sublistView(
                      File('assets/fonts/$name-Regular.ttf')
                          .readAsBytesSync()))))
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
                  home: detail
                      ? const HadithDetailScreen(hadithId: 1)
                      : const HadithLibraryScreen())));
          await t.pumpAndSettle();
          final favorite = find.byTooltip('إضافة إلى المفضلة').first;
          store.reject = true;
          await t.tap(favorite);
          await t.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await t.pumpAndSettle();
          expect(service.isFavorite(1), false);
          expect(
              find.textContaining('لم يتم حفظ تغيير المفضلة'), findsOneWidget);
          expect(
              find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.liveRegion == true),
              findsAtLeastNWidgets(1));
          final dir = Platform.environment['HADITH_PIXELS'];
          if (dir != null)
            await t.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$dir/retry-$detail-$scale.png')
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
          expect(service.isFavorite(1), true);
          expect(find.textContaining('لم يتم حفظ تغيير المفضلة'), findsNothing);
          expect(find.byTooltip('إزالة من المفضلة').first.hitTestable(),
              findsOneWidget);
          if (dir != null)
            await t.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$dir/success-$detail-$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });

  test('favorite getter cannot bypass confirmed storage', () {
    expect(
        () => (service.favoriteIds as Set<int>).add(1), throwsUnsupportedError);
    expect(service.favoriteIds, {999});
  });
  test('malformed last-read reload does not partially publish favorites',
      () async {
    await store
        .setValue('StringList', 'flutter.hadith_favorite_ids', <String>['1']);
    await store.setValue('String', 'flutter.hadith_last_read_id', 'wrong');
    await service.init(forceReload: true);
    expect(service.favoriteIds, {999});
  });
  for (final throwing in [false, true]) {
    test('failed favorite removal keeps stored selection throw=$throwing',
        () async {
      store.reject = !throwing;
      store.throwing = throwing;
      expect(await service.toggleFavorite(999), false);
      expect(service.favoriteIds, {999});
      expect(
          (await SharedPreferences.getInstance())
              .getStringList('hadith_favorite_ids'),
          ['999']);
    });
  }
  testWidgets('detail observes confirmed external favorite import', (t) async {
    await t
        .pumpWidget(const MaterialApp(home: HadithDetailScreen(hadithId: 1)));
    await t.pumpAndSettle();
    await t.runAsync(() => service.importFavorites(<int>[1], replace: true));
    await t.pumpAndSettle();
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  for (final detail in [false, true]) {
    testWidgets('pending favorite ignores repeat taps detail=$detail',
        (t) async {
      await t.pumpWidget(MaterialApp(
          home: detail
              ? const HadithDetailScreen(hadithId: 1)
              : const HadithLibraryScreen()));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        store.gate = Completer<void>();
        await t.tap(find.byTooltip('إضافة إلى المفضلة').first);
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
      await t.tap(pending);
      await t.pump();
      expect(find.byType(HadithDetailScreen),
          detail ? findsOneWidget : findsNothing);
      expect(store.writes, 1);
      expect(service.isFavorite(1), false);
      await t.runAsync(() async {
        store.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(service.isFavorite(1), true);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('library detail favorite round trip refreshes confirmed state',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: HadithLibraryScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('الأعمال بالنيات').first);
    await t.pumpAndSettle();
    expect(find.byType(HadithDetailScreen), findsOneWidget);
    await t.tap(find.byTooltip('إضافة إلى المفضلة').first);
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    expect(service.isFavorite(1), true);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byTooltip('إزالة من المفضلة').first, findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
