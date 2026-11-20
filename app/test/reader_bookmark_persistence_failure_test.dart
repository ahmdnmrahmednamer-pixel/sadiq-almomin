import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/reader_bookmark_service.dart';

class BookmarkStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  bool reject = false,
      throwWrite = false,
      failReads = false,
      failReadsAfterWrite = false;
  Completer<void>? gate;
  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw PlatformException(code: 'read-failure');
    return Map.of(values);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final wait = gate;
    gate = null;
    if (wait != null) await wait.future;
    if (failReadsAfterWrite) failReads = true;
    if (throwWrite) throw PlatformException(code: 'synthetic-failure');
    if (reject) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BookmarkStore store;
  final service = ReaderBookmarkService();
  Future<ReaderBookmark> add(String label) => service.add(
      documentId: 'book',
      locationKind: 'online-page',
      page: 12,
      scrollOffset: 0,
      label: label);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = BookmarkStore();
    SharedPreferencesStorePlatform.instance = store;
  });
  for (final throwing in [false, true]) {
    test('rejected add not visible or later persisted, throwing=$throwing',
        () async {
      store.reject = true;
      store.throwWrite = throwing;
      await expectLater(add('rejected'), throwsA(anything));
      final visible = await service.list('book', 'online-page');
      store.reject = false;
      store.throwWrite = false;
      await add('accepted');
      final disk =
          jsonDecode(store.values['flutter.reader_bookmarks_v1'] as String)
              as List;
      expect(disk.map((x) => x['label']), ['accepted'],
          reason: 'later success must not persist rejected edit');
      expect(visible, isEmpty, reason: 'failed write must not appear as saved');
    });
    test(
        'rejected removal preserves visible and stored mark, throwing=$throwing',
        () async {
      final mark = await add('keep');
      store.reject = true;
      store.throwWrite = throwing;
      await expectLater(service.remove(mark), throwsA(anything));
      final visible = await service.list('book', 'online-page');
      store.reject = false;
      store.throwWrite = false;
      await add('next');
      final disk =
          jsonDecode(store.values['flutter.reader_bookmarks_v1'] as String)
              as List;
      expect(disk.map((x) => x['label']), ['keep', 'next']);
      expect(visible.map((x) => x.label), ['keep']);
    });
  }

  test(
      'list excludes a pending write and subsequent mutation keeps both accepted marks',
      () async {
    final gate = Completer<void>();
    store.gate = gate;
    final pending = add('first');
    await Future<void>.delayed(Duration.zero);
    expect(await service.list('book', 'online-page'), isEmpty);
    final next = add('second');
    gate.complete();
    await pending;
    await next;
    expect((await service.list('book', 'online-page')).map((x) => x.label),
        ['first', 'second']);
  });
  test(
      'failed rollback reload never permits speculative cache on later read or write',
      () async {
    store.reject = true;
    store.failReadsAfterWrite = true;
    await expectLater(add('rejected'), throwsA(isA<StateError>()));
    store.reject = false;
    store.failReadsAfterWrite = false;
    await expectLater(
        service.list('book', 'online-page'), throwsA(isA<PlatformException>()));
    await expectLater(add('blocked'), throwsA(isA<PlatformException>()));
    store.failReads = false;
    await add('accepted');
    final disk =
        jsonDecode(store.values['flutter.reader_bookmarks_v1'] as String)
            as List;
    expect(disk.map((x) => x['label']), ['accepted']);
  });
}
