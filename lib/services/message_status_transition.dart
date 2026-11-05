/// Pure status transition. Returns null when no valid update is needed.
/// Does not write to storage or acknowledge a server event.
List<Map<String, dynamic>>? applyMessageStatusTransition({
  required List<Map<String, dynamic>> messages,
  required String currentUser,
  required String peer,
  required String messageId,
  required String eventType,
  required String from,
  required String to,
}) {
  final nextStatus = switch (eventType) {
    'message_delivered' => 'delivered',
    'message_read' => 'read',
    _ => null,
  };

  final id = messageId.trim();

  if (nextStatus == null ||
      id.isEmpty ||
      currentUser.isEmpty ||
      peer.isEmpty ||
      from != currentUser ||
      to != peer) {
    return null;
  }

  const ranks = <String, int>{
    'queued': 1,
    'sending': 2,
    'sent': 3,
    'delivered': 4,
    'read': 5,
  };

  final result = messages
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  for (var index = 0; index < result.length; index++) {
    final message = result[index];
    if (message['id']?.toString().trim() != id) continue;
    if (message['from']?.toString() != currentUser) return null;
    if (message['to']?.toString() != peer) return null;
    if (message['isMe'] == false) return null;

    final oldStatus = message['status']?.toString() ?? '';
    if ((ranks[oldStatus] ?? 0) >= ranks[nextStatus]!) {
      return null;
    }

    message['status'] = nextStatus;
    return result;
  }

  return null;
}