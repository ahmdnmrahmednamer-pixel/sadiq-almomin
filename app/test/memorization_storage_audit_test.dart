import 'dart:async';
import 'package:almomin/core/services/backup_restore_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:almomin/core/services/quran_repository.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/mushaf/memorization_screen.dart';
import 'package:almomin/features/mushaf/widgets/ayah_action_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/models/memorization_item.dart';
import 'package:almomin/core/services/memorization_service.dart';

class RejectMemorizationStore extends InMemorySharedPreferencesStore {
  RejectMemorizationStore() : super.withData({});
  bool reject = true, throwing = false;
  bool memorizationOnly = false;
  Completer<void>? hold;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (memorizationOnly && !key.endsWith('memorization_items_v1')) {
      return await super.setValue(type, key, value);
    }
    writes++;
    if (hold != null) await hold!.future;
    if (throwing) throw PlatformException(code: 'save-test');
    return reject ? false : await super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (throwing) throw PlatformException(code: 'save-test');
    return reject ? false : await super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = MemorizationService.instance;
  test('rejected review write cannot publish an unsaved tracked ayah',
      () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = RejectMemorizationStore();
    await service.init(forceReload: true);
    try {
      await service.recordReview(
          surahId: 1,
          ayahNumber: 1,
          surahName: 'الفاتحة',
          rating: MemorizationRating.easy);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('memorization_items_v1'), isNull);
    expect(service.hasItem(1, 1), isFalse);
  });
  test('unreadable stored history is not replaced by a new review', () async {
    const original = '{unreadable-history';
    SharedPreferences.setMockInitialValues({'memorization_items_v1': original});
    await service.init(forceReload: true);
    try {
      await service.recordReview(
          surahId: 2,
          ayahNumber: 1,
          surahName: 'البقرة',
          rating: MemorizationRating.easy);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('memorization_items_v1'), original);
    expect(service.exportData, throwsA(isA<MemorizationStorageException>()));
    await expectLater(BackupRestoreService.instance.exportBackupData(),
        throwsA(isA<MemorizationStorageException>()));
  });
  for (final throwing in [false, true]) {
    test(
        'rejected delete/clear/import retain history and retry, throw=$throwing',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = RejectMemorizationStore()..reject = false;
      SharedPreferencesStorePlatform.instance = store;
      await service.init(forceReload: true);
      await service.recordReview(
          surahId: 1,
          ayahNumber: 1,
          surahName: 'الفاتحة',
          rating: MemorizationRating.easy);
      final before = (await SharedPreferences.getInstance())
          .getString('memorization_items_v1');
      store.reject = !throwing;
      store.throwing = throwing;
      final imported = MemorizationItem.createInitial(
              surahId: 2, ayahNumber: 2, surahName: 'البقرة')
          .toJson();
      for (final action in <Future<dynamic> Function()>[
        () => service.deleteItem(1, 1),
        () => service.clearAll(),
        () => service.importData([imported], merge: false),
      ]) {
        await expectLater(
            action(), throwsA(isA<MemorizationStorageException>()));
        expect(service.hasItem(1, 1), isTrue);
        expect(service.hasItem(2, 2), isFalse);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(prefs.getString('memorization_items_v1'), before);
      }
      store.reject = false;
      store.throwing = false;
      await service.deleteItem(1, 1);
      expect(service.hasItem(1, 1), isFalse);
      expect(service.storageError, isNull);
    });
  }
  test('pending reviews serialize without publishing or losing counts',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gate = Completer<void>();
    final store = RejectMemorizationStore()
      ..reject = false
      ..hold = gate;
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
    final first = service.recordReview(
        surahId: 1,
        ayahNumber: 1,
        surahName: 'الفاتحة',
        rating: MemorizationRating.easy);
    final second = service.recordReview(
        surahId: 1,
        ayahNumber: 1,
        surahName: 'الفاتحة',
        rating: MemorizationRating.hard);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(service.hasItem(1, 1), isFalse);
    store.hold = null;
    gate.complete();
    await first;
    await second;
    expect(service.getItem(1, 1)!.timesReviewed, 2);
    await service.init(forceReload: true);
    expect(service.getItem(1, 1)!.timesReviewed, 2);
  });
  test('unknown saved fields survive review and backup export', () async {
    final row = MemorizationItem.createInitial(
            surahId: 1, ayahNumber: 1, surahName: 'الفاتحة')
        .toJson()
      ..['future_metadata'] = {'tag': 'preserve'};
    SharedPreferences.setMockInitialValues({
      'memorization_items_v1': jsonEncode([row])
    });
    await service.init(forceReload: true);
    await service.recordReview(
        surahId: 1,
        ayahNumber: 1,
        surahName: 'الفاتحة',
        rating: MemorizationRating.easy);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        (jsonDecode(prefs.getString('memorization_items_v1')!) as List)
            .single['future_metadata'],
        {'tag': 'preserve'});
    expect(service.exportData().single['future_metadata'], {'tag': 'preserve'});
  });
  test('malformed import is staged, not a partial clear', () async {
    SharedPreferences.setMockInitialValues({});
    await service.init(forceReload: true);
    await service.recordReview(
        surahId: 1,
        ayahNumber: 1,
        surahName: 'الفاتحة',
        rating: MemorizationRating.easy);
    await expectLater(
        service.importData([42], merge: false), throwsFormatException);
    expect(service.hasItem(1, 1), isTrue);
  });

  for (final replace in [true, false]) {
    test('backup reports memorization save failure replace=$replace', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RejectMemorizationStore()..memorizationOnly = true;
      SharedPreferencesStorePlatform.instance = store;
      await service.init(forceReload: true);
      final item = MemorizationItem.createInitial(
              surahId: 1, ayahNumber: 1, surahName: 'Fatiha')
          .toJson();
      final envelope = <String, dynamic>{
        'data': <String, dynamic>{
          'memorization_items': [item]
        }
      };
      expect(
          await BackupRestoreService.instance
              .restoreBackup(envelope, replaceMode: replace),
          isFalse);
      expect(store.writes, 1);
      expect(service.hasItem(1, 1), isFalse);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('memorization_items_v1'), isNull);
    });
  }
  for (final action in ['تثبيت', 'نسيت']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'action sheet $action rejects failed review visibly at $scale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final loader = FontLoader('Cairo');
        loader.addFont(Future.value(ByteData.sublistView(
            File('assets/fonts/Cairo-Regular.ttf').readAsBytesSync())));
        await loader.load();
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = RejectMemorizationStore();
        await service.init(forceReload: true);
        await SettingsService.instance.init(forceReload: true);
        final surah = (await QuranRepository.loadSurahs()).first;
        final ayah = (await QuranRepository.getAyahsForSurah(1)).first;
        final key = GlobalKey();
        const iconsPath = String.fromEnvironment('MATERIAL_ICONS_FONT');
        if (iconsPath.isNotEmpty) {
          final icons = FontLoader('MaterialIcons');
          icons.addFont(Future.value(
              ByteData.sublistView(File(iconsPath).readAsBytesSync())));
          await icons.load();
        }
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
                theme: ThemeData(fontFamily: 'Cairo'),
                builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: Builder(
                        builder: (context) => TextButton(
                            onPressed: () => AyahActionSheet.show(context,
                                surah: surah, ayah: ayah),
                            child: const Text('open')))))));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final target = find.text(action);
        await tester.scrollUntilVisible(target, 200,
            scrollable: find.byType(Scrollable).last);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(service.hasItem(1, 1), isFalse);
        expect(find.textContaining('تم تحديد الآية:'), findsNothing);
        final error = find.text(service.storageError!);
        expect(error, findsOneWidget);
        final rect = tester.getRect(error);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.bottom, lessThanOrEqualTo(800));
        expect(tester.takeException(), isNull);
        const evidencePath = String.fromEnvironment('AUDIT_SCREENSHOT_DIR');
        if (action == 'تثبيت' && evidencePath.isNotEmpty)
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$evidencePath/sheet-failure-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
      });
    }
  }
  testWidgets('memorization screen failed review has no success claim',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = RejectMemorizationStore();
    await service.init(forceReload: true);
    await SettingsService.instance.init(forceReload: true);
    await QuranRepository.loadSurahs();
    await QuranRepository.getAyahsForSurah(1);
    await tester.pumpWidget(const MaterialApp(home: MemorizationScreen()));
    await tester.pumpAndSettle();
    final target = find.text('متقن').first;
    await tester.scrollUntilVisible(target, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(service.hasItem(1, 1), isFalse);
    expect(find.textContaining('تم تقييم آية'), findsNothing);
    expect(find.text(service.storageError!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
