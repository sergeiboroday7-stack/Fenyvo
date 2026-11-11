import 'private_e2ee_edit_protocol.dart';

/// Classifies encrypted edit operations before ordinary message handling.
///
/// This class does not authenticate the sender or encrypt the payload.
/// Those responsibilities remain with Signal and the transport layer.
class PrivateE2eeEditDeliveryPolicy {
  const PrivateE2eeEditDeliveryPolicy();

  bool isEditOperation(Map<String, dynamic> item) {
    return item['kind'] == PrivateE2eeEditProtocol.kind;
  }

  bool isValidEditOperation(Map<String, dynamic> item) {
    if (!isEditOperation(item)) return false;
    try {
      final editedAt = DateTime.tryParse(
        item['editedAt']?.toString() ?? '',
      );
      if (editedAt == null) return false;

      final normalized = PrivateE2eeEditProtocol.create(
        eventId: item['id']?.toString() ?? '',
        from: item['from']?.toString() ?? '',
        to: item['to']?.toString() ?? '',
        targetMessageId: item['targetMessageId']?.toString() ?? '',
        newText: item['newText']?.toString() ?? '',
        editedAt: editedAt,
      );
      return normalized['id'] == item['id'] &&
          normalized['from'] == item['from'] &&
          normalized['to'] == item['to'] &&
          normalized['targetMessageId'] == item['targetMessageId'] &&
          normalized['newText'] == item['newText'] &&
          normalized['editedAt'] == item['editedAt'];
    } catch (_) {
      return false;
    }
  }

  /// An edit ACK must never become an ordinary chat bubble.
  bool suppressOrdinaryMessageForAck({
    required Map<String, dynamic>? queued,
    required String acknowledgedId,
  }) {
    if (queued == null || acknowledgedId.isEmpty) return false;
    return queued['id'] == acknowledgedId && isEditOperation(queued);
  }

  /// Use the dedicated encrypted edit sender, never text-message retry.
  bool needsDedicatedRetry(Map<String, dynamic> queued) {
    return isEditOperation(queued);
  }

  /// Unknown or malformed edit operations must not fall back to plaintext.
  bool blockOrdinaryMessageFallback(Map<String, dynamic> queued) {
    return isEditOperation(queued);
  }
}