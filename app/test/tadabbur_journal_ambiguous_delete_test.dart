// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:almomin/core/services/tadabbur_journal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

class _CountingStore extends SharedPreferencesStorePlatform {
  _CountingStore(this.delegate);
  final SharedPreferencesStorePlatform delegate;
  int writes = 0;

  @override
  bool get isMock => true;
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<Map<String, Object>> getAllWithParameters(
          GetAllParameters parameters) =>
      delegate.getAllWithParameters(parameters);
  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writes++;
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'tadabbur_journal_entries_v1';
  final service = TadabburJournalService.instance;
  late _CountingStore store;

  Map<String, dynamic> entry(String id, String content) => {
        'id': id,
        'surahId': 1,
        'surahName': 'fixture',
        'ayahNumber': 1,
        'ayahSnippet': 'fixture',
        'faithMessage': content,
        'practicalAction': 'fixture',
        'derivedDua': 'fixture',
        'createdAt': '2026-11-20T00:00:00.000Z',
        'futureMetadata': {'keep': content},
      };

  Future<String> load(int duplicates) async {
    final raw = json.encode([
      for (var i = 0; i < duplicates; i++) entry('legacy', 'note-$i'),
      entry('unique', 'separate-note'),
    ]);
    SharedPreferences.setMockInitialValues({key: raw});
    store = _CountingStore(SharedPreferencesStorePlatform.instance);
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
    expect(service.isReadable, isTrue);
    expect(store.writes, 0);
    return raw;
  }

  List<Map<String, dynamic>> snapshot() =>
      service.entries.map((entry) => entry.toJson()).toList();

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final count in [2, 3]) {
    test('refuses ambiguous deletion of $count legacy notes without any write',
        () async {
      final originalRaw = await load(count);
      final before = snapshot();
      var notifications = 0;
      void listener() => notifications++;
      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));

      final result = await service.deleteReflection('legacy');

      expect(snapshot(), before,
          reason: 'An ambiguous ID must not remove multiple distinct notes.');
      expect(result.status.name, 'refusedAmbiguousId');
      expect(result.livePublished, isFalse);
      expect(service.isReadable, isTrue);
      expect(notifications, 0);
      expect(store.writes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), originalRaw);
      expect((await store.getAll())['flutter.$key'], originalRaw);
      await service.init(forceReload: true);
      expect(snapshot(), before);
    });
  }

  test('a unique ID still deletes only that note beside a duplicate group',
      () async {
    await load(2);
    final before =
        snapshot().where((entry) => entry['id'] == 'legacy').toList();
    final result = await service.deleteReflection('unique');
    expect(result.status, JournalOperationStatus.persisted);
    expect(result.livePublished, isTrue);
    expect(store.writes, 1);
    expect(snapshot(), before);
    await service.init(forceReload: true);
    expect(snapshot(), before);
  });

  test('a missing ID retains the existing confirmed-write behavior', () async {
    await load(2);
    final before = snapshot();
    final result = await service.deleteReflection('missing');
    expect(result.status, JournalOperationStatus.persisted);
    expect(result.livePublished, isTrue);
    expect(store.writes, 1);
    expect(snapshot(), before);
  });

  test('an ambiguous refusal does not poison the queued unique deletion',
      () async {
    await load(2);
    final before =
        snapshot().where((entry) => entry['id'] == 'legacy').toList();
    final ambiguous = service.deleteReflection('legacy');
    final unique = service.deleteReflection('unique');
    final results = await Future.wait([ambiguous, unique]);
    expect(
        results.map((r) => r.status.name), ['refusedAmbiguousId', 'persisted']);
    expect(results.map((r) => r.livePublished), [false, true]);
    expect(service.isReadable, isTrue);
    expect(store.writes, 1);
    expect(snapshot(), before);
    await service.init(forceReload: true);
    expect(snapshot(), before);
  });

  test('unreadable-store refusal takes priority over a stale duplicate group',
      () async {
    await load(2);
    final before = snapshot();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, '{malformed');
    await service.init(forceReload: true);
    expect(service.isReadable, isFalse);
    store.writes = 0;
    final result = await service.deleteReflection('legacy');
    expect(result.status, JournalOperationStatus.refusedUnreadable);
    expect(result.livePublished, isFalse);
    expect(store.writes, 0);
    expect(snapshot(), before);
    expect(prefs.getString(key), '{malformed');
  });
}
