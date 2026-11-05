import 'dart:async';

import 'message_status_transition.dart';

enum StatusPersistenceOutcome {
  updated,
  alreadyApplied,
  missing,
  rejected,
}

typedef LoadStatusHistory = List<Map<String, dynamic>> Function(
  String owner,
  String peer,
);

typedef SaveStatusHistory = Future<void> Function(
  String owner,
  String peer,
  List<Map<String, dynamic>> messages,
);

/// Isolated, per-chat serialized status persistence.
/// No WebSocket or ACK integration yet.
class MessageStatusPersistenceService {
  MessageStatusPersistenceService({
    required this.loadMessages,
    required this.saveMessages,
  });

  final LoadStatusHistory loadMessages;
  final SaveStatusHistory saveMessages;

  final Map<String, Future<void>> _pending = {};

  Future<StatusPersistenceOutcome> apply({
    required String currentUser,
    required String peer,
    required String messageId,
    required String eventType,
    required String from,
    required String to,
  }) async {
    final owner = currentUser.trim();
    final contact = peer.trim();
    final id = messageId.trim();

    if (owner.isEmpty ||
        contact.isEmpty ||
        id.isEmpty ||
        from != owner ||
        to != contact ||
        (eventType != 'message_delivered' &&
            eventType != 'message_read')) {
      return StatusPersistenceOutcome.rejected;
    }

    final key = '${owner.length}:$owner:${contact.length}:$contact';
    final previous = _pending[key] ?? Future<void>.value();
    final release = Completer<void>();
    final releaseFuture = release.future;
    _pending[key] = releaseFuture;

    try {
      await previous;

      final messages = loadMessages(owner, contact);

      Map<String, dynamic>? matched;
      for (final item in messages) {
        if (item['id']?.toString().trim() == id) {
          matched = item;
          break;
        }
      }

      if (matched == null) {
        return StatusPersistenceOutcome.missing;
      }

      if (matched['from']?.toString() != owner ||
          matched['to']?.toString() != contact ||
          matched['isMe'] == false) {
        return StatusPersistenceOutcome.rejected;
      }

      const ranks = <String, int>{
        'queued': 1,
        'sending': 2,
        'sent': 3,
        'delivered': 4,
        'read': 5,
      };

      final desired = eventType == 'message_read' ? 5 : 4;
      final existing = ranks[matched['status']?.toString()] ?? 0;

      if (existing >= desired) {
        return StatusPersistenceOutcome.alreadyApplied;
      }

      final updated = applyMessageStatusTransition(
        messages: messages,
        currentUser: owner,
        peer: contact,
        messageId: id,
        eventType: eventType,
        from: from,
        to: to,
      );

      if (updated == null) {
        return StatusPersistenceOutcome.rejected;
      }

      // Errors propagate. Caller must not ACK a failed write.
      await saveMessages(owner, contact, updated);
      return StatusPersistenceOutcome.updated;
    } finally {
      release.complete();
      if (identical(_pending[key], releaseFuture)) {
        _pending.remove(key);
      }
    }
  }
}