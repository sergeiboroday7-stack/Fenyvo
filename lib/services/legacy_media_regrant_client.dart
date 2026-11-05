import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'legacy_media_regrant_coordinator.dart';
import 'legacy_media_regrant_result.dart';
import 'socket_service.dart';

/// Connection-level regrant client.
///
/// Uses exactly one in-flight request. It never treats transport submission
/// as server approval and always verifies the response requestId.
class LegacyMediaRegrantClient {
  LegacyMediaRegrantClient._({
    required this.send,
    required this.subscribe,
    required this.unsubscribe,
    required this.isConnected,
    required this.connectionChanges,
    this.timeout = const Duration(seconds: 15),
  }) {
    _coordinator = LegacyMediaRegrantCoordinator(send: send);
    subscribe(_handleMessage);
    connectionChanges.addListener(_handleConnection);
  }

  static LegacyMediaRegrantClient? _shared;

  static LegacyMediaRegrantClient get instance =>
      _shared ??= LegacyMediaRegrantClient.forSocket(SocketService.instance);

  factory LegacyMediaRegrantClient.forSocket(SocketService socket) {
    return LegacyMediaRegrantClient._(
      send: ({
        required mediaId,
        required recipient,
        required ownerConfirmed,
        required requestId,
      }) => socket.requestLegacyMediaRegrant(
        mediaId: mediaId,
        recipient: recipient,
        ownerConfirmed: ownerConfirmed,
        requestId: requestId,
      ),
      subscribe: socket.addMessageHandler,
      unsubscribe: socket.removeMessageHandler,
      isConnected: () => socket.isAuthenticated,
      connectionChanges: socket.connectionPhase,
    );
  }

  @visibleForTesting
  factory LegacyMediaRegrantClient.test({
    required RegrantSender send,
    required void Function(void Function(Map<String, dynamic>)) subscribe,
    required void Function(void Function(Map<String, dynamic>)) unsubscribe,
    required bool Function() isConnected,
    required Listenable connectionChanges,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return LegacyMediaRegrantClient._(
      send: send,
      subscribe: subscribe,
      unsubscribe: unsubscribe,
      isConnected: isConnected,
      connectionChanges: connectionChanges,
      timeout: timeout,
    );
  }

  final RegrantSender send;
  final void Function(void Function(Map<String, dynamic>)) subscribe;
  final void Function(void Function(Map<String, dynamic>)) unsubscribe;
  final bool Function() isConnected;
  final Listenable connectionChanges;
  final Duration timeout;

  late final LegacyMediaRegrantCoordinator _coordinator;
  Completer<LegacyMediaRegrantResult>? _completion;
  Timer? _timer;
  bool _disposed = false;

  bool get isPending => _coordinator.isPending;

  Future<LegacyMediaRegrantResult> request({
    required String mediaId,
    required String recipient,
    required bool ownerConfirmed,
  }) async {
    if (_disposed || !isConnected() || isPending || !ownerConfirmed) {
      return const LegacyMediaRegrantResult(
        approved: false,
        reason: 'INVALID_OR_UNAPPROVED',
      );
    }

    final random = Random.secure();
    final requestId = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final completion = Completer<LegacyMediaRegrantResult>();
    _completion = completion;

    try {
      final submitted = _coordinator.request(
        mediaId: mediaId,
        recipient: recipient,
        ownerConfirmed: true,
        requestId: requestId,
      );

      if (!submitted) {
        _finish('REGRANT_FAILED');
      } else {
        _timer = Timer(timeout, () => _finish('TIMEOUT'));
      }
    } catch (_) {
      _finish('REGRANT_FAILED');
    }

    return completion.future;
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (_disposed) return;

    final result = _coordinator.acceptServerMessage(message);
    if (result == null) return;

    _finishWith(result);
  }

  void _handleConnection() {
    if (!_disposed && !isConnected()) {
      _finish('DISCONNECTED');
    }
  }

  void _finish(String reason) {
    _finishWith(LegacyMediaRegrantResult(
      approved: false,
      reason: reason,
    ));
  }

  void _finishWith(LegacyMediaRegrantResult result) {
    final completion = _completion;
    _completion = null;
    _timer?.cancel();
    _timer = null;
    _coordinator.reset();

    if (completion != null && !completion.isCompleted) {
      completion.complete(result);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unsubscribe(_handleMessage);
    connectionChanges.removeListener(_handleConnection);
    _finish('DISCONNECTED');
    if (identical(_shared, this)) {
      _shared = null;
    }
  }
}