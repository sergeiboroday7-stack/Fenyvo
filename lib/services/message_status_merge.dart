/// Preserve the highest known delivery/read status when an older
/// message snapshot is about to be saved.
///
/// This function does not add or delete messages and does not
/// mutate either input. Ambiguous duplicate identities are ignored.
///
/// It is not yet wired to production storage.
List<Map<String, dynamic>> preserveMessageStatus({
  required List<Map<String, dynamic>> incoming,
  required List<Map<String, dynamic>> persisted,
}) {
  const ranks = <String, int>{
    'queued': 1,
    'sending': 2,
    'sent': 3,
    'delivered': 4,
    'read': 5,
  };

  String? identity(Map<String, dynamic> message) {
    final id = message['id']?.toString().trim() ?? '';
    final from = message['from']?.toString().trim() ?? '';
    final to = message['to']?.toString().trim() ?? '';

    if (id.isEmpty || from.isEmpty || to.isEmpty) {
      return null;
    }

    return '${id.length}:$id|${from.length}:$from|${to.length}:$to';
  }

  final savedById = <String, Map<String, dynamic>>{};
  final savedCounts = <String, int>{};
  final incomingCounts = <String, int>{};

  for (final message in persisted) {
    final key = identity(message);
    if (key == null) continue;
    savedCounts[key] = (savedCounts[key] ?? 0) + 1;
    savedById[key] = message;
  }

  for (final message in incoming) {
    final key = identity(message);
    if (key == null) continue;
    incomingCounts[key] = (incomingCounts[key] ?? 0) + 1;
  }

  return incoming.map((original) {
    final message = Map<String, dynamic>.from(original);
    final key = identity(message);
    if (key == null ||
        savedCounts[key] != 1 ||
        incomingCounts[key] != 1) {
      return message;
    }

    final saved = savedById[key]!;
    final savedStatus = saved['status']?.toString() ?? '';
    final incomingStatus = message['status']?.toString() ?? '';

    final savedRank = ranks[savedStatus];
    final incomingRank = ranks[incomingStatus];

    if (savedRank != null &&
        incomingRank != null &&
        savedRank > incomingRank) {
      message['status'] = savedStatus;
    }

    return message;
  }).toList();
}