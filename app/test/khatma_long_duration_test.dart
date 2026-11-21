import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/khatma_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final days in [366, 500, 604, 730]) {
    test('supported duration $days survives a model round trip', () {
      final plan = KhatmaPlan(
          id: 'long-plan',
          title: 'Long plan',
          targetDays: days,
          startDate: DateTime.now(),
          reminderEnabled: false);
      final restored = KhatmaPlan.fromJson(plan.toJson());
      expect(restored.targetDays, days);
      expect(restored.pagesPerDay, (604 / days).ceil());
    });
  }
  test('730 day plan uses supported duration for daily pace', () {
    final plan = KhatmaPlan(
        id: 'long-plan',
        title: 'Long plan',
        targetDays: 730,
        startDate: DateTime.now(),
        reminderEnabled: false);
    expect(plan.pagesPerDay, 1);
    expect(plan.targetPageToday, 1);
  });
  test('created long plan keeps duration and pace after persisted reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = KhatmaService.instance;
    await service.init(forceReload: true);
    await service.createPlan(
        title: '730 day plan', targetDays: 730, reminderEnabled: false);
    final before = service.activePlan!;
    final prefs = await SharedPreferences.getInstance();
    expect(
        (jsonDecode(prefs.getString('active_khatma_plan')!)
            as Map)['targetDays'],
        730);
    await service.init(forceReload: true);
    expect(service.activePlan!.targetDays, before.targetDays);
    expect(service.activePlan!.pagesPerDay, 1);
  });
  for (final days in [1, 30, 365]) {
    test('ordinary duration $days retains its existing pace', () {
      final plan = KhatmaPlan(
          id: 'control',
          title: 'Control',
          targetDays: days,
          startDate: DateTime.now(),
          reminderEnabled: false);
      expect(plan.pagesPerDay, (604 / days).ceil());
      expect(KhatmaPlan.fromJson(plan.toJson()).targetDays, days);
    });
  }
  test('legacy invalid duration bounds and custom pace stay bounded', () {
    Map<String, dynamic> input(int days) => {
          'id': 'legacy',
          'targetDays': days,
          'startDate': DateTime.now().toIso8601String(),
          'customDailyPace': 8
        };
    expect(KhatmaPlan.fromJson(input(0)).targetDays, 1);
    expect(KhatmaPlan.fromJson(input(900)).targetDays, 730);
    expect(KhatmaPlan.fromJson(input(730)).pagesPerDay, 8);
  });
}
