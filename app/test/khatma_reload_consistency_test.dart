import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/khatma_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = KhatmaService.instance;
  Map<String, Object> saved(String title) => {
        'active_khatma_plan': jsonEncode(KhatmaPlan(
          id: 'reload-plan',
          title: title,
          targetDays: 30,
          startDate: DateTime.now(),
          currentPage: 45,
          reminderEnabled: false,
        ).toJson()),
      };
  setUp(() async {
    SharedPreferences.setMockInitialValues(saved('Saved plan'));
    await service.init(forceReload: true);
    expect(service.activePlan?.title, 'Saved plan');
  });
  test('reload clears a cached plan when saved key is absent', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_khatma_plan');
    await service.init(forceReload: true);
    expect(service.activePlan, isNull);
    expect(service.hasActivePlan, isFalse);
  });
  test('reload clears a cached plan when saved value is empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_khatma_plan', '');
    await service.init(forceReload: true);
    expect(service.activePlan, isNull);
  });
  test('progress after clearing cannot resurrect the removed plan', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_khatma_plan');
    await service.init(forceReload: true);
    await service.updateProgress(60);
    expect(service.activePlan, isNull);
    expect(prefs.containsKey('active_khatma_plan'), isFalse);
  });
  test('reload notifies listeners after clearing the cached plan', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_khatma_plan');
    final observed = <KhatmaPlan?>[];
    void listener() => observed.add(service.activePlan);
    service.addListener(listener);
    addTearDown(() => service.removeListener(listener));
    await service.init(forceReload: true);
    expect(observed, [null]);
  });
  test('reload still reads a valid replacement plan', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_khatma_plan',
        saved('Replacement')['active_khatma_plan']! as String);
    await service.init(forceReload: true);
    expect(service.activePlan?.title, 'Replacement');
    expect(service.activePlan?.currentPage, 45);
  });
  test('malformed saved data does not leave an old plan active', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_khatma_plan', '{invalid');
    await service.init(forceReload: true);
    expect(service.activePlan, isNull);
  });
}
