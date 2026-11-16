// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class HostMutatingFailureStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;

  HostMutatingFailureStorePlatform(this.delegate);

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
      // Actually mutate host storage first, but return false!
      await delegate.setValue(valueType, key, value);
      return false;
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host-changed-then-false => reload-sync actual host, assert actual host state not assumed unchanged', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = HostMutatingFailureStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    expect(service.isCompleted('fajr_pre_2'), isFalse);

    // Toggle attempt where platform wrote host data then returned false
    final result = await service.toggleSunnah('fajr_pre_2');

    expect(result.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(result.livePublished, isTrue);

    // Live map was updated to reflect actual host reality (no invented rollback)
    expect(service.isCompleted('fajr_pre_2'), isTrue);

    // Host actually holds the new candidate data with both prior date and today's item
    final prefs = await SharedPreferences.getInstance();
    final currentHost = prefs.getString('sunan_rawatib_logs_v1')!;
    expect(currentHost, contains('fajr_pre_2'));
    expect(currentHost, contains('prior_task'));
  });
}
