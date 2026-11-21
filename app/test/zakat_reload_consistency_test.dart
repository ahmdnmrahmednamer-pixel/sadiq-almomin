import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/zakat_service.dart';
import 'package:almomin/core/models/zakat_calculation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ZakatService.instance;
  final draft = ZakatCalculation(
      cashOnHand: 123456, currency: 'TEST', hawlDate: DateTime(2026, 6, 1));
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'zakat_calculation_draft_v1': jsonEncode(draft.toJson()),
    });
    await service.init(forceReload: true);
    expect(service.calculation.cashOnHand, draft.cashOnHand);
  });
  test('forced reload with absent key clears stale draft', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zakat_calculation_draft_v1');
    await service.init(forceReload: true);
    expect(service.exportData(), const ZakatCalculation().toJson());
  });
  test('forced reload with empty saved value clears stale draft', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zakat_calculation_draft_v1', '');
    await service.init(forceReload: true);
    expect(service.exportData(), const ZakatCalculation().toJson());
  });
  test('ordinary init keeps the initialized guard', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zakat_calculation_draft_v1');
    await service.init();
    expect(service.exportData(), draft.toJson());
  });
  test('malformed saved JSON preserves existing cached draft', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zakat_calculation_draft_v1', '{invalid');
    await service.init(forceReload: true);
    expect(service.exportData(), draft.toJson());
  });
  test('listeners observe default draft after missing-value reload', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zakat_calculation_draft_v1');
    final observed = <Map<String, dynamic>>[];
    void listener() => observed.add(service.exportData());
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    await service.init(forceReload: true);
    expect(observed, [const ZakatCalculation().toJson()]);
    expect(service.isInitialized, isTrue);
  });
  test('later draft update does not resurrect cleared fields', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zakat_calculation_draft_v1');
    await service.init(forceReload: true);
    await service
        .updateCalculation(service.calculation.copyWith(cashOnHand: 10));
    final expected = const ZakatCalculation(cashOnHand: 10).toJson();
    expect(service.exportData(), expected);
    expect(
        jsonDecode(prefs.getString('zakat_calculation_draft_v1')!), expected);
  });
  test('valid replacement keeps only replacement values', () async {
    final prefs = await SharedPreferences.getInstance();
    final replacement =
        const ZakatCalculation(cashOnHand: 42, currency: 'NEXT');
    await prefs.setString(
        'zakat_calculation_draft_v1', jsonEncode(replacement.toJson()));
    await service.init(forceReload: true);
    expect(service.exportData(), replacement.toJson());
  });
  test('valid empty object uses existing model defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zakat_calculation_draft_v1', '{}');
    await service.init(forceReload: true);
    expect(service.exportData(), const ZakatCalculation().toJson());
  });
  test('explicit null Hawl date clears saved date and survives reload', () async {
    final prefs = await SharedPreferences.getInstance();
    await service.setHawlDate(null);
    expect(service.calculation.hawlDate, isNull);
    expect(jsonDecode(prefs.getString('zakat_calculation_draft_v1')!)['hawl_date'], isNull);
    expect(service.calculation.cashOnHand, draft.cashOnHand);
    await service.init(forceReload: true);
    expect(service.calculation.hawlDate, isNull);
    expect(service.calculation.cashOnHand, draft.cashOnHand);
  });
  test('explicit Hawl date replacement keeps amount and publishes new date', () async {
    final next = DateTime(2027, 7, 10);
    final seen = <DateTime?>[];
    void listener() => seen.add(service.calculation.hawlDate);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    await service.setHawlDate(next);
    expect(service.calculation.hawlDate, next);
    expect(service.calculation.cashOnHand, draft.cashOnHand);
    expect(seen, [next]);
    await service.init(forceReload: true);
    expect(service.calculation.hawlDate, next);
  });

}
