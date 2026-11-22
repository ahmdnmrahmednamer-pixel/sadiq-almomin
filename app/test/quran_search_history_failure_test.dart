import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/quran_search_service.dart';

class RejectingHistoryStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  final writes = <String>[];
  final gates = <Completer<void>>[];
  bool reject = false,
      throwing = false,
      failReads = false,
      throwAfterWrite = false,
      falseAfterWrite = false,
      failReadsAfterWrite = false;
  Completer<void>? gate, entered;
  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw StateError('synthetic history read failure');
    return Map.of(values);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add(key);
    final wait = gate;
    gate = null;
    if (wait != null) {
      gates.add(wait);
      entered?.complete();
      await wait.future;
    }
    if (throwing) throw StateError('synthetic history write failure');
    if (reject) return false;
    values[key] = value is List<String> ? List<String>.of(value) : value;
    if (failReadsAfterWrite) failReads = true;
    if (throwAfterWrite)
      throw StateError('synthetic history lost acknowledgement');
    return !falseAfterWrite;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = QuranSearchService.instance;
  const key = 'flutter.quran_search_history_v1';
  late RejectingHistoryStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = RejectingHistoryStore();
    store.values[key] = <String>['saved query'];
    SharedPreferencesStorePlatform.instance = store;
  });
  tearDown(() {
    for (final gate in store.gates) {
      if (!gate.isCompleted) gate.complete();
    }
  });
  Future<bool> act(String action) => switch (action) {
        'add' => service.addToHistory('new query'),
        'remove' => service.removeFromHistory('saved query'),
        _ => service.clearHistory(),
      };
  List<String> after(String action) =>
      action == 'add' ? ['new query', 'saved query'] : [];
  for (final throwing in [false, true]) {
    for (final action in ['add', 'remove', 'clear']) {
      test(
          'rejected $action preserves saved history and retries throw=$throwing',
          () async {
        store.throwing = throwing;
        store.reject = !throwing;
        expect(await act(action), isFalse);
        expect(await service.getSearchHistory(), ['saved query']);
        expect(store.values[key], ['saved query']);
        await (await SharedPreferences.getInstance()).reload();
        expect(await service.getSearchHistory(), ['saved query']);
        store.reject = store.throwing = false;
        expect(await act(action), isTrue);
        expect(await service.getSearchHistory(), after(action));
        expect(store.values[key], after(action));
        expect(store.writes.every((written) => written == key), isTrue);
      });
    }
    test(
        'unconfirmed first-use clear does not erase starter defaults throw=$throwing',
        () async {
      store.values.clear();
      store.throwing = throwing;
      store.reject = !throwing;
      expect(await service.clearHistory(), isFalse);
      expect(store.values.containsKey(key), isFalse);
      expect(await service.getSearchHistory(), hasLength(5));
      store.reject = store.throwing = false;
      expect(await service.clearHistory(), isTrue);
      expect(store.values[key], isEmpty);
      expect(await service.getSearchHistory(), isEmpty);
    });
  }
  for (final throwing in [false, true]) {
    for (final action in ['add', 'remove', 'clear']) {
      test(
          'committed $action is confirmed after lost acknowledgement throw=$throwing',
          () async {
        store.throwAfterWrite = throwing;
        store.falseAfterWrite = !throwing;
        expect(await act(action), isTrue);
        expect(await service.getSearchHistory(), after(action));
        expect(store.values[key], after(action));
        store.throwAfterWrite = store.falseAfterWrite = false;
        expect(await act(action), isTrue);
        expect(await service.getSearchHistory(), after(action));
      });
    }
  }
  for (final action in ['add', 'remove', 'clear']) {
    test('uncheckable $action reports false and a later provider read recovers',
        () async {
      store.throwAfterWrite = store.failReadsAfterWrite = true;
      expect(await act(action), isFalse);
      expect(store.values[key], after(action));
      await expectLater(service.getSearchHistory(), throwsStateError);
      store.throwAfterWrite =
          store.failReadsAfterWrite = store.failReads = false;
      expect(await service.getSearchHistory(), after(action));
      expect(await act(action), isTrue);
      expect(await service.getSearchHistory(), after(action));
    });
  }
  test('gated concurrent add remove clear and read retain admission order',
      () async {
    final gate = Completer<void>();
    store.gate = gate;
    store.entered = Completer<void>();
    final first = service.addToHistory('first query');
    await store.entered!.future;
    final second = service.addToHistory('second query');
    final duplicate = service.addToHistory('first query');
    final remove = service.removeFromHistory('second query');
    final clear = service.clearHistory();
    final last = service.addToHistory('last query');
    final read = service.getSearchHistory();
    var readFinished = false;
    read.then((_) => readFinished = true);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, [key]);
    expect(readFinished, isFalse);
    expect(store.values[key], ['saved query']);
    gate.complete();
    expect(await Future.wait([first, second, duplicate, remove, clear, last]),
        everyElement(isTrue));
    expect(await read, ['last query']);
    expect(store.values[key], ['last query']);
    expect(store.writes, hasLength(6));
  });
  test(
      'read-dependent mutations fail closed but absolute clear needs no old list',
      () async {
    await service.getSearchHistory();
    store.failReads = true;
    expect(await service.addToHistory('new query'), isFalse);
    expect(await service.removeFromHistory('saved query'), isFalse);
    expect(store.writes, isEmpty);
    expect(store.values[key], ['saved query']);
    expect(await service.clearHistory(), isTrue);
    expect(store.values[key], isEmpty);
    await expectLater(service.getSearchHistory(), throwsStateError);
    store.failReads = false;
    expect(await service.addToHistory('new query'), isTrue);
    expect(await service.getSearchHistory(), ['new query']);
  });
  test(
      'malformed stored history is preserved unless explicit clear is requested',
      () async {
    store.values[key] = 41;
    await expectLater(service.getSearchHistory(), throwsA(isA<TypeError>()));
    expect(await service.addToHistory('new query'), isFalse);
    expect(await service.removeFromHistory('saved query'), isFalse);
    expect(store.values[key], 41);
    expect(store.writes, isEmpty);
    expect(await service.clearHistory(), isTrue);
    expect(await service.getSearchHistory(), isEmpty);
  });
  test('reads copy confirmed provider state and invalid queries do not write',
      () async {
    final first = await service.getSearchHistory();
    first.add('local only');
    expect(await service.getSearchHistory(), ['saved query']);
    store.values[key] = <String>['external query'];
    expect(await service.getSearchHistory(), ['external query']);
    expect(await service.addToHistory(' '), isTrue);
    expect(await service.addToHistory('x'), isTrue);
    expect(store.writes, isEmpty);
  });
}
