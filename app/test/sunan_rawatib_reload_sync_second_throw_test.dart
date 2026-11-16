// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class SecondReloadThrowStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  int getAllCalls = 0;
  bool throwOnSecondGetAll = false;

  SecondReloadThrowStorePlatform(this.delegate);

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() {
    getAllCalls++;
    if (throwOnSecondGetAll && getAllCalls > 1) {
      throw Exception('Simulated second reload failure');
    }
    return delegate.getAll();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) {
    getAllCalls++;
    if (throwOnSecondGetAll && getAllCalls > 1) {
      throw Exception('Simulated second reload failure');
    }
    return delegate.getAllWithParameters(parameters);
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key.endsWith('sunan_rawatib_logs_v1')) {
      return Future.value(false);
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write-failure + reload-sync where second reload throws returns false and no publish', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = SecondReloadThrowStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    // Arm the mock to throw on second reload (the one inside _reloadAndSyncSunanRawatibFromHost)
    mockPlatform.getAllCalls = 0;
    mockPlatform.throwOnSecondGetAll = true;

    final result = await service.toggleSunnah('fajr_pre_2');

    // F2 contract: second reload throws => livePublished: false, no publish, writeUnconfirmed
    expect(result.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(result.livePublished, isFalse);

    // Live map untouched
    expect(service.isCompleted('fajr_pre_2'), isFalse);
  });
}
