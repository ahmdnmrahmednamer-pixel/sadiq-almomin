import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only storage faults.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:almomin/core/services/fajr_qiyam_alarm_service.dart';
class AlarmStore extends InMemorySharedPreferencesStore {
  AlarmStore() : super.withData({});
  bool reject = false, throwing = false, afterWrite = false;
  bool failReads=false,failReadAfter=false,acceptWithoutWrite=false,throwAfter=false;
  @override Future<Map<String,Object>> getAll() async {
    if(failReads)throw PlatformException(code:'read');return super.getAll();
  }
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if(failReadAfter)failReads=true;
    if(acceptWithoutWrite)return true;
    if(throwAfter){await super.setValue(type,key,value);throw PlatformException(code:'after');}
    if (gate != null) await gate!.future;
    if (throwing) throw PlatformException(code: 'storage');
    if(reject && afterWrite){await super.setValue(type,key,value);return false;}
    return reject ? false : await super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dynamic service = FajrQiyamAlarmService.instance;
  late AlarmStore store;
  final calls = <MethodCall>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AlarmStore();
    SharedPreferencesStorePlatform.instance = store;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
      calls.add(call);
      return null;
    });
    await service.init(forceReload: true);
    calls.clear();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            null);
  });
  final cases = <String, (Future<dynamic> Function(), String, Object)>{
    'pre enabled': (
      () => service.setPreFajrEnabled(false),
      'pre_fajr_enabled',
      false
    ),
    'pre minutes': (
      () => service.setPreFajrMinutesBefore(40),
      'pre_fajr_minutes',
      40
    ),
    'pre tone': (
      () => service.setPreFajrTone('takbeerat'),
      'pre_fajr_tone',
      'takbeerat'
    ),
    'qiyam enabled': (
      () => service.setQiyamEnabled(false),
      'qiyam_enabled',
      false
    ),
    'qiyam mode': (
      () => service.setQiyamMode('fixed_time'),
      'qiyam_mode',
      'fixed_time'
    ),
    'qiyam minutes': (
      () => service.setQiyamMinutesBeforeFajr(90),
      'qiyam_minutes_before',
      90
    ),
    'qiyam tone': (
      () => service.setQiyamTone('takbeerat'),
      'qiyam_tone',
      'takbeerat'
    ),
  };
  for(final entry in cases.entries) {
    for(final mode in ['after','unreadable','acceptedUnreadable','mismatch','throwAfter']) {
      test('${entry.key} checked saved reality $mode', () async {
        final before=service.exportData();
        store.reject=mode=='after'||mode=='unreadable';
        store.afterWrite=mode=='after';store.failReadAfter=mode=='unreadable'||mode=='acceptedUnreadable';
        store.acceptWithoutWrite=mode=='mismatch';store.throwAfter=mode=='throwAfter';
        expect(await entry.value.$1(),false);expect(calls,isEmpty);
        final expected=Map<String,dynamic>.from(before);
        if(mode=='after'||mode=='throwAfter')expected[entry.value.$2]=entry.value.$3;
        expect(service.exportData(),expected);expect(service.preferenceError,isNotNull);
        store.reject=false;store.afterWrite=false;store.failReads=false;store.failReadAfter=false;
        store.acceptWithoutWrite=false;store.throwAfter=false;
        expect(await entry.value.$1(),true);
        expect(service.exportData()[entry.value.$2],entry.value.$3);
      });
    }
  }  for(final mode in ['after','unreadable','acceptedUnreadable','mismatch','throwAfter']) {
    test('packed fixed time checked reality $mode preserves legacy pair', () async {
      final before=service.exportData();
      store.reject=mode=='after'||mode=='unreadable';store.afterWrite=mode=='after';
      store.failReadAfter=mode=='unreadable'||mode=='acceptedUnreadable';
      store.acceptWithoutWrite=mode=='mismatch';store.throwAfter=mode=='throwAfter';
      expect(await service.setQiyamFixedTime(4,44),false);expect(calls,isEmpty);
      final expected=Map<String,dynamic>.from(before);
      if(mode=='after'||mode=='throwAfter') {
        expected['qiyam_fixed_hour']=4;expected['qiyam_fixed_minute']=44;
      }
      expect(service.exportData(),expected);
      store.reject=false;store.afterWrite=false;store.failReads=false;store.failReadAfter=false;
      store.acceptWithoutWrite=false;store.throwAfter=false;
      expect(await service.setQiyamFixedTime(4,44),true);
      expect(service.qiyamFixedHour,4);expect(service.qiyamFixedMinute,44);
      final prefs=await SharedPreferences.getInstance();await prefs.reload();
      expect(prefs.getInt('wake_qiyam_fixed_minutes_v1'),284);
      expect(prefs.get('wake_qiyam_fixed_hour'),isNull);expect(prefs.get('wake_qiyam_fixed_minute'),isNull);
    });
  }

}
