import 'dart:convert';

import 'package:hive/hive.dart';

/// Durable account-scoped markers for locally deleted messages.
/// These markers are separate from delete-for-everyone metadata.
///
/// Store marker data in its own Hive box. Do not store message
/// contents, attachments or E2EE keys in this box.
class MessageLocalDeletionGuard {
  MessageLocalDeletionGuard(this.box);

  final Box box;

  String? _key(String owner, String peer, String messageId) {
    final user = owner.trim();
    final contact = peer.trim();
    final id = messageId.trim();

    if (user.isEmpty ||
        contact.isEmpty ||
        user == contact ||
        id.isEmpty) {
      return null;
    }

    String encode(String value) =>
        base64Url.encode(utf8.encode(value));

    return 'local_deleted:'
        '${encode(user)}:${encode(contact)}:${encode(id)}';
  }

  /// Persist the marker before removing the local history entry.
  Future<bool> markDeleted({
    required String owner,
    required String peer,
    required String messageId,
  }) async {
    final key = _key(owner, peer, messageId);
    if (key == null) return false;

    await box.put(key, true);
    return true;
  }

  bool isDeleted({
    required String owner,
    required String peer,
    required String messageId,
  }) {
    final key = _key(owner, peer, messageId);
    return key != null && box.get(key) == true;
  }
}
