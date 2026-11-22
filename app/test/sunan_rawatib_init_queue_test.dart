// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class DelayedRawatibStore extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  final bool succeeds;
  final entered = Completer<void>();
  final release = Completer<void>();
  DelayedRawatibStore(this.delegate, {required this.succeeds});
  @override
  bool get isMock => true;
  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<bool> clearWithParameters(ClearParameters p) =>
      delegate.clearWithParameters(p);
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters p) =>
      delegate.getAllWithParameters(p);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith('sunan_rawatib_logs_v1') && !entered.isCompleted) {
      entered.complete();
      await release.future;
      if (!succeeds) return false;
    }
    return delegate.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final restoring in [false, true]) {
    for (final succeeds in [false, true]) {
      test(
          'forced init waits for pending ${succeeds ? "successful" : "failed"} ${restoring ? 'restore' : 'toggle'} without publishing unconfirmed cache',
          () async {
        const key = 'sunan_rawatib_logs_v1';
        final date = DateTime(2026, 11, 22);
        SharedPreferences.setMockInitialValues({
          key: jsonEncode({
            '2026-11-21': ['witr_prayer']
          })
        });
        final original = SharedPreferencesStorePlatform.instance;
        final store = DelayedRawatibStore(original, succeeds: succeeds);
        SharedPreferencesStorePlatform.instance = store;
        final service = SunanRawatibService.instance;
        await service.init(forceReload: true);
        final observed = <bool>[];
        void listener() =>
            observed.add(service.isCompleted('fajr_pre_2', date: date));
        service.addListener(listener);
        Future<dynamic>? toggle;
        Future<void>? reload;
        try {
          toggle = restoring
              ? service.restoreSunanRawatibMerge(jsonEncode({
                  '2026-11-22': ['fajr_pre_2']
                }))
              : service.toggleSunnah('fajr_pre_2', date: date);
          await store.entered.future;
          bool reloaded = false;
          reload = service.init(forceReload: true).then((_) {
            reloaded = true;
          });
          await Future<void>.delayed(Duration.zero);
          expect(service.isCompleted('fajr_pre_2', date: date), isFalse,
              reason:
                  'Forced init must not publish an unconfirmed cached candidate');
          expect(reloaded, isFalse,
              reason: 'Forced init must wait for the in-flight transaction');
          expect(observed, isEmpty,
              reason: 'No unconfirmed candidate should reach listeners');
          store.release.complete();
          final result = await toggle;
          await reload;
          expect(
              result.status,
              restoring
                  ? (succeeds
                      ? SunanRawatibRestoreStatus.confirmedWrite
                      : SunanRawatibRestoreStatus.writeUnconfirmed)
                  : (succeeds
                      ? SunanRawatibOperationStatus.persisted
                      : SunanRawatibOperationStatus.writeUnconfirmed));
          expect(service.isCompleted('fajr_pre_2', date: date), succeeds);
          expect(
              service.isCompleted('witr_prayer', date: DateTime(2026, 11, 21)),
              isTrue);
          if (!succeeds) expect(observed, everyElement(isFalse));
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          expect(
              (jsonDecode(prefs.getString(key)!) as Map)
                  .containsKey('2026-11-22'),
              succeeds);
          final followup =
              await service.toggleSunnah('duha_prayer', date: date);
          expect(followup.status, SunanRawatibOperationStatus.persisted);
          await service.init();
          await service.init(forceReload: true);
          expect(service.isCompleted('duha_prayer', date: date), isTrue);
          expect(service.isCompleted('fajr_pre_2', date: date), succeeds);
        } finally {
          if (!store.release.isCompleted) store.release.complete();
          if (toggle != null) await toggle;
          if (reload != null) await reload;
          service.removeListener(listener);
          SharedPreferencesStorePlatform.instance = original;
        }
      });
    }
  }
}
