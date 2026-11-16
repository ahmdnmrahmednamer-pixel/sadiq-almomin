// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class InvalidMutationStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;

  InvalidMutationStorePlatform(this.delegate);

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
      // Simulate host ending up in invalid state upon failure
      await delegate.setValue(valueType, key, '{corrupt_invalid_json:');
      return false;
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write-failure + reload-sync for invalid host state returns false and no publish', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = InvalidMutationStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    expect(service.isCompleted('fajr_pre_2'), isFalse);

    final result = await service.toggleSunnah('fajr_pre_2');

    // F2 contract: invalid actual host => livePublished: false, no publish, writeUnconfirmed
    expect(result.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(result.livePublished, isFalse);

    // Live map untouched
    expect(service.isCompleted('fajr_pre_2'), isFalse);
  });
}
