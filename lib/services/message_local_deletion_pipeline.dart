import 'package:hive/hive.dart';

import 'message_local_deletion_guard.dart';
import 'message_write_coordinator.dart';

/// Locally hide messages for one account without modifying shared history.
/// Marker writes must use the same chat coordinator as durable appends.
class MessageLocalDeletionPipeline {
  MessageLocalDeletionPipeline({
    required this.messagesBox,
    required this.guard,
    required this.coordinator,
  });

  final Box messagesBox;
  final MessageLocalDeletionGuard guard;
  final MessageWriteCoordinator coordinator;

  bool _validParticipants(String owner, String peer) {
    return owner.isNotEmpty && peer.isNotEmpty && owner != peer;
  }

  /// Write a durable owner-scoped marker. Physical history stays unchanged.
  Future<bool> hideForOwner({
    required String chatKey,
    required String owner,
    required String peer,
    required String messageId,
  }) {
    final key = chatKey.trim();
    final user = owner.trim();
    final contact = peer.trim();
    final id = messageId.trim();

    if (key.isEmpty ||
        !_validParticipants(user, contact) ||
        id.isEmpty) {
      return Future<bool>.value(false);
    }

    // Do not trust a caller-provided chat key.
    final participants = <String>[user, contact]..sort();
    if (key != participants.join('_')) {
      return Future<bool>.value(false);
    }

    return coordinator.run<bool>(key, () async {
      final raw = messagesBox.get(key);
      if (raw is! List) return false;

      final found = raw.any((item) {
        if (item is! Map) return false;
        if (item['id']?.toString().trim() != id) return false;

        final from = item['from']?.toString().trim() ?? '';
        final to = item['to']?.toString().trim() ?? '';

        return (from == user && to == contact) ||
            (from == contact && to == user);
      });

      if (!found) return false;

      return guard.markDeleted(
        owner: user,
        peer: contact,
        messageId: id,
      );
    });
  }

  /// Filter a shared history to the current account's visible messages.
  List<Map<String, dynamic>> visibleForOwner({
    required String owner,
    required String peer,
    required List<Map<String, dynamic>> messages,
  }) {
    final user = owner.trim();
    final contact = peer.trim();

    if (!_validParticipants(user, contact)) {
      return <Map<String, dynamic>>[];
    }

    return messages.where((message) {
      final from = message['from']?.toString().trim() ?? '';
      final to = message['to']?.toString().trim() ?? '';

      final validDirection =
          (from == user && to == contact) ||
          (from == contact && to == user);

      if (!validDirection) return false;

      final id = message['id']?.toString().trim() ?? '';
      if (id.isEmpty) return true;

      return !guard.isDeleted(
        owner: user,
        peer: contact,
        messageId: id,
      );
    }).toList();
  }

  bool isHiddenForOwner({
    required String owner,
    required String peer,
    required String messageId,
  }) {
    return guard.isDeleted(
      owner: owner,
      peer: peer,
      messageId: messageId,
    );
  }
}
