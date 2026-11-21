import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/features/library/screens/fiqh_library_screen.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/fiqh_library_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';

class FiqhStore extends InMemorySharedPreferencesStore {
  FiqhStore()
      : super.withData({
          'flutter.fiqh_library_favorites_v1': <String>['old']
        });
  bool reject = false, throwing = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.fiqh_library_favorites_v1') {
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
  final dynamic service = FiqhLibraryService.instance;
  late FiqhStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FiqhStore();
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
      expect(prefs.getStringList('fiqh_library_favorites_v1'), ['old']);
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
            'fiqh_library_favorites': ['new']
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
    final imported = service.importFavorites(incoming);
    incoming.clear();
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    expect(await save, true);
    await imported;
    expect(service.favoriteIds, {'old', 'a', 'b'});
  });
  test('malformed reload keeps confirmed favorites', () async {
    await store.setValue(
        'String', 'flutter.fiqh_library_favorites_v1', 'wrong');
    await service.init(forceReload: true);
    expect(service.favoriteIds, {'old'});
  });
  test('missing reload clears stale favorites', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fiqh_library_favorites_v1');
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
                home: const FiqhLibraryScreen())));
        await t.pumpAndSettle();
        final favorite = find.byTooltip('حفظ في المفضلة').first;
        await t.scrollUntilVisible(favorite, 200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        store.reject = true;
        await t.tap(favorite);
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpAndSettle();
        expect(service.isFavorite(FiqhLibraryService.topics.first.id), false);
        await t.scrollUntilVisible(find.text('إعادة محاولة الحفظ'), -200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        await t.drag(find.byType(ListView).first, const Offset(0, 3000));
        await t.pumpAndSettle();
        expect(find.textContaining('لم يتم حفظ تغيير المفضلة'), findsOneWidget);
        expect(
            find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true),
            findsAtLeastNWidgets(1));
        final dir = Platform.environment['FIQH_PIXELS'];
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
        expect(service.isFavorite(FiqhLibraryService.topics.first.id), true);
        expect(find.textContaining('لم يتم حفظ تغيير المفضلة'), findsNothing);
        await t.scrollUntilVisible(
            find.byTooltip('إزالة من المفضلة').first, 200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        expect(find.byTooltip('إزالة من المفضلة').first.hitTestable(),
            findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  testWidgets(
      'screen observes confirmed external import without optimistic local rebuild',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: FiqhLibraryScreen()));
    await t.pumpAndSettle();
    await t.runAsync(() => service.importFavorites(
        <String>[FiqhLibraryService.topics.first.id],
        replace: true));
    await t.pumpAndSettle();
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
