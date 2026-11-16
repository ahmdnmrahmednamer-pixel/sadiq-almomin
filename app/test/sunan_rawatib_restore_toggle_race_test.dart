// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toggle-during-restore serialized race executes safely via queue', (tester) async {
    const priorDate = '2025-01-01';
    final initialHost = json.encode({
      priorDate: ['prior_task'],
    });

    SharedPreferences.setMockInitialValues({
      'sunan_rawatib_logs_v1': initialHost,
    });
    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);

    const importDate = '2025-01-02';
    final importPayload = json.encode({
      importDate: ['imported_task'],
    });

    // Launch merge restore and toggle concurrently in same turn without intermediate await
    final restoreFuture = service.restoreSunanRawatib(
      rawImport: importPayload,
      replaceMode: false,
    );
    final toggleFuture = service.toggleSunnah('fajr_pre_2');

    final results = await Future.wait([restoreFuture, toggleFuture]);
    final restoreRes = results[0] as SunanRawatibRestoreResult;
    final toggleRes = results[1] as SunanRawatibToggleResult;

    expect(restoreRes.status, equals(SunanRawatibRestoreStatus.confirmedWrite));
    expect(toggleRes.status, equals(SunanRawatibOperationStatus.persisted));
    expect(toggleRes.livePublished, isTrue);

    // Verify host contains all 3 dates: priorDate, importDate, and today's key with 'fajr_pre_2'
    final prefs = await SharedPreferences.getInstance();
    final finalHost = prefs.getString('sunan_rawatib_logs_v1')!;
    final finalMap = json.decode(finalHost) as Map<String, dynamic>;

    expect(finalMap.containsKey(priorDate), isTrue);
    expect(List<String>.from(finalMap[priorDate] as List), equals(['prior_task']));

    expect(finalMap.containsKey(importDate), isTrue);
    expect(List<String>.from(finalMap[importDate] as List), equals(['imported_task']));

    final todayKey = finalMap.keys.firstWhere((k) => k != priorDate && k != importDate);
    expect(List<String>.from(finalMap[todayKey] as List), contains('fajr_pre_2'));

    expect(service.isCompleted('fajr_pre_2'), isTrue);
  });
}
