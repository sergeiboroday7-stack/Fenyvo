import 'dart:async';

/// Approval ACK is receipt of the old-device proof, not new-device activation.
class DeviceTransferAck {
  Object? _scope;
  String? _nonce;
  Completer<bool>? _pending;
  Timer? _timer;
  bool get waiting => _pending != null;
  Future<bool> begin({
    required Object scope,
    required String nonce,
    required Duration timeout,
  }) {
    if (waiting || timeout <= Duration.zero)
      throw StateError('Approval ACK already pending or expired');
    _scope = scope;
    _nonce = nonce;
    final pending = Completer<bool>();
    _pending = pending;
    _timer = Timer(timeout, cancel);
    return pending.future;
  }

  bool receive(Map<String, dynamic> data, {required Object scope}) {
    if (!identical(scope, _scope) ||
        data.length != 1 ||
        data['transferNonce'] != _nonce ||
        !waiting)
      return false;
    _finish(true);
    return true;
  }

  void cancel() => _finish(false);
  void _finish(bool value) {
    final pending = _pending;
    _pending = null;
    _scope = null;
    _nonce = null;
    _timer?.cancel();
    _timer = null;
    if (pending != null && !pending.isCompleted) pending.complete(value);
  }
}
