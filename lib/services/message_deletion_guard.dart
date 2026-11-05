import 'dart:convert';

import 'package:hive/hive.dart';

/// Durable marker for a message deleted for everyone.
///
/// Store this metadata in a dedicated Hive box, never in chat history.
/// Keep markers until a separately verified retention policy is introduced.
///
/// The caller must validate the event and serialize mark/delete/append
/// operations with the same per-chat write coordinator.
class MessageDeletionGuard {
  MessageDeletionGuard(this.box);

  final Box box;

  String? _key(String chatKey, String messageId) {
    final chat = chatKey.trim();
    final id = messageId.trim();

    if (chat.isEmpty || id.isEmpty) {
      return null;
    }

    final encodedChat = base64Url.encode(utf8.encode(chat));
    final encodedId = base64Url.encode(utf8.encode(id));

    return 'deleted:$encodedChat:$encodedId';
  }

  /// Return distinct chat keys that contain durable deletion markers.
  ///
  /// Invalid or unrelated box entries are ignored. No message text
  /// or message IDs are returned.
  Set<String> markedChatKeys() {
    final chats = <String>{};

    for (final rawKey in box.keys) {
      if (rawKey is! String || !rawKey.startsWith('deleted:')) {
        continue;
      }

      if (box.get(rawKey) != true) {
        continue;
      }

      final remainder = rawKey.substring('deleted:'.length);
      final separator = remainder.indexOf(':');

      if (separator <= 0 || separator == remainder.length - 1) {
        continue;
      }

      try {
        final encodedChat = remainder.substring(0, separator);
        final chatKey = utf8.decode(base64Url.decode(encodedChat));

        if (chatKey.trim().isNotEmpty) {
          chats.add(chatKey);
        }
      } catch (_) {
        // A damaged marker must not crash key enumeration.
      }
    }

    return chats;
  }

  Future<bool> markDeleted({
    required String chatKey,
    required String messageId,
  }) async {
    final key = _key(chatKey, messageId);
    if (key == null) return false;

    await box.put(key, true);
    return true;
  }

  bool isDeleted({
    required String chatKey,
    required String messageId,
  }) {
    final key = _key(chatKey, messageId);
    if (key == null) return false;

    return box.get(key) == true;
  }
}