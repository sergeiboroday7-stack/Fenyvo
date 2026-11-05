import 'dart:async';

/// Runs operations for the same key in submission order.
///
/// All writers for a key must share this coordinator.
/// This class does not prevent resurrection from stale snapshots
/// submitted after a delete, or writes that bypass the coordinator.
class MessageWriteCoordinator {
  final Map<String, Future<void>> _tails = {};

  Future<T> run<T>(
    String key,
    Future<T> Function() operation,
  ) {
    final previous = _tails[key] ?? Future<void>.value();
    final release = Completer<void>();
    final completion = release.future;

    _tails[key] = completion;

    return _execute(
      key,
      previous,
      release,
      completion,
      operation,
    );
  }

  Future<T> _execute<T>(
    String key,
    Future<void> previous,
    Completer<void> release,
    Future<void> completion,
    Future<T> Function() operation,
  ) async {
    try {
      await previous;
      return await operation();
    } finally {
      release.complete();
      if (identical(_tails[key], completion)) {
        _tails.remove(key);
      }
    }
  }
}