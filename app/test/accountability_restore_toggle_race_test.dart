// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toggle-during-restore serialized race executes safely via queue', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': initialHost,
    });
    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    const importDate = '2025-01-02';
    final importPayload = json.encode({
      importDate: ['imported_task'],
    });

    // Launch merge restore and toggle concurrently in same turn without intermediate await
    final restoreFuture = service.restoreAccountability(
      rawImport: importPayload,
      replaceMode: false,
    );
    final toggleFuture = service.toggleEthicalItemToday('birr_walidayn');

    final results = await Future.wait([restoreFuture, toggleFuture]);
    final restoreRes = results[0] as AccountabilityRestoreResult;
    final toggleRes = results[1] as AccountabilityToggleResult;

    expect(restoreRes.status, equals(AccountabilityRestoreStatus.confirmedWrite));
    expect(toggleRes.status, equals(AccountabilityOperationStatus.persisted));
    expect(toggleRes.livePublished, isTrue);

    // Verify host contains all 3 dates: priorDate, importDate, and today's key with 'birr_walidayn'
    final prefs = await SharedPreferences.getInstance();
    final finalHost = prefs.getString('tadabbur_daily_accountability_v1')!;
    final finalMap = json.decode(finalHost) as Map<String, dynamic>;

    expect(finalMap.containsKey(priorDate), isTrue);
    expect(List<String>.from(finalMap[priorDate] as List), equals(['prior_task']));

    expect(finalMap.containsKey(importDate), isTrue);
    expect(List<String>.from(finalMap[importDate] as List), equals(['imported_task']));

    final todayKey = finalMap.keys.firstWhere((k) => k != priorDate && k != importDate);
    expect(List<String>.from(finalMap[todayKey] as List), contains('birr_walidayn'));

    expect(service.isEthicalItemDoneToday('birr_walidayn'), isTrue);
  });
}
