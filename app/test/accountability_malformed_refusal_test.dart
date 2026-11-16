// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('malformed host refusal with host bytes pinned UNCHANGED', (tester) async {
    const malformedRaw = 'not a valid json {[';
    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': malformedRaw,
    });

    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    expect(service.isReadable, isTrue);
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    final result = await service.toggleEthicalItemToday('birr_walidayn');

    expect(result.status, equals(AccountabilityOperationStatus.writeRefusedUnreadable));
    expect(result.livePublished, isFalse);

    // Assert live map untouched
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    // Assert journal readability latch untouched (no latch on accountability)
    expect(service.isReadable, isTrue);

    // Assert host bytes pinned UNCHANGED
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(malformedRaw));
  });
}
