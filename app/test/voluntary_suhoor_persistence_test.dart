import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/voluntary_fasting_service.dart';
import 'ramadan_tracker_persistence_test.dart' show RamadanProbeStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dynamic service = VoluntaryFastingService.instance;
  late RamadanProbeStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = RamadanProbeStore();
    SharedPreferencesStorePlatform.instance = store;
    await service.init(forceReload: true);
  });
  for (final throws in [false, true]) {
    test('rejected suhoor save preserves confirmed true, throws=$throws',
        () async {
      store.reject = !throws;
      store.throwWrite = throws;
      final dynamic result = await service.toggleSuhoorReminder(false);
      expect(service.suhoorReminderEnabled, isTrue);
      expect(result, isFalse);
      expect(store.values, isEmpty);
    });
  }
  test('suhoor publication waits for storage confirmation', () async {
    final gate = Completer<void>();
    store.gate = gate;
    final work = service.toggleSuhoorReminder(false);
    await Future<void>.delayed(Duration.zero);
    expect(service.suhoorReminderEnabled, isTrue);
    gate.complete();
    final dynamic result = await work;
    expect(result, isTrue);
    expect(service.suhoorReminderEnabled, isFalse);
    expect(store.values['flutter.voluntary_fast_suhoor_reminder'], isFalse);
  });
  test('queued opposite choices preserve admission order', () async {
    final gate = Completer<void>();
    store.gate = gate;
    final first = service.toggleSuhoorReminder(false);
    final second = service.toggleSuhoorReminder(true);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    gate.complete();
    await Future.wait<dynamic>(
        [first as Future<dynamic>, second as Future<dynamic>]);
    expect(service.suhoorReminderEnabled, isTrue);
    expect(store.values['flutter.voluntary_fast_suhoor_reminder'], isTrue);
  });
  test(
      'reload after rejected write reads stored preference rather than plugin cache',
      () async {
    store.reject = true;
    await service.toggleSuhoorReminder(false);
    await service.init(forceReload: true);
    expect(service.suhoorReminderEnabled, isTrue);
  });
  test('reload waits for an admitted save', () async {
    final gate = Completer<void>();
    store.gate = gate;
    final work = service.toggleSuhoorReminder(false);
    final reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait<dynamic>(
        [work as Future<dynamic>, reload as Future<dynamic>]);
    expect(service.suhoorReminderEnabled, isFalse);
    expect(store.values['flutter.voluntary_fast_suhoor_reminder'], isFalse);
  });
  test('reload must not overwrite an admitted fasting log write', () async {
    final gate = Completer<void>();
    store.gate = gate;
    final Future<void> write =
        service.logFastedDay('white_days', date: DateTime(2026, 11, 20));
    await Future<void>.delayed(Duration.zero);
    final Future<void> reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([write, reload]);
    expect(service.getCountForType('white_days'), 1);
    expect(service.fastedDateLogs, ['2026-11-20|white_days']);
    expect(
        jsonDecode(store.values['flutter.voluntary_fast_progress_v1']
            as String)['date_logs'],
        ['2026-11-20|white_days']);
  });
  test('reload waits for an admitted undo', () async {
    await service.logFastedDay('white_days', date: DateTime(2026, 11, 20));
    final gate = Completer<void>();
    store.gate = gate;
    final Future<void> undo = service.decrementFastCount('white_days');
    await Future<void>.delayed(Duration.zero);
    final Future<void> reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([undo, reload]);
    expect(service.getCountForType('white_days'), 0);
    expect(service.fastedDateLogs, isEmpty);
    expect(
        jsonDecode(store.values['flutter.voluntary_fast_progress_v1']
            as String)['date_logs'],
        isEmpty);
  });
  test('queued mixed types dates and undo preserve admitted order', () async {
    final gate = Completer<void>();
    store.gate = gate;
    final Future<void> first =
        service.logFastedDay('white_days', date: DateTime(2026, 11, 19));
    final Future<void> second =
        service.logFastedDay('white_days', date: DateTime(2026, 11, 20));
    final Future<void> undo = service.decrementFastCount('white_days');
    final Future<void> other =
        service.logFastedDay('monday_thursday', date: DateTime(2026, 11, 20));
    final Future<void> reload = service.init(forceReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    gate.complete();
    await Future.wait([first, second, undo, other, reload]);
    expect(service.getCountForType('white_days'), 1);
    expect(service.getCountForType('monday_thursday'), 1);
    expect(service.fastedDateLogs,
        ['2026-11-20|monday_thursday', '2026-11-19|white_days']);
  });
  test('throwing count operation does not poison later preference work',
      () async {
    store.throwWrite = true;
    final Future<bool> failed =
        service.logFastedDay('white_days', date: DateTime(2026, 11, 20));
    expect(await failed, isFalse);
    store.throwWrite = false;
    // A failed count write returns false without poisoning later work.
    final dynamic saved = await service.toggleSuhoorReminder(false);
    expect(saved, isTrue);
    expect(store.values['flutter.voluntary_fast_suhoor_reminder'], isFalse);
  });
  test('failed choice retry writes requested value and preserves fasting data',
      () async {
    await service.logFastedDay('white_days', date: DateTime(2026, 11, 20));
    store.reject = true;
    final dynamic failed = await service.toggleSuhoorReminder(false);
    expect(failed, isFalse);
    store.reject = false;
    final dynamic retry = await service.toggleSuhoorReminder(false);
    expect(retry, isTrue);
    await service.init(forceReload: true);
    expect(service.suhoorReminderEnabled, isFalse);
    expect(service.getCountForType('white_days'), 1);
    expect(service.fastedDateLogs, ['2026-11-20|white_days']);
  });
}
