import 'package:hive/hive.dart';

import 'message_append_mutation.dart';
import 'message_deletion_guard.dart';
import 'message_persistence_service.dart';
import 'message_write_coordinator.dart';

/// Coordinates durable delete markers and chat history updates.
///
/// All operations for a chat must use the same coordinator.
/// Markers are committed before history deletion. Because two Hive boxes
/// are not transactional, reconciliation is required after interruption.
class MessageDeletionPipeline {
  MessageDeletionPipeline({
    required this.messagesBox,
    required this.guard,
    required this.coordinator,
  });

  final Box messagesBox;
  final MessageDeletionGuard guard;
  final MessageWriteCoordinator coordinator;

  bool _removeMarked(
    String chatKey,
    List<Map<String, dynamic>> messages,
  ) {
    var changed = false;

    messages.removeWhere((message) {
      final id = message['id']?.toString().trim() ?? '';
      if (id.isEmpty ||
          !guard.isDeleted(chatKey: chatKey, messageId: id)) {
        return false;
      }
      changed = true;
      return true;
    });

    // Also repair dangling replies if the deleted original is already gone.
    for (final message in messages) {
      final reply = message['replyTo'];
      final replyId = reply is Map
          ? reply['id']?.toString().trim() ?? ''
          : '';

      if (replyId.isNotEmpty &&
          guard.isDeleted(chatKey: chatKey, messageId: replyId)) {
        message.remove('replyTo');
        changed = true;
      }
    }
    return changed;
  }

  Future<bool> deleteForEveryone({
    required String chatKey,
    required String messageId,
  }) {
    final key = chatKey.trim();
    final id = messageId.trim();

    if (key.isEmpty || id.isEmpty) {
      return Future<bool>.value(false);
    }

    return coordinator.run<bool>(key, () async {
      // Persist the protective marker first.
      final marked = await guard.markDeleted(
        chatKey: key,
        messageId: id,
      );
      if (!marked) return false;

      return mutateMessagesInHive(messagesBox, key, (current) {
        final changed = _removeMarked(key, current);
        return changed ? current : null;
      });
    });
  }

  Future<bool> append({
    required String chatKey,
    required Map<String, dynamic> incoming,
    Future<bool> Function()? allowAppend,
  }) {
    final key = chatKey.trim();
    final id = incoming['id']?.toString().trim() ?? '';

    if (key.isEmpty) return Future<bool>.value(false);

    return coordinator.run<bool>(key, () async {
      if (id.isNotEmpty &&
          guard.isDeleted(chatKey: key, messageId: id)) {
        // Also repair an interrupted earlier deletion.
        await mutateMessagesInHive(messagesBox, key, (current) {
          return _removeMarked(key, current) ? current : null;
        });
        return false;
      }

      // Recheck after earlier queued operations have completed.
      if (allowAppend != null && !await allowAppend()) {
        return false;
      }

      var appended = false;

      await mutateMessagesInHive(messagesBox, key, (current) {
        final recovered = _removeMarked(key, current);
        final next = appendMessageIfMissing(current, incoming);

        if (next != null) {
          appended = true;
          return next;
        }

        // Persist repairs even if no incoming message was added.
        return recovered ? current : null;
      });

      // True now means the incoming message was actually appended.
      // A repair-only write must not increment unread counters.
      return appended;
    });
  }

  Future<bool> reconcile({required String chatKey}) {
    final key = chatKey.trim();
    if (key.isEmpty) return Future<bool>.value(false);

    return coordinator.run<bool>(
      key,
      () => mutateMessagesInHive(messagesBox, key, (current) {
        return _removeMarked(key, current) ? current : null;
      }),
    );
  }
}