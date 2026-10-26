/// Counts the occurrences of each message reaction.
///
/// This function has no dependencies on Flutter widgets,
/// network transport, message storage or encryption.
Map<String, int> countMessageReactions(
  Iterable<String> reactions,
) {
  final counts = <String, int>{};

  for (final reaction in reactions) {
    counts[reaction] = (counts[reaction] ?? 0) + 1;
  }

  return counts;
}

/// Reads current and legacy message reactions using the existing rules.
Map<String, String> parseStoredMessageReactions(Map<String, dynamic> message, Iterable<String> supportedReactions) {
    final result = <String, String>{};
    final rawReactions = message['reactions'];

    if (rawReactions is Map) {
      rawReactions.forEach((rawUser, rawReaction) {
        final user = rawUser.toString().trim();
        final reaction = rawReaction.toString().trim();

        if (user.isEmpty || !supportedReactions.contains(reaction)) {
          return;
        }

        result[user] = reaction;
      });
    }

    if (result.isNotEmpty) {
      return result;
    }

    final legacyUsers = message['reactionUsers'];
    if (legacyUsers is List) {
      for (final rawUser in legacyUsers) {
        final user = rawUser.toString().trim();
        if (user.isNotEmpty) {
          result[user] = '\u2764\uFE0F';
        }
      }
    }

    return result;
  }
