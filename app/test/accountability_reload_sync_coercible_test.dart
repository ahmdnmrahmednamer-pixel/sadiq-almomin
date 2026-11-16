// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

class CoercibleMutationStorePlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  final String coercibleHost;

  CoercibleMutationStorePlatform(this.delegate, this.coercibleHost);

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
      // Host mutated to coercible-but-strict-invalid JSON
      await delegate.setValue(valueType, key, coercibleHost);
      return false;
    }
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coercible-but-strict-invalid actual host publishes coerced via lenient load decode with writeUnconfirmed AND subsequent toggle strict-refuses', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    const coercibleHost = '{"d1":["a"],"bad":42}';

    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = CoercibleMutationStorePlatform(originalPlatform, coercibleHost);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    // 1. First toggle fails write -> reload-sync leniently publishes coerced host
    final res1 = await service.toggleEthicalItemToday('birr_walidayn');

    expect(res1.status, equals(AccountabilityOperationStatus.writeUnconfirmed));
    expect(res1.livePublished, isTrue);

    // 2. Subsequent toggle attempts opening reload + strict validation on the same host:
    // strict validation fails because "bad": 42 is not a List -> strict-refuses!
    final res2 = await service.toggleEthicalItemToday('birr_walidayn');

    expect(res2.status, equals(AccountabilityOperationStatus.writeRefusedUnreadable));
    expect(res2.livePublished, isFalse);

    // Host raw is preserved verbatim as coercibleHost
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(coercibleHost));
  });
}
