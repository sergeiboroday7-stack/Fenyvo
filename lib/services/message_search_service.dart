class MessageSearchService {
  const MessageSearchService._();

  static bool matches(Map<String, dynamic> message, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return false;

    final reply = message['replyTo'];
    final searchableParts = <Object?>[
      message['text'],
      message['fileName'],
      message['forwardComment'],
      message['forwardedFrom'],
      if (reply is Map) reply['text'],
      if (reply is Map) reply['from'],
    ];

    return searchableParts.any(
      (part) =>
          part?.toString().toLowerCase().contains(normalizedQuery) == true,
    );
  }
}
