import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/ramadan_service.dart';

class RamadanProbeStore extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  bool reject = false, throwWrite = false, failReads = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw StateError('synthetic read failure');
    return Map.of(values);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    final wait = gate;
    gate = null;
    if (wait != null) await wait.future;
    if (throwWrite) throw StateError('synthetic write failure');
    if (reject) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = RamadanService.instance;
  late RamadanProbeStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = RamadanProbeStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  for (final kind in ['fasted', 'taraweeh', 'quran']) {
    Future<dynamic> toggle(int day) => switch (kind) {
          'fasted' => service.toggleFasted(day),
          'taraweeh' => service.toggleTaraweeh(day),
          _ => service.toggleQuran(day),
        };
    bool checked(int day) => switch (kind) {
          'fasted' => service.isDayFasted(day),
          'taraweeh' => service.isTaraweehCompleted(day),
          _ => service.isQuranCompleted(day),
        };
    for (final throws in [false, true]) {
      test('$kind rejected write stays uncommitted, throwing=$throws',
          () async {
        store.reject = !throws;
        store.throwWrite = throws;
        final result = await toggle(1);
        expect(checked(1), isFalse);
        expect(result, isFalse);
        expect(store.values, isEmpty);
      });
    }
    test('$kind await and publication wait for confirmed storage', () async {
      final pending = Completer<void>();
      store.gate = pending;
      var completed = false;
      final work = toggle(1).then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(checked(1), isFalse);
      pending.complete();
      expect(await work, isTrue);
      expect(checked(1), isTrue);
    });
    test('$kind retry after failure does not save failed old toggle', () async {
      store.reject = true;
      await toggle(1);
      store.reject = false;
      expect(await toggle(2), isTrue);
      expect(checked(1), isFalse);
      expect(checked(2), isTrue);
    });
  }
  test('same tracker writes run in order without losing confirmed days',
      () async {
    final pending = Completer<void>();
    store.gate = pending;
    final first = service.toggleFasted(1);
    final second = service.toggleFasted(2);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    pending.complete();
    await Future.wait([first, second]);
    expect(service.fastedDays, {1, 2});
    expect(store.values['flutter.ramadan_fasted_days'], ['1', '2']);
  });
  test('forced reload waits for admitted write and reads confirmed tracker',
      () async {
    final pending = Completer<void>();
    store.gate = pending;
    final write = service.toggleQuran(3);
    final reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    pending.complete();
    await Future.wait([write, reload]);
    expect(service.quranDays, {3});
  });
  test(
      'failed initial reload refuses a toggle instead of replacing unread tracker',
      () async {
    await service.toggleFasted(5);
    store.failReads = true;
    await service.init(forceReload: true);
    expect(await service.toggleFasted(6), isFalse);
    expect(service.fastedDays, {5});
    expect(store.writes, 1);
    store.failReads = false;
    await service.init(forceReload: true);
    expect(await service.toggleFasted(6), isTrue);
    expect(service.fastedDays, {5, 6});
  });
}
