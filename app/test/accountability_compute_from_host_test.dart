// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/tadabbur_journal_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('valid host with prior dates preserved + item toggled (compute-from-host pin)', (tester) async {
    const priorDate = '2025-01-01';
    const priorTask = 'item_prior';
    final initialHost = json.encode({
      priorDate: [priorTask],
    });

    SharedPreferences.setMockInitialValues({
      'tadabbur_daily_accountability_v1': initialHost,
    });

    final service = TadabburJournalService.instance;
    await service.init(forceReload: true);

    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    // 1st toggle: adds birr_walidayn
    final res1 = await service.toggleEthicalItemToday('birr_walidayn');
    expect(res1.status, equals(AccountabilityOperationStatus.persisted));
    expect(res1.livePublished, isTrue);
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final hostRaw1 = prefs.getString('tadabbur_daily_accountability_v1')!;
    final hostMap1 = json.decode(hostRaw1) as Map<String, dynamic>;

    // Assert prior date preserved verbatim in host
    expect(hostMap1.containsKey(priorDate), isTrue);
    expect(List<String>.from(hostMap1[priorDate] as List), equals([priorTask]));

    // Find today's key in hostMap1
    final todayKey = hostMap1.keys.firstWhere((k) => k != priorDate);
    expect(List<String>.from(hostMap1[todayKey] as List), contains('birr_walidayn'));

    // 2nd toggle: removes birr_walidayn
    final res2 = await service.toggleEthicalItemToday('birr_walidayn');
    expect(res2.status, equals(AccountabilityOperationStatus.persisted));
    expect(res2.livePublished, isTrue);
    expect(service.isEthicalItemDoneToday('birr_walidayn'), isFalse);

    final hostRaw2 = prefs.getString('tadabbur_daily_accountability_v1')!;
    final hostMap2 = json.decode(hostRaw2) as Map<String, dynamic>;

    // Prior date STILL preserved
    expect(hostMap2.containsKey(priorDate), isTrue);
    expect(List<String>.from(hostMap2[priorDate] as List), equals([priorTask]));
    expect(List<String>.from(hostMap2[todayKey] as List), isNot(contains('birr_walidayn')));
  });
}
