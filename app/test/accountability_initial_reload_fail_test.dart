// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

class InitialReloadThrowingPlatform extends SharedPreferencesStorePlatform {
  final SharedPreferencesStorePlatform delegate;
  bool throwOnGetAll = false;

  InitialReloadThrowingPlatform(this.delegate);

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() => delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      delegate.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() {
    if (throwOnGetAll) {
      throw Exception('Simulated initial host reload failure');
    }
    return delegate.getAll();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) {
    if (throwOnGetAll) {
      throw Exception('Simulated initial host reload failure');
    }
    return delegate.getAllWithParameters(parameters);
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    return delegate.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initial-reload-failure refusal (host bytes pinned verbatim, no write, no publish, writeUnconfirmed, livePublished=false)', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': initialHost,
    });
    final originalPlatform = SharedPreferencesStorePlatform.instance;

    final mockPlatform = InitialReloadThrowingPlatform(originalPlatform);
    SharedPreferencesStorePlatform.instance = mockPlatform;

    addTearDown(() {
      SharedPreferencesStorePlatform.instance = originalPlatform;
    });

    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    // Trigger initial reload exception
    mockPlatform.throwOnGetAll = true;

    final result = await service.toggleEthicalItemToday('birr_walidayn');

    // F1 contract: writeUnconfirmed + livePublished=false, NOT writeRefusedUnreadable
    expect(result.status, equals(AccountabilityOperationStatus.writeUnconfirmed));
    expect(result.livePublished, isFalse);

    // Live map untouched
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    // Turn off exception to verify host bytes were pinned verbatim
    mockPlatform.throwOnGetAll = false;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(initialHost));
  });
}
