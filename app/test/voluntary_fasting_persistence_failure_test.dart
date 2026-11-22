import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/voluntary_fasting_service.dart';

class RejectingFastStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  final writes = <String>[];
  String? rejectKey, throwKey;
  final gates = <Completer<void>>[];
  bool reject = false,
      throwWrite = false,
      failReads = false,
      throwAfterWrite = false,
      failReadsAfterWrite = false;
  Completer<void>? gate;
  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw StateError('synthetic read failure');
    return Map.of(values);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add(key);
    final wait = gate;
    gate = null;
    if (wait != null) {
      gates.add(wait);
      await wait.future;
    }
    if (throwWrite || key == throwKey)
      throw StateError('synthetic write failure');
    if (reject || key == rejectKey) return false;
    values[key] = value;
    if (failReadsAfterWrite) failReads = true;
    if (throwAfterWrite) throw StateError('synthetic lost acknowledgement');
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
  final service = VoluntaryFastingService.instance;
  const key = 'flutter.voluntary_fast_progress_v1';
  const type = 'monday_thursday';
  final date = DateTime(2026, 11, 20);
  late RejectingFastStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = RejectingFastStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  tearDown(() {
    for (final gate in store.gates) {
      if (!gate.isCompleted) gate.complete();
    }
  });
  for (final throwing in [false, true]) {
    test(
        'rejected confirmation is not published and retry is durable throw=$throwing',
        () async {
      store.reject = !throwing;
      store.throwWrite = throwing;
      expect(await service.logFastedDay(type, date: date), isFalse);
      expect(service.getCountForType(type), 0);
      expect(service.fastedDateLogs, isEmpty);
      expect(store.values, isEmpty);
      await service.init(forceReload: true);
      expect(service.getCountForType(type), 0);
      store.reject = store.throwWrite = false;
      expect(await service.logFastedDay(type, date: date), isTrue);
      expect(store.writes.every((k) => k == key), isTrue);
      await service.init(forceReload: true);
      expect(service.getCountForType(type), 1);
      expect(service.fastedDateLogs, ['2026-11-20|$type']);
    });
    test('rejected undo preserves durable count and dated log throw=$throwing',
        () async {
      expect(await service.logFastedDay(type, date: date), isTrue);
      final before = store.values[key];
      store.reject = !throwing;
      store.throwWrite = throwing;
      expect(await service.decrementFastCount(type), isFalse);
      expect(service.getCountForType(type), 1);
      expect(service.fastedDateLogs, ['2026-11-20|$type']);
      expect(store.values[key], before);
      await service.init(forceReload: true);
      expect(service.getCountForType(type), 1);
      store.reject = store.throwWrite = false;
      expect(await service.decrementFastCount(type), isTrue);
      await service.init(forceReload: true);
      expect(service.getCountForType(type), 0);
      expect(service.fastedDateLogs, isEmpty);
    });
  }
  test('legacy independent counts migrate only with a confirmed atomic write',
      () async {
    store.values.addAll({
      'flutter.vfast_count_$type': 9,
      'flutter.vfast_date_logs': ['2026-11-20|$type'],
    });
    await service.init(forceReload: true);
    expect(service.getCountForType(type), 9);
    expect(store.values.containsKey(key), isFalse);
    expect((await service.exportProgress())['counts'][type], 9);
    store.reject = true;
    expect(await service.logFastedDay(type, date: DateTime(2026, 11, 21)),
        isFalse);
    expect(service.getCountForType(type), 9);
    expect(store.values.containsKey(key), isFalse);
    store.reject = false;
    expect(
        await service.logFastedDay(type, date: DateTime(2026, 11, 21)), isTrue);
    expect(store.values['flutter.vfast_count_$type'], 9);
    expect(store.values['flutter.vfast_date_logs'], ['2026-11-20|$type']);
    expect(jsonDecode(store.values[key] as String)['counts'][type], 10);
    await service.init(forceReload: true);
    expect(service.getCountForType(type), 10);
    expect(service.fastedDateLogs, hasLength(2));
  });
  for (final raw in [
    '{bad',
    '{"version":2,"counts":{},"date_logs":[]}',
    '{"version":1,"counts":{"white_days":"bad"},"date_logs":[]}'
  ]) {
    test(
        'unreadable authoritative snapshot blocks overwrite and supports explicit repair $raw',
        () async {
      store.values[key] = raw;
      store.values['flutter.vfast_count_$type'] = 9;
      store.values['flutter.voluntary_fast_suhoor_reminder'] = false;
      await service.init(forceReload: true);
      expect(service.progressLoadFailed, isTrue);
      expect(service.suhoorReminderEnabled, isFalse);
      expect(await service.logFastedDay(type, date: date), isFalse);
      expect(await service.decrementFastCount(type), isFalse);
      expect(
          await service.restoreProgress({
            'counts': {type: 1}
          }, replaceMode: true),
          isFalse);
      await expectLater(service.exportProgress(), throwsFormatException);
      expect(store.values[key], raw);
      expect(store.writes, isEmpty);
      store.values[key] = jsonEncode({
        'version': 1,
        'counts': {type: 9},
        'date_logs': ['2026-11-20|$type']
      });
      await service.init(forceReload: true);
      expect(service.progressLoadFailed, isFalse);
      expect(service.getCountForType(type), 9);
      expect(service.fastedDateLogs, hasLength(1));
    });
  }
  test(
      'publication waits and serialized duplicate log undo and reload retain order',
      () async {
    final gate = Completer<void>();
    store.gate = gate;
    final first = service.logFastedDay(type, date: date);
    final second = service.logFastedDay(type, date: DateTime(2026, 11, 21));
    final duplicate = service.logFastedDay(type, date: date);
    final undo = service.decrementFastCount(type);
    final reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(service.getCountForType(type), 0);
    expect(store.writes, [key]);
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await duplicate, isTrue);
    expect(await undo, isTrue);
    await reload;
    expect(store.writes, [key, key, key]);
    expect(service.getCountForType(type), 1);
    expect(service.fastedDateLogs, ['2026-11-20|$type']);
  });
  test('lost acknowledgement is confirmed by provider readback before retry',
      () async {
    store.throwAfterWrite = true;
    expect(await service.logFastedDay(type, date: date), isTrue);
    expect(service.getCountForType(type), 1);
    store.throwAfterWrite = false;
    await service.init(forceReload: true);
    expect(await service.logFastedDay(type, date: date), isTrue);
    expect(service.getCountForType(type), 1);
    expect(store.writes, [key]);
    expect(
        await service.logFastedDay(type, date: DateTime(2026, 11, 21)), isTrue);
    store.throwAfterWrite = true;
    expect(await service.decrementFastCount(type), isTrue);
    expect(service.getCountForType(type), 1);
  });
  test('unverified committed undo blocks another write until explicit reload',
      () async {
    expect(await service.logFastedDay(type, date: date), isTrue);
    expect(
        await service.logFastedDay(type, date: DateTime(2026, 11, 21)), isTrue);
    store.throwAfterWrite = true;
    store.failReadsAfterWrite = true;
    expect(await service.decrementFastCount(type), isFalse);
    expect(service.getCountForType(type), 2);
    expect(service.progressLoadFailed, isTrue);
    final writes = store.writes.length;
    store.throwAfterWrite = store.failReadsAfterWrite = store.failReads = false;
    expect(await service.decrementFastCount(type), isFalse);
    expect(store.writes, hasLength(writes));
    await service.init(forceReload: true);
    expect(service.progressLoadFailed, isFalse);
    expect(service.getCountForType(type), 1);
    expect(service.fastedDateLogs, ['2026-11-20|$type']);
  });
  test('failed read cannot overwrite saved snapshot and later reload recovers',
      () async {
    expect(await service.logFastedDay(type, date: date), isTrue);
    final before = store.values[key];
    store.failReads = true;
    expect(await service.decrementFastCount(type), isFalse);
    await service.init(forceReload: true);
    expect(service.progressLoadFailed, isTrue);
    expect(store.values[key], before);
    store.failReads = false;
    await service.init(forceReload: true);
    expect(service.progressLoadFailed, isFalse);
    expect(service.getCountForType(type), 1);
  });
  test(
      'confirmed no-op refreshes visible state from the provider without writes',
      () async {
    store.values[key] = jsonEncode({
      'version': 1,
      'counts': {type: 1},
      'date_logs': ['2026-11-20|$type']
    });
    expect(service.getCountForType(type), 0);
    expect(await service.logFastedDay(type, date: date), isTrue);
    expect(service.getCountForType(type), 1);
    expect(service.fastedDateLogs, ['2026-11-20|$type']);
    expect(store.writes, isEmpty);
    store.values[key] = jsonEncode({
      'version': 1,
      'counts': {type: 0},
      'date_logs': <String>[]
    });
    expect(await service.decrementFastCount(type), isTrue);
    expect(service.getCountForType(type), 0);
    expect(service.fastedDateLogs, isEmpty);
    expect(store.writes, isEmpty);
  });
  test('unknown imported counts are retained but do not inflate known totals',
      () async {
    expect(
        await service.restoreProgress({
          'counts': {type: 9, 'future_fast': 400},
          'date_logs': ['2026-11-20|future_fast']
        }, replaceMode: true),
        isTrue);
    expect(service.getCountForType(type), 9);
    expect(service.totalFastedDays, 9);
    expect(service.completedCounts.keys,
        VoluntaryFastingService.fastTypes.map((type) => type.id));
    await service.init(forceReload: true);
    expect(service.totalFastedDays, 9);
    final exported = await service.exportProgress();
    expect(exported['counts']['future_fast'], 400);
    expect(exported['date_logs'], ['2026-11-20|future_fast']);
  });
  test(
      'backup progress keeps legacy merge replace and partial-section semantics',
      () async {
    store.values.addAll({
      'flutter.vfast_count_$type': 9,
      'flutter.vfast_date_logs': ['2026-11-20|$type']
    });
    await service.init(forceReload: true);
    expect(
        await service.restoreProgress({
          'counts': {type: 3, 'white_days': 2},
          'date_logs': ['2026-11-21|white_days']
        }, replaceMode: false),
        isTrue);
    var exported = await service.exportProgress();
    expect(exported['counts'][type], 9);
    expect(exported['counts']['white_days'], 2);
    expect(
        exported['date_logs'], ['2026-11-20|$type', '2026-11-21|white_days']);
    exported['counts']['white_days'] = 99;
    expect((await service.exportProgress())['counts']['white_days'], 2);
    final before = store.values[key];
    store.reject = true;
    expect(
        await service.restoreProgress({
          'counts': {'white_days': 1},
          'date_logs': []
        }, replaceMode: true),
        isFalse);
    expect(store.values[key], before);
    store.reject = false;
    expect(
        await service.restoreProgress({
          'counts': {'white_days': 1},
          'date_logs': []
        }, replaceMode: true),
        isTrue);
    exported = await service.exportProgress();
    expect(exported['counts'][type], 9);
    expect(exported['counts']['white_days'], 1);
    expect(exported['date_logs'], isEmpty);
  });
}
