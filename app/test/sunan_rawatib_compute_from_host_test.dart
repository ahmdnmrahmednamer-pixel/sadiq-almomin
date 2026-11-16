// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('valid host with prior dates preserved + item toggled (compute-from-host pin)', (tester) async {
    const priorDate = '2025-01-01';
    const priorTask = 'item_prior';
    final initialHost = json.encode({
      priorDate: [priorTask],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': initialHost,
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    expect(service.isCompleted('fajr_pre_2'), isFalse);

    // 1st toggle: adds fajr_pre_2
    final res1 = await service.toggleSunnah('fajr_pre_2');
    expect(res1.status, equals(SunanRawatibOperationStatus.persisted));
    expect(res1.livePublished, isTrue);
    expect(service.isCompleted('fajr_pre_2'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final hostRaw1 = prefs.getString('sunan_rawatib_logs_v1')!;
    final hostMap1 = json.decode(hostRaw1) as Map<String, dynamic>;

    // Assert prior date preserved verbatim in host
    expect(hostMap1.containsKey(priorDate), isTrue);
    expect(List<String>.from(hostMap1[priorDate] as List), equals([priorTask]));

    // Find today's key in hostMap1
    final todayKey = hostMap1.keys.firstWhere((k) => k != priorDate);
    expect(List<String>.from(hostMap1[todayKey] as List), contains('fajr_pre_2'));

    // 2nd toggle: removes fajr_pre_2
    final res2 = await service.toggleSunnah('fajr_pre_2');
    expect(res2.status, equals(SunanRawatibOperationStatus.persisted));
    expect(res2.livePublished, isTrue);
    expect(service.isCompleted('fajr_pre_2'), isFalse);

    final hostRaw2 = prefs.getString('sunan_rawatib_logs_v1')!;
    final hostMap2 = json.decode(hostRaw2) as Map<String, dynamic>;

    // Prior date STILL preserved
    expect(hostMap2.containsKey(priorDate), isTrue);
    expect(List<String>.from(hostMap2[priorDate] as List), equals([priorTask]));
    expect(List<String>.from(hostMap2[todayKey] as List), isNot(contains('fajr_pre_2')));
  });
}
