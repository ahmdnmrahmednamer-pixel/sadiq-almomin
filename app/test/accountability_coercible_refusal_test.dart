// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coercible host ({"d1":["a"],"bad":42} and {"d1":[1,2]}) refused', (tester) async {
    final service = TadabburJournalService.instance;

    // Case 1: Value is not a List: {"d1":["a"],"bad":42}
    const coercibleValueNotList = '{"d1":["a"],"bad":42}';
    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': coercibleValueNotList,
    });
    await service.init(forceReload: true);

    final res1 = await service.toggleEthicalItemToday('birr_walidayn');
    expect(res1.status, equals(AccountabilityOperationStatus.writeRefusedUnreadable));
    expect(res1.livePublished, isFalse);

    final prefs1 = await SharedPreferences.getInstance();
    expect(prefs1.getString('tadabbur_daily_accountability_v1'), equals(coercibleValueNotList));
    expect(service.isReadable, isTrue);

    // Case 2: List contains non-String: {"d1":[1,2]}
    const coercibleItemsNotString = '{"d1":[1,2]}';
    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': coercibleItemsNotString,
    });
    await service.init(forceReload: true);

    final res2 = await service.toggleEthicalItemToday('birr_walidayn');
    expect(res2.status, equals(AccountabilityOperationStatus.writeRefusedUnreadable));
    expect(res2.livePublished, isFalse);

    final prefs2 = await SharedPreferences.getInstance();
    expect(prefs2.getString('tadabbur_daily_accountability_v1'), equals(coercibleItemsNotString));
    expect(service.isReadable, isTrue);
  });
}
