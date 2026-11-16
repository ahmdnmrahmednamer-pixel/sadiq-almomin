// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('merge-restore with local 2025-01-01 + import 2025-02-02 => host contains BOTH dates', (tester) async {
    const localDate = '2025-01-01';
    final localJson = json.encode({
      localDate: ['fajr_pre_2'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': localJson,
    });

    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    const importDate = '2025-02-02';
    final importPayload = json.encode({
      importDate: ['dhuhr_post_2'],
    });

    final result = await service.restoreSunanRawatib(
      rawImport: importPayload,
      replaceMode: false,
    );

    expect(result.status, equals(SunanRawatibRestoreStatus.confirmedWrite));
    expect(result.livePublished, isTrue);

    final prefs = await SharedPreferences.getInstance();
    final hostRaw = prefs.getString('sunan_rawatib_logs_v1')!;
    final hostMap = json.decode(hostRaw) as Map<String, dynamic>;

    expect(hostMap.containsKey(localDate), isTrue);
    expect(List<String>.from(hostMap[localDate] as List), equals(['fajr_pre_2']));

    expect(hostMap.containsKey(importDate), isTrue);
    expect(List<String>.from(hostMap[importDate] as List), equals(['dhuhr_post_2']));
  });
}
