// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/core/services/sunan_rawatib_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('completed initialization in a prior fake zone cannot hold later reload',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = SunanRawatibService.instance;
    await service.init(forceReload: true);
    final priorZone = FakeAsync();
    var priorCompleted = false;
    priorZone.run((_) {
      unawaited(service.init().then((_) => priorCompleted = true));
    });
    // Flush both the real-zone completed predecessor and fake-zone callbacks.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
      priorZone.flushMicrotasks();
    }
    expect(priorCompleted, isTrue);
    expect(priorZone.microtaskCount, 0);
    Future<void>? next;
    var nextCompleted = false;
    try {
      next = service.init(forceReload: true).then((_) => nextCompleted = true);
      await next.timeout(const Duration(seconds: 1));
      expect(priorZone.microtaskCount, 0,
          reason: 'A completed old queue tail must not capture new work');
    } finally {
      // If baseline fails, drain it only after the timeout assertion, so the
      // failed regression does not leave its singleton blocked for other tests.
      for (var i = 0; i < 8 && !nextCompleted; i++) {
        priorZone.flushMicrotasks();
        await Future<void>.delayed(Duration.zero);
      }
      if (next != null) await next.timeout(const Duration(seconds: 1));
    }
  });
}
