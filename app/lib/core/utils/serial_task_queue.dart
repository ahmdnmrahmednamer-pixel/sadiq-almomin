import 'dart:async';
import 'dart:collection';

/// Runs asynchronous operations in admission order, one operation at a time.
///
/// Each operation receives its own result or original error/stack. An error
/// never prevents later operations from running. A new idle operation starts
/// immediately; queued operations start before the previous caller resumes.
///
/// An operation may enqueue more work, but must not await work on this same
/// queue: that work cannot start until the current operation finishes.
class SerialTaskQueue {
  final Queue<Future<void> Function()> _pending = Queue();
  bool _running = false;

  Future<T> run<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending.add(() async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _running = false;
        _runNext();
      }
    });
    _runNext();
    return result.future;
  }

  void _runNext() {
    if (_running || _pending.isEmpty) return;
    _running = true;
    unawaited(_pending.removeFirst()());
  }
}
