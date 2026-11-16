// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('replace-restore of malformed raw then toggle => refused + host preserved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    const malformedRaw = '{corrupt-json-raw:';

    // Replace-restore writes raw verbatim per replaceMode semantics
    final restoreRes = await service.restoreAccountability(
      rawImport: malformedRaw,
      replaceMode: true,
    );

    expect(restoreRes.status, equals(AccountabilityRestoreStatus.confirmedWrite));
    expect(restoreRes.livePublished, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(malformedRaw));

    // Later toggle must strictly validate host, refuse to write, and preserve host bytes verbatim
    final toggleRes = await service.toggleEthicalItemToday('birr_walidayn');

    expect(toggleRes.status, equals(AccountabilityOperationStatus.writeRefusedUnreadable));
    expect(toggleRes.livePublished, isFalse);

    // Host raw is preserved verbatim!
    expect(prefs.getString('tadabbur_daily_accountability_v1'), equals(malformedRaw));
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);
    expect(service.isReadable, isTrue);
  });
}
