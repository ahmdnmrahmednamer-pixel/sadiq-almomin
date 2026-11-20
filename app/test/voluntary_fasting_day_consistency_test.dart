import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/voluntary_fasting_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = VoluntaryFastingService.instance;
  final date = DateTime(2026, 11, 20);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await service.init(forceReload: true);
  });
  test('repeated confirmation for one type and date counts one day', () async {
    await service.logFastedDay('monday_thursday', date: date);
    await service.logFastedDay('monday_thursday', date: date);
    final prefs = await SharedPreferences.getInstance();
    expect(service.getCountForType('monday_thursday'), 1);
    expect(service.fastedDateLogs, hasLength(1));
    expect(prefs.getInt('vfast_count_monday_thursday'), 1);
    expect(prefs.getStringList('vfast_date_logs'), hasLength(1));
  });
  test('one undo after repeated confirmation leaves no phantom days', () async {
    await service.logFastedDay('monday_thursday', date: date);
    await service.logFastedDay('monday_thursday', date: date);
    await service.decrementFastCount('monday_thursday');
    expect(service.getCountForType('monday_thursday'), 0);
    expect(service.fastedDateLogs, isEmpty);
  });
  test('different dates remain independent and removing one permits re-add',
      () async {
    await service.logFastedDay('monday_thursday', date: date);
    await service.logFastedDay('monday_thursday',
        date: date.add(const Duration(days: 1)));
    expect(service.getCountForType('monday_thursday'), 2);
    await service.decrementFastCount('monday_thursday');
    expect(service.getCountForType('monday_thursday'), 1);
    await service.logFastedDay('monday_thursday',
        date: date.add(const Duration(days: 1)));
    expect(service.getCountForType('monday_thursday'), 2);
    expect(service.fastedDateLogs, hasLength(2));
  });
  test(
      'different categories on the same date keep existing independent behavior',
      () async {
    await service.logFastedDay('monday_thursday', date: date);
    await service.logFastedDay('white_days', date: date);
    expect(service.getCountForType('monday_thursday'), 1);
    expect(service.getCountForType('white_days'), 1);
    expect(service.fastedDateLogs, hasLength(2));
  });
  test(
      'repeat confirmation after reload stays idempotent without notifying again',
      () async {
    await service.logFastedDay('monday_thursday', date: date);
    await service.init(forceReload: true);
    var notifications = 0;
    void listener() => notifications++;
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    await service.logFastedDay('monday_thursday', date: date);
    expect(service.getCountForType('monday_thursday'), 1);
    expect(notifications, 0);
  });
  test('concurrent duplicate confirmations add only once', () async {
    await Future.wait(List.generate(
        12, (_) => service.logFastedDay('monday_thursday', date: date)));
    expect(service.getCountForType('monday_thursday'), 1);
    expect(service.fastedDateLogs, hasLength(1));
  });
  test('existing legacy count and imported log are not recalculated or erased',
      () async {
    SharedPreferences.setMockInitialValues({
      'vfast_count_monday_thursday': 9,
      'vfast_date_logs': ['2026-11-20|monday_thursday'],
    });
    await service.init(forceReload: true);
    final before = jsonEncode(service.fastedDateLogs);
    await service.logFastedDay('monday_thursday', date: date);
    expect(service.getCountForType('monday_thursday'), 9);
    expect(jsonEncode(service.fastedDateLogs), before);
    await service.logFastedDay('monday_thursday',
        date: date.add(const Duration(days: 1)));
    expect(service.getCountForType('monday_thursday'), 10);
  });
}
