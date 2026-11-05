import 'legacy_media_regrant_result.dart';

typedef RegrantSender = bool Function({
  required String mediaId,
  required String recipient,
  required bool ownerConfirmed,
  required String requestId,
});

/// Coordinates requests but never authorizes file access.
/// Server approval must match the currently outstanding request ID.
class LegacyMediaRegrantCoordinator {
  LegacyMediaRegrantCoordinator({required this.send});

  final RegrantSender send;
  String? _pendingRequestId;

  bool get isPending => _pendingRequestId != null;

  bool request({
    required String mediaId,
    required String recipient,
    required bool ownerConfirmed,
    required String requestId,
  }) {
    if (isPending ||
        !ownerConfirmed ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(requestId)) {
      return false;
    }

    final submitted = send(
      mediaId: mediaId,
      recipient: recipient,
      ownerConfirmed: true,
      requestId: requestId,
    );

    if (submitted) {
      _pendingRequestId = requestId;
    }

    return submitted;
  }

  LegacyMediaRegrantResult? acceptServerMessage(
    Map<String, dynamic> message,
  ) {
    if (!isPending ||
        message['type'] != 'legacy_media_regrant_result' ||
        message['requestId'] != _pendingRequestId) {
      return null;
    }

    _pendingRequestId = null;
    return LegacyMediaRegrantResult.fromMessage(message);
  }

  void reset() {
    _pendingRequestId = null;
  }
}