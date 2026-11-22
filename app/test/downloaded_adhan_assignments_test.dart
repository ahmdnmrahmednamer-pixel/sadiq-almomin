import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing shared_preferences test interface, used only for fault injection.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/downloaded_adhan_assignments.dart';
import 'adhan_choice_write_confirmation_test.dart' as choice;

const a = 'kiwifu_adhan_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const b = 'kiwifu_adhan_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var pending = <Map<String, dynamic>>[];
  var active = <Map<String, dynamic>>[];
  var failNative = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pending = [];
    active = [];
    failNative = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      if (failNative) throw PlatformException(code: 'unavailable');
      if (call.method == 'pendingNotificationRequests') return pending;
      if (call.method == 'getActiveNotifications') return active;
      return null;
    });
  });
  test('only exact pinned IDs enter download protection', () {
    expect(DownloadedAdhanAssignments.isPinnedId(a), isTrue);
    for (final invalid in [
      'adhan_makkah',
      '$a/../x',
      '${a}a',
      a.toUpperCase(),
      'kiwifu_adhan_abc'
    ]) {
      expect(DownloadedAdhanAssignments.isPinnedId(invalid), isFalse);
    }
  });
  test('pending lease is synchronous, deduplicated and refcounted', () async {
    final release = Completer<void>();
    final first =
        DownloadedAdhanAssignments.protect([a, a], () => release.future);
    expect(DownloadedAdhanAssignments.isPending(a), isTrue);
    await DownloadedAdhanAssignments.protect([a], () async {
      expect(DownloadedAdhanAssignments.isPending(a), isTrue);
    });
    expect(DownloadedAdhanAssignments.isPending(a), isTrue);
    expect(await DownloadedAdhanAssignments.protectedIds(), contains(a));
    release.complete();
    await first;
    expect(DownloadedAdhanAssignments.isPending(a), isFalse);
  });
  test('throwing action always releases pending lease', () async {
    await expectLater(
        DownloadedAdhanAssignments.protect([a], () async {
          throw StateError('fixture failure');
        }),
        throwsStateError);
    expect(DownloadedAdhanAssignments.isPending(a), isFalse);
  });
  test(
      'retained possibilities union, and confirmed plan replaces only schedule protection',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_selected_adhan', a);
    await DownloadedAdhanAssignments.retain([a]);
    await DownloadedAdhanAssignments.retain([b, 'adhan_makkah']);
    await prefs.reload();
    expect(
        prefs.getStringList(DownloadedAdhanAssignments.protectionKey), [a, b]);
    await DownloadedAdhanAssignments.confirmedPlan([b]);
    pending = [
      {'id': 100}
    ];
    expect(await DownloadedAdhanAssignments.protectedIds(), {a, b});
  });
  for (final nativeState in ['pending', 'active', 'failure']) {
    test('$nativeState retains old file after saved voice has changed',
        () async {
      await DownloadedAdhanAssignments.retain([a]);
      pending = nativeState == 'pending'
          ? [
              {'id': 399}
            ]
          : [];
      active = nativeState == 'active'
          ? [
              {'id': 100}
            ]
          : [];
      failNative = nativeState == 'failure';
      expect(await DownloadedAdhanAssignments.protectedIds(), {a});
    });
  }
  test('verified empty native prayer range retires stale possibilities only',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_prayer_voice_الفجر', b);
    await DownloadedAdhanAssignments.retain([a]);
    pending = [
      {'id': 995},
      {'id': 999},
      {'id': 99},
      {'id': 400}
    ];
    expect(await DownloadedAdhanAssignments.protectedIds(), {b});
    await prefs.reload();
    expect(
        prefs.getStringList(DownloadedAdhanAssignments.protectionKey), isEmpty);
  });
  for (final corrupt in [
    42,
    <String>['bad identity']
  ]) {
    test('unverifiable saved registry rejects cleanup: $corrupt', () async {
      SharedPreferences.setMockInitialValues(
          {DownloadedAdhanAssignments.protectionKey: corrupt});
      await expectLater(
          DownloadedAdhanAssignments.protectedIds(), throwsA(anything));
    });
  }
  test('invalid saved voice type cannot authorize cleanup', () async {
    SharedPreferences.setMockInitialValues({'notif_selected_adhan': 42});
    await expectLater(
        DownloadedAdhanAssignments.protectedIds(), throwsStateError);
  });
  for (final lie in [false, true]) {
    test(
        'failed protection persistence/readback rejects and queue permits retry: $lie',
        () async {
      final store = choice.RefusingAdhanStore();
      SharedPreferencesStorePlatform.instance = store;
      await (await SharedPreferences.getInstance()).reload();
      store.rejectAt = lie ? null : 1;
      store.lie = lie;
      await expectLater(
          DownloadedAdhanAssignments.retain([a]), throwsStateError);
      store.rejectAt = null;
      store.lie = false;
      await DownloadedAdhanAssignments.retain([a]);
      pending = [
        {'id': 100}
      ];
      expect(await DownloadedAdhanAssignments.protectedIds(), {a});
    });
  }
}
