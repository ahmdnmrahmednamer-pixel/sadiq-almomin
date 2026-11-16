// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

class FailingSetStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  bool returnFalseOnSetValue = true;

  FailingSetStorePlatform(this.delegate);

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
  Future<bool> setValue(String valueType, String key, Object value) {
    if (returnFalseOnSetValue && key.endsWith('sunan_rawatib_logs_v1')) {
      return Future.value(false);
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('setString false pure fixture => host+live unchanged + writeUnconfirmed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = FailingSetStorePlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    expect(service.isCompleted('fajr_pre_2'), isFalse);

    // Toggle attempt with failing setString fixture
    final result = await service.toggleSunnah('fajr_pre_2');

    expect(result.status, equals(SunanRawatibOperationStatus.writeUnconfirmed));
    expect(result.livePublished, isFalse);

    // Live map untouched
    expect(service.isCompleted('fajr_pre_2'), isFalse);

    // Host unchanged (null)
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sunan_rawatib_logs_v1'), isNull);
  });
}
