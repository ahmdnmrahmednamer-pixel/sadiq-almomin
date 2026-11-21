import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/utils/serial_task_queue.dart';

void main() {
  test('idle admission starts immediately and yields its typed result',
      () async {
    final queue = SerialTaskQueue();
    var started = false;
    final result = queue.run(() async {
      started = true;
      return 7;
    });
    expect(started, isTrue);
    expect(await result, 7);
  });
  test('pending operations run FIFO without overlapping', () async {
    final queue = SerialTaskQueue();
    final gate = Completer<void>();
    final events = <int>[];
    var active = 0;
    final first = queue.run(() async {
      active++;
      events.add(1);
      await gate.future;
      active--;
      return 'one';
    });
    final rest = List.generate(
        100,
        (i) => queue.run(() async {
              expect(active, 0);
              active++;
              events.add(i + 2);
              await Future<void>.delayed(Duration.zero);
              active--;
              return i;
            }));
    expect(events, [1]);
    gate.complete();
    expect(await first, 'one');
    expect(await Future.wait(rest), List.generate(100, (i) => i));
    expect(events, List.generate(101, (i) => i + 1));
    expect(active, 0);
  });
  for (final asynchronous in [false, true]) {
    test(
        'original error/stack survive, later tasks proceed async=$asynchronous',
        () async {
      final queue = SerialTaskQueue();
      final error = StateError('expected');
      final stack = StackTrace.current;
      final gate = Completer<void>();
      final first = queue.run(() async {
        await gate.future;
      });
      final failed = queue.run<int>(() {
        if (asynchronous) return Future<int>.error(error, stack);
        Error.throwWithStackTrace(error, stack);
      });
      final captured =
          failed.then<Object?>((_) => null, onError: (Object e, StackTrace s) {
        expect(identical(e, error), isTrue);
        expect(s.toString(), stack.toString());
        return e;
      });
      final next = queue.run(() async => 9);
      gate.complete();
      await first;
      expect(await captured, same(error));
      expect(await next, 9);
      expect(await queue.run(() async => 10), 10);
    });
  }
  test('void and nullable values complete without casts', () async {
    final queue = SerialTaskQueue();
    var done = false;
    await queue.run<void>(() async {
      done = true;
    });
    expect(done, isTrue);
    expect(await queue.run<String?>(() async => null), isNull);
  });
  test('next queued operation starts before prior callers resume', () async {
    final queue = SerialTaskQueue();
    final gate = Completer<void>();
    final events = <String>[];
    final first = queue.run(() async {
      await gate.future;
      return 1;
    });
    final observed = first.then((_) => events.add('caller'));
    final second = queue.run(() async {
      events.add('next');
    });
    gate.complete();
    await observed;
    await second;
    expect(events, ['next', 'caller']);
  });
  test('work enqueued inside a task waits behind already pending work',
      () async {
    final queue = SerialTaskQueue();
    final gate = Completer<void>();
    final events = <int>[];
    Future<void>? nested;
    final first = queue.run(() async {
      await gate.future;
      events.add(1);
      nested = queue.run(() async {
        events.add(3);
      });
    });
    final second = queue.run(() async {
      events.add(2);
    });
    gate.complete();
    await first;
    await second;
    await nested;
    expect(events, [1, 2, 3]);
  });
  test('queues are independent', () async {
    final a = SerialTaskQueue(), b = SerialTaskQueue();
    final gate = Completer<void>();
    final blocked = a.run(() async {
      await gate.future;
    });
    expect(await b.run(() async => 8), 8);
    gate.complete();
    await blocked;
  });
}
