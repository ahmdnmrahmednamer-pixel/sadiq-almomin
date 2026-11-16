// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class NullOrEmptyStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  bool mutateToEmptyString = false;

  NullOrEmptyStorePlatform(this.delegate);

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) =>
      delegate.getAllWithParameters(parameters);

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('sunan_rawatib_logs_v1')) {
      if (mutateToEmptyString) {
        await delegate.setValue(valueType, key, '');
      } else {
        await delegate.remove(key);
      }
      return false;
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write-failure + reload-sync for null and empty string returns false and live untouched', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = NullOrEmptyStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    // Case A: Host key becomes null upon failure
    mockPlatform.mutateToEmptyString = false;
    final resNull = await service.toggleSunnah('fajr_pre_2');

    expect(resNull.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(resNull.livePublished, isFalse);
    expect(service.isCompleted('fajr_pre_2'), isFalse);

    // Case B: Host key becomes empty string '' upon failure
    mockPlatform.mutateToEmptyString = true;
    final resEmpty = await service.toggleSunnah('fajr_pre_2');

    expect(resEmpty.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(resEmpty.livePublished, isFalse);
    expect(service.isCompleted('fajr_pre_2'), isFalse);
  });
}
