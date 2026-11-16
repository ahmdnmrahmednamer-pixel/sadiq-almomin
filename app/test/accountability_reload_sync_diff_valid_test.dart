// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

class DiffValidStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  final String diffValidJson;

  DiffValidStorePlatform(this.delegate, this.diffValidJson);

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
    if (key.endsWith('tadabbur_daily_accountability_v1')) {
      // Simulate host mutating to a DIFFERENT strict-valid map during write failure
      await delegate.setValue(valueType, key, diffValidJson);
      return false;
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write-failure + reload-sync for different strict-valid publishes actual host (true, writeUnconfirmed, NEVER persisted)', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    const diffDate = '2025-05-05';
    final diffValidHost = json.encode({
      diffDate: ['remote_diff_task'],
    });

    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = DiffValidStorePlatform(originalPlatform, diffValidHost);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    final result = await service.toggleEthicalItemToday('birr_walidayn');

    // F2 contract: publishes actual host, livePublished: true, status: writeUnconfirmed (NEVER persisted)
    expect(result.status, equals(AccountabilityOperationStatus.writeUnconfirmed));
    expect(result.livePublished, isTrue);

    // Live map was updated with the actual host's data (not stale candidate)
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(diffValidHost));
  });
}
