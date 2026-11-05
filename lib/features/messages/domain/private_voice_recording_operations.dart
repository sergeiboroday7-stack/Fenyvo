/// Coordinates asynchronous recording starts and finishes.
///
/// Chat owns the microphone, message sending and encryption.
class PrivateVoiceRecordingOperations {
  Future<void>? _pendingStart;
  Future<void>? _pendingFinish;

  Future<void>? get pendingStart => _pendingStart;
  Future<void>? get pendingFinish => _pendingFinish;

  Future<void> start({
    required bool isClosing,
    required Future<void> Function() action,
  }) {
    if (isClosing || _pendingFinish != null) {
      return Future<void>.value();
    }

    return _pendingStart ??= Future<void>.sync(action).whenComplete(() {
      _pendingStart = null;
    });
  }

  Future<void> finish({
    required bool isClosing,
    required Future<void> Function() action,
  }) {
    if (isClosing) {
      return Future<void>.value();
    }

    return _pendingFinish ??= Future<void>.sync(action).whenComplete(() {
      _pendingFinish = null;
    });
  }
}
