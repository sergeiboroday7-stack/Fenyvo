/// Validates decrypted private edit operations.
/// The caller must first authenticate/decrypt the Signal envelope.
class PrivateE2eeEditProtocol {
  static const kind = 'private_edit_v1';
  static const maxTextLength = 4000;

  static final RegExp _eventIdPattern =
      RegExp(r'^[a-zA-Z0-9_-]{6,120}$');

  static Map<String, dynamic> create({
    required String eventId,
    required String from,
    required String to,
    required String targetMessageId,
    required String newText,
    required DateTime editedAt,
  }) {
    final payload = <String, dynamic>{
      'kind': kind,
      'id': eventId.trim(),
      'from': from.trim(),
      'to': to.trim(),
      'targetMessageId': targetMessageId.trim(),
      'newText': newText.trim(),
      'editedAt': editedAt.toUtc().toIso8601String(),
    };

    if (!_validShape(payload)) {
      throw ArgumentError('Invalid private E2EE edit payload');
    }

    return payload;
  }

  /// [authenticatedFrom] must come from the verified Signal sender.
  /// [original] must come from trusted local chat history.
  /// This method alone does not authenticate the network sender.
  static bool canApply({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> original,
    required String authenticatedFrom,
    required String localUser,
    required String peer,
  }) {
    if (!_validShape(payload)) return false;

    final sender = payload['from'] as String;
    final recipient = payload['to'] as String;
    final originalFrom = original['from']?.toString().trim() ?? '';
    final originalTo = original['to']?.toString().trim() ?? '';
    final originalId = original['id']?.toString().trim() ?? '';

    if (localUser.trim().isEmpty || peer.trim().isEmpty) return false;
    if (localUser.trim() == peer.trim()) return false;
    if (sender != authenticatedFrom.trim()) return false;
    if (original['e2ee'] != true) return false;
    if (originalId != payload['targetMessageId']) return false;
    if (sender != originalFrom || recipient != originalTo) return false;

    final belongsToChat =
        (sender == localUser.trim() && recipient == peer.trim()) ||
        (sender == peer.trim() && recipient == localUser.trim());

    if (!belongsToChat) return false;
    if (payload['id'] == originalId) return false;

    final lastEditId = original['lastEditEventId']?.toString() ?? '';
    if (lastEditId == payload['id']) return false;

    final priorEditTime =
        DateTime.tryParse(original['editedAt']?.toString() ?? '');
    final nextEditTime =
        DateTime.tryParse(payload['editedAt'] as String);

    if (nextEditTime == null) return false;
    if (priorEditTime != null &&
        !nextEditTime.isAfter(priorEditTime)) {
      return false;
    }

    return true;
  }

  static bool _validShape(Map<String, dynamic> payload) {
    if (payload['kind'] != kind) return false;

    final id = payload['id'];
    final from = payload['from'];
    final to = payload['to'];
    final targetId = payload['targetMessageId'];
    final newText = payload['newText'];
    final editedAt = payload['editedAt'];

    if (id is! String || !_eventIdPattern.hasMatch(id)) {
      return false;
    }
    if (from is! String || from.isEmpty) return false;
    if (to is! String || to.isEmpty || from == to) return false;
    if (targetId is! String || targetId.isEmpty) return false;
    if (newText is! String ||
        newText.isEmpty ||
        newText.length > maxTextLength) {
      return false;
    }
    if (editedAt is! String ||
        DateTime.tryParse(editedAt) == null) {
      return false;
    }

    return true;
  }
}