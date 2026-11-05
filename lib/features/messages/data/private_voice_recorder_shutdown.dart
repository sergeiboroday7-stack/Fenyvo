import 'dart:async';

/// Coordinates orderly recorder shutdown.
///
/// The owner must prevent new starts once [isClosing] is true.
/// This class does not own message sending or cryptography.
class PrivateVoiceRecorderShutdown {
  Future<void>? _closeFuture;

  bool get isClosing => _closeFuture != null;

  Future<void> close({
    Future<void>? pendingStart,
    Future<void>? pendingFinish,
    required Future<void> Function() stop,
    required Future<void> Function() cleanup,
    required Future<void> Function() dispose,
  }) {
    return _closeFuture ??= _run(
      pendingStart: pendingStart,
      pendingFinish: pendingFinish,
      stop: stop,
      cleanup: cleanup,
      dispose: dispose,
    );
  }

  Future<void> _run({
    required Future<void>? pendingStart,
    required Future<void>? pendingFinish,
    required Future<void> Function() stop,
    required Future<void> Function() cleanup,
    required Future<void> Function() dispose,
  }) async {
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }

    if (pendingStart != null) {
      await attempt(() => pendingStart);
    }

    if (pendingFinish != null) {
      await attempt(() => pendingFinish);
    }

    await attempt(stop);
    await attempt(cleanup);
    await attempt(dispose);

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }
}
