// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class ThrowingStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  bool mutateBeforeThrow = false;

  ThrowingStorePlatform(this.delegate);

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
      if (mutateBeforeThrow) {
        await delegate.setValue(valueType, key, value);
      }
      throw Exception('Simulated platform I/O failure on setValue');
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('throw discipline matches false (both host-unchanged and host-changed branches)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = ThrowingStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    // Branch 1: Throw on empty host (null host) => live untouched, livePublished: false, writeUnconfirmed
    mockPlatform.mutateBeforeThrow = false;
    final res1 = await service.toggleSunnah('fajr_pre_2');

    expect(res1.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(res1.livePublished, isFalse);
    expect(service.isCompleted('fajr_pre_2'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sunan_rawatib_logs_v1'), isNull);

    // Branch 2: Throw AFTER host mutated => reload-sync catches host, livePublished: true, writeUnconfirmed
    mockPlatform.mutateBeforeThrow = true;
    final res2 = await service.toggleSunnah('fajr_pre_2');

    expect(res2.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(res2.livePublished, isTrue);
    expect(service.isCompleted('fajr_pre_2'), isTrue);
    expect(prefs.getString('sunan_rawatib_logs_v1'), contains('fajr_pre_2'));
  });
}
