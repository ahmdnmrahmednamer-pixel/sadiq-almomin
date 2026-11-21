import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/models/zakat_calculation.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/core/services/zakat_service.dart';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'package:almomin/features/zakat/zakat_screen.dart';

class ZakatRejectStore extends InMemorySharedPreferencesStore {
  ZakatRejectStore(Map<String, Object> data) : super.withData(data);
  bool reject = false, throwing = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.zakat_calculation_draft_v1') {
      writes++;
      if (throwing) throw PlatformException(code: 'storage');
      if (gate != null)
        return gate!.future.then((_) async =>
            reject ? false : await super.setValue(type, key, value));
      if (reject) return Future.value(false);
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dynamic service = ZakatService.instance;
  final draft =
      ZakatCalculation(cashOnHand: 1000, hawlDate: DateTime(2027, 1, 1));
  late ZakatRejectStore store;
  setUpAll(() async {
    await (FontLoader('Cairo')
          ..addFont(Future.value(ByteData.sublistView(
              File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync()))))
        .load();
    const icons = String.fromEnvironment('MATERIAL_ICONS_FONT');
    if (icons.isNotEmpty)
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                ByteData.sublistView(File(icons).readAsBytesSync()))))
          .load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ZakatRejectStore(
        {'flutter.zakat_calculation_draft_v1': jsonEncode(draft.toJson())});
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  final cases = <String, Future<dynamic> Function()>{
    'update': () =>
        service.updateCalculation(const ZakatCalculation(cashOnHand: 2000)),
    'reset': () => service.reset(),
    'Hawl date': () => service.setHawlDate(DateTime(2027, 2, 1)),
  };
  for (final c in cases.entries)
    for (final throwing in [false, true]) {
      test(
          '${c.key} failed save preserves confirmed calculation throw=$throwing',
          () async {
        store.reject = !throwing;
        store.throwing = throwing;
        var changes = 0;
        void listener() => changes++;
        service.addListener(listener);
        addTearDown(() => service.removeListener(listener));
        expect(await c.value(), false);
        expect(service.exportData(), draft.toJson());
        expect(changes, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString('zakat_calculation_draft_v1')!),
            draft.toJson());
        await prefs.reload();
        expect(jsonDecode(prefs.getString('zakat_calculation_draft_v1')!),
            draft.toJson());
      });
    }
  for (final throwing in [false, true]) {
    test('backup cannot report success when Zakat import fails throw=$throwing',
        () async {
      store.reject = !throwing;
      store.throwing = throwing;
      final restored = await BackupRestoreService.instance.restoreBackup({
        'app': 'AlMomin',
        'schema_version': 1,
        'data': {
          'zakat_calculation': const ZakatCalculation(cashOnHand: 2000).toJson()
        },
      }, replaceMode: false);
      expect(restored, false);
      expect(service.exportData(), draft.toJson());
    });
  }
  test('queued saves publish only after confirmation and in order', () async {
    store.gate = Completer<void>();
    final seen = <double>[];
    void listener() => seen.add(service.calculation.cashOnHand);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    final first =
        service.updateCalculation(const ZakatCalculation(cashOnHand: 2000));
    final second =
        service.updateCalculation(const ZakatCalculation(cashOnHand: 3000));
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.calculation.cashOnHand, 1000);
    expect(seen, isEmpty);
    store.gate!.complete();
    expect(await first, true);
    expect(await second, true);
    expect(seen, [2000, 3000]);
    await service.init(forceReload: true);
    expect(service.calculation.cashOnHand, 3000);
  });
  test('reload waits for admitted save and observes durable result', () async {
    store.gate = Completer<void>();
    final saved =
        service.updateCalculation(const ZakatCalculation(cashOnHand: 2000));
    final reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(service.calculation.cashOnHand, 1000);
    store.gate!.complete();
    expect(await saved, true);
    await reload;
    expect(service.calculation.cashOnHand, 2000);
  });
  test('queued Hawl change uses latest confirmed amounts', () async {
    store.gate = Completer<void>();
    final saved = service.updateCalculation(
        const ZakatCalculation(cashOnHand: 2000, currency: '€'));
    final date = service.setHawlDate(DateTime(2027, 2, 1));
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    expect(await saved, true);
    expect(await date, true);
    await service.init(forceReload: true);
    expect(service.calculation.cashOnHand, 2000);
    expect(service.calculation.currency, '€');
    expect(service.calculation.hawlDate, DateTime(2027, 2, 1));
  });
  test('queued reset preserves latest confirmed currency prices and basis',
      () async {
    store.gate = Completer<void>();
    final saved = service.updateCalculation(const ZakatCalculation(
        cashOnHand: 2000,
        currency: '€',
        goldPricePerGram24: 4000,
        silverPricePerGram: 70,
        nisabBasis: ZakatNisabBasis.silver));
    final reset = service.reset();
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    expect(await saved, true);
    expect(await reset, true);
    await service.init(forceReload: true);
    expect(service.calculation.cashOnHand, 0);
    expect(service.calculation.currency, '€');
    expect(service.calculation.goldPricePerGram24, 4000);
    expect(service.calculation.silverPricePerGram, 70);
    expect(service.calculation.nisabBasis, ZakatNisabBasis.silver);
  });
  test(
      'failed import is propagated and a later successful retry survives reload',
      () async {
    final next =
        const ZakatCalculation(cashOnHand: 2000, currency: '€').toJson();
    store.reject = true;
    await expectLater(service.importData(next), throwsStateError);
    expect(service.exportData(), draft.toJson());
    store.reject = false;
    await service.importData(next);
    await service.init(forceReload: true);
    expect(service.exportData(), next);
  });
  test('malformed import propagates without mutation or write', () async {
    await expectLater(
        service.importData({'cash_on_hand': 'bad'}), throwsA(isA<TypeError>()));
    expect(service.exportData(), draft.toJson());
    expect(store.writes, 0);
  });
  for (final scale in [1.0]) {
    testWidgets(
        'screen preserves failed draft and saves actual retry at $scale',
        (t) async {
      await SettingsService.instance.init(forceReload: true);
      t.view.physicalSize = const Size(420, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
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
              home: const ZakatScreen())));
      await t.pumpAndSettle();
      final cash = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.labelText?.contains('الأموال النقدية') ?? false));
      await t.scrollUntilVisible(cash, 300,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      store.reject = true;
      await t.enterText(cash, '400000');
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(service.calculation.cashOnHand, 1000);
      expect(t.widget<TextField>(cash).controller!.text, '400000');
      await t.scrollUntilVisible(find.text('إعادة محاولة الحفظ'), -300,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(find.textContaining('مسودة غير محفوظة'), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true),
          findsAtLeastNWidgets(1));
      await t.drag(find.byType(ListView), const Offset(0, 1200));
      await t.pumpAndSettle();
      final dir = Platform.environment['ZAKAT_PIXELS'];
      if (dir != null)
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$dir/failure-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      store.reject = false;
      await t.tap(find.text('إعادة محاولة الحفظ'));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(find.textContaining('مسودة غير محفوظة'), findsNothing);
      await t.runAsync(() => service.init(forceReload: true));
      expect(service.calculation.cashOnHand, 400000);
      expect(t.takeException(), isNull);
      semantics.dispose();
    });
  }
  testWidgets(
      'screen reset retains inputs on rejection and announces only confirmed retry',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: ZakatScreen()));
    await t.pumpAndSettle();
    store.reject = true;
    await t.tap(find.byTooltip('إعادة تعيين'));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
    expect(service.calculation.cashOnHand, 1000);
    expect(find.text('تمت إعادة تعيين حاسبة الزكاة'), findsNothing);
    final cash = find.byWidgetPredicate((w) =>
        w is TextField &&
        (w.decoration?.labelText?.contains('الأموال النقدية') ?? false));
    await t.scrollUntilVisible(cash, 300,
        scrollable: find.byType(Scrollable).first);
    expect(t.widget<TextField>(cash).controller!.text, '1000');
    await t.scrollUntilVisible(find.text('إعادة محاولة الحفظ'), -300,
        scrollable: find.byType(Scrollable).first);
    store.reject = false;
    await t.tap(find.text('إعادة محاولة الحفظ'));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
    expect(find.text('تمت إعادة تعيين حاسبة الزكاة'), findsOneWidget);
    expect(service.calculation.cashOnHand, 0);
    await t.scrollUntilVisible(cash, 300,
        scrollable: find.byType(Scrollable).first);
    expect(t.widget<TextField>(cash).controller!.text, '');
  });
}
